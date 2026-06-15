const std = @import("std");

pub const path_max: u32 = 512;

pub const Error = error{
    InvalidPath,
};

pub const Path = struct {
    directory: [path_max]u8 = [_]u8{0} ** path_max,
    directory_len: u32 = 0,
    filename: [path_max]u8 = [_]u8{0} ** path_max,
    filename_len: u32 = 0,

    pub fn get_directory(self: *const Path) []const u8 {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.directory_len <= path_max);

        const result = self.directory[0..self.directory_len];

        return result;
    }

    pub fn get_filename(self: *const Path) []const u8 {
        std.debug.assert(self.is_valid());
        std.debug.assert(self.filename_len <= path_max);

        const result = self.filename[0..self.filename_len];

        return result;
    }

    pub fn is_valid(self: *const Path) bool {
        const dir_valid = self.directory_len > 0 and self.directory_len <= path_max;
        const file_valid = self.filename_len > 0 and self.filename_len <= path_max;
        const result = dir_valid and file_valid;

        return result;
    }

    pub fn parse(input: []const u8) Error!Path {
        if (input.len == 0 or input.len > path_max) {
            return Error.InvalidPath;
        }

        const directory = std.fs.path.dirname(input) orelse {
            return Error.InvalidPath;
        };

        const filename = std.fs.path.basename(input);

        std.debug.assert(directory.len > 0);
        std.debug.assert(filename.len > 0);

        if (!is_valid_component(directory) or !is_valid_component(filename)) {
            return Error.InvalidPath;
        }

        var path = Path{};

        copy_component(&path.directory, directory);
        path.directory_len = @intCast(directory.len);

        copy_component(&path.filename, filename);
        path.filename_len = @intCast(filename.len);

        std.debug.assert(path.is_valid());

        return path;
    }
};

fn copy_component(destination: []u8, source: []const u8) void {
    std.debug.assert(destination.len >= source.len);
    std.debug.assert(source.len > 0);
    std.debug.assert(source.len <= path_max);

    var index: u32 = 0;

    while (index < source.len) : (index += 1) {
        std.debug.assert(index < destination.len);

        destination[index] = source[index];
    }
}

fn is_valid_component(component: []const u8) bool {
    const not_empty = component.len > 0;
    const not_too_long = component.len <= path_max;
    const result = not_empty and not_too_long;

    return result;
}
