const std = @import("std");

const runtime = @import("runtime.zig");

const assert = std.debug.assert;

pub const Handle = u32;

pub const handle_value: Handle = 1;
pub const posted_max: u32 = 16;

comptime {
    assert(handle_value != 0);
    assert(posted_max > 0);
}

const Message = struct {
    lparam: i64,
    message: u32,
    wparam: u64,
};

var posted: [posted_max]Message = undefined;
var posted_count: u32 = 0;
var post_count: u32 = 0;

pub fn handle() ?Handle {
    if (!runtime.is_open()) {
        return null;
    }

    return handle_value;
}

pub fn post(message: u32, wparam: u64, lparam: i64) bool {
    if (!runtime.is_open()) {
        return false;
    }

    post_count += 1;

    if (posted_count < posted_max) {
        posted[posted_count] = .{ .lparam = lparam, .message = message, .wparam = wparam };
        posted_count += 1;
    }

    assert(posted_count <= posted_max);

    return true;
}

pub fn posted_message(index: u32) ?u32 {
    if (index >= posted_count) {
        return null;
    }

    return posted[index].message;
}

pub fn posts() u32 {
    return post_count;
}

pub fn reset() void {
    posted_count = 0;
    post_count = 0;

    assert(posted_count == 0);
    assert(post_count == 0);
}

const testing = std.testing;

test "handle is available only while the runtime is open" {
    runtime.reset();
    reset();

    try testing.expect(handle() == null);

    try runtime.open(.{ .name = "umbra" });

    try testing.expectEqual(@as(?Handle, handle_value), handle());

    runtime.close();
}

test "post records the message while the runtime is open" {
    runtime.reset();
    reset();

    try testing.expect(!post(1, 0, 0));

    try runtime.open(.{ .name = "umbra" });

    try testing.expect(post(0x0010, 2, -3));
    try testing.expectEqual(@as(?u32, 0x0010), posted_message(0));
    try testing.expectEqual(@as(u32, 1), posts());

    runtime.close();
}
