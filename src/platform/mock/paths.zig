const std = @import("std");

const contract = @import("../contract.zig");

const assert = std.debug.assert;

pub const Error = contract.PathError;

pub const separator: u8 = '/';

pub const config_base = "/mock/config";
pub const state_base = "/mock/state";

comptime {
    assert(separator == '/');
    assert(config_base.len > 0);
    assert(state_base.len > 0);
}

pub fn config_dir(buffer: []u8, app: []const u8) Error![]const u8 {
    return try join(buffer, config_base, app);
}

pub fn state_dir(buffer: []u8, app: []const u8) Error![]const u8 {
    return try join(buffer, state_base, app);
}

fn join(buffer: []u8, base: []const u8, app: []const u8) Error![]const u8 {
    assert(base.len > 0);

    if (app.len == 0) {
        return Error.NotFound;
    }

    const total = base.len + 1 + app.len;

    if (total > buffer.len) {
        return Error.TooLong;
    }

    @memcpy(buffer[0..base.len], base);

    buffer[base.len] = separator;

    @memcpy(buffer[base.len + 1 ..][0..app.len], app);

    assert(total <= buffer.len);

    return buffer[0..total];
}

const testing = std.testing;

test "state_dir returns a fixed path under the app name" {
    var buffer: [contract.path_bytes_max]u8 = undefined;

    try testing.expectEqualStrings("/mock/state/phantom", try state_dir(&buffer, "phantom"));
}

test "config_dir returns a fixed path under the app name" {
    var buffer: [contract.path_bytes_max]u8 = undefined;

    try testing.expectEqualStrings("/mock/config/phantom", try config_dir(&buffer, "phantom"));
}

test "an empty app name is refused" {
    var buffer: [contract.path_bytes_max]u8 = undefined;

    try testing.expectError(Error.NotFound, state_dir(&buffer, ""));
}

test "a buffer that cannot hold the path is refused" {
    var buffer: [8]u8 = undefined;

    try testing.expectError(Error.TooLong, state_dir(&buffer, "phantom"));
}
