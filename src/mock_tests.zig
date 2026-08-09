const std = @import("std");

const app_mod = @import("app.zig");
const event = @import("event/root.zig");
const mock = @import("platform/mock.zig");
const platform = @import("platform.zig");
const root = @import("root.zig");

const App = app_mod.App;
const Event = event.Event;
const Response = event.Response;

test {
    _ = @import("platform/mock.zig");
    _ = @import("platform/mock/balloon.zig");
    _ = @import("platform/mock/icon.zig");
    _ = @import("platform/mock/loop.zig");
    _ = @import("platform/mock/menu.zig");
    _ = @import("platform/mock/notification.zig");
    _ = @import("platform/mock/paths.zig");
    _ = @import("platform/mock/record.zig");
    _ = @import("platform/mock/runtime.zig");
    _ = @import("platform/mock/shell.zig");
    _ = @import("platform/mock/taskbar.zig");
    _ = @import("platform/mock/time.zig");
    _ = @import("platform/mock/timer.zig");
    _ = @import("platform/mock/tray.zig");
    _ = @import("platform/mock/watcher.zig");
    _ = @import("platform/mock/window.zig");
}

const Counters = struct {
    var double_clicks: u32 = 0;
    var inits: u32 = 0;
    var menu_selects: u32 = 0;
    var quit_after_menu: bool = false;
    var shutdowns: u32 = 0;
    var ticks: u64 = 0;
    var tray_clicks: u32 = 0;

    fn reset() void {
        double_clicks = 0;
        inits = 0;
        menu_selects = 0;
        quit_after_menu = false;
        shutdowns = 0;
        ticks = 0;
        tray_clicks = 0;
    }

    fn on_init(_: *const Event, _: ?*anyopaque) Response {
        inits += 1;

        return .pass;
    }

    fn on_shutdown(_: *const Event, _: ?*anyopaque) Response {
        shutdowns += 1;

        return .pass;
    }

    fn on_tray_click(_: *const Event, _: ?*anyopaque) Response {
        tray_clicks += 1;

        return .pass;
    }

    fn on_double_click(_: *const Event, _: ?*anyopaque) Response {
        double_clicks += 1;

        return .pass;
    }

    fn on_timer(incoming: *const Event, _: ?*anyopaque) Response {
        ticks = incoming.payload.timer_tick.tick_count;

        return .pass;
    }

    fn on_menu(_: *const Event, _: ?*anyopaque) Response {
        menu_selects += 1;

        if (quit_after_menu) {
            return .quit;
        }

        return .pass;
    }
};

fn build_app(app: *App) !void {
    try app.init(.{
        .initial_state = "idle",
        .name = "MockApp",
        .tooltip = "Mock Tooltip",
    });

    _ = try root.IconBuilder.init(&app.icon)
        .stock("default", .application)
        .stock("active", .shield)
        .done();

    _ = try root.MenuBuilder.init(&app.menu)
        .toggle(1, "Enable Feature", false)
        .separator()
        .action(2, "Quit")
        .done();

    _ = app.configure();
}

const testing = std.testing;

test "the mock backend reports every capability" {
    try testing.expect(platform.capabilities.balloon);
    try testing.expect(platform.capabilities.icon_resource);
    try testing.expect(platform.capabilities.taskbar_restart);
    try testing.expect(platform.capabilities.window_message);
}

test "a full run opens the runtime, creates the tray, and shuts down" {
    mock.reset();
    Counters.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    _ = app.bus.on(.app_init, Counters.on_init, null);
    _ = app.bus.on(.app_shutdown, Counters.on_shutdown, null);

    try app.run();

    try testing.expectEqual(@as(u32, 1), Counters.inits);
    try testing.expectEqual(@as(u32, 1), Counters.shutdowns);
    try testing.expectEqual(@as(u32, 1), mock.runtime.counts().opened);
    try testing.expectEqual(@as(u32, 1), mock.runtime.counts().closed);
    try testing.expectEqual(@as(u32, 1), mock.tray.counts().created);
    try testing.expectEqual(@as(u32, 1), mock.tray.counts().destroyed);
    try testing.expectEqualStrings("Mock Tooltip", mock.tray.current_tooltip());
    try testing.expectEqual(@as(u32, 1), mock.menu.counts().built);
    try testing.expectEqual(@as(u32, 1), mock.menu.counts().destroyed);
    try testing.expectEqual(@as(u32, 0), mock.menu.item_count());
}

