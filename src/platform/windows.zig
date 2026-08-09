const std = @import("std");

const contract = @import("contract.zig");

const assert = std.debug.assert;

pub const balloon = @import("windows/balloon.zig");
pub const icon = @import("windows/icon.zig");
pub const loop = @import("windows/loop.zig");
pub const menu = @import("windows/menu.zig");
pub const notification = @import("windows/notification.zig");
pub const paths = @import("windows/paths.zig");
pub const runtime = @import("windows/runtime.zig");
pub const taskbar = @import("windows/taskbar.zig");
pub const shell = @import("windows/shell.zig");
pub const time = @import("windows/time.zig");
pub const timer = @import("windows/timer.zig");
pub const tray = @import("windows/tray.zig");
pub const watcher = @import("windows/watcher/root.zig");
pub const window = @import("windows/window.zig");

pub const capabilities: contract.Capabilities = .{
    .balloon = true,
    .icon_resource = true,
    .taskbar_restart = true,
    .window_message = true,
};

comptime {
    assert(capabilities.balloon);
    assert(capabilities.icon_resource);
    assert(capabilities.taskbar_restart);
    assert(capabilities.window_message);

    contract.assert_backend(@This());
}
