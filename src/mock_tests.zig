const std = @import("std");

const app_mod = @import("app.zig");
const umbra = @import("root.zig");

const assert = std.debug.assert;

const App = umbra.App;
const Event = umbra.Event;
const mock = umbra.mock;
const testing = std.testing;

test {
    _ = @import("loop.zig");
    _ = @import("paths.zig");
    _ = @import("platform/mock.zig");
    _ = @import("platform/mock/fault.zig");
    _ = @import("platform/mock/icon.zig");
    _ = @import("platform/mock/loop.zig");
    _ = @import("platform/mock/menu.zig");
    _ = @import("platform/mock/notification.zig");
    _ = @import("platform/mock/paths.zig");
    _ = @import("platform/mock/record.zig");
    _ = @import("platform/mock/runtime.zig");
    _ = @import("platform/mock/shell.zig");
    _ = @import("platform/mock/time.zig");
    _ = @import("platform/mock/timer.zig");
    _ = @import("platform/mock/tray.zig");
    _ = @import("platform/mock/watcher.zig");
    _ = @import("root.zig");
    _ = @import("shell.zig");
    _ = @import("time.zig");
    _ = @import("watcher.zig");
}

const Counters = struct {
    app: *App,
    double_clicks: u32 = 0,
    inits: u32 = 0,
    items: u32 = 0,
    menu_selects: u32 = 0,
    quit_after_menu: bool = false,
    selected_checked: bool = false,
    shutdowns: u32 = 0,
    ticks: u64 = 0,
    timers: u32 = 0,
    tray_clicks: u32 = 0,

    pub fn on_app_init(counters: *Counters) void {
        counters.inits += 1;
        counters.items = mock.menu.item_count();

        counters.app.timers.start(.{ .id = 1, .interval_ms = 100 }) catch {
            return;
        };

        counters.timers = mock.timer.active_count();
    }

    pub fn on_app_shutdown(counters: *Counters) void {
        counters.shutdowns += 1;
    }

    pub fn on_menu_select(counters: *Counters, selection: Event.Selection) void {
        assert(selection.id <= umbra.limits.menu_item_id_max);

        counters.menu_selects += 1;
        counters.selected_checked = selection.checked;

        if (counters.quit_after_menu) {
            counters.app.quit();
        }
    }

    pub fn on_timer_tick(counters: *Counters, tick: Event.Tick) void {
        assert(tick.tick_count > 0);

        counters.ticks = tick.tick_count;
    }

    pub fn on_tray_double_click(counters: *Counters) void {
        counters.double_clicks += 1;
    }

    pub fn on_tray_left_click(counters: *Counters) void {
        counters.tray_clicks += 1;
    }
};

fn build_app(app: *App) !void {
    try app.init(.{ .name = "MockApp", .tooltip = "Mock Tooltip" });

    _ = try umbra.IconBuilder.init(&app.icons)
        .stock("default", .application)
        .stock("active", .shield)
        .done();

    _ = try umbra.MenuBuilder.init(&app.menu)
        .toggle(1, "Enable Feature", .{})
        .separator()
        .action(2, "Quit")
        .done();
}

test "a full run opens the runtime, creates the tray, and shuts down" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var counters = Counters{ .app = &app };

    try app.bus.attach(Counters, &counters);
    try app.run();

    try testing.expectEqual(@as(u32, 1), counters.inits);
    try testing.expectEqual(@as(u32, 1), counters.shutdowns);
    try testing.expectEqual(@as(u32, 1), mock.runtime.counts().opened);
    try testing.expectEqual(@as(u32, 1), mock.runtime.counts().closed);
    try testing.expectEqual(@as(u32, 1), mock.tray.counts().created);
    try testing.expectEqual(@as(u32, 1), mock.tray.counts().destroyed);
    try testing.expectEqualStrings("Mock Tooltip", mock.tray.tooltip_current());
    try testing.expectEqual(@as(u32, 1), mock.menu.counts().built);
    try testing.expectEqual(@as(u32, 1), mock.menu.counts().destroyed);
}

test "closing the runtime tears down the tray, the menu, and the timers" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var counters = Counters{ .app = &app };

    try app.bus.attach(Counters, &counters);
    try app.run();

    try testing.expectEqual(@as(u32, 3), counters.items);
    try testing.expectEqual(@as(u32, 1), counters.timers);
    try testing.expect(!mock.tray.is_created());
    try testing.expectEqual(@as(u32, 0), mock.menu.item_count());
    try testing.expectEqual(@as(u32, 0), mock.timer.active_count());
}

