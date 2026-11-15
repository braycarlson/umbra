const std = @import("std");

const builder_module = @import("builder.zig");
const bus_module = @import("bus.zig");
const event_module = @import("event.zig");
const icon_module = @import("ui.zig").icon;
const lifecycle_module = @import("lifecycle.zig");
const menu_module = @import("ui.zig").menu;
const notification_module = @import("ui.zig").notification;
const platform = @import("platform.zig");
const timer_module = @import("ui.zig").timer;
const tray_module = @import("ui.zig").tray;

const assert = std.debug.assert;

const Bus = bus_module.Bus;
const CapacityError = platform.CapacityError;
const Event = event_module.Event;
const IconBuilderType = builder_module.IconBuilderType;
const IconSetType = icon_module.IconSetType;
const Lifecycle = lifecycle_module.Lifecycle;
const MenuBuilderType = builder_module.MenuBuilderType;
const MenuType = menu_module.MenuType;
const NotifierType = notification_module.NotifierType;
const PlatformError = platform.PlatformError;
const RequestError = platform.RequestError;
const TimerSetType = timer_module.TimerSetType;
const TrayType = tray_module.TrayType;
const Watch = platform.Watch;

const app_name_bytes_max = platform.app_name_bytes_max;

pub const tray_retry_attempt_max: u32 = 60;
pub const tray_retry_interval_ms: u32 = 1000;
pub const tray_retry_timer_id: u32 = std.math.maxInt(u32);

comptime {
    assert(tray_retry_attempt_max > 0);
    assert(tray_retry_interval_ms > 0);
    assert(tray_retry_timer_id > platform.timer_id_max);
}

