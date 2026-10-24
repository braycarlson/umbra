const std = @import("std");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const second_ms: u64 = 1_000;
pub const millisecond_ns: u64 = 1_000_000;

comptime {
    assert(second_ms == 1_000);
    assert(millisecond_ns == 1_000_000);
}

pub fn now_ms() u64 {
    var value: linux.timespec = undefined;

    const status = linux.clock_gettime(linux.CLOCK.MONOTONIC, &value);

    if (posix.errno(status) != .SUCCESS) {
        return 0;
    }

    const seconds: u64 = @intCast(value.sec);
    const nanoseconds: u64 = @intCast(value.nsec);

    return seconds * second_ms + nanoseconds / millisecond_ns;
}

const testing = std.testing;

test "now_ms never moves backwards" {
    const first = now_ms();
    const second = now_ms();

    try testing.expect(second >= first);
}
