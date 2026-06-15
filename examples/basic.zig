const std = @import("std");

const tray = @import("wisp");

const App = tray.App;
const Event = tray.Event;
const Response = tray.Response;
const IconBuilder = tray.IconBuilder;
const MenuBuilder = tray.MenuBuilder;

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
    app.init(.{
        .name = "MyTrayApp",
        .tooltip = "My Application",
        .initial_state = "idle",
    });

    defer app.deinit();

    _ = app.configure();

    _ = try IconBuilder.init(app.get_icon())
        .system("default", .application)
        .system("active", .shield)
        .done();

    _ = try MenuBuilder.init(app.get_menu())
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

    _ = app.event_bus().on(.app_init, on_init, &app);
    _ = app.event_bus().on(.app_shutdown, on_shutdown, null);
    _ = app.event_bus().on(.menu_select, on_menu_select, &app);
    _ = app.event_bus().on(.tray_left_click, on_left_click, &app);
    _ = app.event_bus().on(.tray_double_click, on_double_click, &app);
    _ = app.event_bus().on(.state_change, on_state_change, &app);
    _ = app.event_bus().on(.icon_change, on_icon_change, &app);

    try app.run();
}

fn on_init(e: *const Event, ctx: ?*anyopaque) Response {
    _ = e;

    const app: *App = @ptrCast(@alignCast(ctx.?));

    app.get_notification().send_simple("Started", "Application is running") catch {};

    _ = app.get_timer().start(1, 1000) catch null;

    return .pass;
}

fn on_shutdown(e: *const Event, ctx: ?*anyopaque) Response {
    _ = e;
    _ = ctx;

    return .pass;
}

fn on_menu_select(e: *const Event, ctx: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(ctx.?));
    const data = e.payload.menu_select;

    switch (data.id) {
        MenuId.toggle_feature => {
            const new_state = app.get_menu().toggle_item(MenuId.toggle_feature) catch false;

            if (new_state) {
                app.get_icon().set_current("active") catch {};
            } else {
                app.get_icon().set_current("default") catch {};
            }

            return .handled;
        },
        MenuId.option_a, MenuId.option_b, MenuId.option_c => {
            app.get_menu().set_checked(data.id, true) catch {};

            return .handled;
        },
        MenuId.about => {
            app.get_notification().send_simple("About", "MyTrayApp v1.0.0") catch {};

            return .handled;
        },
        MenuId.quit => {
            return .quit;
        },
        else => {},
    }

    return .pass;
}

fn on_left_click(e: *const Event, ctx: ?*anyopaque) Response {
    _ = e;

    const app: *App = @ptrCast(@alignCast(ctx.?));
    const state = app.get_state();

    if (state.equals("idle")) {
        state.set("active") catch {};
    } else if (state.equals("active")) {
        state.set("idle") catch {};
    }

    return .handled;
}

fn on_double_click(e: *const Event, ctx: ?*anyopaque) Response {
    _ = e;

    const app: *App = @ptrCast(@alignCast(ctx.?));

    app.get_notification().send_simple("Double Click", "You double-clicked the tray icon") catch {};

    return .handled;
}

fn on_state_change(e: *const Event, ctx: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(ctx.?));
    const data = e.payload.state_change;

    if (std.mem.eql(u8, data.to, "active")) {
        app.get_icon().set_current("active") catch {};
        app.get_tray().set_tooltip("Active Mode") catch {};
    } else if (std.mem.eql(u8, data.to, "idle")) {
        app.get_icon().set_current("default") catch {};
        app.get_tray().set_tooltip("Idle Mode") catch {};
    }

    return .pass;
}

fn on_icon_change(e: *const Event, ctx: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(ctx.?));
    const data = e.payload.icon_change;

    const icon = app.get_icon().get(data.name) orelse return .pass;

    app.get_tray().set_icon(icon) catch {};

    return .pass;
}
