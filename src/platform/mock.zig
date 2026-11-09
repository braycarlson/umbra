const std = @import("std");

const contract = @import("contract.zig");
const event_module = @import("../event.zig");

const assert = std.debug.assert;

pub const fault = @import("mock/fault.zig");
pub const icon = @import("mock/icon.zig");
pub const loop = @import("mock/loop.zig");
pub const menu = @import("mock/menu.zig");
pub const notification = @import("mock/notification.zig");
pub const paths = @import("mock/paths.zig");
pub const record = @import("mock/record.zig");
pub const runtime = @import("mock/runtime.zig");
pub const shell = @import("mock/shell.zig");
pub const time = @import("mock/time.zig");
pub const timer = @import("mock/timer.zig");
pub const tray = @import("mock/tray.zig");
pub const watcher = @import("mock/watcher.zig");

comptime {
    contract.assert_backend(@This());
}

pub fn reset() void {
    fault.reset();
    icon.reset();
    loop.reset();
    menu.reset();
    notification.reset();
    runtime.reset();
    shell.reset();
    time.reset();
    timer.reset();
    tray.reset();
    watcher.reset();

    assert(!runtime.is_open());
    assert(!tray.is_created());
    assert(loop.dispatch_count() == 0);
}

const testing = std.testing;

test "reset clears every module tape" {
    reset();

    try runtime.open(.{ .name = "umbra" });

    const handle = try icon.load(.{ .stock = .application });

    try tray.create(.{ .icon = handle, .tooltip = "umbra" });
    try notification.send(.{ .body = "b", .title = "t" });
    try timer.start(.{ .id = 1, .interval_ms = 100 });
    try loop.push(event_module.Event.create(.{ .app_init = {} }));

    time.advance(500);
    fault.arm(.tray_create);

    reset();

    try testing.expect(!runtime.is_open());
    try testing.expect(!tray.is_created());
    try testing.expect(!fault.is_armed(.tray_create));
    try testing.expectEqual(@as(u32, 0), icon.live_count());
    try testing.expectEqual(@as(u32, 0), notification.sent_count());
    try testing.expectEqual(@as(u32, 0), timer.active_count());
    try testing.expectEqual(@as(u32, 0), loop.pending_count());
    try testing.expectEqual(time.base_ms, time.now_ms());
}
