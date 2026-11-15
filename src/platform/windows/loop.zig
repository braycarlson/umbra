const std = @import("std");

const w32 = @import("win32.zig");

const event_module = @import("../../event.zig");
const interface = @import("../interface.zig");
const Menu = @import("menu.zig");
const Taskbar = @import("taskbar.zig");
const time = @import("time.zig");
const Tray = @import("tray.zig");
const Watcher = @import("watcher.zig");
const Window = @import("window.zig");

const assert = std.debug.assert;

const Event = event_module.Event;
const PlatformError = interface.PlatformError;

const Loop = @This();

dispatch: ?Dispatch,
menu: *const Menu,
owner: ?*anyopaque,
taskbar: *const Taskbar,
watcher: *const Watcher,
window: *const Window,

pub const Options = struct {
    menu: *const Menu,
    taskbar: *const Taskbar,
    watcher: *const Watcher,
    window: *const Window,
};

const Dispatch = *const fn (*anyopaque, *const Event) void;

pub const iteration_max: u64 = 1 << 48;
pub const message_custom: u32 = w32.WM_APP + 2;

comptime {
    assert(iteration_max > 0);
    assert(message_custom > w32.WM_APP);
    assert(message_custom != Tray.message);
}

pub fn init(loop: *Loop, options: Options) void {
    loop.* = .{
        .dispatch = null,
        .menu = options.menu,
        .owner = null,
        .taskbar = options.taskbar,
        .watcher = options.watcher,
        .window = options.window,
    };

    assert(loop.owner == null);
    assert(loop.dispatch == null);
}

pub fn quit() void {
    w32.PostQuitMessage(0);
}

pub fn post(loop: *const Loop, code: Event.Code) bool {
    return loop.window.post(message_custom, @backingInt(code), 0);
}

