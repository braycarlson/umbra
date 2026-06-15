const std = @import("std");
const testing = std.testing;

const wisp = @import("wisp");

const App = wisp.App;
const Config = wisp.AppConfig;
const Stage = wisp.Stage;

test "App.init creates app with name" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expectEqualStrings("TestApp", app.config.name);
}

test "App.init sets lifecycle to created" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expectEqual(Stage.created, app.lifecycle.stage);
}

test "App.init creates empty bus" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expectEqual(@as(u8, 0), app.bus.handler_count());
}

test "App.init creates empty icon manager" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expect(app.icon.is_empty());
}

test "App.init creates empty menu manager" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expect(app.menu.is_empty());
}

test "App.init uses name as tooltip when not specified" {
    var app: App = undefined;
    app.init(.{ .name = "MyApp" });
    defer app.deinit();

    try testing.expectEqualStrings("MyApp", app.tray.get_tooltip());
}

test "App.init uses custom tooltip when specified" {
    var app: App = undefined;
    app.init(.{ .name = "MyApp", .tooltip = "Custom Tooltip" });
    defer app.deinit();

    try testing.expectEqualStrings("Custom Tooltip", app.tray.get_tooltip());
}

test "App.init sets initial state when specified" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp", .initial_state = "idle" });
    defer app.deinit();

    try testing.expectEqualStrings("idle", app.state.get());
}

test "App.init leaves state empty when not specified" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expect(app.state.is_empty());
}

test "App.init converts name to wide string" {
    var app: App = undefined;
    app.init(.{ .name = "Test" });
    defer app.deinit();

    try testing.expectEqual(@as(u16, 'T'), app.name_wide[0]);
    try testing.expectEqual(@as(u16, 'e'), app.name_wide[1]);
    try testing.expectEqual(@as(u16, 's'), app.name_wide[2]);
    try testing.expectEqual(@as(u16, 't'), app.name_wide[3]);
    try testing.expectEqual(@as(u16, 0), app.name_wide[4]);
}

test "App.configure transitions to configured state" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    _ = app.configure();

    try testing.expectEqual(Stage.configured, app.lifecycle.stage);
}

test "App.configure returns self for chaining" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const result = app.configure();

    try testing.expectEqual(&app, result);
}

test "App.is_running returns false initially" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expect(!app.is_running());
}

test "App.get_hwnd returns null before run" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expect(app.get_hwnd() == null);
}

test "App.event_bus returns bus pointer" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const bus = app.event_bus();

    try testing.expectEqual(&app.bus, bus);
}

test "App.get_icon returns icon manager pointer" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const icon_mgr = app.get_icon();

    try testing.expectEqual(&app.icon, icon_mgr);
}

test "App.get_menu returns menu manager pointer" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const menu_mgr = app.get_menu();

    try testing.expectEqual(&app.menu, menu_mgr);
}

test "App.get_notification returns notification manager pointer" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const notif_mgr = app.get_notification();

    try testing.expectEqual(&app.notification, notif_mgr);
}

test "App.get_state returns state manager pointer" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const state_mgr = app.get_state();

    try testing.expectEqual(&app.state, state_mgr);
}

test "App.get_timer returns timer manager pointer" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const timer_mgr = app.get_timer();

    try testing.expectEqual(&app.timer, timer_mgr);
}

test "App.get_tray returns tray manager pointer" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const tray_mgr = app.get_tray();

    try testing.expectEqual(&app.tray, tray_mgr);
}

test "App.run returns error when not configured" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const result = app.run();

    try testing.expectError(wisp.AppError.InvalidState, result);
}

test "App.post_message returns false when window is null" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const result = app.post_message(0x0010, 0, 0);

    try testing.expect(!result);
}

test "App.deinit transitions to stopped state" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });

    app.deinit();

    try testing.expectEqual(Stage.stopped, app.lifecycle.stage);
}

test "App.deinit clears window" {
    var app: App = undefined;
    app.init(.{ .name = "TestApp" });

    app.deinit();

    try testing.expect(app.window == null);
}
