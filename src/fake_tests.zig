const std = @import("std");

const app_module = @import("app.zig");
const umbra = @import("root.zig");

const assert = std.debug.assert;

const App = umbra.AppType(umbra.Fake);
const Event = umbra.Event;
const testing = std.testing;

test {
    _ = @import("platform/fake.zig");
    _ = @import("platform/fake/clock.zig");
    _ = @import("platform/fake/fault.zig");
    _ = @import("platform/fake/icon_table.zig");
    _ = @import("platform/fake/loop.zig");
    _ = @import("platform/fake/menu.zig");
    _ = @import("platform/fake/notifier.zig");
    _ = @import("platform/fake/paths.zig");
    _ = @import("platform/fake/record.zig");
    _ = @import("platform/fake/shell.zig");
    _ = @import("platform/fake/timer_table.zig");
    _ = @import("platform/fake/tray.zig");
    _ = @import("platform/fake/watcher.zig");
    _ = @import("root.zig");
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
        counters.items = counters.app.platform.menu.item_count();

        counters.app.timers.start(.{ .id = 1, .interval_ms = 100 }) catch {
            return;
        };

        counters.timers = counters.app.platform.timers.active_count();
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
        assert(tick.count > 0);

        counters.ticks = tick.count;
    }

    pub fn on_tray_double_click(counters: *Counters) void {
        counters.double_clicks += 1;
    }

    pub fn on_tray_left_click(counters: *Counters) void {
        counters.tray_clicks += 1;
    }
};

fn build_app(app: *App) !void {
    try app.init(.{ .name = "FakeApp", .tooltip = "Fake Tooltip" });

    _ = try App.IconBuilder.init(&app.icons)
        .stock("default", .application)
        .stock("active", .shield)
        .done();

    _ = try App.MenuBuilder.init(&app.menu)
        .toggle(1, "Enable Feature", .{})
        .separator()
        .action(2, "Quit")
        .done();
}

fn push(app: *App, payload: Event.Payload) !void {
    assert(app.platform.live);

    try app.platform.loop.push(Event.create(payload, app.now_ms()));
}

test "a full run initializes the fake, creates the tray, and shuts down" {
    var app: App = undefined;

    try build_app(&app);

    var counters = Counters{ .app = &app };

    try app.bus.attach(Counters, &counters);
    try app.run();

    try testing.expectEqual(@as(u32, 1), counters.inits);
    try testing.expectEqual(@as(u32, 1), counters.shutdowns);
    try testing.expect(app.platform.live);
    try testing.expectEqual(@as(u32, 1), app.platform.tray.counts().created);
    try testing.expectEqual(@as(u32, 1), app.platform.tray.counts().destroyed);
    try testing.expectEqualStrings("Fake Tooltip", app.platform.tray.tooltip_current());
    try testing.expectEqual(@as(u32, 1), app.platform.menu.counts().built);
    try testing.expectEqual(@as(u32, 1), app.platform.menu.counts().destroyed);

    app.deinit();

    try testing.expect(!app.platform.live);
}

test "the end of a run tears down the tray, the menu, and the timers" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var counters = Counters{ .app = &app };

    try app.bus.attach(Counters, &counters);
    try app.run();

    try testing.expectEqual(@as(u32, 3), counters.items);
    try testing.expectEqual(@as(u32, 1), counters.timers);
    try testing.expect(!app.platform.tray.is_created());
    try testing.expectEqual(@as(u32, 0), app.platform.menu.item_count());
    try testing.expectEqual(@as(u32, 0), app.platform.timers.active_count());
}

test "a scripted queue drives tray clicks, timer ticks, and menu selection" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var counters = Counters{ .app = &app };

    try app.bus.attach(Counters, &counters);

    try push(&app, .{ .tray_left_click = {} });
    try push(&app, .{ .tray_double_click = {} });
    try push(&app, .{ .timer_tick = .{ .id = 1, .count = 0 } });
    try push(&app, .{ .timer_tick = .{ .id = 1, .count = 0 } });
    try push(&app, .{ .menu_select = .{ .checked = false, .id = 1 } });

    try app.run();

    try testing.expectEqual(@as(u32, 1), counters.tray_clicks);
    try testing.expectEqual(@as(u32, 1), counters.double_clicks);
    try testing.expectEqual(@as(u64, 2), counters.ticks);
    try testing.expectEqual(@as(u32, 1), counters.menu_selects);
    try testing.expectEqual(@as(u32, 5), app.platform.loop.dispatch_count());
}

