const std = @import("std");

const contract = @import("../contract.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

pub const Error = contract.ShellError;

pub const opened_max: u32 = 16;

comptime {
    assert(opened_max > 0);
}

var entries: [opened_max]record.Text = undefined;
var count: u32 = 0;
var open_count: u32 = 0;
var fail_open: bool = false;

pub fn open(path: []const u8) Error!void {
    if (path.len == 0 or path.len >= contract.path_bytes_max) {
        return Error.InvalidPath;
    }

    if (fail_open) {
        return Error.LaunchFailed;
    }

    open_count += 1;

    if (count >= opened_max) {
        return;
    }

    assert(count < opened_max);

    entries[count] = record.Text.empty();
    entries[count].set(path);
    count += 1;

    assert(count <= opened_max);
}

pub fn opened_count() u32 {
    return open_count;
}

pub fn recorded_count() u32 {
    assert(count <= opened_max);

    return count;
}

pub fn path_at(index: u32) []const u8 {
    assert(index < count);

    return entries[index].get();
}

pub fn set_fail_open(fail: bool) void {
    fail_open = fail;
}

pub fn reset() void {
    count = 0;
    open_count = 0;
    fail_open = false;

    assert(count == 0);
    assert(open_count == 0);
}

const testing = std.testing;

test "open records the requested path" {
    reset();

    try open("/tmp/config.zon");

    try testing.expectEqual(@as(u32, 1), opened_count());
    try testing.expectEqual(@as(u32, 1), recorded_count());
    try testing.expectEqualStrings("/tmp/config.zon", path_at(0));

    reset();
}

test "open rejects an empty path" {
    reset();

    try testing.expectError(Error.InvalidPath, open(""));
    try testing.expectEqual(@as(u32, 0), opened_count());
}

test "a failing shell reports LaunchFailed" {
    reset();
    set_fail_open(true);

    try testing.expectError(Error.LaunchFailed, open("/tmp/file"));

    reset();
}
