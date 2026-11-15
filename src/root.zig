const std = @import("std");

const app_module = @import("app.zig");
const bus_module = @import("bus.zig");
const event_module = @import("event.zig");
const platform = @import("platform.zig");

const assert = std.debug.assert;

pub const App = AppType(platform.Native);
pub const AppType = app_module.AppType;
pub const Bus = bus_module.Bus;
pub const CapacityError = platform.CapacityError;
pub const Error = CapacityError || PlatformError || RequestError;
pub const Event = event_module.Event;
pub const Fake = platform.Fake;
pub const Icon = platform.Icon;
pub const IconBuilder = App.IconBuilder;
pub const IconSet = App.IconSet;
pub const Menu = App.Menu;
pub const MenuBuilder = App.MenuBuilder;
pub const Notifier = App.Notifier;
pub const PlatformError = platform.PlatformError;
pub const RequestError = platform.RequestError;
pub const TimerSet = App.TimerSet;
pub const Tray = App.Tray;
pub const Watch = platform.Watch;

pub const limits = struct {
    pub const activation_token_bytes_max = platform.activation_token_bytes_max;
    pub const app_name_bytes_max = platform.app_name_bytes_max;
    pub const icon_count_max = platform.icon_count_max;
    pub const icon_name_bytes_max = platform.icon_name_bytes_max;
    pub const listener_count_max = bus_module.listener_count_max;
    pub const menu_depth_max = platform.menu_depth_max;
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
    pub const timer_id_max = platform.timer_id_max;
    pub const timer_interval_ms_max = platform.timer_interval_ms_max;
    pub const tooltip_bytes_max = platform.tooltip_bytes_max;
    pub const watch_count_max = platform.watch_count_max;
};

const testing = std.testing;

const FakeApp = AppType(Fake);

const Owner = struct {
    selected: u32 = 0,

    pub fn on_menu_select(owner: *Owner, selection: Event.Selection) void {
        assert(selection.id <= platform.menu_item_id_max);

        owner.selected = selection.id;
    }
};

test Error {
    var app: FakeApp = undefined;

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
    var app: FakeApp = undefined;

    try app.init(.{ .name = "example" });
    defer app.deinit();

    const long: [limits.icon_name_bytes_max + 1]u8 = @splat('i');
    const refused: CapacityError = error.NameTooLong;

    try testing.expectError(refused, app.icons.add(&long, .{ .stock = .application }));
}

test PlatformError {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "example" });
    defer app.deinit();

    app.platform.fault.arm(.icon_load);

    _ = try FakeApp.IconBuilder.init(&app.icons).stock("default", .application).done();

    const refused: PlatformError = error.IconLoadFailed;

    try testing.expectError(refused, app.run());
}

test RequestError {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "example" });
    defer app.deinit();

    const refused: RequestError = error.ItemUnknown;

    try testing.expectError(refused, app.menu.update(7, .{ .checked = true }));
}

test Icon {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "example" });
    defer app.deinit();

    const rgba = [_]u8{ 255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255 };
    const pixmap = Icon.Pixmap.from_rgba(&rgba, 2);

    try app.icons.add("badge", .{ .pixels = pixmap });
    try app.icons.add("shield", .{ .stock = .shield });
    try app.icons.load();

    try testing.expectEqual(@as(u32, 2), pixmap.height);
    try testing.expect(app.icons.get_current() != null);
}

test App {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "example", .tooltip = "Example" });
    defer app.deinit();

    var owner = Owner{};

    _ = try FakeApp.IconBuilder.init(&app.icons).stock("default", .application).done();
    _ = try FakeApp.MenuBuilder.init(&app.menu).action(2, "Quit").done();

    const selection = Event.Selection{ .checked = false, .id = 2 };

    try app.bus.attach(Owner, &owner);
    try app.platform.loop.push(Event.create(.{ .menu_select = selection }, app.now_ms()));
    try app.run();

    try testing.expectEqual(@as(u32, 2), owner.selected);
    try testing.expect(!app.platform.tray.is_created());
}

test limits {
    try testing.expect(limits.icon_name_bytes_max < limits.app_name_bytes_max);
    try testing.expect(limits.app_name_bytes_max < limits.tooltip_bytes_max);
    try testing.expect(limits.notification_title_bytes_max < limits.notification_body_bytes_max);
    try testing.expect(limits.watch_count_max > 0);
    try testing.expect(limits.pending_count_max <= limits.listener_count_max);
    try testing.expect(limits.menu_depth_max < limits.menu_item_count_max);

    const side: u32 = limits.pixmap_dimension_max;

    try testing.expectEqual(side * side * 4, limits.pixmap_bytes_max);
}

test "the root surface resolves" {
    testing.refAllDecls(@This());
    testing.refAllDecls(limits);
}
