const std = @import("std");

const assert = std.debug.assert;

const Clock = @This();

time_ms: u64,

pub const base_ms: u64 = 1_000;
pub const start: Clock = .{ .time_ms = base_ms };

comptime {
    assert(base_ms > 0);
    assert(start.time_ms == base_ms);
}

pub fn now_ms(clock: *const Clock) u64 {
    assert(clock.time_ms >= base_ms);

    return clock.time_ms;
}

pub fn advance(clock: *Clock, duration_ms: u64) void {
    const previous = clock.time_ms;

    clock.time_ms += duration_ms;

    assert(clock.time_ms >= previous);
}

const testing = std.testing;

test "now_ms starts at the base and never moves backwards" {
    var clock: Clock = .start;

    const first = clock.now_ms();

    clock.advance(5);

    const second = clock.now_ms();

    try testing.expectEqual(base_ms, first);
    try testing.expect(second > first);
}

test "a fresh clock reads the base however far another clock advanced" {
    var clock: Clock = .start;

    clock.advance(1_000);

    const fresh: Clock = .start;

    try testing.expectEqual(base_ms, fresh.now_ms());
}
