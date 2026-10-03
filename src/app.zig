const std = @import("std");

const event = @import("event/root.zig");
const platform = @import("platform.zig");
const runtime = @import("runtime/root.zig");
const ui = @import("ui/root.zig");

const assert = std.debug.assert;

const Bus = event.Bus;
const Event = event.Event;
const Lifecycle = runtime.Lifecycle;
const Response = event.Response;

const IconManager = ui.IconManager;
const MenuManager = ui.MenuManager;
const NotificationManager = ui.NotificationManager;
const StateManager = ui.StateManager;
const TimerManager = ui.TimerManager;
const TrayManager = ui.TrayManager;

pub const name_max: u32 = 64;
pub const tray_retry_attempt_max: u32 = 60;
pub const tray_retry_interval_ms: u32 = 1000;
pub const tray_retry_timer_id: u32 = std.math.maxInt(u32);

pub const Error = error{
    IconLoadFailed,
    InvalidName,
    InvalidState,
    InvalidTooltip,
    LoopFailed,
    MenuBuildFailed,
    RuntimeOpenFailed,
};

pub const Config = struct {
    initial_state: []const u8 = "",
    name: []const u8,
    tooltip: []const u8 = "",
};

comptime {
    assert(name_max > 1);
    assert(tray_retry_attempt_max > 0);
    assert(tray_retry_interval_ms > 0);
    assert(tray_retry_timer_id > 0);
}

