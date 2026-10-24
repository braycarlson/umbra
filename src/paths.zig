const std = @import("std");

const platform = @import("platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.paths;

const CapacityError = platform.CapacityError;
const PlatformError = platform.PlatformError;

pub fn config_dir(buffer: []u8, name: []const u8) (CapacityError || PlatformError)![]const u8 {
    assert(name.len > 0);

    const result = try backend.config_dir(buffer, name);

    assert(result.len <= buffer.len);
    assert(std.mem.endsWith(u8, result, name));

    return result;
}

pub fn state_dir(buffer: []u8, name: []const u8) (CapacityError || PlatformError)![]const u8 {
    assert(name.len > 0);

    const result = try backend.state_dir(buffer, name);

    assert(result.len <= buffer.len);
    assert(std.mem.endsWith(u8, result, name));

    return result;
}

const testing = std.testing;

test config_dir {
    var buffer: [platform.path_bytes_max]u8 = undefined;

    try testing.expectEqualStrings("/mock/config/phantom", try config_dir(&buffer, "phantom"));
}

test state_dir {
    var buffer: [platform.path_bytes_max]u8 = undefined;

    try testing.expectEqualStrings("/mock/state/phantom", try state_dir(&buffer, "phantom"));

    var small: [8]u8 = undefined;

    try testing.expectError(error.PathTooLong, state_dir(&small, "phantom"));
}
