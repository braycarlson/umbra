const std = @import("std");

const w32 = @import("win32.zig");

const contract = @import("../contract.zig");

const assert = std.debug.assert;

pub const Error = contract.PathError;

pub const base_wide_max: u32 = 512;
pub const separator: u8 = '\\';
pub const utf8_bytes_per_unit_max: u32 = 3;
pub const base_bytes_max: u32 = base_wide_max * utf8_bytes_per_unit_max;

pub const config_variable = "APPDATA";
pub const state_variable = "LOCALAPPDATA";

comptime {
    assert(base_wide_max > 0);
    assert(base_bytes_max == base_wide_max * utf8_bytes_per_unit_max);
    assert(base_bytes_max > base_wide_max);
    assert(separator == '\\');
    assert(config_variable.len > 0);
    assert(state_variable.len > 0);
    assert(!std.mem.eql(u8, config_variable, state_variable));
}

pub fn config_dir(buffer: []u8, app: []const u8) Error![]const u8 {
    return try resolve(buffer, app, config_variable);
}

pub fn state_dir(buffer: []u8, app: []const u8) Error![]const u8 {
    return try resolve(buffer, app, state_variable);
}

fn resolve(buffer: []u8, app: []const u8, comptime variable: []const u8) Error![]const u8 {
    assert(app.len > 0);
    assert(variable.len > 0);

    var wide: [base_wide_max:0]u16 = undefined;

    const name = std.unicode.utf8ToUtf16LeStringLiteral(variable);
    const length = w32.GetEnvironmentVariableW(name, &wide, base_wide_max);

    if (length == 0) {
        return Error.NotFound;
    }

    if (length >= base_wide_max) {
        return Error.TooLong;
    }

    assert(length < base_wide_max);
    assert(length * utf8_bytes_per_unit_max <= base_bytes_max);

    var narrow: [base_bytes_max]u8 = undefined;

    const written = std.unicode.utf16LeToUtf8(&narrow, wide[0..length]) catch {
        return Error.TooLong;
    };

    const base = trim(narrow[0..written]);

    if (base.len == 0) {
        return Error.NotFound;
    }

    assert(base.len <= narrow.len);

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

fn trim(value: []const u8) []const u8 {
    var length = value.len;

    while (length > 1 and value[length - 1] == separator) {
        length -= 1;
    }

    assert(length <= value.len);

    return value[0..length];
}

const testing = std.testing;

test "trim drops trailing separators but keeps a single character" {
    try testing.expectEqualStrings("C:\\Users\\a", trim("C:\\Users\\a\\"));
    try testing.expectEqualStrings("C:\\Users\\a", trim("C:\\Users\\a\\\\"));
    try testing.expectEqualStrings("\\", trim("\\"));
    try testing.expectEqualStrings("C:\\Users\\a", trim("C:\\Users\\a"));
}

test "state_dir appends the app to the local application data directory" {
    var buffer: [contract.path_bytes_max]u8 = undefined;

    const state = state_dir(&buffer, "phantom") catch |err| {
        try testing.expectEqual(Error.NotFound, err);

        return;
    };

    try testing.expect(std.mem.endsWith(u8, state, "\\phantom"));
}

test "config_dir appends the app to the roaming application data directory" {
    var buffer: [contract.path_bytes_max]u8 = undefined;

    const config = config_dir(&buffer, "phantom") catch |err| {
        try testing.expectEqual(Error.NotFound, err);

        return;
    };

    try testing.expect(std.mem.endsWith(u8, config, "\\phantom"));
}

test "a base longer than the buffer is refused" {
    var buffer: [8]u8 = undefined;

    try testing.expectError(Error.TooLong, config_dir(&buffer, "phantom"));
}

test "a buffer too small for the app segment is refused" {
    var buffer: [4]u8 = undefined;

    try testing.expectError(Error.TooLong, state_dir(&buffer, "phantom"));
}
