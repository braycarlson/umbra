const std = @import("std");

const umbra = @import("umbra");

const App = umbra.App;
const Event = umbra.Event;
const IconBuilder = umbra.IconBuilder;
const MenuBuilder = umbra.MenuBuilder;
const Response = umbra.Response;

const MenuId = struct {
    pub const toggle_feature: u32 = 1;
    pub const option_a: u32 = 2;
    pub const option_b: u32 = 3;
    pub const option_c: u32 = 4;
    pub const about: u32 = 5;
    pub const quit: u32 = 6;
};

pub fn main() !void {
    var app: App = undefined;

    try app.init(.{
        .initial_state = "idle",
        .name = "MyTrayApp",
        .tooltip = "My Application",
    });

    defer app.deinit();

    _ = app.configure();

    _ = try IconBuilder.init(&app.icon)
        .stock("default", .application)
        .stock("active", .shield)
        .done();

    _ = try MenuBuilder.init(&app.menu)
        .toggle(MenuId.toggle_feature, "Enable Feature", false)
        .separator()
        .radio(MenuId.option_a, "Option A", "options", true)
        .radio(MenuId.option_b, "Option B", "options", false)
        .radio(MenuId.option_c, "Option C", "options", false)
        .separator()
        .action(MenuId.about, "About")
        .separator()
        .action(MenuId.quit, "Quit")
        .done();

    _ = app.bus.on(.app_init, on_init, &app);
    _ = app.bus.on(.app_shutdown, on_shutdown, null);
    _ = app.bus.on(.menu_select, on_menu_select, &app);
    _ = app.bus.on(.tray_left_click, on_left_click, &app);
    _ = app.bus.on(.tray_double_click, on_double_click, &app);
    _ = app.bus.on(.state_change, on_state_change, &app);
    _ = app.bus.on(.icon_change, on_icon_change, &app);

    try app.run();
}

fn on_init(_: *const Event, context: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(context.?));

    app.notification.send_simple("Started", "Application is running") catch {
        return .pass;
    };

    _ = app.timer.start(1, 1000) catch null;

    return .pass;
}

fn on_shutdown(_: *const Event, _: ?*anyopaque) Response {
    return .pass;
}

fn on_menu_select(incoming: *const Event, context: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(context.?));
    const payload = incoming.payload.menu_select;

    switch (payload.id) {
        MenuId.toggle_feature => {
            const enabled = app.menu.toggle_item(MenuId.toggle_feature) catch false;
            const name = if (enabled) "active" else "default";

            app.icon.set_current(name) catch {
                return .handled;
            };

            return .handled;
        },
        MenuId.option_a, MenuId.option_b, MenuId.option_c => {
            app.menu.set_checked(payload.id, true) catch {
                return .handled;
            };

            return .handled;
        },
        MenuId.about => {
            app.notification.send_simple("About", "MyTrayApp v1.0.0") catch {
                return .handled;
            };

            return .handled;
        },
        MenuId.quit => {
            return .quit;
        },
        else => {},
    }

    return .pass;
}

fn on_left_click(_: *const Event, context: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(context.?));
    const next = if (app.state.equals("idle")) "active" else "idle";

    app.state.set(next) catch {
        return .handled;
    };

    return .handled;
}

fn on_double_click(_: *const Event, context: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(context.?));

    app.notification.send_simple("Double Click", "You clicked twice") catch {
        return .handled;
    };

    return .handled;
}

fn on_state_change(incoming: *const Event, context: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(context.?));
    const payload = incoming.payload.state_change;

    const active = std.mem.eql(u8, payload.to, "active");
    const icon_name = if (active) "active" else "default";
    const tooltip = if (active) "Active Mode" else "Idle Mode";

    app.icon.set_current(icon_name) catch {
        return .pass;
    };

    app.tray.set_tooltip(tooltip) catch {
        return .pass;
    };

    return .pass;
}

fn on_icon_change(incoming: *const Event, context: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(context.?));
    const payload = incoming.payload.icon_change;

    const handle = app.icon.get(payload.name) orelse return .pass;

    app.tray.set_icon(handle) catch {
        return .pass;
    };

    return .pass;
}
