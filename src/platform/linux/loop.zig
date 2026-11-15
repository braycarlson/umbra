const std = @import("std");

const Client = @import("dbus.zig").Client;
const event_module = @import("../../event.zig");
const IconTable = @import("icon_table.zig");
const interface = @import("../interface.zig");
const Menu = @import("menu.zig");
const PostQueue = @import("post_queue.zig");
const sys = @import("sys.zig");
const time = @import("time.zig");
const TimerTable = @import("timer_table.zig");
const Tray = @import("tray.zig");
const Watcher = @import("watcher.zig");
const wire = @import("dbus.zig").wire;

const assert = std.debug.assert;

const linux = std.os.linux;

const Event = event_module.Event;
const PlatformError = interface.PlatformError;

const Loop = @This();

client: *Client,
dispatch: ?Dispatch,
epoll: sys.Epoll,
menu: *Menu,
owner: ?*anyopaque,
post_queue: *PostQueue,
quit_requested: bool,
timers: *TimerTable,
tray: *Tray,
watcher: *Watcher,

pub const Options = struct {
    client: *Client,
    menu: *Menu,
    post_queue: *PostQueue,
    timers: *TimerTable,
    tray: *Tray,
    watcher: *Watcher,
};

const Dispatch = *const fn (*anyopaque, *const Event) void;

pub const events_max: u32 = 16;
pub const iteration_max: u64 = 1 << 48;
pub const messages_max: u32 = 64;
pub const wait_timeout_ms: i32 = 1_000;

comptime {
    assert(events_max > 0);
    assert(iteration_max > 0);
    assert(messages_max > 0);
    assert(wait_timeout_ms > 0);
}

pub fn init(loop: *Loop, options: Options) void {
    loop.* = .{
        .client = options.client,
        .dispatch = null,
        .epoll = .closed,
        .menu = options.menu,
        .owner = null,
        .post_queue = options.post_queue,
        .quit_requested = false,
        .timers = options.timers,
        .tray = options.tray,
        .watcher = options.watcher,
    };

    assert(loop.owner == null);
    assert(loop.epoll.fd == null);
}

pub fn quit(loop: *Loop) void {
    loop.quit_requested = true;

    assert(loop.quit_requested);
}

pub fn run(loop: *Loop, comptime Owner: type, owner: *Owner) PlatformError!void {
    assert(loop.owner == null);
    assert(loop.client.is_connected());

    loop.quit_requested = false;
    loop.owner = owner;
    loop.dispatch = &DispatchType(Owner).dispatch;
    defer {
        loop.owner = null;
        loop.dispatch = null;
        loop.quit_requested = false;
    }

    try loop.open();
    defer loop.close();

    try loop.pump();
}

fn DispatchType(comptime Owner: type) type {
    return struct {
        fn dispatch(pointer: *anyopaque, event: *const Event) void {
            const owner: *Owner = @ptrCast(@alignCast(pointer));

            owner.dispatch(event);
        }
    };
}

fn open(loop: *Loop) PlatformError!void {
    loop.epoll.open() catch return error.LoopFailed;
    errdefer loop.close();

    loop.epoll.register(loop.client.descriptor().?, true);

    const doorbell = loop.post_queue.open() catch {
        return error.LoopFailed;
    };

    loop.epoll.register(doorbell, true);
    loop.timers.adopt();
    loop.watcher.adopt();

    assert(loop.epoll.fd != null);
    assert(loop.post_queue.descriptor() != null);
}

fn close(loop: *Loop) void {
    loop.post_queue.close();
    loop.epoll.close();

    assert(loop.epoll.fd == null);
    assert(loop.post_queue.descriptor() == null);
}

fn pump(loop: *Loop) PlatformError!void {
    assert(loop.epoll.fd != null);

    var ready: [events_max]linux.epoll_event = undefined;
    var iteration: u64 = 0;

    while (iteration < iteration_max) : (iteration += 1) {
        if (loop.quit_requested) {
            return;
        }

        if (loop.client.has_pending()) {
            try loop.drain_messages();
        }

        if (loop.quit_requested) {
            return;
        }

        const count = loop.epoll.wait(&ready, wait_timeout_ms) orelse return error.LoopFailed;

        assert(count <= events_max);

        var index: u32 = 0;

        while (index < count) : (index += 1) {
            assert(index < events_max);

            try loop.service(ready[index].data.fd);

            if (loop.quit_requested) {
                return;
            }
        }
    }
}