pub const App = struct {
    bus: Bus,
    icon: IconManager,
    lifecycle: Lifecycle,
    menu: MenuManager,
    name: [name_max]u8,
    name_len: u8,
    notification: NotificationManager,
    state: StateManager,
    timer: TimerManager,
    tray: TrayManager,
    tray_failures: u32,
    tray_retry_count: u32,

    pub fn init(app: *App, config: Config) Error!void {
        if (config.name.len == 0 or config.name.len >= name_max) {
            return Error.InvalidName;
        }

        if (!std.unicode.utf8ValidateSlice(config.name)) {
            return Error.InvalidName;
        }

        if (config.tooltip.len >= ui.tray.tooltip_max) {
            return Error.InvalidTooltip;
        }

        if (config.initial_state.len >= ui.state.state_max) {
            return Error.InvalidState;
        }

        const tooltip = if (config.tooltip.len > 0) config.tooltip else config.name;

        app.* = App{
            .bus = Bus.init(),
            .icon = IconManager.init(),
            .lifecycle = Lifecycle.init(),
            .menu = MenuManager.init(),
            .name = @splat(0),
            .name_len = @intCast(config.name.len),
            .notification = NotificationManager.init(),
            .state = StateManager.init(),
            .timer = TimerManager.init(),
            .tray = TrayManager.init(.{ .tooltip = tooltip }),
            .tray_failures = 0,
            .tray_retry_count = 0,
        };

        @memcpy(app.name[0..config.name.len], config.name);

        app.icon.bind(&app.bus);
        app.state.bind(&app.bus);

        if (config.initial_state.len > 0) {
            app.state.set(config.initial_state) catch {
                return Error.InvalidState;
            };
        }

        assert(app.lifecycle.stage == .created);
    }

    pub fn deinit(app: *App) void {
        app.timer.deinit();
        app.menu.deinit();
        app.tray.deinit();
        app.icon.deinit();
        app.bus.deinit();
        app.state.deinit();
        app.notification.deinit();

        app.lifecycle.force_stop();

        assert(app.lifecycle.stage == .stopped);
    }

    pub fn configure(app: *App) *App {
        _ = app.lifecycle.transition(.configured);

        assert(app.lifecycle.stage == .configured);

        return app;
    }

    pub fn get_name(app: *const App) []const u8 {
        assert(app.name_len > 0);
        assert(app.name_len < name_max);

        return app.name[0..app.name_len];
    }

    pub fn is_running(app: *const App) bool {
        return app.lifecycle.is_running();
    }

    pub fn quit(app: *App) void {
        platform.backend.loop.quit();

        _ = app.lifecycle.transition(.stopping);
    }

    pub fn dispatch(app: *App, incoming: *const Event) Response {
        assert(incoming.kind().is_valid());

        const response = switch (incoming.payload) {
            .menu_select => |payload| app.on_menu_select(payload.id),
            .taskbar_restart => app.on_taskbar_restart(),
            .timer_tick => |payload| app.on_timer_tick(payload.id),
            else => app.emit(incoming),
        };

        return response;
    }

    pub fn run(app: *App) Error!void {
        if (app.lifecycle.stage != .configured) {
            return Error.InvalidState;
        }

        platform.backend.runtime.open(.{ .name = app.get_name() }) catch {
            return Error.RuntimeOpenFailed;
        };

        defer platform.backend.runtime.close();

        app.icon.load() catch {
            return Error.IconLoadFailed;
        };

        const handle = app.icon.get_current() orelse return Error.IconLoadFailed;

        app.tray.create(handle) catch {
            app.tray_failures += 1;
        };

        defer app.tray.destroy();

        app.menu.build() catch {
            return Error.MenuBuildFailed;
        };

        _ = app.lifecycle.transition(.running);

        assert(app.lifecycle.is_running());

        app.start_tray_retry();

        const started = Event.app_init();

        _ = app.emit(&started);

        var instance = platform.backend.loop.LoopType(App).init();

        instance.run(app) catch {
            return Error.LoopFailed;
        };

        _ = app.lifecycle.transition(.stopping);

        const stopped = Event.app_shutdown();

        _ = app.emit(&stopped);
    }

    fn emit(app: *App, outgoing: *const Event) Response {
        const response = app.bus.emit(outgoing);

        if (response.should_quit()) {
            app.quit();
        }

        return response;
    }

    fn on_menu_select(app: *App, id: u32) Response {
        const item = app.menu.get_item(id);
        const checked = if (item) |value| value.checked else false;

        const selected = Event.menu_select(id, checked);
        const response = app.emit(&selected);

        return response;
    }

    fn on_taskbar_restart(app: *App) Response {
        const handle = app.icon.get_current();

        app.tray.recreate(handle) catch {
            app.tray_failures += 1;
        };

        const restarted = Event.taskbar_restart();
        const response = app.emit(&restarted);

        return response;
    }

    fn on_timer_tick(app: *App, id: u32) Response {
        if (id == tray_retry_timer_id) {
            const retried = app.on_tray_retry();

            return retried;
        }

        const tick_count = app.timer.handle_tick(id);

        const ticked = Event.timer_tick(id, tick_count);
        const response = app.emit(&ticked);

        return response;
    }

    fn on_tray_retry(app: *App) Response {
        assert(app.tray_retry_count < tray_retry_attempt_max);

        _ = app.timer.handle_tick(tray_retry_timer_id);

        if (app.tray.is_created()) {
            app.stop_tray_retry();

            return .pass;
        }

        app.tray_retry_count += 1;

        const handle = app.icon.get_current();

        app.tray.recreate(handle) catch {
            app.tray_failures += 1;
        };

        if (app.tray.is_created() or app.tray_retry_count >= tray_retry_attempt_max) {
            app.stop_tray_retry();
        }

        return .pass;
    }

    fn start_tray_retry(app: *App) void {
        if (app.tray.is_created()) {
            return;
        }

        assert(app.tray_failures > 0);

        _ = app.timer.start(tray_retry_timer_id, tray_retry_interval_ms) catch {
            return;
        };
    }

    fn stop_tray_retry(app: *App) void {
        assert(app.timer.is_running(tray_retry_timer_id));

        app.timer.stop(tray_retry_timer_id) catch {
            return;
        };
    }
};

const testing = std.testing;

const Stage = runtime.Stage;

test "an application carries the name it was built from" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expectEqualStrings("TestApp", app.get_name());
    try testing.expectEqual(Stage.created, app.lifecycle.stage);
}

test "an application rejects an empty name" {
    var app: App = undefined;

    try testing.expectError(Error.InvalidName, app.init(.{ .name = "" }));
}

test "an application rejects an oversized name" {
    var app: App = undefined;

    const long: [name_max]u8 = @splat('a');

    try testing.expectError(Error.InvalidName, app.init(.{ .name = &long }));
}

test "an application rejects a name that is not valid utf8" {
    var app: App = undefined;

    const invalid = [_]u8{ 0xC3, 0x28 };

    try testing.expectError(Error.InvalidName, app.init(.{ .name = &invalid }));
}

test "an application rejects an oversized initial state" {
    var app: App = undefined;

    const long: [ui.state.state_max]u8 = @splat('a');

    try testing.expectError(
        Error.InvalidState,
        app.init(.{ .name = "TestApp", .initial_state = &long }),
    );
}

