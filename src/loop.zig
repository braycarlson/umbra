const std = @import("std");

const platform = @import("platform.zig");

const backend = platform.backend.loop;

pub fn post(code: u32) bool {
    return backend.post(code);
}

const testing = std.testing;

const mock = platform.mock;

test post {
    mock.reset();

    try testing.expect(post(42));
    try testing.expectEqual(@as(u32, 1), mock.loop.posts());
    try testing.expectEqual(@as(u32, 1), mock.loop.pending_count());
}