fn service(loop: *Loop, fd: sys.Fd) PlatformError!void {
    assert(fd >= 0);

    if (loop.client.descriptor()) |bus| {
        if (fd == bus) {
            try loop.drain_bus();

            return;
        }
    }

    if (loop.watcher.descriptor()) |inotify| {
        if (fd == inotify) {
            _ = loop.watcher.drain();

            return;
        }
    }

    if (loop.post_queue.descriptor()) |doorbell| {
        if (fd == doorbell) {
            loop.drain_posts();

            return;
        }
    }

    if (loop.timers.id_of(fd)) |id| {
        _ = TimerTable.drain(fd);

        loop.deliver(.{ .timer_tick = .{ .id = id, .count = 0 } });
    }
}

fn drain_posts(loop: *Loop) void {
    loop.post_queue.drain();

    var delivered: u32 = 0;

    while (delivered < PostQueue.capacity) : (delivered += 1) {
        assert(delivered < PostQueue.capacity);

        const code = loop.post_queue.take() orelse return;

        loop.deliver(.{ .custom = .{ .code = code } });

        if (loop.quit_requested) {
            return;
        }
    }
}

fn drain_bus(loop: *Loop) PlatformError!void {
    const filled = loop.client.fill(false) catch {
        return error.LoopFailed;
    };

    if (filled) {
        try loop.drain_messages();

        return;
    }

    if (loop.client.has_pending()) {
        try loop.drain_messages();
    }
}

fn drain_messages(loop: *Loop) PlatformError!void {
    var messages: u32 = 0;

    while (messages < messages_max) : (messages += 1) {
        const message = loop.client.take_message() catch |err| switch (err) {
            error.Incomplete => return,
            else => return error.LoopFailed,
        };

        if (message.header.kind == .signal) {
            loop.route_signal(message);

            if (loop.quit_requested) {
                return;
            }

            continue;
        }

        if (message.header.kind != .method_call) {
            continue;
        }

        loop.route(message);

        if (loop.quit_requested) {
            return;
        }
    }
}

fn route_signal(loop: *Loop, message: Client.Message) void {
    assert(message.header.kind == .signal);

    if (!Tray.is_watcher_restart(message)) {
        return;
    }

    loop.deliver(.{ .taskbar_restart = {} });
}

fn route(loop: *Loop, message: Client.Message) void {
    assert(message.header.kind == .method_call);

    if (std.mem.eql(u8, message.header.path, Menu.object_path)) {
        switch (loop.menu.handle_call(message)) {
            .about_to_show => loop.deliver(.{ .menu_show = {} }),
            .selected => |id| loop.deliver(.{ .menu_select = .{ .checked = false, .id = id } }),
            .ignored => {},
        }

        return;
    }

    switch (loop.tray.handle_call(message)) {
        .activate => loop.deliver(.{ .tray_left_click = {} }),
        .secondary_activate => loop.deliver(.{ .tray_double_click = {} }),
        .context_menu => loop.deliver(.{ .tray_right_click = {} }),
        .ignored => {},
    }
}

fn deliver(loop: *Loop, payload: Event.Payload) void {
    const pointer = loop.owner orelse return;
    const dispatch = loop.dispatch orelse return;
    const event = Event.create(payload, time.now_ms());

    dispatch(pointer, &event);

    if (interface.is_activation(event.kind())) loop.tray.activation_clear();
}

const testing = std.testing;

const Fixture = struct {
    client: Client,
    icons: IconTable,
    loop: Loop,
    menu: Menu,
    post_queue: PostQueue,
    timers: TimerTable,
    tray: Tray,
    watcher: Watcher,

    fn create() !*Fixture {
        const fixture = try testing.allocator.create(Fixture);

        fixture.client.init();
        fixture.icons.init();
        fixture.menu.init(&fixture.client);
        fixture.post_queue.init();
        fixture.timers.init(&fixture.loop.epoll);
        fixture.tray.init(&fixture.client, &fixture.icons, "umbra");
        fixture.watcher.init(&fixture.loop.epoll);

        fixture.loop.init(.{
            .client = &fixture.client,
            .menu = &fixture.menu,
            .post_queue = &fixture.post_queue,
            .timers = &fixture.timers,
            .tray = &fixture.tray,
            .watcher = &fixture.watcher,
        });

        assert(fixture.loop.owner == null);
        assert(!fixture.client.is_connected());

        return fixture;
    }

    fn destroy(fixture: *Fixture) void {
        assert(fixture.loop.owner == null);

        testing.allocator.destroy(fixture);
    }
};

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
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const collector = Collector.init();

    fixture.loop.deliver(.{ .app_init = {} });

    try testing.expectEqual(@as(u32, 0), collector.count);
    try testing.expect(fixture.loop.owner == null);
}

