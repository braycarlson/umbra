const std = @import("std");

const platform = @import("platform.zig");

const backend = platform.backend.time;

pub fn now_ms() u64 {
    return backend.now_ms();
}

const testing = std.testing;

const mock = platform.mock;

test now_ms {
    mock.reset();

    const before = now_ms();

    mock.time.advance(25);

    try testing.expectEqual(before + 25, now_ms());
}