test "a quit from a listener stops the queue and the lifecycle" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var counters = Counters{ .app = &app, .quit_after_menu = true };

    try app.bus.attach(Counters, &counters);

    try push(&app, .{ .menu_select = .{ .checked = false, .id = 2 } });
    try push(&app, .{ .tray_left_click = {} });

    try app.run();

    try testing.expectEqual(@as(u32, 1), counters.menu_selects);
    try testing.expectEqual(@as(u32, 1), app.platform.loop.pending_count());
    try testing.expect(!app.is_running());
}

test "menu selection reports the model checked state" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try app.menu.update(1, .{ .checked = true });

    var counters = Counters{ .app = &app };

    try app.bus.attach(Counters, &counters);
    try push(&app, .{ .menu_select = .{ .checked = false, .id = 1 } });
    try app.run();

    try testing.expect(counters.selected_checked);
}

const Nesting = struct {
    app: *App,
    depths: [nesting_item_count]u8 = @splat(0),
    selected: u32 = 0,

    pub fn on_app_init(nesting: *Nesting) void {
        const menu = &nesting.app.platform.menu;

        assert(menu.item_count() == nesting_item_count);

        for (&nesting.depths, 0..) |*depth, index| {
            depth.* = menu.depth_at(@intCast(index));
        }
    }

    pub fn on_menu_select(nesting: *Nesting, selection: Event.Selection) void {
        assert(selection.id <= umbra.limits.menu_item_id_max);

        nesting.selected = selection.id;
    }
};

const nesting_item_count: u32 = 5;

test "a nested menu reaches the backend with each item at its depth" {
    var app: App = undefined;

    try app.init(.{ .name = "FakeApp" });
    defer app.deinit();

    _ = try App.IconBuilder.init(&app.icons).stock("default", .application).done();

    _ = try App.MenuBuilder.init(&app.menu)
        .submenu_begin(1, "Mode")
        .radio(2, "Quiet", .{ .checked = true, .group = "mode" })
        .submenu_begin(3, "Loud")
        .radio(4, "Very loud", .{ .group = "mode" })
        .submenu_end()
        .submenu_end()
        .action(5, "Quit")
        .done();

    var nesting = Nesting{ .app = &app };

    try app.bus.attach(Nesting, &nesting);
    try push(&app, .{ .menu_select = .{ .checked = false, .id = 4 } });
    try app.run();

    try testing.expectEqualSlices(u8, &.{ 0, 1, 1, 2, 0 }, &nesting.depths);
    try testing.expectEqual(@as(u32, 4), nesting.selected);
}

test "a taskbar restart recreates the tray icon" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    try push(&app, .{ .taskbar_restart = {} });
    try app.run();

    try testing.expectEqual(@as(u32, 0), app.tray_failures);
    try testing.expectEqual(@as(u32, 2), app.platform.tray.counts().created);
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
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var selector = Selector{ .app = &app };

    try app.bus.attach(Selector, &selector);
    try push(&app, .{ .tray_left_click = {} });
    try app.run();

    try testing.expectEqual(@as(u32, 2), app.platform.icons.counts().loaded);
    try testing.expectEqual(@as(u32, 1), app.platform.tray.counts().icons);
    try testing.expectEqualStrings("active", app.icons.get_current_name().?);
}

test "the notifier records through the backend" {
    var fake: umbra.Fake = undefined;

    try fake.init(.{ .name = "FakeApp" });
    defer fake.deinit();

    var notifier = App.Notifier.init(&fake);
    defer notifier.deinit();

    try notifier.send(.{ .body = "Application is running", .title = "Started" });
    try notifier.send(.{ .body = "Something looks odd", .kind = .warning, .title = "Careful" });

    const Kind = App.Notifier.Notification.Kind;

    try testing.expectEqual(@as(u32, 2), fake.notifier.sent_count());
    try testing.expectEqualStrings("Started", fake.notifier.title_at(0));
    try testing.expectEqual(Kind.warning, fake.notifier.kind_at(1).?);
    try testing.expectEqual(@as(u32, 2), notifier.sent_count());
}

test "the timer set mirrors the backend timer table" {
    var fake: umbra.Fake = undefined;

    try fake.init(.{ .name = "FakeApp" });
    defer fake.deinit();

    var timers = App.TimerSet.init(&fake);
    defer timers.deinit();

    try timers.start(.{ .id = 1, .interval_ms = 250 });
    try timers.start(.{ .id = 2, .interval_ms = 500 });

    try testing.expectEqual(@as(u32, 2), fake.timers.active_count());
    try testing.expectEqual(@as(?u32, 250), fake.timers.interval_of(1));

    try timers.stop(1);

    try testing.expectEqual(@as(u32, 1), fake.timers.active_count());
}

