pub const icon = @import("icon.zig");
pub const menu = @import("menu.zig");
pub const notification = @import("notification.zig");
pub const state = @import("state.zig");
pub const timer = @import("timer.zig");
pub const tray = @import("tray.zig");

pub const IconManager = icon.IconManager;
pub const IconEntry = icon.Entry;
pub const IconHandle = icon.Handle;
pub const IconPixmap = icon.Pixmap;
pub const IconSource = icon.Source;
pub const IconStock = icon.Stock;
pub const IconError = icon.Error;

pub const MenuManager = menu.MenuManager;
pub const MenuItem = menu.Item;
pub const MenuItemKind = menu.ItemKind;
pub const MenuError = menu.Error;

pub const NotificationManager = notification.NotificationManager;
pub const Notification = notification.Notification;
pub const NotificationIcon = notification.Icon;
pub const NotificationError = notification.Error;

pub const StateManager = state.StateManager;
pub const StateTransition = state.Transition;
pub const StateError = state.Error;

pub const TimerManager = timer.TimerManager;
pub const TimerHandle = timer.Handle;
pub const TimerError = timer.Error;

pub const TrayManager = tray.TrayManager;
pub const TrayConfig = tray.Config;
pub const TrayError = tray.Error;
pub const TrayBalloonIcon = tray.BalloonIcon;
