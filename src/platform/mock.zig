const std = @import("std");

const contract = @import("contract.zig");

const assert = std.debug.assert;

pub const balloon = @import("mock/balloon.zig");
pub const icon = @import("mock/icon.zig");
pub const loop = @import("mock/loop.zig");
pub const menu = @import("mock/menu.zig");
pub const notification = @import("mock/notification.zig");
pub const paths = @import("mock/paths.zig");
pub const record = @import("mock/record.zig");
pub const runtime = @import("mock/runtime.zig");
pub const taskbar = @import("mock/taskbar.zig");
pub const shell = @import("mock/shell.zig");
pub const time = @import("mock/time.zig");
pub const timer = @import("mock/timer.zig");
pub const tray = @import("mock/tray.zig");
pub const watcher = @import("mock/watcher.zig");
pub const window = @import("mock/window.zig");

pub const capabilities: contract.Capabilities = .{
    .balloon = true,
    .icon_resource = true,
    .taskbar_restart = true,
    .window_message = true,
};

comptime {
    contract.assert_backend(@This());
}

pub fn reset() void {
    balloon.reset();
    icon.reset();
    loop.reset();
    menu.reset();
    notification.reset();
    runtime.reset();
    taskbar.reset();
    time.reset();
    timer.reset();
    tray.reset();
    watcher.reset();
    window.reset();

    assert(!runtime.is_open());
    assert(!tray.is_created());
    assert(loop.dispatch_count() == 0);
}

const testing = std.testing;

test "every capability is available on the mock backend" {
    try testing.expect(capabilities.balloon);
    try testing.expect(capabilities.icon_resource);
    try testing.expect(capabilities.taskbar_restart);
    try testing.expect(capabilities.window_message);
}

test "reset clears every module tape" {
    reset();

    try runtime.open(.{ .name = "umbra" });

    const handle = try icon.load(.{ .stock = .application });

    try tray.create(.{ .icon = handle, .id = 1, .tooltip = "umbra" });
    try notification.send(.{ .body = "b", .title = "t" });
    try timer.start(1, 100);
    try loop.push(@import("../event/types.zig").Event.app_init());

    time.advance(500);

    reset();

    try testing.expect(!runtime.is_open());
    try testing.expect(!tray.is_created());
    try testing.expectEqual(@as(u32, 0), icon.live_count());
    try testing.expectEqual(@as(u32, 0), notification.sent_count());
    try testing.expectEqual(@as(u32, 0), timer.active_count());
    try testing.expectEqual(@as(u32, 0), loop.pending_count());
    try testing.expectEqual(time.base_ms, time.now_ms());
}
