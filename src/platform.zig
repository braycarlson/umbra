const builtin = @import("builtin");

const interface = @import("platform/interface.zig");

pub const CapacityError = interface.CapacityError;
pub const Icon = interface.Icon;
pub const Listener = interface.Listener;
pub const MenuItem = interface.MenuItem;
pub const MenuItemKind = interface.MenuItemKind;
pub const Notification = interface.Notification;
pub const PlatformError = interface.PlatformError;
pub const RequestError = interface.RequestError;
pub const Timer = interface.Timer;
pub const Watch = interface.Watch;

pub const is_activation = interface.is_activation;
pub const is_valid_layout = interface.is_valid_layout;
pub const is_valid_text = interface.is_valid_text;

pub const activation_token_bytes_max = interface.activation_token_bytes_max;
pub const app_name_bytes_max = interface.app_name_bytes_max;
pub const channel_count = interface.channel_count;
pub const icon_count_max = interface.icon_count_max;
pub const icon_name_bytes_max = interface.icon_name_bytes_max;
pub const menu_depth_max = interface.menu_depth_max;
pub const menu_group_bytes_max = interface.menu_group_bytes_max;
pub const menu_item_count_max = interface.menu_item_count_max;
pub const menu_item_id_max = interface.menu_item_id_max;
pub const menu_label_bytes_max = interface.menu_label_bytes_max;
pub const notification_body_bytes_max = interface.notification_body_bytes_max;
pub const notification_title_bytes_max = interface.notification_title_bytes_max;
pub const path_bytes_max = interface.path_bytes_max;
pub const pixmap_bytes_max = interface.pixmap_bytes_max;
pub const pixmap_dimension_max = interface.pixmap_dimension_max;
pub const timer_count_max = interface.timer_count_max;
pub const timer_id_max = interface.timer_id_max;
pub const timer_interval_ms_max = interface.timer_interval_ms_max;
pub const tooltip_bytes_max = interface.tooltip_bytes_max;
pub const watch_count_max = interface.watch_count_max;

pub const Fake = @import("platform/fake.zig");

pub const Native = switch (builtin.target.os.tag) {
    .linux => @import("platform/linux.zig"),
    .windows => @import("platform/windows.zig"),
    else => @compileError("umbra: unsupported target OS"),
};
