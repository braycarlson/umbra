const std = @import("std");

const w32 = @import("win32.zig");

const contract = @import("../contract.zig");
const event_module = @import("../../event.zig");
const menu = @import("menu.zig");
const taskbar = @import("taskbar.zig");
const tray = @import("tray.zig");
const watcher = @import("watcher/root.zig");
const window = @import("window.zig");

const assert = std.debug.assert;

const Event = event_module.Event;
const PlatformError = contract.PlatformError;

pub const iteration_max: u64 = 1 << 48;
pub const message_custom: u32 = w32.WM_APP + 2;
const Dispatch = *const fn (*anyopaque, *const Event) void;

var owner_pointer: ?*anyopaque = null;
var dispatch_fn: ?Dispatch = null;

comptime {
    assert(iteration_max > 0);
    assert(message_custom > w32.WM_APP);
    assert(message_custom != tray.message);
}

pub fn quit() void {
    w32.PostQuitMessage(0);
}

pub fn post(code: u32) bool {
    return window.post(message_custom, code, 0);
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

            instance.started = true;

            owner_pointer = owner;
            dispatch_fn = &thunk;
            defer {
                owner_pointer = null;
                dispatch_fn = null;
            }

            try pump();
        }

        fn thunk(pointer: *anyopaque, event: *const Event) void {
            const typed: *Owner = @ptrCast(@alignCast(pointer));

            typed.dispatch(event);
        }
    };
}

pub fn window_proc(
    hwnd: w32.HWND,
    message: u32,
    wparam: w32.WPARAM,
    lparam: w32.LPARAM,
) callconv(.winapi) w32.LRESULT {
    return handle_message(hwnd, message, wparam, lparam);
}

fn pump() PlatformError!void {
    assert(owner_pointer != null);
    assert(dispatch_fn != null);

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

fn deliver(event: *const Event) void {
    assert(event.kind().is_valid());

    const pointer = owner_pointer orelse return;
    const dispatch = dispatch_fn orelse return;

    dispatch(pointer, event);
}

fn handle_message(
    hwnd: w32.HWND,
    message: u32,
    wparam: w32.WPARAM,
    lparam: w32.LPARAM,
) w32.LRESULT {
    if (taskbar.is_restart(message)) {
        deliver(&Event.create(.{ .taskbar_restart = {} }));

        return 0;
    }

    if (watcher.is_change(message)) {
        watcher.deliver(wparam);

        return 0;
    }

    if (message == tray.message) {
        handle_tray(lparam);

        return 0;
    }

    if (message == message_custom) {
        const code: u32 = @truncate(wparam);

        deliver(&Event.create(.{ .custom = .{ .code = code } }));

        return 0;
    }

    switch (message) {
        w32.WM_TIMER => {
            const id: u32 = @intCast(wparam);

            deliver(&Event.create(.{ .timer_tick = .{ .id = id, .tick_count = 0 } }));

            return 0;
        },
        w32.WM_DESTROY => {
            quit();

            return 0;
        },
        else => {},
    }

    return w32.DefWindowProcW(hwnd, message, wparam, lparam);
}

fn handle_tray(lparam: w32.LPARAM) void {
    const parsed = tray.Notification.parse(lparam) orelse return;

    switch (parsed) {
        .left_click => deliver(&Event.create(.{ .tray_left_click = {} })),
        .left_double_click => deliver(&Event.create(.{ .tray_double_click = {} })),
        .right_click => deliver(&Event.create(.{ .tray_right_click = {} })),
        .context_menu => handle_context_menu(),
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

fn handle_context_menu() void {
    deliver(&Event.create(.{ .menu_show = {} }));

    const selected = menu.track() orelse return;

    deliver(&Event.create(.{ .menu_select = .{ .checked = false, .id = selected } }));
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

test "deliver is inert until a loop installs an owner" {
    owner_pointer = null;
    dispatch_fn = null;

    const collector = Collector.init();

    deliver(&Event.create(.{ .app_init = {} }));

    try testing.expectEqual(@as(u32, 0), collector.count);
    try testing.expect(owner_pointer == null);
}

test "LoopType installs and removes the owner thunk" {
    var collector = Collector.init();

    owner_pointer = &collector;
    dispatch_fn = &LoopType(Collector).thunk;

    deliver(&Event.create(.{ .app_init = {} }));

    owner_pointer = null;
    dispatch_fn = null;

    try testing.expectEqual(@as(u32, 1), collector.count);
    try testing.expectEqual(Event.Kind.app_init, collector.last.?);
}
