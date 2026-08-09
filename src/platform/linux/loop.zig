const std = @import("std");

const client = @import("dbus/client.zig");
const contract = @import("../contract.zig");
const menu = @import("menu.zig");
const post_queue = @import("post.zig");
const sys = @import("sys.zig");
const timer = @import("timer.zig");
const tray = @import("tray.zig");
const types = @import("../../event/types.zig");
const watcher = @import("watcher.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

const Event = types.Event;
const Response = types.Response;

pub const Error = contract.LoopError;

pub const events_max: u32 = 16;
pub const iteration_max: u64 = 1 << 48;
pub const interrupt_retry_max: u32 = 64;
pub const messages_max: u32 = 64;
pub const wait_timeout_ms: i32 = 1_000;

const Dispatch = *const fn (*anyopaque, *const Event) Response;

var epoll_fd: ?sys.Fd = null;
var owner_pointer: ?*anyopaque = null;
var dispatch_fn: ?Dispatch = null;
var quit_requested: bool = false;

comptime {
    assert(events_max > 0);
    assert(iteration_max > 0);
    assert(interrupt_retry_max > 0);
    assert(messages_max > 0);
    assert(wait_timeout_ms > 0);
}

pub fn quit() void {
    quit_requested = true;

    assert(quit_requested);
}

pub fn post(code: u32) bool {
    return post_queue.post(code);
}

fn reset() void {
    quit_requested = false;
    owner_pointer = null;
    dispatch_fn = null;

    assert(!quit_requested);
}

pub fn LoopType(comptime Owner: type) type {
    return struct {
        started: bool,

        const Instance = @This();

        pub fn init() Instance {
            assert(owner_pointer == null);

            const result = Instance{ .started = false };

            assert(!result.started);

            return result;
        }

        pub fn run(instance: *Instance, owner: *Owner) Error!void {
            assert(!instance.started);

            if (owner_pointer != null) {
                return Error.AlreadyRunning;
            }

            instance.started = true;
            quit_requested = false;

            owner_pointer = owner;
            dispatch_fn = &thunk;
            defer {
                owner_pointer = null;
                dispatch_fn = null;
                quit_requested = false;
            }

            try open();
            defer close();

            try pump();
        }

        fn thunk(pointer: *anyopaque, event: *const Event) Response {
            const typed: *Owner = @ptrCast(@alignCast(pointer));

            return typed.dispatch(event);
        }
    };
}

fn open() Error!void {
    const raw = linux.epoll_create1(linux.EPOLL.CLOEXEC);

    if (!sys.ok(raw)) {
        return Error.Failed;
    }

    epoll_fd = @intCast(raw);
    errdefer close();

    const bus = client.descriptor() orelse return Error.NotConnected;

    register(bus, true);

    const doorbell = post_queue.open() catch {
        return Error.Failed;
    };

    register(doorbell, true);

    timer.set_watch(on_watch);
    watcher.set_watch(on_watch);

    assert(epoll_fd != null);
    assert(post_queue.descriptor() != null);
}

fn close() void {
    timer.set_watch(null);
    watcher.set_watch(null);

    post_queue.close();

    const fd = epoll_fd orelse return;

    sys.close(fd);

    epoll_fd = null;

    assert(epoll_fd == null);
    assert(post_queue.descriptor() == null);
}

fn on_watch(fd: sys.Fd, add: bool) void {
    register(fd, add);
}

fn register(fd: sys.Fd, add: bool) void {
    const epoll = epoll_fd orelse return;

    var description = linux.epoll_event{
        .events = linux.EPOLL.IN,
        .data = .{ .fd = fd },
    };

    const operation: u32 = if (add) linux.EPOLL.CTL_ADD else linux.EPOLL.CTL_DEL;

    _ = linux.epoll_ctl(epoll, operation, fd, &description);
}

fn pump() Error!void {
    const epoll = epoll_fd orelse return Error.Failed;

    var ready: [events_max]linux.epoll_event = undefined;
    var iteration: u64 = 0;

    while (iteration < iteration_max and !quit_requested) : (iteration += 1) {
        if (client.has_pending()) {
            try drain_messages();
        }

        if (quit_requested) {
            return;
        }

        const count = wait(epoll, &ready) orelse return Error.Failed;

        assert(count <= events_max);

        var index: u32 = 0;

        while (index < count) : (index += 1) {
            assert(index < events_max);

            try service(ready[index].data.fd);

            if (quit_requested) {
                return;
            }
        }
    }
}

fn wait(epoll: sys.Fd, ready: *[events_max]linux.epoll_event) ?u32 {
    var retries: u32 = 0;

    while (retries < interrupt_retry_max) : (retries += 1) {
        const raw = linux.epoll_wait(epoll, ready, events_max, wait_timeout_ms);
        const status = std.posix.errno(raw);

        if (status == .SUCCESS) {
            return @intCast(raw);
        }

        if (status != .INTR) {
            return null;
        }
    }

    return null;
}

fn service(fd: sys.Fd) Error!void {
    if (client.descriptor()) |bus| {
        if (fd == bus) {
            try drain_bus();

            return;
        }
    }

    if (watcher.descriptor()) |inotify| {
        if (fd == inotify) {
            _ = watcher.drain();

            return;
        }
    }

    if (post_queue.descriptor()) |doorbell| {
        if (fd == doorbell) {
            drain_posts();

            return;
        }
    }

    if (timer.id_of(fd)) |id| {
        _ = timer.drain(fd);

        const ticked = Event.timer_tick(id, 0);

        _ = deliver(&ticked);
    }
}

fn drain_posts() void {
    post_queue.drain();

    var delivered: u32 = 0;

    while (delivered < post_queue.queue_capacity) : (delivered += 1) {
        assert(delivered < post_queue.queue_capacity);

        const code = post_queue.take() orelse return;
        const posted = Event.custom(code, null);

        _ = deliver(&posted);

        if (quit_requested) {
            return;
        }
    }
}

fn drain_bus() Error!void {
    const filled = client.fill(false) catch {
        return Error.Failed;
    };

    if (!filled and !client.has_pending()) {
        return;
    }

    try drain_messages();
}

fn drain_messages() Error!void {
    var messages: u32 = 0;

    while (messages < messages_max) : (messages += 1) {
        const taken = client.take_message() catch {
            return Error.Failed;
        };

        const message = taken orelse return;

        if (message.header.kind == .signal) {
            route_signal(message);

            if (quit_requested) {
                return;
            }

            continue;
        }

        if (message.header.kind != .method_call) {
            continue;
        }

        route(message);

        if (quit_requested) {
            return;
        }
    }
}

fn route_signal(message: client.Message) void {
    if (!tray.is_watcher_restart(message)) {
        return;
    }

    const restarted = Event.taskbar_restart();

    _ = deliver(&restarted);
}

fn route(message: client.Message) void {
    if (std.mem.eql(u8, message.header.path, menu.object_path)) {
        switch (menu.handle_call(message)) {
            .about_to_show => {
                const shown = Event.menu_show();

                _ = deliver(&shown);
            },
            .selected => |id| {
                const selected = Event.menu_select(id, false);

                _ = deliver(&selected);
            },
            .ignored => {},
        }

        return;
    }

    switch (tray.handle_call(message)) {
        .activate => {
            const clicked = Event.tray_left_click();

            _ = deliver(&clicked);
        },
        .secondary_activate => {
            const clicked = Event.tray_double_click();

            _ = deliver(&clicked);
        },
        .context_menu => {
            const clicked = Event.tray_right_click();

            _ = deliver(&clicked);
        },
        .ignored => {},
    }
}

fn deliver(event: *const Event) Response {
    const pointer = owner_pointer orelse return .pass;
    const dispatch = dispatch_fn orelse return .pass;

    const response = dispatch(pointer, event);

    if (response.should_quit()) {
        quit();
    }

    return response;
}

const testing = std.testing;

const Collector = struct {
    count: u32,
    last: ?types.Kind,

    fn init() Collector {
        return .{ .count = 0, .last = null };
    }

    pub fn dispatch(collector: *Collector, event: *const Event) Response {
        collector.count += 1;
        collector.last = event.kind();

        return .pass;
    }
};

test "deliver is inert without an installed owner" {
    reset();

    const event = Event.app_init();

    try testing.expectEqual(Response.pass, deliver(&event));
}

test "deliver forwards to the installed owner" {
    reset();

    var collector = Collector.init();

    owner_pointer = &collector;
    dispatch_fn = &LoopType(Collector).thunk;

    const event = Event.tray_left_click();

    _ = deliver(&event);

    reset();

    try testing.expectEqual(@as(u32, 1), collector.count);
    try testing.expectEqual(types.Kind.tray_left_click, collector.last.?);
}

test "a quit response stops the loop" {
    reset();

    const Quitter = struct {
        pub fn dispatch(_: *@This(), _: *const Event) Response {
            return .quit;
        }
    };

    var quitter = Quitter{};

    owner_pointer = &quitter;
    dispatch_fn = &LoopType(Quitter).thunk;

    const event = Event.tray_left_click();

    _ = deliver(&event);

    const requested = quit_requested;

    reset();

    try testing.expect(requested);
}

test "run without a bus connection reports the failure" {
    reset();

    if (client.is_connected()) {
        return;
    }

    var collector = Collector.init();
    var instance = LoopType(Collector).init();

    try testing.expectError(Error.NotConnected, instance.run(&collector));

    reset();
}
