const std = @import("std");

const Clock = @import("fake/clock.zig");
const event_module = @import("../event.zig");
const Fault = @import("fake/fault.zig");
const IconTable = @import("fake/icon_table.zig");
const interface = @import("interface.zig");
const Loop = @import("fake/loop.zig");
const Menu = @import("fake/menu.zig");
const Notifier = @import("fake/notifier.zig");
const paths = @import("fake/paths.zig");
const record = @import("fake/record.zig");
const Shell = @import("fake/shell.zig");
const TimerTable = @import("fake/timer_table.zig");
const Tray = @import("fake/tray.zig");
const Watcher = @import("fake/watcher.zig");

const assert = std.debug.assert;

const CapacityError = interface.CapacityError;
const Event = event_module.Event;
const Icon = interface.Icon;
const Listener = interface.Listener;
const MenuItem = interface.MenuItem;
const Notification = interface.Notification;
const PlatformError = interface.PlatformError;
const Timer = interface.Timer;
const TrayCreateOptions = interface.TrayCreateOptions;
const Watch = interface.Watch;

const Fake = @This();

clock: Clock,
fault: Fault,
icons: IconTable,
live: bool,
loop: Loop,
menu: Menu,
name: record.Text,
notifier: Notifier,
shell: Shell,
timers: TimerTable,
tray: Tray,
watcher: Watcher,

pub const paths_config_dir = paths.config_dir;
pub const paths_state_dir = paths.state_dir;

comptime {
    interface.assert_backend(Fake);
}

pub fn init(fake: *Fake, options: interface.Options) PlatformError!void {
    assert(options.is_valid());
    assert(options.name.len <= record.text_bytes_max);

    fake.clock = .start;
    fake.fault = .empty;
    fake.live = true;
    fake.name = record.Text.empty();

    fake.icons.init();
    fake.loop.init();
    fake.menu.init();
    fake.name.set(options.name);
    fake.notifier.init();
    fake.shell.init();
    fake.timers.init();
    fake.tray.init();
    fake.watcher.init();

    assert(fake.live);
    assert(fake.name.equals(options.name));
}

pub fn deinit(fake: *Fake) void {
    assert(fake.live);
    assert(!fake.loop.is_running());

    fake.tray.destroy();
    fake.menu.destroy();
    fake.timers.stop_all();
    fake.watcher.stop_all();

    fake.live = false;

    assert(!fake.tray.is_created());
    assert(fake.watcher.active_count() == 0);
}

pub fn now_ms(fake: *const Fake) u64 {
    assert(fake.live);

    const result = fake.clock.now_ms();

    assert(result >= Clock.base_ms);

    return result;
}

pub fn icon_load(fake: *Fake, source: Icon.Source) (CapacityError || PlatformError)!Icon {
    assert(fake.live);
    assert(source.is_valid());

    if (fake.fault.is_armed(.icon_load)) return error.IconLoadFailed;

    return fake.icons.load(source);
}

pub fn icon_destroy(fake: *Fake, icon: Icon) void {
    assert(fake.live);
    assert(@backingInt(icon) < interface.icon_count_max);

    fake.icons.destroy(icon);
}

pub fn tray_activation_token(fake: *const Fake) []const u8 {
    assert(fake.live);

    const result = fake.tray.activation_token();

    assert(result.len <= interface.activation_token_bytes_max);

    return result;
}

pub fn tray_create(fake: *Fake, options: TrayCreateOptions) PlatformError!void {
    assert(fake.live);
    assert(options.tooltip.len <= interface.tooltip_bytes_max);

    if (fake.fault.is_armed(.tray_create)) return error.TrayCreateFailed;

    fake.tray.create(options);
}

pub fn tray_destroy(fake: *Fake) void {
    assert(fake.live);

    fake.tray.destroy();

    assert(!fake.tray.is_created());
}

pub fn tray_is_created(fake: *const Fake) bool {
    assert(fake.live);

    return fake.tray.is_created();
}

