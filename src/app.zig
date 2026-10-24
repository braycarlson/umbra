const std = @import("std");

const bus_module = @import("bus.zig");
const event_module = @import("event.zig");
const icon_module = @import("ui/icon.zig");
const lifecycle_module = @import("lifecycle.zig");
const menu_module = @import("ui/menu.zig");
const notification_module = @import("ui/notification.zig");
const platform = @import("platform.zig");
const timer_module = @import("ui/timer.zig");
const tray_module = @import("ui/tray.zig");

const assert = std.debug.assert;

const Bus = bus_module.Bus;
const CapacityError = platform.CapacityError;
const Event = event_module.Event;
const IconSet = icon_module.IconSet;
const Lifecycle = lifecycle_module.Lifecycle;
const Menu = menu_module.Menu;
const Notifier = notification_module.Notifier;
const PlatformError = platform.PlatformError;
const RequestError = platform.RequestError;
const TimerSet = timer_module.TimerSet;
const Tray = tray_module.Tray;

const app_name_bytes_max = platform.app_name_bytes_max;

pub const tray_retry_attempt_max: u32 = 60;
pub const tray_retry_interval_ms: u32 = 1000;
pub const tray_retry_timer_id: u32 = std.math.maxInt(u32);

comptime {
    assert(tray_retry_attempt_max > 0);
    assert(tray_retry_interval_ms > 0);
    assert(tray_retry_timer_id > 0);
}

pub const App = struct {
    bus: Bus,
    icons: IconSet,
    lifecycle: Lifecycle,
    menu: Menu,
    name: [app_name_bytes_max]u8,
    name_len: u8,
    notifier: Notifier,
    timers: TimerSet,
    tray: Tray,
    tray_failures: u32,
    tray_retry_count: u32,

    pub const Options = struct {
        name: []const u8,
        tooltip: []const u8 = "",
    };

    pub fn init(app: *App, options: Options) (CapacityError || RequestError)!void {
        if (options.name.len == 0) return error.NameEmpty;
        if (options.name.len > app_name_bytes_max) return error.NameTooLong;
        if (!platform.is_valid_text(options.name)) return error.NameInvalid;
        if (options.tooltip.len > platform.tooltip_bytes_max) return error.TooltipTooLong;
        if (!platform.is_valid_text(options.tooltip)) return error.TooltipInvalid;

        const tooltip = if (options.tooltip.len > 0) options.tooltip else options.name;

        app.* = App{
            .bus = Bus.init(),
            .icons = IconSet.init(),
            .lifecycle = Lifecycle.init(),
            .menu = Menu.init(),
            .name = @splat(0),
            .name_len = @intCast(options.name.len),
            .notifier = Notifier.init(),
            .timers = TimerSet.init(),
            .tray = Tray.init(tooltip),
            .tray_failures = 0,
            .tray_retry_count = 0,
        };

        @memcpy(app.name[0..options.name.len], options.name);

        app.icons.bind(&app.tray);

        assert(app.lifecycle.stage == .created);
    }

    pub fn deinit(app: *App) void {
        app.timers.deinit();
        app.menu.deinit();
        app.tray.deinit();
        app.icons.deinit();
        app.bus.deinit();
        app.notifier.deinit();

        app.lifecycle.force_stop();

        assert(app.lifecycle.is_stopped());
    }

    pub fn dispatch(app: *App, incoming: *const Event) void {
        assert(incoming.kind().is_valid());

        switch (incoming.payload) {
            .menu_select => |selection| app.on_menu_select(selection.id),
            .taskbar_restart => app.on_taskbar_restart(),
            .timer_tick => |tick| app.on_timer_tick(tick.id),
            else => app.bus.emit(incoming),
        }
    }

    pub fn get_name(app: *const App) []const u8 {
        assert(app.name_len > 0);
        assert(app.name_len <= app_name_bytes_max);

        return app.name[0..app.name_len];
    }

    pub fn is_running(app: *const App) bool {
        return app.lifecycle.is_running();
    }

    pub fn quit(app: *App) void {
        platform.backend.loop.quit();

        _ = app.lifecycle.transition(.stopping);
    }

    pub fn run(app: *App) (CapacityError || PlatformError || RequestError)!void {
        assert(app.lifecycle.stage == .created);

        try platform.backend.runtime.open(.{ .name = app.get_name() });
        defer platform.backend.runtime.close();

        try app.icons.load();

        assert(app.icons.get_current() != null);

        app.tray.create(app.icons.get_current()) catch {
            app.tray_failures += 1;
        };

        defer app.tray.destroy();

        try app.menu.build();

        _ = app.lifecycle.transition(.running);

        assert(app.lifecycle.is_running());

        app.start_tray_retry();
        app.bus.emit(&Event.create(.{ .app_init = {} }));

        var instance = platform.backend.loop.LoopType(App).init();

        try instance.run(app);

        _ = app.lifecycle.transition(.stopping);

        app.bus.emit(&Event.create(.{ .app_shutdown = {} }));
    }

    fn on_menu_select(app: *App, id: u32) void {
        const checked = app.menu.is_checked(id);

        app.bus.emit(&Event.create(.{ .menu_select = .{ .checked = checked, .id = id } }));
    }

    fn on_taskbar_restart(app: *App) void {
        app.tray.recreate(app.icons.get_current()) catch {
            app.tray_failures += 1;
        };

        app.bus.emit(&Event.create(.{ .taskbar_restart = {} }));
    }

    fn on_timer_tick(app: *App, id: u32) void {
        if (id == tray_retry_timer_id) {
            app.on_tray_retry();

            return;
        }

        const tick_count = app.timers.tick(id);

        app.bus.emit(&Event.create(.{ .timer_tick = .{ .id = id, .tick_count = tick_count } }));
    }

    fn on_tray_retry(app: *App) void {
        assert(app.tray_retry_count < tray_retry_attempt_max);

        _ = app.timers.tick(tray_retry_timer_id);

        if (app.tray.is_created()) {
            app.stop_tray_retry();

            return;
        }

        app.tray_retry_count += 1;

        app.tray.recreate(app.icons.get_current()) catch {
            app.tray_failures += 1;
        };

        if (app.tray.is_created()) {
            app.stop_tray_retry();

            return;
        }

        if (app.tray_retry_count >= tray_retry_attempt_max) {
            app.stop_tray_retry();
        }
    }

    fn start_tray_retry(app: *App) void {
        if (app.tray.is_created()) {
            return;
        }

        assert(app.tray_failures > 0);

        const retry = TimerSet.Timer{
            .id = tray_retry_timer_id,
            .interval_ms = tray_retry_interval_ms,
        };

        app.timers.start(retry) catch {
            return;
        };
    }

    fn stop_tray_retry(app: *App) void {
        assert(app.timers.is_running(tray_retry_timer_id));

        app.timers.stop(tray_retry_timer_id) catch {
            return;
        };
    }
};

