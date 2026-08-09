const std = @import("std");

const contract = @import("../../contract.zig");

const assert = std.debug.assert;

pub const path_max: u32 = contract.path_bytes_max;

pub const Error = error{
    InvalidPath,
};

pub const Path = struct {
    directory: [path_max]u8 = [_]u8{0} ** path_max,
    directory_len: u32 = 0,
    filename: [path_max]u8 = [_]u8{0} ** path_max,
    filename_len: u32 = 0,

    pub fn get_directory(path: *const Path) []const u8 {
        assert(path.is_valid());
        assert(path.directory_len <= path_max);

        return path.directory[0..path.directory_len];
    }

    pub fn get_filename(path: *const Path) []const u8 {
        assert(path.is_valid());
        assert(path.filename_len <= path_max);

        return path.filename[0..path.filename_len];
    }

    pub fn is_valid(path: *const Path) bool {
        const dir_valid = path.directory_len > 0 and path.directory_len <= path_max;
        const file_valid = path.filename_len > 0 and path.filename_len <= path_max;

        return dir_valid and file_valid;
    }

    pub fn parse(input: []const u8) Error!Path {
        if (input.len == 0 or input.len > path_max) {
            return Error.InvalidPath;
        }

        const directory = std.fs.path.dirname(input) orelse {
            return Error.InvalidPath;
        };

        const filename = std.fs.path.basename(input);

        assert(directory.len > 0);
        assert(filename.len > 0);

        if (!is_valid_component(directory) or !is_valid_component(filename)) {
            return Error.InvalidPath;
        }

        var path = Path{};

        copy_component(&path.directory, directory);
        path.directory_len = @intCast(directory.len);

        copy_component(&path.filename, filename);
        path.filename_len = @intCast(filename.len);

        assert(path.is_valid());

        return path;
    }
};

fn copy_component(destination: []u8, source: []const u8) void {
    assert(destination.len >= source.len);
    assert(source.len > 0);
    assert(source.len <= path_max);

    var index: u32 = 0;

    while (index < source.len) : (index += 1) {
        assert(index < destination.len);

        destination[index] = source[index];
    }
}

fn is_valid_component(component: []const u8) bool {
    const not_empty = component.len > 0;
    const not_too_long = component.len <= path_max;

    return not_empty and not_too_long;
}

const testing = std.testing;

test "parsing a path splits the directory from the filename" {
    const path = try Path.parse("C:\\Users\\test\\file.txt");

    try testing.expectEqualStrings("C:\\Users\\test", path.get_directory());
    try testing.expectEqualStrings("file.txt", path.get_filename());
}

test "parsing a bare filename yields no directory" {
    const path = try Path.parse("dir\\file.txt");

    try testing.expectEqualStrings("dir", path.get_directory());
    try testing.expectEqualStrings("file.txt", path.get_filename());
}

test "parsing an empty path is rejected" {
    const result = Path.parse("");

    try testing.expectError(Error.InvalidPath, result);
}

test "a parsed path is valid" {
    const path = try Path.parse("C:\\dir\\file.txt");

    try testing.expect(path.is_valid());
}

test "a path with empty halves is not valid" {
    var path = Path{};

    try testing.expect(!path.is_valid());

    path.directory_len = 5;

    try testing.expect(!path.is_valid());

    path.directory_len = 0;
    path.filename_len = 5;

    try testing.expect(!path.is_valid());
}

test "a path returns the directory it stored" {
    const path = try Path.parse("C:\\test\\example.txt");

    try testing.expectEqualStrings("C:\\test", path.get_directory());
}

test "a path returns the filename it stored" {
    const path = try Path.parse("C:\\test\\example.txt");

    try testing.expectEqualStrings("example.txt", path.get_filename());
}

test "Path handles forward slashes" {
    const path = try Path.parse("dir/subdir/file.txt");

    try testing.expect(path.is_valid());
    try testing.expectEqualStrings("file.txt", path.get_filename());
}

test "Path handles deep nesting" {
    const path = try Path.parse("C:\\a\\b\\c\\d\\e\\file.txt");

    try testing.expect(path.is_valid());
    try testing.expectEqualStrings("C:\\a\\b\\c\\d\\e", path.get_directory());
    try testing.expectEqualStrings("file.txt", path.get_filename());
}

test "Path handles filename with multiple dots" {
    const path = try Path.parse("dir\\file.name.txt");

    try testing.expectEqualStrings("file.name.txt", path.get_filename());
}

test "Path handles filename without extension" {
    const path = try Path.parse("dir\\filename");

    try testing.expectEqualStrings("filename", path.get_filename());
}