test "a scripted tape drives tray clicks, timer ticks, and menu selection" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var counters = Counters{ .app = &app };

    try app.bus.attach(Counters, &counters);

    try mock.loop.push(Event.create(.{ .tray_left_click = {} }));
    try mock.loop.push(Event.create(.{ .tray_double_click = {} }));
    try mock.loop.push(Event.create(.{ .timer_tick = .{ .id = 1, .tick_count = 0 } }));
    try mock.loop.push(Event.create(.{ .timer_tick = .{ .id = 1, .tick_count = 0 } }));
    try mock.loop.push(Event.create(.{ .menu_select = .{ .checked = false, .id = 1 } }));

    try app.run();

    try testing.expectEqual(@as(u32, 1), counters.tray_clicks);
    try testing.expectEqual(@as(u32, 1), counters.double_clicks);
    try testing.expectEqual(@as(u64, 2), counters.ticks);
    try testing.expectEqual(@as(u32, 1), counters.menu_selects);
    try testing.expectEqual(@as(u32, 5), mock.loop.dispatch_count());
}

test "a quit from a listener stops the tape and the lifecycle" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var counters = Counters{ .app = &app, .quit_after_menu = true };

    try app.bus.attach(Counters, &counters);

    try mock.loop.push(Event.create(.{ .menu_select = .{ .checked = false, .id = 2 } }));
    try mock.loop.push(Event.create(.{ .tray_left_click = {} }));

    try app.run();

    try testing.expectEqual(@as(u32, 1), counters.menu_selects);
    try testing.expectEqual(@as(u32, 1), mock.loop.pending_count());
    try testing.expect(!app.is_running());
}

test "menu selection reports the model checked state" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try app.menu.update(1, .{ .checked = true });

    var counters = Counters{ .app = &app };

    try app.bus.attach(Counters, &counters);
    try mock.loop.push(Event.create(.{ .menu_select = .{ .checked = false, .id = 1 } }));
    try app.run();

    try testing.expect(counters.selected_checked);
}

test "a taskbar restart recreates the tray icon" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try mock.loop.push(Event.create(.{ .taskbar_restart = {} }));
    try app.run();

    try testing.expectEqual(@as(u32, 0), app.tray_failures);
    try testing.expectEqual(@as(u32, 2), mock.tray.counts().created);
}

const Selector = struct {
    app: *App,

    pub fn on_tray_left_click(selector: *Selector) void {
        selector.app.icons.set_current("active") catch {
            return;
        };
    }
};

test "selecting an icon while running shows it in the tray" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var selector = Selector{ .app = &app };

    try app.bus.attach(Selector, &selector);
    try mock.loop.push(Event.create(.{ .tray_left_click = {} }));
    try app.run();

    try testing.expectEqual(@as(u32, 2), mock.icon.counts().loaded);
    try testing.expectEqual(@as(u32, 1), mock.tray.counts().icons);
    try testing.expectEqualStrings("active", app.icons.get_current_name().?);
}

test "the notifier records through the backend" {
    mock.reset();

    var notifier = umbra.Notifier.init();
    defer notifier.deinit();

    try notifier.send(.{ .body = "Application is running", .title = "Started" });
    try notifier.send(.{ .body = "Something looks odd", .kind = .warning, .title = "Careful" });

    const Kind = umbra.Notifier.Notification.Kind;

    try testing.expectEqual(@as(u32, 2), mock.notification.sent_count());
    try testing.expectEqualStrings("Started", mock.notification.title_at(0));
    try testing.expectEqual(Kind.warning, mock.notification.kind_at(1).?);
    try testing.expectEqual(@as(u32, 2), notifier.sent_count());
}

test "the timer set mirrors the backend timer table" {
    mock.reset();

    try mock.runtime.open(.{ .name = "MockApp" });
    defer mock.runtime.close();

    var timers = umbra.TimerSet.init();
    defer timers.deinit();

    try timers.start(.{ .id = 1, .interval_ms = 250 });
    try timers.start(.{ .id = 2, .interval_ms = 500 });

    try testing.expectEqual(@as(u32, 2), mock.timer.active_count());
    try testing.expectEqual(@as(?u32, 250), mock.timer.interval_of(1));

    try timers.stop(1);

    try testing.expectEqual(@as(u32, 1), mock.timer.active_count());
}

test "a failing backend surfaces the platform error that caused it" {
    mock.reset();

    mock.fault.arm(.runtime_open);

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try testing.expectError(error.RuntimeOpenFailed, app.run());
}

const Retrier = struct {
    interval_ms: ?u32 = null,

    pub fn on_app_init(retrier: *Retrier) void {
        retrier.interval_ms = mock.timer.interval_of(app_mod.tray_retry_timer_id);
    }
};

test "a tray the shell rejects leaves the application running behind a retry timer" {
    mock.reset();

    mock.fault.arm(.tray_create);

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var retrier = Retrier{};

    try app.bus.attach(Retrier, &retrier);
    try app.run();

    try testing.expect(!app.tray.is_created());
    try testing.expectEqual(@as(u32, 1), app.tray_failures);
    try testing.expectEqual(@as(u32, 0), app.tray_retry_count);
    try testing.expectEqual(@as(?u32, app_mod.tray_retry_interval_ms), retrier.interval_ms);
    try testing.expect(app.tray_retrying);
}

const Healer = struct {
    pub fn on_app_init(_: *Healer) void {
        mock.fault.disarm(.tray_create);
    }
};