pub fn tray_set_icon(fake: *Fake, icon: Icon) PlatformError!void {
    assert(fake.live);
    assert(@backingInt(icon) < interface.icon_count_max);

    fake.tray.set_icon(icon);
}

pub fn tray_set_tooltip(fake: *Fake, tooltip: []const u8) PlatformError!void {
    assert(fake.live);
    assert(tooltip.len <= interface.tooltip_bytes_max);

    fake.tray.set_tooltip(tooltip);
}

pub fn menu_build(fake: *Fake, items: []const MenuItem) PlatformError!void {
    assert(fake.live);
    assert(interface.is_valid_layout(items));

    if (fake.fault.is_armed(.menu_build)) return error.MenuBuildFailed;

    fake.menu.build(items);
}

pub fn menu_destroy(fake: *Fake) void {
    assert(fake.live);

    fake.menu.destroy();

    assert(fake.menu.item_count() == 0);
}

pub fn notification_send(fake: *Fake, notification: Notification) PlatformError!void {
    assert(fake.live);
    assert(notification.is_valid());

    if (fake.fault.is_armed(.notification_send)) return error.NotificationFailed;

    fake.notifier.send(notification);
}

pub fn shell_open(fake: *Fake, path: []const u8) PlatformError!void {
    assert(fake.live);
    assert(path.len > 0);

    if (fake.fault.is_armed(.shell_open)) return error.LaunchFailed;

    fake.shell.open(path);
}

pub fn timer_start(fake: *Fake, timer: Timer) PlatformError!void {
    assert(fake.live);
    assert(timer.interval_ms > 0);

    if (fake.fault.is_armed(.timer_start)) return error.TimerStartFailed;

    return fake.timers.start(timer);
}

pub fn timer_stop(fake: *Fake, id: u32) bool {
    assert(fake.live);

    const result = fake.timers.stop(id);

    assert(!fake.timers.is_running(id));

    return result;
}

pub fn timer_stop_all(fake: *Fake) void {
    assert(fake.live);

    fake.timers.stop_all();

    assert(fake.timers.active_count() == 0);
}

pub fn watcher_watch(
    fake: *Fake,
    path: []const u8,
    listener: Listener,
    context: *anyopaque,
) (CapacityError || PlatformError)!Watch {
    assert(fake.live);
    assert(path.len > 0);

    if (fake.fault.is_armed(.watcher_watch)) return error.WatchAddFailed;

    return fake.watcher.watch(path, listener, context);
}

pub fn watcher_unwatch(fake: *Fake, handle: Watch) void {
    assert(fake.live);
    assert(@backingInt(handle) < interface.watch_count_max);

    fake.watcher.unwatch(handle);
}

pub fn watcher_stop_all(fake: *Fake) void {
    assert(fake.live);

    fake.watcher.stop_all();

    assert(fake.watcher.active_count() == 0);
}

pub fn loop_run(fake: *Fake, comptime Owner: type, owner: *Owner) PlatformError!void {
    assert(fake.live);
    assert(!fake.loop.is_running());

    fake.loop.run(Owner, owner, &fake.tray);

    assert(!fake.loop.is_running());
}

pub fn loop_quit(fake: *Fake) void {
    assert(fake.live);

    fake.loop.quit();

    assert(!fake.loop.is_running());
}

pub fn loop_post(fake: *Fake, code: Event.Code) bool {
    assert(fake.live);

    return fake.loop.post(code, fake.clock.now_ms());
}

const testing = std.testing;

const Counter = struct {
    count: u32 = 0,

    pub fn dispatch(counter: *Counter, event: *const Event) void {
        assert(event.kind().is_valid());

        counter.count += 1;
    }
};

test Fake {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "umbra" });
    defer fake.deinit();

    const icon = try fake.icon_load(.{ .stock = .application });

    try fake.tray_create(.{ .icon = icon, .tooltip = "umbra" });
    try fake.loop.push(Event.create(.{ .tray_left_click = {} }, fake.now_ms()));

    var counter = Counter{};

    try fake.loop_run(Counter, &counter);

    try testing.expectEqualStrings("umbra", fake.name.get());
    try testing.expectEqualStrings("umbra", fake.tray.tooltip_current());
    try testing.expectEqual(@as(u32, 1), counter.count);
    try testing.expectEqual(@as(u32, 1), fake.loop.dispatch_count());
}

