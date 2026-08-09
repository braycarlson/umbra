const builtin = @import("builtin");
const build_options = @import("build_options");

const contract = @import("platform/contract.zig");

pub const Capabilities = contract.Capabilities;
pub const IconError = contract.IconError;
pub const IconSource = contract.IconSource;
pub const MenuItem = contract.MenuItem;
pub const MenuItemKind = contract.MenuItemKind;
pub const MenuError = contract.MenuError;
pub const NotificationError = contract.NotificationError;
pub const NotificationKind = contract.NotificationKind;
pub const NotificationOptions = contract.NotificationOptions;
pub const Pixmap = contract.Pixmap;
pub const RuntimeOptions = contract.RuntimeOptions;
pub const Stock = contract.Stock;
pub const TimerError = contract.TimerError;
pub const TrayError = contract.TrayError;
pub const WatchCallback = contract.WatchCallback;

pub const pixmap_bytes_max = contract.pixmap_bytes_max;
pub const pixmap_dimension_max = contract.pixmap_dimension_max;

pub const backend = if (build_options.backend_mock)
    @import("platform/mock.zig")
else switch (builtin.os.tag) {
    .linux => @import("platform/linux.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("wisp: unsupported target OS"),
};

pub const mock = if (build_options.backend_mock)
    backend
else
    @compileError("wisp: mock surface requires -Dbackend=mock");

pub const capabilities: Capabilities = backend.capabilities;

comptime {
    contract.assert_backend(backend);
}
