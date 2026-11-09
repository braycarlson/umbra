const std = @import("std");

const w32 = @import("win32.zig");

const contract = @import("../contract.zig");
const loop = @import("loop.zig");
const menu = @import("menu.zig");
const taskbar = @import("taskbar.zig");
const timer = @import("timer.zig");
const watcher = @import("watcher/root.zig");
const tray = @import("tray.zig");
const window_api = @import("window.zig");

const assert = std.debug.assert;

const Options = contract.RuntimeOptions;
const PlatformError = contract.PlatformError;

const name_units_max: u32 = contract.app_name_bytes_max + 1;

var opened: bool = false;
var name_wide: [name_units_max]u16 = undefined;

comptime {
    assert(name_units_max > contract.app_name_bytes_max);
    assert(name_units_max < window_api.name_max);
}

pub fn open(options: Options) PlatformError!void {
    assert(!opened);
    assert(options.is_valid());

    const length = std.unicode.utf8ToUtf16Le(name_wide[0..options.name.len], options.name) catch {
        return error.RuntimeOpenFailed;
    };

    assert(length > 0);
    assert(length < name_units_max);

    name_wide[length] = 0;

    const module: w32.HINSTANCE = @ptrCast(w32.GetModuleHandleW(null));

    assert(@intFromPtr(module) != 0);

    const pointer: [*:0]const u16 = @ptrCast(&name_wide);

    const config = window_api.Config{
        .callback = loop.window_proc,
        .instance = module,
        .name = pointer[0..length :0],
    };

    window_api.open(&config) catch {
        return error.RuntimeOpenFailed;
    };

    opened = true;

    _ = taskbar.register();

    assert(opened);
    assert(window_api.is_open());
    assert(taskbar.restart_message() != 0);
}

pub fn close() void {
    if (!opened) {
        return;
    }

    tray.destroy();
    menu.destroy();
    timer.stop_all();
    watcher.stop_all();

    window_api.close();

    opened = false;

    assert(!opened);
    assert(!window_api.is_open());
    assert(!tray.is_created());
}

pub fn is_open() bool {
    return opened;
}
