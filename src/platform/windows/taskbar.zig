const std = @import("std");

const w32 = @import("win32.zig");

const assert = std.debug.assert;

var registered: u32 = 0;

pub fn register() u32 {
    if (registered != 0) {
        return registered;
    }

    const name = std.unicode.utf8ToUtf16LeStringLiteral("TaskbarCreated");

    registered = w32.RegisterWindowMessageW(name);

    return registered;
}

pub fn restart_message() u32 {
    return register();
}

pub fn is_restart(message: u32) bool {
    if (registered == 0) {
        return false;
    }

    return message == registered;
}

fn reset() void {
    registered = 0;

    assert(registered == 0);
}

const testing = std.testing;

test "is_restart is false before the message is registered" {
    reset();

    try testing.expect(!is_restart(0));
    try testing.expect(!is_restart(0x8000));
}

test "restart_message caches the registration" {
    reset();

    const first = restart_message();
    const second = restart_message();

    try testing.expectEqual(first, second);
}
