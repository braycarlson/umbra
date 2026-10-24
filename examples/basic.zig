const std = @import("std");

const umbra = @import("umbra");

const App = umbra.App;
const Event = umbra.Event;

const MenuId = struct {
    pub const toggle_feature: u32 = 1;
    pub const option_a: u32 = 2;
    pub const option_b: u32 = 3;
    pub const option_c: u32 = 4;
    pub const settings: u32 = 5;
    pub const about: u32 = 6;
    pub const quit: u32 = 7;
};

const app_name = "MyTrayApp";
const settings_name = "settings.zon";
const heartbeat_id: u32 = 1;
const heartbeat_interval_ms: u32 = 1000;

const Mode = enum(u8) {
    active = 0,
    idle = 1,
};

const Example = struct {
    app: *App,
    beats: u64 = 0,
    mode: Mode = .idle,
    settings: [umbra.limits.path_bytes_max]u8 = undefined,
    settings_len: u32 = 0,
    watch: ?umbra.watcher.Watch = null,

    pub fn on_app_init(example: *Example) void {
        example.notify("Started", "Application is running");

        const heartbeat = umbra.TimerSet.Timer{
            .id = heartbeat_id,
            .interval_ms = heartbeat_interval_ms,
        };

        example.app.timers.start(heartbeat) catch |err| {
            std.log.warn("heartbeat refused: {t}", .{err});
        };

        example.watch_settings();
    }

    pub fn on_app_shutdown(example: *Example) void {
        const watch = example.watch orelse return;

        umbra.watcher.unwatch(watch);

        example.watch = null;
    }

    pub fn on_menu_select(example: *Example, selection: Event.Selection) void {
        switch (selection.id) {
            MenuId.toggle_feature => example.toggle_feature(selection.checked),
            MenuId.option_a, MenuId.option_b, MenuId.option_c => example.select(selection.id),
            MenuId.settings => example.open_settings(),
            MenuId.about => example.notify("About", "MyTrayApp v1.0.0"),
            MenuId.quit => example.app.quit(),
            else => {},
        }
    }

    pub fn on_timer_tick(example: *Example, tick: Event.Tick) void {
        if (tick.id != heartbeat_id) {
            return;
        }

        example.beats = tick.tick_count;
    }

    pub fn on_tray_double_click(example: *Example) void {
        example.notify("Double Click", "You clicked twice");
    }

    pub fn on_tray_left_click(example: *Example) void {
        example.mode = if (example.mode == .idle) .active else .idle;

        const icon_name = if (example.mode == .active) "active" else "default";
        const tooltip = if (example.mode == .active) "Active Mode" else "Idle Mode";

        example.app.icons.set_current(icon_name) catch |err| {
            std.log.warn("icon refused: {t}", .{err});
        };

        example.app.tray.set_tooltip(tooltip) catch |err| {
            std.log.warn("tooltip refused: {t}", .{err});
        };
    }

    fn notify(example: *Example, title: []const u8, body: []const u8) void {
        example.app.notifier.send(.{ .body = body, .title = title }) catch |err| {
            std.log.warn("notification refused: {t}", .{err});
        };
    }

    fn on_settings_changed(example: *Example) void {
        example.notify("Settings", "The settings file changed");
    }

    fn open_settings(example: *Example) void {
        if (example.settings_len == 0) {
            return;
        }

        umbra.shell.open(example.settings[0..example.settings_len]) catch |err| {
            std.log.warn("settings refused: {t}", .{err});
        };
    }

    fn rebuild(example: *Example) void {
        example.app.menu.build() catch |err| {
            std.log.warn("menu refused: {t}", .{err});
        };
    }

    fn select(example: *Example, id: u32) void {
        example.app.menu.update(id, .{ .checked = true }) catch |err| {
            std.log.warn("option refused: {t}", .{err});
        };

        example.rebuild();
    }

    fn toggle_feature(example: *Example, checked: bool) void {
        const enabled = !checked;

        example.app.menu.update(MenuId.toggle_feature, .{ .checked = enabled }) catch |err| {
            std.log.warn("toggle refused: {t}", .{err});
        };

        example.rebuild();
    }

    fn watch_settings(example: *Example) void {
        var directory: [umbra.limits.path_bytes_max]u8 = undefined;

        const base = umbra.paths.config_dir(&directory, app_name) catch |err| {
            std.log.warn("settings directory refused: {t}", .{err});

            return;
        };

        const path = std.fmt.bufPrint(&example.settings, "{s}{c}{s}", .{
            base,
            std.Io.Dir.path.sep,
            settings_name,
        }) catch {
            return;
        };

        example.settings_len = @intCast(path.len);

        const changed = Example.on_settings_changed;

        example.watch = umbra.watcher.watch(path, Example, example, changed) catch |err| blk: {
            std.log.warn("settings watch refused: {t}", .{err});

            break :blk null;
        };
    }
};

pub fn main() !void {
    var app: App = undefined;

    try app.init(.{ .name = app_name, .tooltip = "My Application" });
    defer app.deinit();

    _ = try umbra.IconBuilder.init(&app.icons)
        .stock("default", .application)
        .stock("active", .shield)
        .done();

    _ = try umbra.MenuBuilder.init(&app.menu)
        .toggle(MenuId.toggle_feature, "Enable Feature", .{})
        .separator()
        .radio(MenuId.option_a, "Option A", .{ .checked = true, .group = "options" })
        .radio(MenuId.option_b, "Option B", .{ .group = "options" })
        .radio(MenuId.option_c, "Option C", .{ .group = "options" })
        .separator()
        .action(MenuId.settings, "Settings")
        .action(MenuId.about, "About")
        .separator()
        .action(MenuId.quit, "Quit")
        .done();

    var example = Example{ .app = &app };

    try app.bus.attach(Example, &example);
    try app.run();
}
