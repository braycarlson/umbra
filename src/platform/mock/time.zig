const std = @import("std");

const assert = std.debug.assert;

pub const base_ms: u64 = 1_000;

var current_ms: u64 = base_ms;
var sleep_total_ms: u64 = 0;

comptime {
    assert(base_ms > 0);
}

pub fn now_ms() u64 {
    assert(current_ms >= base_ms);

    return current_ms;
}

pub fn sleep_ms(duration_ms: u32) void {
    sleep_total_ms += duration_ms;

    advance(duration_ms);

    assert(current_ms >= base_ms);
}

pub fn advance(duration_ms: u64) void {
    const previous = current_ms;

    current_ms += duration_ms;

    assert(current_ms >= previous);
}

pub fn slept_ms() u64 {
    return sleep_total_ms;
}

pub fn reset() void {
    current_ms = base_ms;
    sleep_total_ms = 0;

    assert(current_ms == base_ms);
    assert(sleep_total_ms == 0);
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

test "sleep_ms advances the virtual clock" {
    reset();

    sleep_ms(25);

    try testing.expectEqual(base_ms + 25, now_ms());
    try testing.expectEqual(@as(u64, 25), slept_ms());
}

test "reset restores the base" {
    reset();
    advance(1_000);
    reset();

    try testing.expectEqual(base_ms, now_ms());
    try testing.expectEqual(@as(u64, 0), slept_ms());
}