test "init starts every part of the fake empty" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "umbra" });

    const icon = try fake.icon_load(.{ .stock = .application });

    try fake.tray_create(.{ .icon = icon, .tooltip = "umbra" });
    try fake.notification_send(.{ .body = "b", .title = "t" });
    try fake.timer_start(.{ .id = 1, .interval_ms = 100 });
    try fake.loop.push(Event.create(.{ .app_init = {} }, fake.now_ms()));

    fake.clock.advance(500);
    fake.fault.arm(.tray_create);
    fake.deinit();

    try fake.init(.{ .name = "umbra" });
    defer fake.deinit();

    try testing.expect(!fake.tray_is_created());
    try testing.expect(!fake.fault.is_armed(.tray_create));
    try testing.expectEqual(@as(u32, 0), fake.icons.live_count());
    try testing.expectEqual(@as(u32, 0), fake.notifier.sent_count());
    try testing.expectEqual(@as(u32, 0), fake.timers.active_count());
    try testing.expectEqual(@as(u32, 0), fake.loop.pending_count());
    try testing.expectEqual(Clock.base_ms, fake.now_ms());
}

test "deinit tears down the tray, the menu, the timers, and the watchers" {
    var fake: Fake = undefined;
    var fired: u32 = 0;

    try fake.init(.{ .name = "umbra" });
    try fake.tray_create(.{});
    try fake.menu_build(&.{.{ .id = 1, .kind = .action, .label = "Open" }});
    try fake.timer_start(.{ .id = 1, .interval_ms = 100 });

    _ = try fake.watcher_watch("config.zon", count_change, &fired);

    fake.deinit();

    try testing.expect(!fake.live);
    try testing.expect(!fake.tray.is_created());
    try testing.expectEqual(@as(u32, 0), fake.menu.item_count());
    try testing.expectEqual(@as(u32, 0), fake.timers.active_count());
    try testing.expectEqual(@as(u32, 0), fake.watcher.active_count());
}

fn count_change(context: *anyopaque) void {
    const fired: *u32 = @ptrCast(@alignCast(context));

    fired.* += 1;
}

test "each armed point fails its call with the platform error that names it" {
    var fake: Fake = undefined;
    var fired: u32 = 0;

    try fake.init(.{ .name = "umbra" });
    defer fake.deinit();

    for (std.enums.values(Fault.Point)) |point| fake.fault.arm(point);

    const items = [_]MenuItem{.{ .id = 1, .kind = .action, .label = "Open" }};
    const notification = Notification{ .body = "b", .title = "t" };
    const timer = Timer{ .id = 1, .interval_ms = 5 };

    try testing.expectError(error.IconLoadFailed, fake.icon_load(.{ .stock = .shield }));
    try testing.expectError(error.MenuBuildFailed, fake.menu_build(&items));
    try testing.expectError(error.NotificationFailed, fake.notification_send(notification));
    try testing.expectError(error.LaunchFailed, fake.shell_open("/tmp/file"));
    try testing.expectError(error.TimerStartFailed, fake.timer_start(timer));
    try testing.expectError(error.TrayCreateFailed, fake.tray_create(.{}));
    try testing.expectError(error.WatchAddFailed, fake.watcher_watch("c", count_change, &fired));

    try testing.expectEqual(@as(u32, 0), fake.notifier.sent_count());
    try testing.expectEqual(@as(u32, 0), fake.shell.opened_count());
    try testing.expect(!fake.tray.is_created());
}

test "loop_post stamps the posted event with the fake clock" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "umbra" });
    defer fake.deinit();

    fake.clock.advance(25);

    try testing.expect(fake.loop_post(@fromBackingInt(7)));
    try testing.expectEqual(Clock.base_ms + 25, fake.loop.queue[0].timestamp_ms);
}