const testing = std.testing;

const Sink = struct {
    checked: bool = false,
    clicks: u32 = 0,
    ticks: u64 = 0,

    pub fn on_menu_select(sink: *Sink, selection: Event.Selection) void {
        sink.checked = selection.checked;
    }

    pub fn on_timer_tick(sink: *Sink, tick: Event.Tick) void {
        sink.ticks = tick.tick_count;
    }

    pub fn on_tray_left_click(sink: *Sink) void {
        sink.clicks += 1;
    }
};

test App {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp", .tooltip = "Custom Tooltip" });
    defer app.deinit();

    try testing.expectEqualStrings("TestApp", app.get_name());
    try testing.expectEqualStrings("Custom Tooltip", app.tray.get_tooltip());
    try testing.expect(!app.is_running());
    try testing.expect(app.icons.is_empty());
    try testing.expect(app.menu.is_empty());
}

test "an application names the fault in each refused option" {
    var app: App = undefined;

    const long: [app_name_bytes_max + 1]u8 = @splat('a');
    const invalid = [_]u8{ 0xC3, 0x28 };
    const tooltip: [platform.tooltip_bytes_max + 1]u8 = @splat('a');

    try testing.expectError(error.NameEmpty, app.init(.{ .name = "" }));
    try testing.expectError(error.NameTooLong, app.init(.{ .name = &long }));
    try testing.expectError(error.NameInvalid, app.init(.{ .name = &invalid }));
    try testing.expectError(error.TooltipTooLong, app.init(.{ .name = "a", .tooltip = &tooltip }));
    try testing.expectError(error.TooltipInvalid, app.init(.{ .name = "a", .tooltip = &invalid }));
}

test "an application falls back to its name for the tooltip" {
    var app: App = undefined;

    try app.init(.{ .name = "MyApp" });
    defer app.deinit();

    try testing.expectEqualStrings("MyApp", app.tray.get_tooltip());
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

test "tearing down an application lands in the stopped stage" {
    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });

    app.deinit();

    try testing.expect(app.lifecycle.is_stopped());
}

test "a dispatched event reaches the attached owner with its payload" {
    platform.mock.reset();

    try platform.mock.runtime.open(.{ .name = "TestApp" });
    defer platform.mock.runtime.close();

    var app: App = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    var sink = Sink{};

    try app.bus.attach(Sink, &sink);
    try app.menu.add(.toggle(7, "Enabled", .{ .checked = true }));
    try app.timers.start(.{ .id = 3, .interval_ms = 10 });

    app.dispatch(&Event.create(.{ .tray_left_click = {} }));
    app.dispatch(&Event.create(.{ .menu_select = .{ .checked = false, .id = 7 } }));
    app.dispatch(&Event.create(.{ .timer_tick = .{ .id = 3, .tick_count = 0 } }));

    try testing.expectEqual(@as(u32, 1), sink.clicks);
    try testing.expect(sink.checked);
    try testing.expectEqual(@as(u64, 1), sink.ticks);
}
