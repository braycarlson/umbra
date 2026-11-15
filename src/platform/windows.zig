const std = @import("std");

const event_module = @import("../event.zig");
const IconTable = @import("windows/icon_table.zig");
const interface = @import("interface.zig");
const Loop = @import("windows/loop.zig");
const Menu = @import("windows/menu.zig");
const notification_module = @import("windows/notification.zig");
const paths = @import("windows/paths.zig");
const shell = @import("windows/shell.zig");
const Taskbar = @import("windows/taskbar.zig");
const time = @import("windows/time.zig");
const TimerTable = @import("windows/timer_table.zig");
const Tray = @import("windows/tray.zig");
const w32 = @import("windows/win32.zig");
const Watcher = @import("windows/watcher.zig");
const Window = @import("windows/window.zig");

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

const Windows = @This();

icons: IconTable,
loop: Loop,
menu: Menu,
name: [name_units_max]u16,
taskbar: Taskbar,
timers: TimerTable,
tray: Tray,
watcher: Watcher,
window: Window,

pub const paths_config_dir = paths.config_dir;
pub const paths_state_dir = paths.state_dir;
const name_units_max: u32 = interface.app_name_bytes_max + 1;

comptime {
    assert(name_units_max > interface.app_name_bytes_max);
    assert(name_units_max < Window.name_max);

    interface.assert_backend(Windows);
}

pub fn init(windows: *Windows, options: interface.Options) PlatformError!void {
    assert(options.is_valid());
    assert(options.name.len < name_units_max);

    windows.taskbar = .unregistered;
    windows.window = .closed;

    windows.icons.init();
    windows.menu.init(&windows.window);
    windows.timers.init(&windows.window);
    windows.tray.init(&windows.icons, &windows.window);
    windows.watcher.init(&windows.window);

    windows.loop.init(.{
        .menu = &windows.menu,
        .taskbar = &windows.taskbar,
        .watcher = &windows.watcher,
        .window = &windows.window,
    });

    try windows.open(options.name);

    _ = windows.taskbar.register();

    assert(windows.window.is_open());
    assert(windows.taskbar.restart_message() != 0);
}

fn open(windows: *Windows, name: []const u8) PlatformError!void {
    assert(name.len > 0);
    assert(name.len < name_units_max);

    const length = std.unicode.utf8ToUtf16Le(windows.name[0..name.len], name) catch {
        return error.InitFailed;
    };

    assert(length > 0);
    assert(length < name_units_max);

    windows.name[length] = 0;

    const module: w32.HINSTANCE = @ptrCast(w32.GetModuleHandleW(null));

    assert(@intFromPtr(module) != 0);

    const pointer: [*:0]const u16 = @ptrCast(&windows.name);

    const config = Window.Config{
        .callback = Loop.window_proc,
        .context = &windows.loop,
        .instance = module,
        .name = pointer[0..length :0],
    };

    windows.window.open(&config) catch {
        return error.InitFailed;
    };
}

pub fn deinit(windows: *Windows) void {
    assert(windows.window.is_open());
    assert(windows.loop.owner == null);

    windows.tray.destroy();
    windows.menu.destroy();
    windows.timers.stop_all();
    windows.watcher.stop_all();
    windows.window.close();

    assert(!windows.window.is_open());
    assert(!windows.tray.is_created());
}

pub fn now_ms(windows: *const Windows) u64 {
    assert(windows.window.is_open());

    return time.now_ms();
}

pub fn icon_load(windows: *Windows, source: Icon.Source) (CapacityError || PlatformError)!Icon {
    assert(windows.window.is_open());
    assert(source.is_valid());

    return windows.icons.load(source);
}

pub fn icon_destroy(windows: *Windows, icon: Icon) void {
    assert(windows.window.is_open());
    assert(@backingInt(icon) < interface.icon_count_max);

    windows.icons.destroy(icon);
}

pub fn tray_activation_token(windows: *const Windows) []const u8 {
    assert(windows.window.is_open());

    const result = windows.tray.activation_token();

    assert(result.len <= interface.activation_token_bytes_max);

    return result;
}

pub fn tray_create(windows: *Windows, options: TrayCreateOptions) PlatformError!void {
    assert(windows.window.is_open());
    assert(options.tooltip.len <= interface.tooltip_bytes_max);

    return windows.tray.create(options);
}

pub fn tray_destroy(windows: *Windows) void {
    assert(windows.window.is_open());

    windows.tray.destroy();

    assert(!windows.tray.is_created());
}

pub fn tray_is_created(windows: *const Windows) bool {
    assert(windows.window.is_open());

    return windows.tray.is_created();
}

pub fn tray_set_icon(windows: *Windows, icon: Icon) PlatformError!void {
    assert(windows.window.is_open());
    assert(@backingInt(icon) < interface.icon_count_max);

    return windows.tray.set_icon(icon);
}

pub fn tray_set_tooltip(windows: *Windows, tooltip: []const u8) PlatformError!void {
    assert(windows.window.is_open());
    assert(tooltip.len <= interface.tooltip_bytes_max);

    return windows.tray.set_tooltip(tooltip);
}

pub fn menu_build(windows: *Windows, items: []const MenuItem) PlatformError!void {
    assert(windows.window.is_open());
    assert(interface.is_valid_layout(items));

    return windows.menu.build(items);
}

pub fn menu_destroy(windows: *Windows) void {
    assert(windows.window.is_open());

    windows.menu.destroy();

    assert(windows.menu.current == null);
}

pub fn notification_send(windows: *Windows, notification: Notification) PlatformError!void {
    assert(windows.window.is_open());
    assert(notification.is_valid());

    return notification_module.send(&windows.tray, notification);
}

pub fn shell_open(windows: *Windows, path: []const u8) PlatformError!void {
    assert(windows.window.is_open());
    assert(path.len > 0);

    return shell.open(path);
}

pub fn timer_start(windows: *Windows, timer: Timer) PlatformError!void {
    assert(windows.window.is_open());
    assert(timer.interval_ms > 0);

    return windows.timers.start(timer);
}

pub fn timer_stop(windows: *Windows, id: u32) bool {
    assert(windows.window.is_open());

    const result = windows.timers.stop(id);

    assert(!windows.timers.is_running(id));

    return result;
}

pub fn timer_stop_all(windows: *Windows) void {
    assert(windows.window.is_open());

    windows.timers.stop_all();

    assert(windows.timers.active_count() == 0);
}

pub fn watcher_watch(
    windows: *Windows,
    path: []const u8,
    listener: Listener,
    context: *anyopaque,
) (CapacityError || PlatformError)!Watch {
    assert(windows.window.is_open());
    assert(path.len > 0);

    return windows.watcher.watch(path, listener, context);
}

pub fn watcher_unwatch(windows: *Windows, handle: Watch) void {
    assert(windows.window.is_open());
    assert(@backingInt(handle) < interface.watch_count_max);

    windows.watcher.unwatch(handle);
}

pub fn watcher_stop_all(windows: *Windows) void {
    assert(windows.window.is_open());

    windows.watcher.stop_all();

    assert(windows.watcher.active_count() == 0);
}

pub fn loop_run(windows: *Windows, comptime Owner: type, owner: *Owner) PlatformError!void {
    assert(windows.window.is_open());
    assert(windows.loop.owner == null);

    try windows.loop.run(Owner, owner);

    assert(windows.loop.owner == null);
}

pub fn loop_quit(windows: *Windows) void {
    assert(windows.window.is_open());

    Loop.quit();
}

pub fn loop_post(windows: *Windows, code: Event.Code) bool {
    return windows.loop.post(code);
}
