const std = @import("std");

const Client = @import("linux/dbus.zig").Client;
const event_module = @import("../event.zig");
const IconTable = @import("linux/icon_table.zig");
const interface = @import("interface.zig");
const Loop = @import("linux/loop.zig");
const Menu = @import("linux/menu.zig");
const notification_module = @import("linux/notification.zig");
const paths = @import("linux/paths.zig");
const PostQueue = @import("linux/post_queue.zig");
const shell = @import("linux/shell.zig");
const time = @import("linux/time.zig");
const TimerTable = @import("linux/timer_table.zig");
const Tray = @import("linux/tray.zig");
const Watcher = @import("linux/watcher.zig");

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

const app_name_bytes_max = interface.app_name_bytes_max;

const Linux = @This();

client: Client,
icons: IconTable,
loop: Loop,
menu: Menu,
name: [app_name_bytes_max]u8,
name_len: u8,
post_queue: PostQueue,
timers: TimerTable,
tray: Tray,
watcher: Watcher,

pub const paths_config_dir = paths.config_dir;
pub const paths_state_dir = paths.state_dir;

comptime {
    interface.assert_backend(Linux);
}

pub fn init(linux: *Linux, options: interface.Options) PlatformError!void {
    assert(options.is_valid());
    assert(options.name.len <= app_name_bytes_max);

    linux.copy_name(options.name);
    linux.client.init();
    linux.icons.init();
    linux.menu.init(&linux.client);
    linux.post_queue.init();
    linux.timers.init(&linux.loop.epoll);
    linux.tray.init(&linux.client, &linux.icons, linux.name_get());
    linux.watcher.init(&linux.loop.epoll);

    linux.loop.init(.{
        .client = &linux.client,
        .menu = &linux.menu,
        .post_queue = &linux.post_queue,
        .timers = &linux.timers,
        .tray = &linux.tray,
        .watcher = &linux.watcher,
    });

    linux.client.connect() catch return error.InitFailed;
    errdefer linux.client.disconnect();

    linux.tray.claim() catch return error.InitFailed;

    assert(linux.client.is_connected());
    assert(!linux.tray.is_created());
}

pub fn deinit(linux: *Linux) void {
    assert(linux.client.is_connected());
    assert(linux.loop.owner == null);

    linux.tray.destroy();
    linux.menu.destroy();
    linux.timers.stop_all();
    linux.watcher.stop_all();
    linux.client.disconnect();

    assert(!linux.client.is_connected());
    assert(!linux.tray.is_created());
}

pub fn now_ms(linux: *const Linux) u64 {
    assert(linux.client.is_connected());

    return time.now_ms();
}

pub fn icon_load(linux: *Linux, source: Icon.Source) (CapacityError || PlatformError)!Icon {
    assert(linux.client.is_connected());
    assert(source.is_valid());

    return linux.icons.load(source);
}

pub fn icon_destroy(linux: *Linux, icon: Icon) void {
    assert(linux.client.is_connected());
    assert(@backingInt(icon) < interface.icon_count_max);

    linux.icons.destroy(icon);
}

pub fn tray_activation_token(linux: *const Linux) []const u8 {
    assert(linux.client.is_connected());

    const result = linux.tray.activation_token();

    assert(result.len <= interface.activation_token_bytes_max);

    return result;
}

pub fn tray_create(linux: *Linux, options: TrayCreateOptions) PlatformError!void {
    assert(linux.client.is_connected());
    assert(options.tooltip.len <= interface.tooltip_bytes_max);

    return linux.tray.create(options);
}

pub fn tray_destroy(linux: *Linux) void {
    assert(linux.client.is_connected());

    linux.tray.destroy();

    assert(!linux.tray.is_created());
}

pub fn tray_is_created(linux: *const Linux) bool {
    assert(linux.client.is_connected());

    return linux.tray.is_created();
}

