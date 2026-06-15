const std = @import("std");

const w32 = @import("win32").everything;

const path_mod = @import("path.zig");

const path_max = path_mod.path_max;

const flag_backup_semantics: u32 = 0x02000000;
const flag_overlapped: u32 = 0x40000000;
const access_list_directory: u32 = 0x0001;

pub const Error = error{
    DirectoryOpenFailed,
    InvalidPath,
};

pub const Directory = struct {
    handle: w32.HANDLE,

    pub fn open(path: []const u8) Error!Directory {
        if (path.len == 0 or path.len >= path_max) {
            return Error.InvalidPath;
        }

        var wide: [path_max]u16 = undefined;

        const length = std.unicode.utf8ToUtf16Le(&wide, path) catch {
            return Error.InvalidPath;
        };

        std.debug.assert(length > 0);
        std.debug.assert(length < path_max);

        if (length == 0 or length >= path_max) {
            return Error.InvalidPath;
        }

        wide[length] = 0;

        const handle = w32.CreateFileW(
            @ptrCast(&wide),
            @bitCast(access_list_directory),
            .{ .DELETE = 1, .READ = 1, .WRITE = 1 },
            null,
            w32.OPEN_EXISTING,
            @bitCast(flag_backup_semantics | flag_overlapped),
            null,
        );

        if (handle == w32.INVALID_HANDLE_VALUE) {
            return Error.DirectoryOpenFailed;
        }

        std.debug.assert(handle != w32.INVALID_HANDLE_VALUE);

        const result = Directory{
            .handle = handle,
        };

        return result;
    }

    pub fn close(self: *const Directory) bool {
        std.debug.assert(self.is_valid());

        const status = w32.CloseHandle(self.handle);
        const result = status != 0;

        return result;
    }

    pub fn is_valid(self: *const Directory) bool {
        const result = self.handle != w32.INVALID_HANDLE_VALUE;

        return result;
    }
};
