const std = @import("std");

const contract = @import("../contract.zig");
const win32 = @import("win32.zig");

const assert = std.debug.assert;

const PlatformError = contract.PlatformError;

pub const operation = std.unicode.utf8ToUtf16LeStringLiteral("open");
pub const show_normal: i32 = 1;
pub const instance_error_max: usize = 32;

comptime {
    assert(operation.len == 4);
    assert(show_normal == 1);
    assert(instance_error_max == 32);
}

pub fn open(path: []const u8) PlatformError!void {
    assert(path.len > 0);
    assert(path.len < contract.path_bytes_max);

    var wide: [contract.path_bytes_max:0]u16 = undefined;

    const length = std.unicode.utf8ToUtf16Le(&wide, path) catch {
        return error.LaunchFailed;
    };

    assert(length > 0);
    assert(length < contract.path_bytes_max);

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
        return error.LaunchFailed;
    }
}