pub fn tray_set_icon(linux: *Linux, icon: Icon) PlatformError!void {
    assert(linux.client.is_connected());
    assert(@backingInt(icon) < interface.icon_count_max);

    return linux.tray.set_icon(icon);
}

pub fn tray_set_tooltip(linux: *Linux, tooltip: []const u8) PlatformError!void {
    assert(linux.client.is_connected());
    assert(tooltip.len <= interface.tooltip_bytes_max);

    return linux.tray.set_tooltip(tooltip);
}

pub fn menu_build(linux: *Linux, items: []const MenuItem) PlatformError!void {
    assert(linux.client.is_connected());
    assert(interface.is_valid_layout(items));

    return linux.menu.build(items);
}

pub fn menu_destroy(linux: *Linux) void {
    assert(linux.client.is_connected());

    linux.menu.destroy();

    assert(linux.menu.item_count() == 0);
}

pub fn notification_send(linux: *Linux, notification: Notification) PlatformError!void {
    assert(linux.client.is_connected());
    assert(notification.is_valid());

    return notification_module.send(&linux.client, linux.name_get(), notification);
}

pub fn shell_open(linux: *Linux, path: []const u8) PlatformError!void {
    assert(linux.client.is_connected());
    assert(path.len > 0);

    return shell.open(path);
}

pub fn timer_start(linux: *Linux, timer: Timer) PlatformError!void {
    assert(linux.client.is_connected());
    assert(timer.interval_ms > 0);

    return linux.timers.start(timer);
}

pub fn timer_stop(linux: *Linux, id: u32) bool {
    assert(linux.client.is_connected());

    const result = linux.timers.stop(id);

    assert(!linux.timers.is_running(id));

    return result;
}

pub fn timer_stop_all(linux: *Linux) void {
    assert(linux.client.is_connected());

    linux.timers.stop_all();

    assert(linux.timers.active_count() == 0);
}

pub fn watcher_watch(
    linux: *Linux,
    path: []const u8,
    listener: Listener,
    context: *anyopaque,
) (CapacityError || PlatformError)!Watch {
    assert(linux.client.is_connected());
    assert(path.len > 0);

    return linux.watcher.watch(path, listener, context);
}

pub fn watcher_unwatch(linux: *Linux, handle: Watch) void {
    assert(linux.client.is_connected());
    assert(@backingInt(handle) < interface.watch_count_max);

    linux.watcher.unwatch(handle);
}

pub fn watcher_stop_all(linux: *Linux) void {
    assert(linux.client.is_connected());

    linux.watcher.stop_all();

    assert(linux.watcher.active_count() == 0);
}

pub fn loop_run(linux: *Linux, comptime Owner: type, owner: *Owner) PlatformError!void {
    assert(linux.client.is_connected());
    assert(linux.loop.owner == null);

    try linux.loop.run(Owner, owner);

    assert(linux.loop.owner == null);
}

pub fn loop_quit(linux: *Linux) void {
    assert(linux.client.is_connected());

    linux.loop.quit();

    assert(linux.loop.quit_requested);
}

pub fn loop_post(linux: *Linux, code: Event.Code) bool {
    return linux.post_queue.post(code);
}

fn copy_name(linux: *Linux, name: []const u8) void {
    assert(name.len <= app_name_bytes_max);

    @memcpy(linux.name[0..name.len], name);

    linux.name_len = @intCast(name.len);

    assert(linux.name_len == name.len);
}

fn name_get(linux: *const Linux) []const u8 {
    assert(linux.name_len <= app_name_bytes_max);

    return linux.name[0..linux.name_len];
}

const testing = std.testing;

test "the name storage holds the full application name bound" {
    const linux = try testing.allocator.create(Linux);
    defer testing.allocator.destroy(linux);

    const longest: [app_name_bytes_max]u8 = @splat('a');

    linux.copy_name(&longest);

    try testing.expectEqualStrings(&longest, linux.name_get());
}
