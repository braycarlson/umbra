const std = @import("std");

const assert = std.debug.assert;

pub const restart_message_id: u32 = 0xC001;
pub const registered_range_start: u32 = 0xC000;

var registered: u32 = 0;
var restart_count: u32 = 0;

comptime {
    assert(restart_message_id >= registered_range_start);
}

pub fn restart_message() u32 {
    if (registered == 0) {
        registered = restart_message_id;
    }

    assert(registered == restart_message_id);

    return registered;
}

pub fn is_restart(message: u32) bool {
    if (registered == 0) {
        return false;
    }

    return message == registered;
}

pub fn note_restart() void {
    restart_count += 1;

    assert(restart_count > 0);
}

pub fn restarts() u32 {
    return restart_count;
}

pub fn reset() void {
    registered = 0;
    restart_count = 0;

    assert(registered == 0);
    assert(restart_count == 0);
}

const testing = std.testing;

test "is_restart is false before the message is registered" {
    reset();

    try testing.expect(!is_restart(0));
    try testing.expect(!is_restart(restart_message_id));
}

test "is_restart matches only the registered message" {
    reset();

    try testing.expect(is_restart(restart_message()));
    try testing.expect(!is_restart(restart_message_id + 1));
    try testing.expect(restart_message() >= registered_range_start);
}

test "note_restart counts observed restarts" {
    reset();

    note_restart();
    note_restart();

    try testing.expectEqual(@as(u32, 2), restarts());
}