pub fn AppType(comptime Platform: type) type {
    return struct {
        bus: Bus,
        icons: IconSet,
        lifecycle: Lifecycle,
        menu: Menu,
        name: [app_name_bytes_max]u8,
        name_len: u8,
        notifier: Notifier,
        platform: Platform,
        timers: TimerSet,
        tray: Tray,
        tray_failures: u32,
        tray_retry_count: u32,
        tray_retrying: bool,

        const App = @This();

        pub const IconBuilder = IconBuilderType(Platform);
        pub const IconSet = IconSetType(Platform);
        pub const Menu = MenuType(Platform);
        pub const MenuBuilder = MenuBuilderType(Platform);
        pub const Notifier = NotifierType(Platform);
        pub const TimerSet = TimerSetType(Platform);
        pub const Tray = TrayType(Platform);

        pub const Options = struct {
            name: []const u8,
            tooltip: []const u8 = "",
        };

        pub fn init(
            app: *App,
            options: Options,
        ) (CapacityError || PlatformError || RequestError)!void {
            if (options.name.len == 0) return error.NameEmpty;
            if (options.name.len > app_name_bytes_max) return error.NameTooLong;
            if (!platform.is_valid_text(options.name)) return error.NameInvalid;
            if (options.tooltip.len > platform.tooltip_bytes_max) return error.TooltipTooLong;
            if (!platform.is_valid_text(options.tooltip)) return error.TooltipInvalid;

            try app.platform.init(.{ .name = options.name });

            const tooltip = if (options.tooltip.len > 0) options.tooltip else options.name;

            app.bus = Bus.init();
            app.icons = IconSet.init(&app.platform);
            app.lifecycle = Lifecycle.init();
            app.menu = Menu.init(&app.platform);
            app.name = @splat(0);
            app.name_len = @intCast(options.name.len);
            app.notifier = Notifier.init(&app.platform);
            app.timers = TimerSet.init(&app.platform);
            app.tray = Tray.init(&app.platform, tooltip);
            app.tray_failures = 0;
            app.tray_retry_count = 0;
            app.tray_retrying = false;

            @memcpy(app.name[0..options.name.len], options.name);

            app.icons.bind(&app.tray);

            assert(app.lifecycle.stage == .created);
        }

        pub fn deinit(app: *App) void {
            if (app.tray_retrying) app.stop_tray_retry();

            app.timers.deinit();
            app.menu.deinit();
            app.tray.deinit();
            app.icons.deinit();
            app.bus.deinit();
            app.notifier.deinit();
            app.platform.deinit();

            app.lifecycle.force_stop();

            assert(app.lifecycle.is_stopped());
        }

        pub fn dispatch(app: *App, incoming: *const Event) void {
            assert(incoming.kind().is_valid());

            switch (incoming.payload) {
                .menu_select => |selection| app.on_menu_select(selection.id),
                .taskbar_restart => app.on_taskbar_restart(),
                .timer_tick => |tick| switch (tick.id) {
                    tray_retry_timer_id => app.on_tray_retry(),
                    else => app.on_timer_tick(tick.id),
                },
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

        pub fn now_ms(app: *const App) u64 {
            return app.platform.now_ms();
        }

        pub fn post(app: *App, code: Event.Code) bool {
            return app.platform.loop_post(code);
        }

        pub fn quit(app: *App) void {
            app.platform.loop_quit();

            _ = app.lifecycle.transition(.stopping);
        }

        pub fn run(app: *App) (CapacityError || PlatformError || RequestError)!void {
            assert(app.lifecycle.stage == .created);

            defer {
                app.platform.menu_destroy();
                app.platform.timer_stop_all();
                app.platform.watcher_stop_all();
            }

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
            app.bus.emit(&Event.create(.{ .app_init = {} }, app.platform.now_ms()));

            try app.platform.loop_run(App, app);

            _ = app.lifecycle.transition(.stopping);

            app.bus.emit(&Event.create(.{ .app_shutdown = {} }, app.platform.now_ms()));
        }

        pub fn config_dir(
            io: std.Io,
            buffer: []u8,
            name: []const u8,
        ) (CapacityError || PlatformError)![]const u8 {
            assert(name.len > 0);
            assert(std.mem.findAny(u8, name, "/\\") == null);
            assert(@intFromPtr(buffer.ptr) >= @intFromPtr(name.ptr) + name.len or
                @intFromPtr(name.ptr) >= @intFromPtr(buffer.ptr) + buffer.len);

            const result = try Platform.paths_config_dir(io, buffer, name);

            assert(result.len <= buffer.len);
            assert(std.Io.Dir.path.isAbsolute(result));
            assert(std.mem.endsWith(u8, result, name));

            return result;
        }

        pub fn state_dir(
            io: std.Io,
            buffer: []u8,
            name: []const u8,
        ) (CapacityError || PlatformError)![]const u8 {
            assert(name.len > 0);
            assert(std.mem.findAny(u8, name, "/\\") == null);
            assert(@intFromPtr(buffer.ptr) >= @intFromPtr(name.ptr) + name.len or
                @intFromPtr(name.ptr) >= @intFromPtr(buffer.ptr) + buffer.len);

            const result = try Platform.paths_state_dir(io, buffer, name);

            assert(result.len <= buffer.len);
            assert(std.Io.Dir.path.isAbsolute(result));
            assert(std.mem.endsWith(u8, result, name));

            return result;
        }

        pub fn open_path(
            app: *App,
            path: []const u8,
        ) (CapacityError || PlatformError || RequestError)!void {
            if (path.len == 0) return error.PathEmpty;
            if (path.len >= platform.path_bytes_max) return error.PathTooLong;
            if (!platform.is_valid_text(path)) return error.PathInvalid;

            try app.platform.shell_open(path);
        }

        pub fn watch(
            app: *App,
            path: []const u8,
            comptime Owner: type,
            owner: *Owner,
            comptime callback: fn (*Owner) void,
        ) (CapacityError || PlatformError || RequestError)!Watch {
            if (path.len == 0) return error.PathEmpty;
            if (path.len >= platform.path_bytes_max) return error.PathTooLong;
            if (!platform.is_valid_text(path)) return error.PathInvalid;

            const Listener = ListenerType(Owner, callback);
            return try app.platform.watcher_watch(path, Listener.invoke, owner);
        }

        pub fn unwatch(app: *App, handle: Watch) void {
            assert(@backingInt(handle) < platform.watch_count_max);

            app.platform.watcher_unwatch(handle);
        }

        fn on_menu_select(app: *App, id: u32) void {
            assert(id <= platform.menu_item_id_max);

            const checked = app.menu.is_checked(id);
            const selection = Event.Selection{ .checked = checked, .id = id };

            app.bus.emit(&Event.create(.{ .menu_select = selection }, app.platform.now_ms()));
        }

        fn on_taskbar_restart(app: *App) void {
            app.tray.recreate(app.icons.get_current()) catch {
                app.tray_failures += 1;
            };

            app.bus.emit(&Event.create(.{ .taskbar_restart = {} }, app.platform.now_ms()));
        }

        fn on_timer_tick(app: *App, id: u32) void {
            assert(id <= platform.timer_id_max);

            const tick_count = app.timers.tick(id);
            if (tick_count == 0) return;

            const tick = Event.Tick{ .id = id, .count = tick_count };

            app.bus.emit(&Event.create(.{ .timer_tick = tick }, app.platform.now_ms()));
        }

        fn on_tray_retry(app: *App) void {
            if (!app.tray_retrying) return;

            assert(app.tray_retry_count < tray_retry_attempt_max);

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
            assert(!app.tray_retrying);

            if (app.tray.is_created()) {
                return;
            }

            assert(app.tray_failures > 0);

            const retry = TimerSet.Timer{
                .id = tray_retry_timer_id,
                .interval_ms = tray_retry_interval_ms,
            };

            app.platform.timer_start(retry) catch {
                return;
            };

            app.tray_retrying = true;
        }

        fn stop_tray_retry(app: *App) void {
            assert(app.tray_retrying);

            _ = app.platform.timer_stop(tray_retry_timer_id);

            app.tray_retrying = false;
        }
    };
}

fn ListenerType(comptime Owner: type, comptime callback: fn (*Owner) void) type {
    return struct {
        fn invoke(context: *anyopaque) void {
            const owner: *Owner = @ptrCast(@alignCast(context));

            callback(owner);
        }
    };
}

const testing = std.testing;

const Fake = platform.Fake;
const FakeApp = AppType(Fake);

const Sink = struct {
    checked: bool = false,
    clicks: u32 = 0,
    ticks: u64 = 0,

    pub fn on_menu_select(sink: *Sink, selection: Event.Selection) void {
        assert(selection.id <= platform.menu_item_id_max);

        sink.checked = selection.checked;
    }

    pub fn on_timer_tick(sink: *Sink, tick: Event.Tick) void {
        assert(tick.count > 0);

        sink.ticks = tick.count;
    }

    pub fn on_tray_left_click(sink: *Sink) void {
        sink.clicks += 1;
    }
};

test AppType {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "TestApp", .tooltip = "Custom Tooltip" });
    defer app.deinit();

    try testing.expectEqualStrings("TestApp", app.get_name());
    try testing.expectEqualStrings("Custom Tooltip", app.tray.get_tooltip());
    try testing.expectEqualStrings("TestApp", app.platform.name.get());
    try testing.expect(!app.is_running());
    try testing.expect(app.icons.is_empty());
    try testing.expect(app.menu.is_empty());
}

