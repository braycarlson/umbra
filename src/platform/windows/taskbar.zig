const std = @import("std");

const w32 = @import("win32.zig");

const assert = std.debug.assert;

const Taskbar = @This();

registered: u32,

pub const unregistered: Taskbar = .{ .registered = 0 };

pub fn register(taskbar: *Taskbar) u32 {
    if (taskbar.registered != 0) {
        return taskbar.registered;
    }

    const name = std.unicode.utf8ToUtf16LeStringLiteral("TaskbarCreated");

    taskbar.registered = w32.RegisterWindowMessageW(name);

    return taskbar.registered;
}

pub fn restart_message(taskbar: *Taskbar) u32 {
    return taskbar.register();
}

pub fn is_restart(taskbar: *const Taskbar, message: u32) bool {
    if (taskbar.registered == 0) {
        return false;
    }

    return message == taskbar.registered;
}

const testing = std.testing;

test "is_restart is false before the message is registered" {
    const taskbar: Taskbar = .unregistered;

    try testing.expect(!taskbar.is_restart(0));
    try testing.expect(!taskbar.is_restart(0x8000));
}

test "restart_message caches the registration" {
    var taskbar: Taskbar = .unregistered;

    const first = taskbar.restart_message();
    const second = taskbar.restart_message();

    assert(first == taskbar.registered);

    try testing.expectEqual(first, second);
}
