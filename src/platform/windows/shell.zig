const std = @import("std");

const contract = @import("../contract.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;

pub const Error = contract.ShellError;

pub const operation = std.unicode.utf8ToUtf16LeStringLiteral("open");
pub const show_normal: i32 = 1;
pub const instance_error_max: usize = 32;

comptime {
    assert(operation.len == 4);
    assert(show_normal == 1);
    assert(instance_error_max == 32);
}

pub fn open(path: []const u8) Error!void {
    if (path.len == 0 or path.len >= contract.path_bytes_max) {
        return Error.InvalidPath;
    }

    var wide: [contract.path_bytes_max:0]u16 = undefined;

    const length = std.unicode.utf8ToUtf16Le(&wide, path) catch {
        return Error.InvalidPath;
    };

    if (length == 0 or length >= contract.path_bytes_max) {
        return Error.InvalidPath;
    }

    wide[length] = 0;

    const result = win32.ShellExecuteW(
        null,
        operation,
        wide[0..length :0],
        null,
        null,
        show_normal,
    );

    const value = @intFromPtr(result);

    if (value <= instance_error_max) {
        return Error.LaunchFailed;
    }
}

const testing = std.testing;

test "open rejects an empty path" {
    try testing.expectError(Error.InvalidPath, open(""));
}

test "open rejects an oversized path" {
    const long = [_]u8{'a'} ** contract.path_bytes_max;

    try testing.expectError(Error.InvalidPath, open(&long));
}
