const std = @import("std");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const ms_per_second: u64 = 1_000;
pub const ns_per_ms: u64 = 1_000_000;

comptime {
    assert(ms_per_second == 1_000);
    assert(ns_per_ms == 1_000_000);
}

pub fn now_ms() u64 {
    var value: linux.timespec = undefined;

    const status = linux.clock_gettime(linux.CLOCK.MONOTONIC, &value);

    if (posix.errno(status) != .SUCCESS) {
        return 0;
    }

    const seconds: u64 = @intCast(value.sec);
    const nanoseconds: u64 = @intCast(value.nsec);

    return seconds * ms_per_second + nanoseconds / ns_per_ms;
}

pub fn sleep_ms(duration_ms: u32) void {
    if (duration_ms == 0) {
        return;
    }

    const total: u64 = @as(u64, duration_ms) * ns_per_ms;

    var request = linux.timespec{
        .sec = @intCast(total / (ms_per_second * ns_per_ms)),
        .nsec = @intCast(total % (ms_per_second * ns_per_ms)),
    };

    var remaining: linux.timespec = undefined;

    _ = linux.nanosleep(&request, &remaining);
}

const testing = std.testing;

test "now_ms never moves backwards" {
    const first = now_ms();
    const second = now_ms();

    try testing.expect(second >= first);
}

test "sleep_ms advances the monotonic clock" {
    const before = now_ms();

    sleep_ms(2);

    const after = now_ms();

    try testing.expect(after >= before);
}
