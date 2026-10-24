const std = @import("std");

const app_module = @import("app.zig");
const builder_module = @import("builder.zig");
const bus_module = @import("bus.zig");
const event_module = @import("event.zig");
const icon_module = @import("ui/icon.zig");
const loop_module = @import("loop.zig");
const menu_module = @import("ui/menu.zig");
const notification_module = @import("ui/notification.zig");
const paths_module = @import("paths.zig");
const platform = @import("platform.zig");
const shell_module = @import("shell.zig");
const time_module = @import("time.zig");
const timer_module = @import("ui/timer.zig");
const tray_module = @import("ui/tray.zig");
const watcher_module = @import("watcher.zig");

pub const App = app_module.App;
pub const Bus = bus_module.Bus;
pub const CapacityError = platform.CapacityError;
pub const Error = CapacityError || PlatformError || RequestError;
pub const Event = event_module.Event;
pub const Icon = platform.Icon;
pub const IconBuilder = builder_module.IconBuilder;
pub const IconSet = icon_module.IconSet;
pub const Menu = menu_module.Menu;
pub const MenuBuilder = builder_module.MenuBuilder;
pub const Notifier = notification_module.Notifier;
pub const PlatformError = platform.PlatformError;
pub const RequestError = platform.RequestError;
pub const TimerSet = timer_module.TimerSet;
pub const Tray = tray_module.Tray;

pub const loop = struct {
    pub const post = loop_module.post;
};

pub const mock = platform.mock;

pub const paths = struct {
    pub const config_dir = paths_module.config_dir;
    pub const state_dir = paths_module.state_dir;
};

pub const shell = struct {
    pub const open = shell_module.open;
};

pub const time = struct {
    pub const now_ms = time_module.now_ms;
};

pub const watcher = struct {
    pub const Watch = platform.Watch;

    pub const unwatch = watcher_module.unwatch;
    pub const watch = watcher_module.watch;
};

pub const limits = struct {
    pub const app_name_bytes_max = platform.app_name_bytes_max;
    pub const icon_count_max = platform.icon_count_max;
    pub const icon_name_bytes_max = platform.icon_name_bytes_max;
    pub const listener_count_max = bus_module.listener_count_max;
    pub const menu_group_bytes_max = platform.menu_group_bytes_max;
    pub const menu_item_count_max = platform.menu_item_count_max;
    pub const menu_item_id_max = platform.menu_item_id_max;
    pub const menu_label_bytes_max = platform.menu_label_bytes_max;
    pub const notification_body_bytes_max = platform.notification_body_bytes_max;
    pub const notification_title_bytes_max = platform.notification_title_bytes_max;
    pub const path_bytes_max = platform.path_bytes_max;
    pub const pending_count_max = bus_module.pending_count_max;
    pub const pixmap_bytes_max = platform.pixmap_bytes_max;
    pub const pixmap_dimension_max = platform.pixmap_dimension_max;
    pub const timer_count_max = platform.timer_count_max;
    pub const timer_interval_ms_max = platform.timer_interval_ms_max;
    pub const tooltip_bytes_max = platform.tooltip_bytes_max;
    pub const watch_count_max = platform.watch_count_max;
};

const testing = std.testing;

const Owner = struct {
    selected: u32 = 0,

    pub fn on_menu_select(owner: *Owner, selection: Event.Selection) void {
        owner.selected = selection.id;
    }
};

test Error {
    mock.reset();

    var app: App = undefined;

    const sized: CapacityError = error.NameTooLong;
    const long: [limits.app_name_bytes_max + 1]u8 = @splat('a');

    try testing.expectError(sized, app.init(.{ .name = &long }));

    try app.init(.{ .name = "example" });
    defer app.deinit();

    const asked: RequestError = error.IconsEmpty;
    const failure: Error = asked;

    try testing.expectError(failure, app.run());
}

test CapacityError {
    var icons = IconSet.init();
    defer icons.deinit();

    const long: [limits.icon_name_bytes_max + 1]u8 = @splat('i');
    const refused: CapacityError = error.NameTooLong;

    try testing.expectError(refused, icons.add(&long, .{ .stock = .application }));
}

test PlatformError {
    mock.reset();

    mock.fault.arm(.runtime_open);
    defer mock.fault.reset();

    var app: App = undefined;

    try app.init(.{ .name = "example" });
    defer app.deinit();

    _ = try IconBuilder.init(&app.icons).stock("default", .application).done();

    const refused: PlatformError = error.RuntimeOpenFailed;

    try testing.expectError(refused, app.run());
}

test RequestError {
    var menu = Menu.init();
    defer menu.deinit();

    const refused: RequestError = error.ItemUnknown;

    try testing.expectError(refused, menu.update(7, .{ .checked = true }));
}

test Icon {
    mock.reset();

    const rgba = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
    const pixmap = Icon.Pixmap.from_rgba(&rgba, 2);

    var icons = IconSet.init();
    defer icons.deinit();

    try icons.add("badge", .{ .pixels = pixmap });
    try icons.add("shield", .{ .stock = .shield });
    try icons.load();

    try testing.expectEqual(@as(u32, 2), pixmap.height);
    try testing.expect(icons.get_current() != null);
}

test App {
    mock.reset();

    var app: App = undefined;

    try app.init(.{ .name = "example", .tooltip = "Example" });
    defer app.deinit();

    var owner = Owner{};

    _ = try IconBuilder.init(&app.icons).stock("default", .application).done();
    _ = try MenuBuilder.init(&app.menu).action(2, "Quit").done();

    try app.bus.attach(Owner, &owner);
    try mock.loop.push(Event.create(.{ .menu_select = .{ .checked = false, .id = 2 } }));
    try app.run();

    try testing.expectEqual(@as(u32, 2), owner.selected);
    try testing.expect(!mock.tray.is_created());
}

test limits {
    try testing.expect(limits.icon_name_bytes_max < limits.app_name_bytes_max);
    try testing.expect(limits.app_name_bytes_max < limits.tooltip_bytes_max);
    try testing.expect(limits.notification_title_bytes_max < limits.notification_body_bytes_max);
    try testing.expect(limits.watch_count_max > 0);
    try testing.expect(limits.pending_count_max <= limits.listener_count_max);

    const side: u32 = limits.pixmap_dimension_max;

    try testing.expectEqual(side * side * 4, limits.pixmap_bytes_max);
}

test "the root surface resolves on the mock backend" {
    testing.refAllDecls(@This());
    testing.refAllDecls(limits);
    testing.refAllDecls(loop);
    testing.refAllDecls(paths);
    testing.refAllDecls(shell);
    testing.refAllDecls(time);
    testing.refAllDecls(watcher);
}