test "closing the runtime tears down the tray, the menu, and the timers" {
    mock.reset();
    Counters.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    const Sink = struct {
        var app_pointer: ?*App = null;
        var items: u32 = 0;
        var timers: u32 = 0;

        fn handle(_: *const Event, _: ?*anyopaque) Response {
            const live = app_pointer orelse return .pass;

            _ = live.timer.start(9, 100) catch return .pass;

            items = mock.menu.item_count();
            timers = mock.timer.active_count();

            return .pass;
        }
    };

    Sink.app_pointer = &app;
    Sink.items = 0;
    Sink.timers = 0;

    _ = app.bus.on(.app_init, Sink.handle, null);

    try app.run();

    try testing.expectEqual(@as(u32, 3), Sink.items);
    try testing.expectEqual(@as(u32, 1), Sink.timers);
    try testing.expect(!mock.tray.is_created());
    try testing.expectEqual(@as(u32, 0), mock.menu.item_count());
    try testing.expectEqual(@as(u32, 0), mock.timer.active_count());
}

test "a scripted tape drives tray clicks, timer ticks, and menu selection" {
    mock.reset();
    Counters.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    const Starter = struct {
        var app_pointer: ?*App = null;

        fn handle(_: *const Event, _: ?*anyopaque) Response {
            const live = app_pointer orelse return .pass;

            _ = live.timer.start(1, 100) catch return .pass;

            return .pass;
        }
    };

    Starter.app_pointer = &app;

    _ = app.bus.on(.app_init, Starter.handle, null);
    _ = app.bus.on(.tray_left_click, Counters.on_tray_click, null);
    _ = app.bus.on(.tray_double_click, Counters.on_double_click, null);
    _ = app.bus.on(.timer_tick, Counters.on_timer, null);
    _ = app.bus.on(.menu_select, Counters.on_menu, null);

    try mock.loop.push(Event.tray_left_click());
    try mock.loop.push(Event.tray_double_click());
    try mock.loop.push(Event.timer_tick(1, 0));
    try mock.loop.push(Event.timer_tick(1, 0));
    try mock.loop.push(Event.menu_select(1, false));

    try app.run();

    try testing.expectEqual(@as(u32, 1), Counters.tray_clicks);
    try testing.expectEqual(@as(u32, 1), Counters.double_clicks);
    try testing.expectEqual(@as(u64, 2), Counters.ticks);
    try testing.expectEqual(@as(u32, 1), Counters.menu_selects);
    try testing.expectEqual(@as(u32, 5), mock.loop.dispatch_count());
}

test "a quit response stops the tape and the lifecycle" {
    mock.reset();
    Counters.reset();

    Counters.quit_after_menu = true;

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    _ = app.bus.on(.menu_select, Counters.on_menu, null);

    try mock.loop.push(Event.menu_select(2, false));
    try mock.loop.push(Event.tray_left_click());

    try app.run();

    try testing.expectEqual(@as(u32, 1), Counters.menu_selects);
    try testing.expectEqual(@as(u32, 1), mock.loop.pending_count());
    try testing.expectEqual(root.Stage.stopping, app.lifecycle.stage);
}

test "menu selection reports the model checked state" {
    mock.reset();
    Counters.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try app.menu.set_checked(1, true);

    const Sink = struct {
        var checked: bool = false;

        fn handle(incoming: *const Event, _: ?*anyopaque) Response {
            checked = incoming.payload.menu_select.checked;

            return .pass;
        }
    };

    Sink.checked = false;

    _ = app.bus.on(.menu_select, Sink.handle, null);

    try mock.loop.push(Event.menu_select(1, false));

    try app.run();

    try testing.expect(Sink.checked);
}

