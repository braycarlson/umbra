const std = @import("std");

const contract = @import("../contract.zig");
const fault = @import("fault.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

const PlatformError = contract.PlatformError;

pub const opened_max: u32 = 16;

comptime {
    assert(opened_max > 0);
}

var entries: [opened_max]record.Text = undefined;
var count: u32 = 0;
var open_count: u32 = 0;

pub fn open(path: []const u8) PlatformError!void {
    assert(path.len > 0);
    assert(path.len < contract.path_bytes_max);

    if (fault.is_armed(.shell_open)) {
        return error.LaunchFailed;
    }

    open_count += 1;

    if (count == opened_max) {
        return;
    }

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

pub fn reset() void {
    count = 0;
    open_count = 0;

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
}

test "a failing shell reports the failed launch" {
    reset();
    fault.reset();
    fault.arm(.shell_open);
    defer fault.reset();

    try testing.expectError(error.LaunchFailed, open("/tmp/file"));
    try testing.expectEqual(@as(u32, 0), opened_count());
}
