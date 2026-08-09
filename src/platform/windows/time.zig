const std = @import("std");

const w32 = @import("win32.zig");

const assert = std.debug.assert;

pub fn now_ms() u64 {
    const result: u64 = w32.GetTickCount64();

    return result;
}

pub fn sleep_ms(duration_ms: u32) void {
    w32.Sleep(duration_ms);
}

const testing = std.testing;

test "now_ms never moves backwards" {
    const first = now_ms();
    const second = now_ms();

    assert(second >= first);

    try testing.expect(second >= first);
}
