const std = @import("std");

const contract = @import("contract.zig");

const assert = std.debug.assert;

pub const icon = @import("linux/icon.zig");
pub const loop = @import("linux/loop.zig");
pub const menu = @import("linux/menu.zig");
pub const notification = @import("linux/notification.zig");
pub const paths = @import("linux/paths.zig");
pub const runtime = @import("linux/runtime.zig");
pub const shell = @import("linux/shell.zig");
pub const time = @import("linux/time.zig");
pub const timer = @import("linux/timer.zig");
pub const tray = @import("linux/tray.zig");
pub const watcher = @import("linux/watcher.zig");

pub const capabilities: contract.Capabilities = .{
    .balloon = false,
    .icon_resource = false,
    .taskbar_restart = false,
    .window_message = false,
};

comptime {
    assert(!capabilities.balloon);
    assert(!capabilities.icon_resource);
    assert(!capabilities.taskbar_restart);
    assert(!capabilities.window_message);

    contract.assert_backend(@This());
}
