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

pub const name_bytes_max: u32 = 64;

pub const Error = contract.RuntimeError;

pub const Options = contract.RuntimeOptions;

var opened: bool = false;
var instance: ?w32.HINSTANCE = null;
var name_wide: [name_bytes_max]u16 = undefined;

comptime {
    assert(name_bytes_max > 0);
}

pub fn open(options: Options) Error!void {
    if (opened) {
        return Error.AlreadyOpen;
    }

    if (!options.is_valid() or options.name.len >= name_bytes_max) {
        return Error.InvalidOptions;
    }

    const length = std.unicode.utf8ToUtf16Le(name_wide[0..options.name.len], options.name) catch {
        return Error.InvalidOptions;
    };

    if (length == 0 or length >= name_bytes_max) {
        return Error.InvalidOptions;
    }

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
        return Error.OpenFailed;
    };

    instance = module;
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

    instance = null;
    opened = false;

    assert(!opened);
    assert(!window_api.is_open());
    assert(!tray.is_created());
}

pub fn is_open() bool {
    return opened;
}

pub fn module_instance() ?w32.HINSTANCE {
    return instance;
}

const testing = std.testing;

test "open rejects an empty name" {
    if (is_open()) {
        return;
    }

    try testing.expectError(Error.InvalidOptions, open(.{ .name = "" }));
}

test "open rejects an oversized name" {
    if (is_open()) {
        return;
    }

    const long = [_]u8{'a'} ** name_bytes_max;

    try testing.expectError(Error.InvalidOptions, open(.{ .name = &long }));
}