test "a taskbar restart recreates the tray icon" {
    mock.reset();
    Counters.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try mock.loop.push(Event.taskbar_restart());

    try app.run();

    try testing.expectEqual(@as(u32, 0), app.tray_failures);
    try testing.expectEqual(@as(u32, 2), mock.tray.counts().created);
}

test "icon selection reaches the backend through the tray manager" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    const Sink = struct {
        var app_pointer: ?*App = null;

        fn handle(incoming: *const Event, context: ?*anyopaque) Response {
            _ = context;

            const live = app_pointer orelse return .pass;
            const selected = live.icon.get(incoming.payload.icon_change.name) orelse
                return .pass;

            live.tray.set_icon(selected) catch {
                return .pass;
            };

            return .pass;
        }
    };

    Sink.app_pointer = &app;

    _ = app.bus.on(.icon_change, Sink.handle, null);

    try app.run();

    try app.icon.set_current("active");

    try testing.expectEqual(@as(u32, 2), mock.icon.counts().loaded);
}

test "the notification manager records through the backend" {
    mock.reset();

    var manager = root.NotificationManager.init();
    defer manager.deinit();

    try manager.send_simple("Started", "Application is running");
    try manager.send_warning("Careful", "Something looks odd");

    try testing.expectEqual(@as(u32, 2), mock.notification.sent_count());
    try testing.expectEqualStrings("Started", mock.notification.title_at(0));
    try testing.expectEqual(platform.NotificationKind.warning, mock.notification.kind_at(1).?);
    try testing.expectEqual(@as(u32, 2), manager.sent_count());
}

test "the tray manager forwards balloons to the backend" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try app.run();

    try mock.runtime.open(.{ .name = "MockApp" });
    defer mock.runtime.close();

    try app.tray.create(null);
    try app.tray.show_balloon_info("Title", "Body");

    try testing.expect(mock.balloon.is_visible());
    try testing.expectEqualStrings("Title", mock.balloon.current_title());

    try app.tray.hide_balloon();

    try testing.expect(!mock.balloon.is_visible());
}

test "the timer manager mirrors the backend timer table" {
    mock.reset();

    try mock.runtime.open(.{ .name = "MockApp" });
    defer mock.runtime.close();

    var manager = root.TimerManager.init();
    defer manager.deinit();

    _ = try manager.start(1, 250);
    _ = try manager.start(2, 500);

    try testing.expectEqual(@as(u32, 2), mock.timer.active_count());
    try testing.expectEqual(@as(?u32, 250), mock.timer.interval_of(1));

    try manager.stop(1);

    try testing.expectEqual(@as(u32, 1), mock.timer.active_count());

    manager.stop_all();

    try testing.expectEqual(@as(u32, 0), mock.timer.active_count());
}

test "a failing backend surfaces a typed application error" {
    mock.reset();

    mock.runtime.set_fail_open(true);

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try testing.expectError(app_mod.Error.RuntimeOpenFailed, app.run());

    mock.runtime.set_fail_open(false);
}

test "a tray the shell rejects leaves the application running behind a retry timer" {
    mock.reset();

    mock.tray.set_fail_create(true);

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try app.run();

    try testing.expect(!app.tray.is_created());
    try testing.expectEqual(@as(u32, 1), app.tray_failures);
    try testing.expectEqual(@as(u32, 0), app.tray_retry_count);
    try testing.expect(app.timer.is_running(app_mod.tray_retry_timer_id));

    mock.tray.set_fail_create(false);
}

test "a retry tick claims the tray once the shell accepts it" {
    mock.reset();

    const Sink = struct {
        fn on_init(_: *const Event, _: ?*anyopaque) Response {
            mock.tray.set_fail_create(false);

            return .pass;
        }
    };

    mock.tray.set_fail_create(true);

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    _ = app.bus.on(.app_init, Sink.on_init, null);

    try mock.loop.push(Event.timer_tick(app_mod.tray_retry_timer_id, 0));

    try app.run();

    try testing.expectEqual(@as(u32, 1), app.tray_failures);
    try testing.expectEqual(@as(u32, 1), app.tray_retry_count);
    try testing.expectEqual(@as(u32, 1), mock.tray.counts().created);
    try testing.expect(!app.timer.is_running(app_mod.tray_retry_timer_id));
}

