const contract = @import("contract.zig");

pub const icon = @import("windows/icon.zig");
pub const loop = @import("windows/loop.zig");
pub const menu = @import("windows/menu.zig");
pub const notification = @import("windows/notification.zig");
pub const paths = @import("windows/paths.zig");
pub const runtime = @import("windows/runtime.zig");
pub const shell = @import("windows/shell.zig");
pub const time = @import("windows/time.zig");
pub const timer = @import("windows/timer.zig");
pub const tray = @import("windows/tray.zig");
pub const watcher = @import("windows/watcher/root.zig");

comptime {
    contract.assert_backend(@This());
}
