const std = @import("std");

const contract = @import("../contract.zig");
const sys = @import("sys.zig");

const assert = std.debug.assert;

pub const Error = contract.PathError;

pub const segment_max: u32 = 3;
pub const separator: u8 = '/';

pub const config_variable = "XDG_CONFIG_HOME";
pub const config_fallback = ".config";
pub const state_variable = "XDG_STATE_HOME";
pub const state_fallback = ".local/state";

comptime {
    assert(segment_max > 0);
    assert(separator == '/');
    assert(config_variable.len > 0);
    assert(config_fallback.len > 0);
    assert(state_variable.len > 0);
    assert(state_fallback.len > 0);
}

pub fn config_dir(buffer: []u8, app: []const u8) Error![]const u8 {
    return try resolve(buffer, app, config_variable, config_fallback);
}

pub fn state_dir(buffer: []u8, app: []const u8) Error![]const u8 {
    return try resolve(buffer, app, state_variable, state_fallback);
}

fn resolve(
    buffer: []u8,
    app: []const u8,
    variable: []const u8,
    fallback: []const u8,
) Error![]const u8 {
    assert(app.len > 0);
    assert(variable.len > 0);
    assert(fallback.len > 0);

    if (sys.getenv(variable)) |value| {
        const base = trim(value);

        if (base.len > 0 and base[0] == separator) {
            return try join(buffer, &.{ base, app });
        }
    }

    const home = trim(sys.getenv("HOME") orelse return Error.NotFound);

    if (home.len == 0 or home[0] != separator) {
        return Error.NotFound;
    }

    return try join(buffer, &.{ home, fallback, app });
}

fn join(buffer: []u8, segments: []const []const u8) Error![]const u8 {
    assert(segments.len > 0);
    assert(segments.len <= segment_max);

    var length: usize = 0;
    var index: usize = 0;

    while (index < segments.len and index < segment_max) : (index += 1) {
        const segment = segments[index];

        assert(segment.len > 0);

        if (length > 0) {
            if (length + 1 > buffer.len) {
                return Error.TooLong;
            }

            buffer[length] = separator;
            length += 1;
        }

        if (length + segment.len > buffer.len) {
            return Error.TooLong;
        }

        @memcpy(buffer[length..][0..segment.len], segment);

        length += segment.len;
    }

    assert(index == segments.len);
    assert(length <= buffer.len);
    assert(length > 0);

    return buffer[0..length];
}

fn trim(value: []const u8) []const u8 {
    var length = value.len;

    while (length > 1 and value[length - 1] == separator) {
        length -= 1;
    }

    assert(length <= value.len);

    return value[0..length];
}

const testing = std.testing;

test "join builds a separated path" {
    var buffer: [64]u8 = undefined;

    const joined = try join(&buffer, &.{ "/home/user", ".config", "phantom" });

    try testing.expectEqualStrings("/home/user/.config/phantom", joined);
}

test "join refuses a path longer than the buffer" {
    var buffer: [8]u8 = undefined;

    try testing.expectError(Error.TooLong, join(&buffer, &.{ "/home/user", "phantom" }));
}

test "join refuses a separator that does not fit" {
    var buffer: [4]u8 = undefined;

    try testing.expectError(Error.TooLong, join(&buffer, &.{ "/abc", "d" }));
}

test "trim drops trailing separators but keeps the root" {
    try testing.expectEqualStrings("/home/user", trim("/home/user/"));
    try testing.expectEqualStrings("/home/user", trim("/home/user" ++ "/" ++ "/" ++ "/"));
    try testing.expectEqualStrings("/", trim("/"));
    try testing.expectEqualStrings("/home/user", trim("/home/user"));
}

test "state_dir and config_dir land under a directory named for the app" {
    var buffer: [contract.path_bytes_max]u8 = undefined;

    const state = state_dir(&buffer, "phantom") catch |err| {
        try testing.expectEqual(Error.NotFound, err);

        return;
    };

    try testing.expect(std.mem.endsWith(u8, state, "/phantom"));
    try testing.expectEqual(@as(u8, separator), state[0]);

    const config = try config_dir(&buffer, "phantom");

    try testing.expect(std.mem.endsWith(u8, config, "/phantom"));
    try testing.expectEqual(@as(u8, separator), config[0]);
}
