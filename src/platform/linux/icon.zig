const std = @import("std");

const contract = @import("../contract.zig");

const assert = std.debug.assert;

pub const Error = contract.IconError;

pub const Source = contract.IconSource;
pub const Handle = contract.IconHandle;

pub const supports_resource: bool = false;

pub const handle_max: u32 = 32;
pub const path_bytes_max: u32 = contract.path_bytes_max;
pub const pixmap_bytes_max: u32 = contract.pixmap_bytes_max;

comptime {
    assert(handle_max > 0);
    assert(path_bytes_max > 0);
    assert(pixmap_bytes_max > 0);
}

var entries: [handle_max]?Source = @splat(null);
var paths: [handle_max][path_bytes_max]u8 = undefined;
var pixmap_storage: [pixmap_bytes_max]u8 = undefined;
var pixmap_used: u32 = 0;
var pixmap_live: u32 = 0;

pub fn load(source: Source) Error!Handle {
    if (!source.is_valid()) {
        return Error.InvalidSource;
    }

    const slot = find_empty_slot() orelse return Error.CapacityExceeded;

    assert(slot < handle_max);

    const owned = try adopt(slot, source);

    entries[slot] = owned;

    assert(entries[slot] != null);

    return slot;
}

pub fn destroy(handle: Handle) void {
    if (handle >= handle_max) {
        return;
    }

    const entry = entries[handle] orelse return;

    if (entry == .pixels) {
        release_pixmap();
    }

    entries[handle] = null;

    assert(entries[handle] == null);
}

pub fn get(handle: Handle) ?Source {
    if (handle >= handle_max) {
        return null;
    }

    return entries[handle];
}

pub fn theme_name(stock: contract.Stock) []const u8 {
    const result = switch (stock) {
        .application => "application-x-executable",
        .err => "dialog-error",
        .information => "dialog-information",
        .question => "dialog-question",
        .shield => "security-high",
        .warning => "dialog-warning",
    };

    assert(result.len > 0);

    return result;
}

fn adopt(slot: u32, source: Source) Error!Source {
    assert(slot < handle_max);

    const result: Source = switch (source) {
        .file_path => |path| blk: {
            if (path.len >= path_bytes_max) {
                return Error.CapacityExceeded;
            }

            @memcpy(paths[slot][0..path.len], path);

            break :blk .{ .file_path = paths[slot][0..path.len] };
        },
        .pixels => |pixmap| blk: {
            const argb = reserve_pixmap(pixmap.argb) orelse return Error.CapacityExceeded;

            break :blk .{ .pixels = contract.Pixmap.init(argb, pixmap.width, pixmap.height) };
        },
        .resource => return Error.InvalidSource,
        .stock => source,
    };

    return result;
}

fn reserve_pixmap(argb: []const u8) ?[]const u8 {
    assert(argb.len > 0);
    assert(pixmap_used <= pixmap_bytes_max);

    if (argb.len > pixmap_bytes_max - pixmap_used) {
        return null;
    }

    const start = pixmap_used;
    const length: u32 = @intCast(argb.len);

    @memcpy(pixmap_storage[start .. start + length], argb);

    pixmap_used += length;
    pixmap_live += 1;

    assert(pixmap_used <= pixmap_bytes_max);

    return pixmap_storage[start .. start + length];
}

fn release_pixmap() void {
    assert(pixmap_live > 0);

    pixmap_live -= 1;

    if (pixmap_live == 0) {
        pixmap_used = 0;
    }
}

fn reset() void {
    entries = @splat(null);
    pixmap_used = 0;
    pixmap_live = 0;

    assert(entries[0] == null);
}

fn find_empty_slot() ?Handle {
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

        if (entries[index] == null) return index;
    }

    return null;
}

const testing = std.testing;

test "load stores the source" {
    reset();

    const handle = try load(.{ .stock = .application });

    try testing.expect(get(handle) != null);
    try testing.expectEqual(contract.Stock.application, get(handle).?.stock);
}

test "load rejects an invalid source" {
    reset();

    try testing.expectError(Error.InvalidSource, load(.{ .file_path = "" }));
}

test "load rejects a resource source the backend cannot serve" {
    reset();

    try testing.expect(!supports_resource);
    try testing.expectError(Error.InvalidSource, load(.{ .resource = 7 }));
}

test "load copies a file path into backend storage" {
    reset();

    var caller: [16]u8 = undefined;

    @memcpy(caller[0.."/tmp/icon.png".len], "/tmp/icon.png");

    const handle = try load(.{ .file_path = caller[0.."/tmp/icon.png".len] });

    @memset(&caller, 'x');

    try testing.expectEqualStrings("/tmp/icon.png", get(handle).?.file_path);
}

test "load copies pixels into backend storage" {
    reset();

    var caller = [_]u8{ 1, 2, 3, 4 };

    const handle = try load(.{ .pixels = contract.Pixmap.init(&caller, 1, 1) });

    @memset(&caller, 0);

    const stored = get(handle).?.pixels;

    try testing.expectEqual(@as(u8, 1), stored.argb[0]);
    try testing.expectEqual(@as(u8, 4), stored.argb[3]);

    destroy(handle);

    try testing.expectEqual(@as(u32, 0), pixmap_used);
}

test "destroy frees the slot" {
    reset();

    const handle = try load(.{ .stock = .shield });

    destroy(handle);

    try testing.expect(get(handle) == null);
}

test "theme_name covers every stock icon" {
    try testing.expectEqualStrings("application-x-executable", theme_name(.application));
    try testing.expectEqualStrings("dialog-error", theme_name(.err));
    try testing.expectEqualStrings("dialog-information", theme_name(.information));
    try testing.expectEqualStrings("dialog-question", theme_name(.question));
    try testing.expectEqualStrings("security-high", theme_name(.shield));
    try testing.expectEqualStrings("dialog-warning", theme_name(.warning));
}

test "load reports capacity exhaustion" {
    reset();

    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        _ = try load(.{ .stock = .application });
    }

    try testing.expectError(Error.CapacityExceeded, load(.{ .stock = .application }));

    reset();
}

const full_argb: [pixmap_bytes_max]u8 = @splat(0);

test "the pixmap arena reports exhaustion and reclaims on release" {
    reset();

    const dimension = contract.pixmap_dimension_max;
    const full = contract.Pixmap.init(&full_argb, dimension, dimension);
    const first = try load(.{ .pixels = full });

    try testing.expectEqual(pixmap_bytes_max, pixmap_used);
    try testing.expectError(Error.CapacityExceeded, load(.{ .pixels = full }));

    destroy(first);

    try testing.expectEqual(@as(u32, 0), pixmap_used);

    reset();
}