test "a retry tick claims the tray once the shell accepts it" {
    mock.reset();

    mock.fault.arm(.tray_create);

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var healer = Healer{};

    try app.bus.attach(Healer, &healer);

    const retry = Event.Tick{ .id = app_mod.tray_retry_timer_id, .tick_count = 0 };

    try mock.loop.push(Event.create(.{ .timer_tick = retry }));
    try app.run();

    try testing.expectEqual(@as(u32, 1), app.tray_failures);
    try testing.expectEqual(@as(u32, 1), app.tray_retry_count);
    try testing.expectEqual(@as(u32, 1), mock.tray.counts().created);
    try testing.expect(!app.tray_retrying);
}

const Claimant = struct {
    app: *App,
    refused: bool = false,
    ticks: u64 = 0,

    pub fn on_app_init(claimant: *Claimant) void {
        const reserved = app_mod.tray_retry_timer_id;
        const highest = umbra.limits.timer_id_max;
        const refusal = claimant.app.timers.start(.{ .id = reserved, .interval_ms = 100 });

        claimant.refused = if (refusal) |_| false else |err| switch (err) {
            error.TimerReserved => true,
            else => false,
        };

        claimant.app.timers.start(.{ .id = highest, .interval_ms = 100 }) catch return;
    }

    pub fn on_timer_tick(claimant: *Claimant, tick: Event.Tick) void {
        assert(tick.id == umbra.limits.timer_id_max);
        assert(tick.tick_count > 0);

        claimant.ticks = tick.tick_count;
    }
};

test "a caller timer cannot take the retry timer's id, and a stray retry tick is ignored" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var claimant = Claimant{ .app = &app };

    const highest = Event.Tick{ .id = umbra.limits.timer_id_max, .tick_count = 0 };
    const stray = Event.Tick{ .id = app_mod.tray_retry_timer_id, .tick_count = 0 };

    try app.bus.attach(Claimant, &claimant);
    try mock.loop.push(Event.create(.{ .timer_tick = stray }));
    try mock.loop.push(Event.create(.{ .timer_tick = highest }));
    try app.run();

    try testing.expect(claimant.refused);
    try testing.expectEqual(@as(u64, 1), claimant.ticks);
    try testing.expectEqual(@as(u32, 0), app.tray_retry_count);
    try testing.expect(!app.tray_retrying);
}

const Reloader = struct {
    reloads: u32 = 0,

    fn on_change(reloader: *Reloader) void {
        reloader.reloads += 1;
    }
};

test "closing the runtime releases the file watchers" {
    mock.reset();

    try mock.runtime.open(.{ .name = "MockApp" });

    var reloader = Reloader{};

    _ = try umbra.watcher.watch("config.json", Reloader, &reloader, Reloader.on_change);
    _ = try umbra.watcher.watch("other.json", Reloader, &reloader, Reloader.on_change);

    try testing.expectEqual(@as(u32, 2), mock.watcher.active_count());

    mock.runtime.close();

    try testing.expectEqual(@as(u32, 0), mock.watcher.active_count());
    try testing.expectEqual(@as(u32, 2), mock.watcher.counts().unwatched);
}

test "the virtual clock stamps events monotonically" {
    mock.reset();

    const first = Event.create(.{ .app_init = {} });

    mock.time.advance(50);

    const second = Event.create(.{ .app_init = {} });

    try testing.expectEqual(mock.time.base_ms, first.timestamp_ms);
    try testing.expectEqual(mock.time.base_ms + 50, second.timestamp_ms);
}

const Activator = struct {
    app: *App,
    clicks: u32 = 0,
    later_len: u32 = 0,
    token: [umbra.limits.activation_token_bytes_max]u8 = undefined,
    token_len: u32 = 0,

    pub fn on_menu_select(activator: *Activator, _: Event.Selection) void {
        activator.observe();
    }

    pub fn on_tray_left_click(activator: *Activator) void {
        activator.observe();
    }

    fn observe(activator: *Activator) void {
        const token = activator.app.tray.get_activation_token();

        if (activator.clicks == 0) {
            @memcpy(activator.token[0..token.len], token);

            activator.token_len = @intCast(token.len);
        } else {
            activator.later_len += @intCast(token.len);
        }

        activator.clicks += 1;
    }
};

test "a tray host's activation token is read during the click it precedes" {
    mock.reset();

    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var activator = Activator{ .app = &app };

    try app.bus.attach(Activator, &activator);

    mock.tray.activation_provide("kwin-42");

    try mock.loop.push(Event.create(.{ .tray_left_click = {} }));
    try mock.loop.push(Event.create(.{ .menu_select = .{ .checked = false, .id = 2 } }));
    try app.run();

    try testing.expectEqual(@as(u32, 2), activator.clicks);
    try testing.expectEqualStrings("kwin-42", activator.token[0..activator.token_len]);
    try testing.expectEqual(@as(u32, 0), activator.later_len);
    try testing.expectEqualStrings("", app.tray.get_activation_token());
}
