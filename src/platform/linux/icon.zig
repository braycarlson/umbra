const std = @import("std");

const contract = @import("../contract.zig");

const assert = std.debug.assert;

const CapacityError = contract.CapacityError;
const Icon = contract.Icon;
const PlatformError = contract.PlatformError;

const icon_count_max = contract.icon_count_max;
const path_bytes_max = contract.path_bytes_max;
const pixmap_bytes_max = contract.pixmap_bytes_max;

var entries: [icon_count_max]?Icon.Source = @splat(null);
var paths: [icon_count_max][path_bytes_max]u8 = undefined;
var pixmap_storage: [pixmap_bytes_max]u8 = undefined;
var pixmap_used: u32 = 0;
var pixmap_live: u32 = 0;

pub fn load(source: Icon.Source) (CapacityError || PlatformError)!Icon {
    assert(source.is_valid());

    const slot = find_empty_slot() orelse return error.IconsExhausted;

    assert(slot < icon_count_max);

    entries[slot] = try adopt(slot, source);

    assert(entries[slot] != null);

    return @fromBackingInt(slot);
}

pub fn destroy(icon: Icon) void {
    const slot = @backingInt(icon);

    if (slot >= icon_count_max) {
        return;
    }

    const entry = entries[slot] orelse return;

    if (entry == .pixels) {
        release_pixmap();
    }

    entries[slot] = null;

    assert(entries[slot] == null);
}

pub fn get(icon: Icon) ?Icon.Source {
    const slot = @backingInt(icon);

    if (slot >= icon_count_max) {
        return null;
    }

    return entries[slot];
}

pub fn theme_name(stock: Icon.Stock) []const u8 {
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

fn adopt(slot: u32, source: Icon.Source) CapacityError!Icon.Source {
    assert(slot < icon_count_max);

    const result: Icon.Source = switch (source) {
        .file_path => |path| blk: {
            assert(path.len < path_bytes_max);

            @memcpy(paths[slot][0..path.len], path);

            break :blk .{ .file_path = paths[slot][0..path.len] };
        },
        .pixels => |pixmap| blk: {
            const argb = reserve_pixmap(pixmap.argb) orelse return error.IconsExhausted;

            break :blk .{ .pixels = Icon.Pixmap.init(argb, pixmap.width, pixmap.height) };
        },
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

fn find_empty_slot() ?u32 {
    var index: u32 = 0;

    while (index < icon_count_max) : (index += 1) {
        assert(index < icon_count_max);

        if (entries[index] == null) return index;
    }

    return null;
}

const testing = std.testing;

test "load stores the source" {
    reset();

    const icon = try load(.{ .stock = .application });

    try testing.expect(get(icon) != null);
    try testing.expectEqual(Icon.Stock.application, get(icon).?.stock);
}

test "load copies a file path into backend storage" {
    reset();

    var caller: [16]u8 = undefined;

    @memcpy(caller[0.."/tmp/icon.png".len], "/tmp/icon.png");

    const icon = try load(.{ .file_path = caller[0.."/tmp/icon.png".len] });

    @memset(&caller, 'x');

    try testing.expectEqualStrings("/tmp/icon.png", get(icon).?.file_path);
}

test "load copies pixels into backend storage" {
    reset();

    var caller = [_]u8{ 1, 2, 3, 4 };

    const icon = try load(.{ .pixels = Icon.Pixmap.init(&caller, 1, 1) });

    @memset(&caller, 0);

    const stored = get(icon).?.pixels;

    try testing.expectEqual(@as(u8, 1), stored.argb[0]);
    try testing.expectEqual(@as(u8, 4), stored.argb[3]);

    destroy(icon);

    try testing.expectEqual(@as(u32, 0), pixmap_used);
}

test "destroy frees the slot" {
    reset();

    const icon = try load(.{ .stock = .shield });

    destroy(icon);

    try testing.expect(get(icon) == null);
}

test "theme_name covers every stock icon" {
    try testing.expectEqualStrings("application-x-executable", theme_name(.application));
    try testing.expectEqualStrings("dialog-error", theme_name(.err));
    try testing.expectEqualStrings("dialog-information", theme_name(.information));
    try testing.expectEqualStrings("dialog-question", theme_name(.question));
    try testing.expectEqualStrings("security-high", theme_name(.shield));
    try testing.expectEqualStrings("dialog-warning", theme_name(.warning));
}

test "load reports a full icon table" {
    reset();

    var index: u32 = 0;

    while (index < icon_count_max) : (index += 1) {
        _ = try load(.{ .stock = .application });
    }

    try testing.expectError(error.IconsExhausted, load(.{ .stock = .application }));

    reset();
}

const full_argb: [pixmap_bytes_max]u8 = @splat(0);

test "the pixmap arena reports exhaustion and reclaims on release" {
    reset();

    const dimension = contract.pixmap_dimension_max;
    const full = Icon.Pixmap.init(&full_argb, dimension, dimension);
    const first = try load(.{ .pixels = full });

    try testing.expectEqual(pixmap_bytes_max, pixmap_used);
    try testing.expectError(error.IconsExhausted, load(.{ .pixels = full }));

    destroy(first);

    try testing.expectEqual(@as(u32, 0), pixmap_used);

    reset();
}
