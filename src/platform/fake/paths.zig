const std = @import("std");

const interface = @import("../interface.zig");

const assert = std.debug.assert;

const CapacityError = interface.CapacityError;
const PlatformError = interface.PlatformError;

pub const separator = std.Io.Dir.path.sep;
pub const separator_text = std.Io.Dir.path.sep_str;
pub const root = ".zig-cache" ++ separator_text ++ "tmp" ++ separator_text ++ "umbra-fake";
pub const config_base = root ++ separator_text ++ "config";
pub const state_base = root ++ separator_text ++ "state";

comptime {
    assert(separator_text.len == 1);
    assert(separator_text[0] == separator);
    assert(root[0] != separator);
    assert(std.mem.startsWith(u8, config_base, root));
    assert(std.mem.startsWith(u8, state_base, root));
}

pub fn config_dir(
    io: std.Io,
    buffer: []u8,
    app: []const u8,
) (CapacityError || PlatformError)![]const u8 {
    assert(buffer.len > 0);
    assert(app.len > 0);
    assert(@intFromPtr(buffer.ptr) >= @intFromPtr(app.ptr) + app.len or
        @intFromPtr(app.ptr) >= @intFromPtr(buffer.ptr) + buffer.len);

    return try resolve(io, buffer, config_base, app);
}

pub fn state_dir(
    io: std.Io,
    buffer: []u8,
    app: []const u8,
) (CapacityError || PlatformError)![]const u8 {
    assert(buffer.len > 0);
    assert(app.len > 0);
    assert(@intFromPtr(buffer.ptr) >= @intFromPtr(app.ptr) + app.len or
        @intFromPtr(app.ptr) >= @intFromPtr(buffer.ptr) + buffer.len);

    return try resolve(io, buffer, state_base, app);
}

fn resolve(
    io: std.Io,
    buffer: []u8,
    base: []const u8,
    app: []const u8,
) (CapacityError || PlatformError)![]const u8 {
    assert(buffer.len > 0);
    assert(base.len > 0);
    assert(app.len > 0);

    const working_len = std.process.currentPath(io, buffer) catch |err| switch (err) {
        error.NameTooLong => return error.PathTooLong,
        error.CurrentDirUnlinked,
        error.PathExceedsLimit,
        error.Canceled,
        error.Unexpected,
        => return error.DirectoryMissing,
    };

    assert(working_len > 0);
    assert(std.Io.Dir.path.isAbsolute(buffer[0..working_len]));

    const base_offset = working_len + 1;
    const app_offset = base_offset + base.len + 1;
    const total = app_offset + app.len;

    if (total > buffer.len) {
        return error.PathTooLong;
    }

    buffer[working_len] = separator;

    @memcpy(buffer[base_offset..][0..base.len], base);

    buffer[app_offset - 1] = separator;

    @memcpy(buffer[app_offset..][0..app.len], app);

    assert(std.Io.Dir.path.isAbsolute(buffer[0..total]));
    assert(std.mem.endsWith(u8, buffer[0..total], app));

    return buffer[0..total];
}

const testing = std.testing;

fn expect_under_working_directory(actual: []const u8, kind: []const u8) !void {
    assert(actual.len > 0);
    assert(kind.len > 0);

    const working = try std.process.currentPathAlloc(testing.io, testing.allocator);
    defer testing.allocator.free(working);

    const expected = try std.Io.Dir.path.join(
        testing.allocator,
        &.{ working, ".zig-cache", "tmp", "umbra-fake", kind, "phantom" },
    );

    defer testing.allocator.free(expected);

    try testing.expectEqualStrings(expected, actual);
}

test "state_dir lands in the build cache of the working directory" {
    var buffer: [interface.path_bytes_max]u8 = undefined;

    const state = try state_dir(testing.io, &buffer, "phantom");

    try expect_under_working_directory(state, "state");
}

test "config_dir lands in the build cache of the working directory" {
    var buffer: [interface.path_bytes_max]u8 = undefined;

    const config = try config_dir(testing.io, &buffer, "phantom");

    try expect_under_working_directory(config, "config");
}

test "a buffer too short for the working directory or for the suffix is refused" {
    var buffer: [interface.path_bytes_max]u8 = undefined;

    const working_len = try std.process.currentPath(testing.io, &buffer);
    const short = buffer[0 .. working_len + 1];

    try testing.expectError(error.PathTooLong, state_dir(testing.io, buffer[0..1], "phantom"));
    try testing.expectError(error.PathTooLong, state_dir(testing.io, short, "phantom"));
}

test "the fake directories sit under the root that std.testing.tmpDir uses" {
    const io = testing.io;

    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    var buffer: [interface.path_bytes_max]u8 = undefined;
    var joined: [interface.path_bytes_max]u8 = undefined;

    const config = try config_dir(io, &buffer, "phantom");
    const fake_root = std.Io.Dir.path.dirname(std.Io.Dir.path.dirname(config).?).?;
    const cache_root = std.Io.Dir.path.dirname(fake_root).?;
    const parts = .{ cache_root, separator, &temporary.sub_path };
    const sibling = try std.mem.print(&joined, "{s}{c}{s}", parts);

    var opened = try std.Io.Dir.cwd().openDir(io, sibling, .{});
    defer opened.close(io);

    try testing.expect(std.mem.endsWith(u8, fake_root, root));
    try testing.expect(std.Io.Dir.path.isAbsolute(config));
}
