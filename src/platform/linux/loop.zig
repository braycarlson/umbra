const std = @import("std");

const client = @import("dbus/client.zig");
const contract = @import("../contract.zig");
const event_module = @import("../../event.zig");
const menu = @import("menu.zig");
const post_queue = @import("post.zig");
const sys = @import("sys.zig");
const timer = @import("timer.zig");
const tray = @import("tray.zig");
const watcher = @import("watcher.zig");
const wire = @import("dbus/wire.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

const Event = event_module.Event;
const PlatformError = contract.PlatformError;

pub const events_max: u32 = 16;
pub const iteration_max: u64 = 1 << 48;
pub const interrupt_retry_max: u32 = 64;
pub const messages_max: u32 = 64;
pub const wait_timeout_ms: i32 = 1_000;
const Dispatch = *const fn (*anyopaque, *const Event) void;

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

pub fn post(code: Event.Code) bool {
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

        pub fn run(instance: *Instance, owner: *Owner) PlatformError!void {
            assert(!instance.started);
            assert(owner_pointer == null);
            assert(client.is_connected());

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

        fn thunk(pointer: *anyopaque, event: *const Event) void {
            const typed: *Owner = @ptrCast(@alignCast(pointer));

            typed.dispatch(event);
        }
    };
}

fn open() PlatformError!void {
    const raw = linux.epoll_create1(linux.EPOLL.CLOEXEC);

    if (!sys.ok(raw)) {
        return error.LoopFailed;
    }

    epoll_fd = @intCast(raw);
    errdefer close();

    register(client.descriptor().?, true);

    const doorbell = post_queue.open() catch {
        return error.LoopFailed;
    };

    register(doorbell, true);

    timer.set_hook(on_hook);
    watcher.set_hook(on_hook);

    assert(epoll_fd != null);
    assert(post_queue.descriptor() != null);
}

fn close() void {
    timer.set_hook(null);
    watcher.set_hook(null);

    post_queue.close();

    const fd = epoll_fd orelse return;

    sys.close(fd);

    epoll_fd = null;

    assert(epoll_fd == null);
    assert(post_queue.descriptor() == null);
}

fn on_hook(fd: sys.Fd, add: bool) void {
    assert(fd >= 0);

    register(fd, add);
}

fn register(fd: sys.Fd, add: bool) void {
    assert(fd >= 0);
    if (epoll_fd) |epoll| assert(fd != epoll);

    const epoll = epoll_fd orelse return;

    var description = linux.epoll_event{ .events = linux.EPOLL.IN, .data = .{ .fd = fd } };

    const operation: u32 = if (add) linux.EPOLL.CTL_ADD else linux.EPOLL.CTL_DEL;

    _ = linux.epoll_ctl(epoll, operation, fd, &description);
}

fn pump() PlatformError!void {
    const epoll = epoll_fd orelse return error.LoopFailed;

    var ready: [events_max]linux.epoll_event = undefined;
    var iteration: u64 = 0;

    while (iteration < iteration_max) : (iteration += 1) {
        if (quit_requested) {
            return;
        }

        if (client.has_pending()) {
            try drain_messages();
        }

        if (quit_requested) {
            return;
        }

        const count = wait(epoll, &ready) orelse return error.LoopFailed;

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
    assert(epoll >= 0);

    var retries: u32 = 0;

    while (retries < interrupt_retry_max) : (retries += 1) {
        const raw = linux.epoll_wait(epoll, ready, events_max, wait_timeout_ms);
        const status = std.posix.errno(raw);

        if (status == .SUCCESS) {
            const result: u32 = @intCast(raw);
            assert(result <= events_max);

            return result;
        }

        if (status != .INTR) {
            return null;
        }
    }

    return null;
}

fn service(fd: sys.Fd) PlatformError!void {
    assert(fd >= 0);

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

        deliver(&Event.create(.{ .timer_tick = .{ .id = id, .tick_count = 0 } }));
    }
}

fn drain_posts() void {
    post_queue.drain();

    var delivered: u32 = 0;

    while (delivered < post_queue.queue_capacity) : (delivered += 1) {
        assert(delivered < post_queue.queue_capacity);

        const code = post_queue.take() orelse return;

        deliver(&Event.create(.{ .custom = .{ .code = code } }));

        if (quit_requested) {
            return;
        }
    }
}

fn drain_bus() PlatformError!void {
    const filled = client.fill(false) catch {
        return error.LoopFailed;
    };

    if (filled) {
        try drain_messages();

        return;
    }

    if (client.has_pending()) {
        try drain_messages();
    }
}

fn drain_messages() PlatformError!void {
    var messages: u32 = 0;

    while (messages < messages_max) : (messages += 1) {
        const message = client.take_message() catch |err| switch (err) {
            error.Incomplete => return,
            else => return error.LoopFailed,
        };

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
    assert(message.header.kind == .signal);

    if (!tray.is_watcher_restart(message)) {
        return;
    }

    deliver(&Event.create(.{ .taskbar_restart = {} }));
}

fn route(message: client.Message) void {
    assert(message.header.kind == .method_call);

    if (std.mem.eql(u8, message.header.path, menu.object_path)) {
        switch (menu.handle_call(message)) {
            .about_to_show => deliver(&Event.create(.{ .menu_show = {} })),
            .selected => |id| {
                deliver(&Event.create(.{ .menu_select = .{ .checked = false, .id = id } }));
            },
            .ignored => {},
        }

        return;
    }

    switch (tray.handle_call(message)) {
        .activate => deliver(&Event.create(.{ .tray_left_click = {} })),
        .secondary_activate => deliver(&Event.create(.{ .tray_double_click = {} })),
        .context_menu => deliver(&Event.create(.{ .tray_right_click = {} })),
        .ignored => {},
    }
}

fn deliver(event: *const Event) void {
    const pointer = owner_pointer orelse return;
    const dispatch = dispatch_fn orelse return;

    dispatch(pointer, event);

    if (contract.is_activation(event.kind())) tray.activation_clear();
}

const testing = std.testing;

const Collector = struct {
    count: u32,
    last: ?Event.Kind,

    fn init() Collector {
        return .{ .count = 0, .last = null };
    }

    pub fn dispatch(collector: *Collector, event: *const Event) void {
        collector.count += 1;
        collector.last = event.kind();
    }
};

test "deliver is inert without an installed owner" {
    reset();

    const collector = Collector.init();

    deliver(&Event.create(.{ .app_init = {} }));

    try testing.expectEqual(@as(u32, 0), collector.count);
    try testing.expect(owner_pointer == null);
}

test "deliver forwards to the installed owner" {
    reset();

    var collector = Collector.init();

    owner_pointer = &collector;
    dispatch_fn = &LoopType(Collector).thunk;

    deliver(&Event.create(.{ .tray_left_click = {} }));

    reset();

    try testing.expectEqual(@as(u32, 1), collector.count);
    try testing.expectEqual(Event.Kind.tray_left_click, collector.last.?);
}

test "a quit from the owner stops the loop" {
    reset();

    const Quitter = struct {
        pub fn dispatch(_: *@This(), _: *const Event) void {
            quit();
        }
    };

    var quitter = Quitter{};

    owner_pointer = &quitter;
    dispatch_fn = &LoopType(Quitter).thunk;

    deliver(&Event.create(.{ .tray_left_click = {} }));

    const requested = quit_requested;

    reset();

    try testing.expect(requested);
}

const Witness = struct {
    kind: ?Event.Kind,
    token: [contract.activation_token_bytes_max]u8,
    token_len: u32,

    const empty: Witness = .{ .kind = null, .token = undefined, .token_len = 0 };

    pub fn dispatch(witness: *Witness, event: *const Event) void {
        const token = tray.activation_token();

        assert(token.len <= contract.activation_token_bytes_max);

        @memcpy(witness.token[0..token.len], token);

        witness.kind = event.kind();
        witness.token_len = @intCast(token.len);
    }

    fn seen(witness: *const Witness) []const u8 {
        return witness.token[0..witness.token_len];
    }
};

fn call(
    path: []const u8,
    interface: []const u8,
    member: []const u8,
    body: []const u8,
) client.Message {
    assert(path.len > 0);
    assert(interface.len > 0);
    assert(member.len > 0);
    assert(body.len <= client.receive_bytes_max);

    var header = wire.Header.empty();

    header.body_length = @intCast(body.len);
    header.interface = interface;
    header.kind = .method_call;
    header.member = member;
    header.path = path;
    header.serial = 1;

    return .{ .body = body, .header = header };
}

test "a token from the tray host reaches the next activation and no later one" {
    reset();

    const token = "gnome-shell/Solopass/2541-0-fedora_TIME51234";

    var witness: Witness = .empty;

    owner_pointer = &witness;
    dispatch_fn = &LoopType(Witness).thunk;

    var provided: [128]u8 = undefined;
    var provided_writer = wire.Writer.init(&provided);

    try provided_writer.put_string(token);

    var closed: [64]u8 = undefined;
    var closed_writer = wire.Writer.init(&closed);

    try closed_writer.put_i32(0);
    try closed_writer.put_string("closed");

    const provide = "ProvideXdgActivationToken";

    route(call(tray.object_path, tray.interface_name, provide, provided_writer.bytes()));
    route(call(menu.object_path, menu.interface_name, "Event", closed_writer.bytes()));

    try testing.expect(witness.kind == null);
    try testing.expectEqualStrings(token, tray.activation_token());

    route(call(tray.object_path, tray.interface_name, "Activate", &.{}));

    try testing.expectEqual(Event.Kind.tray_left_click, witness.kind.?);
    try testing.expectEqualStrings(token, witness.seen());
    try testing.expectEqualStrings("", tray.activation_token());

    route(call(tray.object_path, tray.interface_name, "SecondaryActivate", &.{}));

    try testing.expectEqual(Event.Kind.tray_double_click, witness.kind.?);
    try testing.expectEqualStrings("", witness.seen());

    reset();
}
