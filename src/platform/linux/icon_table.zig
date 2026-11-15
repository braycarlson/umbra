const std = @import("std");

const interface = @import("../interface.zig");

const assert = std.debug.assert;

const CapacityError = interface.CapacityError;
const Icon = interface.Icon;

const icon_count_max = interface.icon_count_max;
const path_bytes_max = interface.path_bytes_max;
const pixmap_bytes_max = interface.pixmap_bytes_max;

const IconTable = @This();

entries: [icon_count_max]?Icon.Source,
paths: [icon_count_max][path_bytes_max]u8,
pixmap_live: u32,
pixmap_storage: [pixmap_bytes_max]u8,
pixmap_used: u32,

pub fn init(table: *IconTable) void {
    table.entries = @splat(null);
    table.pixmap_live = 0;
    table.pixmap_used = 0;

    assert(table.entries[0] == null);
    assert(table.pixmap_used == 0);
}

pub fn load(table: *IconTable, source: Icon.Source) CapacityError!Icon {
    assert(source.is_valid());

    const slot = table.find_empty_slot() orelse return error.IconsExhausted;

    assert(slot < icon_count_max);

    table.entries[slot] = try table.adopt(slot, source);

    assert(table.entries[slot] != null);

    return @fromBackingInt(slot);
}

pub fn destroy(table: *IconTable, icon: Icon) void {
    assert(@backingInt(icon) < icon_count_max);

    const slot = @backingInt(icon);
    const entry = table.entries[slot] orelse return;

    if (entry == .pixels) {
        table.release_pixmap();
    }

    table.entries[slot] = null;

    assert(table.entries[slot] == null);
}

pub fn get(table: *const IconTable, icon: Icon) ?Icon.Source {
    assert(@backingInt(icon) < icon_count_max);

    return table.entries[@backingInt(icon)];
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

fn adopt(table: *IconTable, slot: u32, source: Icon.Source) CapacityError!Icon.Source {
    assert(slot < icon_count_max);
    assert(source.is_valid());

    const result: Icon.Source = switch (source) {
        .file_path => |path| blk: {
            assert(path.len < path_bytes_max);

            @memcpy(table.paths[slot][0..path.len], path);

            break :blk .{ .file_path = table.paths[slot][0..path.len] };
        },
        .pixels => |pixmap| blk: {
            const argb = table.reserve_pixmap(pixmap.argb) orelse return error.IconsExhausted;

            break :blk .{ .pixels = Icon.Pixmap.init(argb, pixmap.width, pixmap.height) };
        },
        .stock => source,
    };

    return result;
}

fn reserve_pixmap(table: *IconTable, argb: []const u8) ?[]const u8 {
    assert(argb.len > 0);
    assert(table.pixmap_used <= pixmap_bytes_max);

    if (argb.len > pixmap_bytes_max - table.pixmap_used) {
        return null;
    }

    const start = table.pixmap_used;
    const length: u32 = @intCast(argb.len);

    @memcpy(table.pixmap_storage[start .. start + length], argb);

    table.pixmap_used += length;
    table.pixmap_live += 1;

    assert(table.pixmap_used <= pixmap_bytes_max);

    return table.pixmap_storage[start .. start + length];
}

fn release_pixmap(table: *IconTable) void {
    assert(table.pixmap_live > 0);

    table.pixmap_live -= 1;

    if (table.pixmap_live == 0) {
        table.pixmap_used = 0;
    }
}

fn find_empty_slot(table: *const IconTable) ?u32 {
    var index: u32 = 0;

    while (index < icon_count_max) : (index += 1) {
        assert(index < icon_count_max);

        if (table.entries[index] == null) return index;
    }

    return null;
}

const testing = std.testing;

fn create_table() !*IconTable {
    const table = try testing.allocator.create(IconTable);

    table.init();

    assert(table.pixmap_used == 0);

    return table;
}

test "load stores the source" {
    const table = try create_table();
    defer testing.allocator.destroy(table);

    const icon = try table.load(.{ .stock = .application });

    try testing.expect(table.get(icon) != null);
    try testing.expectEqual(Icon.Stock.application, table.get(icon).?.stock);
}

test "load copies a file path into backend storage" {
    const table = try create_table();
    defer testing.allocator.destroy(table);

    var caller: [16]u8 = undefined;

    @memcpy(caller[0.."/tmp/icon.png".len], "/tmp/icon.png");

    const icon = try table.load(.{ .file_path = caller[0.."/tmp/icon.png".len] });

    @memset(&caller, 'x');

    try testing.expectEqualStrings("/tmp/icon.png", table.get(icon).?.file_path);
}

test "load copies pixels into backend storage" {
    const table = try create_table();
    defer testing.allocator.destroy(table);

    var caller = [_]u8{ 1, 2, 3, 4 };

    const icon = try table.load(.{ .pixels = Icon.Pixmap.init(&caller, 1, 1) });

    @memset(&caller, 0);

    const stored = table.get(icon).?.pixels;

    try testing.expectEqual(@as(u8, 1), stored.argb[0]);
    try testing.expectEqual(@as(u8, 4), stored.argb[3]);

    table.destroy(icon);

    try testing.expectEqual(@as(u32, 0), table.pixmap_used);
}

test "destroy frees the slot" {
    const table = try create_table();
    defer testing.allocator.destroy(table);

    const icon = try table.load(.{ .stock = .shield });

    table.destroy(icon);

    try testing.expect(table.get(icon) == null);
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
    const table = try create_table();
    defer testing.allocator.destroy(table);

    var index: u32 = 0;

    while (index < icon_count_max) : (index += 1) {
        _ = try table.load(.{ .stock = .application });
    }

    try testing.expectError(error.IconsExhausted, table.load(.{ .stock = .application }));
}

const full_argb: [pixmap_bytes_max]u8 = @splat(0);

test "the pixmap arena reports exhaustion and reclaims on release" {
    const table = try create_table();
    defer testing.allocator.destroy(table);

    const dimension = interface.pixmap_dimension_max;
    const full = Icon.Pixmap.init(&full_argb, dimension, dimension);
    const first = try table.load(.{ .pixels = full });

    try testing.expectEqual(pixmap_bytes_max, table.pixmap_used);
    try testing.expectError(error.IconsExhausted, table.load(.{ .pixels = full }));

    table.destroy(first);

    try testing.expectEqual(@as(u32, 0), table.pixmap_used);
}