test "a failing backend surfaces the platform error that caused it" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    app.platform.fault.arm(.icon_load);

    try testing.expectError(error.IconLoadFailed, app.run());
}

const Retrier = struct {
    app: *App,
    interval_ms: ?u32 = null,

    pub fn on_app_init(retrier: *Retrier) void {
        retrier.interval_ms = retrier.app.platform.timers.interval_of(
            app_module.tray_retry_timer_id,
        );
    }
};

test "a tray the shell rejects leaves the application running behind a retry timer" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    app.platform.fault.arm(.tray_create);

    var retrier = Retrier{ .app = &app };

    try app.bus.attach(Retrier, &retrier);
    try app.run();

    try testing.expect(!app.tray.is_created());
    try testing.expectEqual(@as(u32, 1), app.tray_failures);
    try testing.expectEqual(@as(u32, 0), app.tray_retry_count);
    try testing.expectEqual(@as(?u32, app_module.tray_retry_interval_ms), retrier.interval_ms);
    try testing.expect(app.tray_retrying);
}

const Healer = struct {
    app: *App,

    pub fn on_app_init(healer: *Healer) void {
        healer.app.platform.fault.disarm(.tray_create);
    }
};

test "a retry tick claims the tray once the shell accepts it" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    app.platform.fault.arm(.tray_create);

    var healer = Healer{ .app = &app };

    try app.bus.attach(Healer, &healer);

    const retry = Event.Tick{ .id = app_module.tray_retry_timer_id, .count = 0 };

    try push(&app, .{ .timer_tick = retry });
    try app.run();

    try testing.expectEqual(@as(u32, 1), app.tray_failures);
    try testing.expectEqual(@as(u32, 1), app.tray_retry_count);
    try testing.expectEqual(@as(u32, 1), app.platform.tray.counts().created);
    try testing.expect(!app.tray_retrying);
}

const Claimant = struct {
    app: *App,
    refused: bool = false,
    ticks: u64 = 0,

    pub fn on_app_init(claimant: *Claimant) void {
        const reserved = app_module.tray_retry_timer_id;
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
        assert(tick.count > 0);

        claimant.ticks = tick.count;
    }
};

test "a caller timer cannot take the retry timer's id, and a stray retry tick is ignored" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var claimant = Claimant{ .app = &app };

    const highest = Event.Tick{ .id = umbra.limits.timer_id_max, .count = 0 };
    const stray = Event.Tick{ .id = app_module.tray_retry_timer_id, .count = 0 };

    try app.bus.attach(Claimant, &claimant);
    try push(&app, .{ .timer_tick = stray });
    try push(&app, .{ .timer_tick = highest });
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

test "the end of a run releases the file watchers" {
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var reloader = Reloader{};

    _ = try app.watch("config.json", Reloader, &reloader, Reloader.on_change);
    _ = try app.watch("other.json", Reloader, &reloader, Reloader.on_change);

    try testing.expectEqual(@as(u32, 2), app.platform.watcher.active_count());

    try app.run();

    try testing.expectEqual(@as(u32, 0), app.platform.watcher.active_count());
    try testing.expectEqual(@as(u32, 2), app.platform.watcher.counts().unwatched);
}

test "the virtual clock stamps events monotonically" {
    var fake: umbra.Fake = undefined;

    try fake.init(.{ .name = "FakeApp" });
    defer fake.deinit();

    const first = Event.create(.{ .app_init = {} }, fake.now_ms());

    fake.clock.advance(50);

    const second = Event.create(.{ .app_init = {} }, fake.now_ms());
    const base_ms = @TypeOf(fake.clock).base_ms;

    try testing.expectEqual(base_ms, first.timestamp_ms);
    try testing.expectEqual(base_ms + 50, second.timestamp_ms);
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
    var app: App = undefined;

    try build_app(&app);
    defer app.deinit();

    var activator = Activator{ .app = &app };

    try app.bus.attach(Activator, &activator);

    app.platform.tray.activation_provide("kwin-42");

    try push(&app, .{ .tray_left_click = {} });
    try push(&app, .{ .menu_select = .{ .checked = false, .id = 2 } });
    try app.run();

    try testing.expectEqual(@as(u32, 2), activator.clicks);
    try testing.expectEqualStrings("kwin-42", activator.token[0..activator.token_len]);
    try testing.expectEqual(@as(u32, 0), activator.later_len);
    try testing.expectEqualStrings("", app.tray.get_activation_token());
}