test "deliver forwards to the installed owner" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    var collector = Collector.init();

    fixture.loop.owner = &collector;
    fixture.loop.dispatch = &DispatchType(Collector).dispatch;

    fixture.loop.deliver(.{ .tray_left_click = {} });

    fixture.loop.owner = null;
    fixture.loop.dispatch = null;

    try testing.expectEqual(@as(u32, 1), collector.count);
    try testing.expectEqual(Event.Kind.tray_left_click, collector.last.?);
}

test "a quit from the owner stops the loop" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const Quitter = struct {
        loop: *Loop,

        pub fn dispatch(quitter: *@This(), _: *const Event) void {
            quitter.loop.quit();
        }
    };

    var quitter = Quitter{ .loop = &fixture.loop };

    fixture.loop.owner = &quitter;
    fixture.loop.dispatch = &DispatchType(Quitter).dispatch;

    fixture.loop.deliver(.{ .tray_left_click = {} });

    const requested = fixture.loop.quit_requested;

    fixture.loop.owner = null;
    fixture.loop.dispatch = null;

    try testing.expect(requested);
}

const Witness = struct {
    kind: ?Event.Kind,
    token: [interface.activation_token_bytes_max]u8,
    token_len: u32,
    tray: *const Tray,

    pub fn dispatch(witness: *Witness, event: *const Event) void {
        const token = witness.tray.activation_token();

        assert(token.len <= interface.activation_token_bytes_max);

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
    interface_name: []const u8,
    member: []const u8,
    body: []const u8,
) Client.Message {
    assert(path.len > 0);
    assert(interface_name.len > 0);
    assert(member.len > 0);
    assert(body.len <= Client.receive_bytes_max);

    var header = wire.Header.empty();

    header.body_length = @intCast(body.len);
    header.interface = interface_name;
    header.kind = .method_call;
    header.member = member;
    header.path = path;
    header.serial = 1;

    return .{ .body = body, .header = header };
}

test "a token from the tray host reaches the next activation and no later one" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const loop = &fixture.loop;
    const token = "gnome-shell/Solopass/2541-0-fedora_TIME51234";

    var witness: Witness = .{ .kind = null, .token = undefined, .token_len = 0, .tray = loop.tray };

    loop.owner = &witness;
    loop.dispatch = &DispatchType(Witness).dispatch;

    defer {
        loop.owner = null;
        loop.dispatch = null;
    }

    var provided: [128]u8 = undefined;
    var provided_writer = wire.Writer.init(&provided);

    try provided_writer.put_string(token);

    var closed: [64]u8 = undefined;
    var closed_writer = wire.Writer.init(&closed);

    try closed_writer.put_i32(0);
    try closed_writer.put_string("closed");

    const provide = "ProvideXdgActivationToken";

    loop.route(call(Tray.object_path, Tray.interface_name, provide, provided_writer.bytes()));
    loop.route(call(Menu.object_path, Menu.interface_name, "Event", closed_writer.bytes()));

    try testing.expect(witness.kind == null);
    try testing.expectEqualStrings(token, loop.tray.activation_token());

    loop.route(call(Tray.object_path, Tray.interface_name, "Activate", &.{}));

    try testing.expectEqual(Event.Kind.tray_left_click, witness.kind.?);
    try testing.expectEqualStrings(token, witness.seen());
    try testing.expectEqualStrings("", loop.tray.activation_token());

    loop.route(call(Tray.object_path, Tray.interface_name, "SecondaryActivate", &.{}));

    try testing.expectEqual(Event.Kind.tray_double_click, witness.kind.?);
    try testing.expectEqualStrings("", witness.seen());
}