test "a fresh application starts with empty managers" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expectEqual(@as(u8, 0), app.bus.handler_count());
    try testing.expect(app.icon.is_empty());
    try testing.expect(app.menu.is_empty());
    try testing.expect(app.state.is_empty());
}

test "an application falls back to its name for the tooltip" {
    var app: App = undefined;

    try app.init(.{ .name = "MyApp" });
    defer app.deinit();

    try testing.expectEqualStrings("MyApp", app.tray.get_tooltip());
}

test "an application rejects an oversized tooltip" {
    var app: App = undefined;

    const long: [ui.tray.tooltip_max]u8 = @splat('a');

    try testing.expectError(Error.InvalidTooltip, app.init(.{ .name = "MyApp", .tooltip = &long }));
}

test "an application copies the name into storage of its own" {
    var app: App = undefined;

    var caller: [8]u8 = undefined;

    @memcpy(caller[0.."Borrowed".len], "Borrowed");

    try app.init(.{ .name = caller[0.."Borrowed".len] });
    defer app.deinit();

    @memset(&caller, 'x');

    try testing.expectEqualStrings("Borrowed", app.get_name());
}

test "an application keeps a tooltip it is given" {
    var app: App = undefined;

    try app.init(.{ .name = "MyApp", .tooltip = "Custom Tooltip" });
    defer app.deinit();

    try testing.expectEqualStrings("Custom Tooltip", app.tray.get_tooltip());
}

test "an application applies the initial state it is given" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp", .initial_state = "idle" });
    defer app.deinit();

    try testing.expectEqualStrings("idle", app.state.get());
}

test "configuring an application transitions the stage and chains" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const chained = app.configure();

    try testing.expectEqual(Stage.configured, app.lifecycle.stage);
    try testing.expectEqual(&app, chained);
}

test "an application is not running before it is run" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expect(!app.is_running());
}

test "an unconfigured application refuses to run" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expectError(Error.InvalidState, app.run());
}

test "tearing down an application lands in the stopped stage" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });

    app.deinit();

    try testing.expectEqual(Stage.stopped, app.lifecycle.stage);
}

test "a neutral event is forwarded to the bus" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const Sink = struct {
        var seen: u32 = 0;

        fn handle(_: *const Event, _: ?*anyopaque) Response {
            seen += 1;

            return .pass;
        }
    };

    Sink.seen = 0;

    _ = app.bus.on(.tray_left_click, Sink.handle, null);

    const clicked = Event.tray_left_click();

    try testing.expectEqual(Response.pass, app.dispatch(&clicked));
    try testing.expectEqual(@as(u32, 1), Sink.seen);
}

test "a dispatched menu event carries the checked flag from the menu" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try app.menu.add_toggle(7, "Enabled", true);

    const Sink = struct {
        var checked: bool = false;

        fn handle(incoming: *const Event, _: ?*anyopaque) Response {
            checked = incoming.payload.menu_select.checked;

            return .pass;
        }
    };

    Sink.checked = false;

    _ = app.bus.on(.menu_select, Sink.handle, null);

    const selected = Event.menu_select(7, false);

    _ = app.dispatch(&selected);

    try testing.expect(Sink.checked);
}

test "dispatched timer ticks are counted" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const Sink = struct {
        var last: u64 = 0;

        fn handle(incoming: *const Event, _: ?*anyopaque) Response {
            last = incoming.payload.timer_tick.tick_count;

            return .pass;
        }
    };

    Sink.last = 0;

    _ = app.bus.on(.timer_tick, Sink.handle, null);

    const ticked = Event.timer_tick(3, 0);

    _ = app.dispatch(&ticked);

    try testing.expectEqual(@as(u64, 0), Sink.last);
}

test "a quit response ends the dispatch loop" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    _ = app.configure();
    _ = app.lifecycle.transition(.running);

    const Sink = struct {
        fn handle(_: *const Event, _: ?*anyopaque) Response {
            return .quit;
        }
    };

    _ = app.bus.on(.tray_left_click, Sink.handle, null);

    const clicked = Event.tray_left_click();

    try testing.expectEqual(Response.quit, app.dispatch(&clicked));
    try testing.expectEqual(Stage.stopping, app.lifecycle.stage);
}
