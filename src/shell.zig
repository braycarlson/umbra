const std = @import("std");

const platform = @import("platform.zig");

const backend = platform.backend.shell;

const CapacityError = platform.CapacityError;
const PlatformError = platform.PlatformError;
const RequestError = platform.RequestError;

pub fn open(path: []const u8) (CapacityError || PlatformError || RequestError)!void {
    if (path.len == 0) return error.PathEmpty;
    if (path.len >= platform.path_bytes_max) return error.PathTooLong;
    if (!platform.is_valid_text(path)) return error.PathInvalid;

    try backend.open(path);
}

const testing = std.testing;

const mock = platform.mock;

test open {
    mock.reset();

    try open("/home/user/.config/locker/config.zon");

    try testing.expectEqualStrings("/home/user/.config/locker/config.zon", mock.shell.path_at(0));

    const long: [platform.path_bytes_max]u8 = @splat('a');

    try testing.expectError(error.PathEmpty, open(""));
    try testing.expectError(error.PathTooLong, open(&long));
    try testing.expectError(error.PathInvalid, open("config\x00.zon"));
    try testing.expectEqual(@as(u32, 1), mock.shell.opened_count());
}
