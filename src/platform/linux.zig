const contract = @import("contract.zig");

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

comptime {
    contract.assert_backend(@This());
}