test "an application names the fault in each refused option" {
    var app: FakeApp = undefined;

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
    var app: FakeApp = undefined;

    try app.init(.{ .name = "MyApp" });
    defer app.deinit();

    try testing.expectEqualStrings("MyApp", app.tray.get_tooltip());
}

test "an application copies the name into storage of its own" {
    var app: FakeApp = undefined;
    var caller: [8]u8 = undefined;

    @memcpy(caller[0.."Borrowed".len], "Borrowed");

    try app.init(.{ .name = caller[0.."Borrowed".len] });
    defer app.deinit();

    @memset(&caller, 'x');

    try testing.expectEqualStrings("Borrowed", app.get_name());
}

test "tearing down an application lands in the stopped stage" {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "TestApp" });

    app.deinit();

    try testing.expect(app.lifecycle.is_stopped());
}

test "a dispatched event reaches the attached owner with its payload" {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    var sink = Sink{};

    try app.bus.attach(Sink, &sink);
    try app.menu.add(.toggle(7, "Enabled", .{ .checked = true }));
    try app.timers.start(.{ .id = 3, .interval_ms = 10 });

    const now = app.now_ms();

    app.dispatch(&Event.create(.{ .tray_left_click = {} }, now));
    app.dispatch(&Event.create(.{ .menu_select = .{ .checked = false, .id = 7 } }, now));
    app.dispatch(&Event.create(.{ .timer_tick = .{ .id = 3, .count = 0 } }, now));

    try testing.expectEqual(@as(u32, 1), sink.clicks);
    try testing.expect(sink.checked);
    try testing.expectEqual(@as(u64, 1), sink.ticks);
}