pub fn run(loop: *Loop, comptime Owner: type, owner: *Owner) PlatformError!void {
    assert(loop.owner == null);
    assert(loop.window.is_open());

    loop.owner = owner;
    loop.dispatch = &DispatchType(Owner).dispatch;
    defer {
        loop.owner = null;
        loop.dispatch = null;
    }

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

pub fn window_proc(
    hwnd: w32.HWND,
    message: u32,
    wparam: w32.WPARAM,
    lparam: w32.LPARAM,
) callconv(.winapi) w32.LRESULT {
    if (message == w32.WM_NCCREATE) {
        const create: *const w32.CREATESTRUCTW = @ptrFromInt(@as(usize, @bitCast(lparam)));

        const context = create.lpCreateParams orelse return w32.DefWindowProcW(
            hwnd,
            message,
            wparam,
            lparam,
        );

        _ = w32.SetWindowLongPtrW(hwnd, w32.GWLP_USERDATA, @bitCast(@intFromPtr(context)));

        return w32.DefWindowProcW(hwnd, message, wparam, lparam);
    }

    const stored = w32.GetWindowLongPtrW(hwnd, w32.GWLP_USERDATA);

    if (stored == 0) {
        return w32.DefWindowProcW(hwnd, message, wparam, lparam);
    }

    const loop: *const Loop = @ptrFromInt(@as(usize, @bitCast(stored)));

    assert(loop.window.handle == null or loop.window.handle == hwnd);

    return handle_message(loop, hwnd, message, wparam, lparam);
}

fn pump(loop: *const Loop) PlatformError!void {
    assert(loop.owner != null);
    assert(loop.dispatch != null);

    var message: w32.MSG = undefined;
    var iteration: u64 = 0;

    while (iteration < iteration_max) : (iteration += 1) {
        const status = w32.GetMessageW(&message, null, 0, 0);

        if (status < 0) {
            return error.LoopFailed;
        }

        if (status == 0) {
            return;
        }

        _ = w32.TranslateMessage(&message);
        _ = w32.DispatchMessageW(&message);
    }
}

fn deliver(loop: *const Loop, payload: Event.Payload) void {
    const pointer = loop.owner orelse return;
    const dispatch = loop.dispatch orelse return;
    const event = Event.create(payload, time.now_ms());

    assert(event.kind().is_valid());

    dispatch(pointer, &event);
}

fn handle_message(
    loop: *const Loop,
    hwnd: w32.HWND,
    message: u32,
    wparam: w32.WPARAM,
    lparam: w32.LPARAM,
) w32.LRESULT {
    assert(loop.window.handle == null or loop.window.handle == hwnd);

    if (loop.taskbar.is_restart(message)) {
        loop.deliver(.{ .taskbar_restart = {} });

        return 0;
    }

    if (loop.watcher.is_change(message)) {
        _ = loop.watcher.deliver(wparam);

        return 0;
    }

    if (message == Tray.message) {
        loop.handle_tray(lparam);

        return 0;
    }

    if (message == message_custom) {
        if (wparam > std.math.maxInt(u32)) return 0;

        const code: u32 = @intCast(wparam);

        loop.deliver(.{ .custom = .{ .code = @fromBackingInt(code) } });

        return 0;
    }

    switch (message) {
        w32.WM_TIMER => {
            if (std.math.cast(u32, wparam)) |id| {
                loop.deliver(.{ .timer_tick = .{ .id = id, .count = 0 } });

                return 0;
            }
        },
        w32.WM_DESTROY => {
            quit();

            return 0;
        },
        else => {},
    }

    return w32.DefWindowProcW(hwnd, message, wparam, lparam);
}

fn handle_tray(loop: *const Loop, lparam: w32.LPARAM) void {
    const parsed = Tray.Notification.parse(lparam) orelse return;

    switch (parsed) {
        .left_click => loop.deliver(.{ .tray_left_click = {} }),
        .left_double_click => loop.deliver(.{ .tray_double_click = {} }),
        .right_click => loop.deliver(.{ .tray_right_click = {} }),
        .context_menu => loop.handle_context_menu(),
        .balloon_click,
        .balloon_hide,
        .balloon_show,
        .balloon_timeout,
        .key_select,
        .left_button_down,
        .middle_button_down,
        .middle_button_up,
        .middle_double_click,
        .mouse_move,
        .popup_close,
        .popup_open,
        .right_button_down,
        .right_double_click,
        .select,
        => {},
    }
}

fn handle_context_menu(loop: *const Loop) void {
    loop.deliver(.{ .menu_show = {} });

    const selected = loop.menu.track() orelse return;

    loop.deliver(.{ .menu_select = .{ .checked = false, .id = selected } });
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

const Fixture = struct {
    loop: Loop,
    menu: Menu,
    taskbar: Taskbar,
    watcher: Watcher,
    window: Window,

    fn init(fixture: *Fixture) void {
        fixture.window = .closed;
        fixture.taskbar = .unregistered;
        fixture.menu.init(&fixture.window);
        fixture.watcher.init(&fixture.window);

        fixture.loop.init(.{
            .menu = &fixture.menu,
            .taskbar = &fixture.taskbar,
            .watcher = &fixture.watcher,
            .window = &fixture.window,
        });

        assert(fixture.loop.owner == null);
        assert(!fixture.window.is_open());
    }
};

test "deliver is inert until a loop installs an owner" {
    var fixture: Fixture = undefined;

    fixture.init();

    const collector = Collector.init();

    fixture.loop.deliver(.{ .app_init = {} });

    try testing.expectEqual(@as(u32, 0), collector.count);
    try testing.expect(fixture.loop.owner == null);
}

test "a loop forwards each delivered event to the installed owner" {
    var fixture: Fixture = undefined;

    fixture.init();

    var collector = Collector.init();

    fixture.loop.owner = &collector;
    fixture.loop.dispatch = &DispatchType(Collector).dispatch;

    fixture.loop.deliver(.{ .app_init = {} });

    fixture.loop.owner = null;
    fixture.loop.dispatch = null;

    try testing.expectEqual(@as(u32, 1), collector.count);
    try testing.expectEqual(Event.Kind.app_init, collector.last.?);
}
