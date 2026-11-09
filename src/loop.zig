const std = @import("std");

const event_module = @import("event.zig");
const platform = @import("platform.zig");

const backend = platform.backend.loop;

const Event = event_module.Event;

pub fn post(code: Event.Code) bool {
    return backend.post(code);
}

const testing = std.testing;

const mock = platform.mock;

test post {
    mock.reset();

    try testing.expect(post(@fromBackingInt(42)));
    try testing.expectEqual(@as(u32, 1), mock.loop.posts());
    try testing.expectEqual(@as(u32, 1), mock.loop.pending_count());
}