test "a post queues a custom event on the loop" {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    try testing.expect(app.post(@fromBackingInt(42)));
    try testing.expectEqual(@as(u32, 1), app.platform.loop.posts());
    try testing.expectEqual(@as(u32, 1), app.platform.loop.pending_count());
}

test "now_ms reads the platform clock" {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const before = app.now_ms();

    app.platform.clock.advance(25);

    try testing.expectEqual(before + 25, app.now_ms());
}

test "the configuration directory lands in the build cache under the given name" {
    var buffer: [platform.path_bytes_max]u8 = undefined;

    const config = try FakeApp.config_dir(testing.io, &buffer, "phantom");

    try expect_fake_directory(config, "config");
}

test "the state directory lands in the build cache under the given name or reports a short buffer" {
    var buffer: [platform.path_bytes_max]u8 = undefined;

    const state = try FakeApp.state_dir(testing.io, &buffer, "phantom");

    try expect_fake_directory(state, "state");

    var small: [8]u8 = undefined;

    try testing.expectError(error.PathTooLong, FakeApp.state_dir(testing.io, &small, "phantom"));
}

fn expect_fake_directory(actual: []const u8, kind: []const u8) !void {
    assert(actual.len > 0);
    assert(kind.len > 0);

    const working = try std.process.currentPathAlloc(testing.io, testing.allocator);
    defer testing.allocator.free(working);

    const expected = try std.Io.Dir.path.join(
        testing.allocator,
        &.{ working, ".zig-cache", "tmp", "umbra-fake", kind, "phantom" },
    );

    defer testing.allocator.free(expected);

    try testing.expect(std.Io.Dir.path.isAbsolute(actual));
    try testing.expectEqualStrings(expected, actual);
}

test "opening a path reaches the shell and names the fault in each refused path" {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    const path = "/home/user/.config/locker/config.zon";

    try app.open_path(path);

    try testing.expectEqualStrings(path, app.platform.shell.path_at(0));

    const long: [platform.path_bytes_max]u8 = @splat('a');

    try testing.expectError(error.PathEmpty, app.open_path(""));
    try testing.expectError(error.PathTooLong, app.open_path(&long));
    try testing.expectError(error.PathInvalid, app.open_path("config\x00.zon"));
    try testing.expectEqual(@as(u32, 1), app.platform.shell.opened_count());
}

const Reloader = struct {
    reloads: u32 = 0,

    fn on_change(reloader: *Reloader) void {
        reloader.reloads += 1;
    }
};

test "a watch reaches its owner and names the fault in each refused path" {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    var reloader = Reloader{};

    const handle = try app.watch("config.zon", Reloader, &reloader, Reloader.on_change);
    defer app.unwatch(handle);

    try testing.expect(app.platform.watcher.fire(handle));
    try testing.expectEqual(@as(u32, 1), reloader.reloads);

    const long: [platform.path_bytes_max]u8 = @splat('a');
    const empty = app.watch("", Reloader, &reloader, Reloader.on_change);
    const oversized = app.watch(&long, Reloader, &reloader, Reloader.on_change);
    const garbled = app.watch("\xC3\x28", Reloader, &reloader, Reloader.on_change);

    try testing.expectError(error.PathEmpty, empty);
    try testing.expectError(error.PathTooLong, oversized);
    try testing.expectError(error.PathInvalid, garbled);
}

test "an unwatched path no longer reaches its owner" {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    var reloader = Reloader{};

    const handle = try app.watch("config.zon", Reloader, &reloader, Reloader.on_change);

    app.unwatch(handle);

    try testing.expect(!app.platform.watcher.fire(handle));
    try testing.expectEqual(@as(u32, 0), reloader.reloads);
    try testing.expectEqual(@as(u32, 0), app.platform.watcher.active_count());
}

test "a full watcher refuses another watch" {
    var app: FakeApp = undefined;

    try app.init(.{ .name = "TestApp" });
    defer app.deinit();

    var reloader = Reloader{};
    var index: u8 = 0;

    while (index < platform.watch_count_max) : (index += 1) {
        _ = try app.watch("config.zon", Reloader, &reloader, Reloader.on_change);
    }

    const overflow = app.watch("config.zon", Reloader, &reloader, Reloader.on_change);

    try testing.expectError(error.WatchesExhausted, overflow);
}
