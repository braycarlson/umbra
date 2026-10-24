const builtin = @import("builtin");
const build_options = @import("build_options");

const contract = @import("platform/contract.zig");

pub const CapacityError = contract.CapacityError;
pub const Icon = contract.Icon;
pub const Listener = contract.Listener;
pub const MenuItem = contract.MenuItem;
pub const MenuItemKind = contract.MenuItemKind;
pub const Notification = contract.Notification;
pub const PlatformError = contract.PlatformError;
pub const RequestError = contract.RequestError;
pub const Timer = contract.Timer;
pub const Watch = contract.Watch;

pub const is_valid_text = contract.is_valid_text;

pub const app_name_bytes_max = contract.app_name_bytes_max;
pub const channel_count = contract.channel_count;
pub const icon_count_max = contract.icon_count_max;
pub const icon_name_bytes_max = contract.icon_name_bytes_max;
pub const menu_group_bytes_max = contract.menu_group_bytes_max;
pub const menu_item_count_max = contract.menu_item_count_max;
pub const menu_item_id_max = contract.menu_item_id_max;
pub const menu_label_bytes_max = contract.menu_label_bytes_max;
pub const notification_body_bytes_max = contract.notification_body_bytes_max;
pub const notification_title_bytes_max = contract.notification_title_bytes_max;
pub const path_bytes_max = contract.path_bytes_max;
pub const pixmap_bytes_max = contract.pixmap_bytes_max;
pub const pixmap_dimension_max = contract.pixmap_dimension_max;
pub const timer_count_max = contract.timer_count_max;
pub const timer_interval_ms_max = contract.timer_interval_ms_max;
pub const tooltip_bytes_max = contract.tooltip_bytes_max;
pub const watch_count_max = contract.watch_count_max;

pub const backend = if (build_options.backend_mock)
    @import("platform/mock.zig")
else switch (builtin.target.os.tag) {
    .linux => @import("platform/linux.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("umbra: unsupported target OS"),
};

pub const mock = if (build_options.backend_mock)
    backend
else
    @compileError("umbra: mock surface requires -Dbackend=mock");

comptime {
    contract.assert_backend(backend);
}