test "the watcher contract fires the registered callback" {
    mock.reset();

    const Sink = struct {
        var fired: u32 = 0;

        fn handle(_: ?*anyopaque) void {
            fired += 1;
        }
    };

    Sink.fired = 0;

    const handle = try root.watcher.watch("config.json", Sink.handle, null);

    try testing.expect(mock.watcher.fire(handle));
    try testing.expectEqual(@as(u32, 1), Sink.fired);

    root.watcher.unwatch(handle);

    try testing.expect(!mock.watcher.fire(handle));
}

test "the gated window module posts through the backend" {
    mock.reset();

    try testing.expect(root.window.handle() == null);

    try mock.runtime.open(.{ .name = "MockApp" });
    defer mock.runtime.close();

    try testing.expect(root.window.handle() != null);
    try testing.expect(root.window.post(0x0010, 0, 0));
    try testing.expectEqual(@as(?u32, 0x0010), mock.window.posted_message(0));
}

test "the gated taskbar module recognises its restart message" {
    mock.reset();

    try testing.expect(root.taskbar.is_restart(root.taskbar.restart_message()));
    try testing.expect(!root.taskbar.is_restart(root.taskbar.restart_message() + 1));
}

test "the gated icon_resource helper builds a resource source" {
    const source = root.icon_resource(42);

    try testing.expectEqual(@as(u32, 42), source.resource);
    try testing.expect(source.is_valid());
}

const Example = struct {
    var app_pointer: ?*App = null;
    var state_changes: u32 = 0;

    fn on_left_click(_: *const Event, context: ?*anyopaque) Response {
        const app: *App = @ptrCast(@alignCast(context.?));
        const next = if (app.state.equals("idle")) "active" else "idle";

        app.state.set(next) catch {
            return .handled;
        };

        return .handled;
    }

    fn on_state_change(incoming: *const Event, context: ?*anyopaque) Response {
        const app: *App = @ptrCast(@alignCast(context.?));
        const payload = incoming.payload.state_change;

        state_changes += 1;

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
};

test "a left click flips the state and updates the icon and the tooltip" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    Example.app_pointer = &app;
    Example.state_changes = 0;

    _ = app.bus.on(.tray_left_click, Example.on_left_click, &app);
    _ = app.bus.on(.state_change, Example.on_state_change, &app);
    _ = app.bus.on(.icon_change, Example.on_icon_change, &app);

    try mock.loop.push(Event.tray_left_click());

    const active_handle = mock.tray.icon_handle();

    try app.run();

    try testing.expectEqual(@as(u32, 1), Example.state_changes);
    try testing.expectEqualStrings("active", app.state.get());
    try testing.expectEqualStrings("active", app.icon.get_current_name().?);
    try testing.expectEqualStrings("Active Mode", app.tray.get_tooltip());
    try testing.expectEqualStrings("Active Mode", mock.tray.current_tooltip());
    try testing.expectEqual(@as(u32, 1), mock.tray.counts().tooltips);
    try testing.expectEqual(@as(u32, 1), mock.tray.counts().icons);
    try testing.expect(active_handle == null);
}

test "closing the runtime releases the file watchers" {
    mock.reset();

    const Sink = struct {
        fn handle(_: ?*anyopaque) void {}
    };

    try mock.runtime.open(.{ .name = "MockApp" });

    _ = try root.watcher.watch("config.json", Sink.handle, null);
    _ = try root.watcher.watch("other.json", Sink.handle, null);

    try testing.expectEqual(@as(u32, 2), mock.watcher.active_count());

    mock.runtime.close();

    try testing.expectEqual(@as(u32, 0), mock.watcher.active_count());
    try testing.expectEqual(@as(u32, 2), mock.watcher.counts().unwatched);
}

test "the virtual clock stamps events monotonically" {
    mock.reset();

    const first = Event.app_init();

    mock.time.advance(50);

    const second = Event.app_init();

    try testing.expectEqual(mock.time.base_ms, first.timestamp_ms);
    try testing.expectEqual(mock.time.base_ms + 50, second.timestamp_ms);
}
