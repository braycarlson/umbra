const std = @import("std");

const assert = std.debug.assert;

pub const base_ms: u64 = 1_000;

var clock_ms: u64 = base_ms;

comptime {
    assert(base_ms > 0);
}

pub fn now_ms() u64 {
    assert(clock_ms >= base_ms);

    return clock_ms;
}

pub fn advance(duration_ms: u64) void {
    const previous = clock_ms;

    clock_ms += duration_ms;

    assert(clock_ms >= previous);
}

pub fn reset() void {
    clock_ms = base_ms;

    assert(clock_ms == base_ms);
}

const testing = std.testing;

test "now_ms starts at the base and never moves backwards" {
    reset();

    const first = now_ms();

    advance(5);

    const second = now_ms();

    try testing.expectEqual(base_ms, first);
    try testing.expect(second > first);
}

test "reset restores the base" {
    reset();
    advance(1_000);
    reset();

    try testing.expectEqual(base_ms, now_ms());
}
