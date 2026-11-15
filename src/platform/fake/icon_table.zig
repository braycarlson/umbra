const std = @import("std");

const interface = @import("../interface.zig");

const assert = std.debug.assert;

const CapacityError = interface.CapacityError;
const Icon = interface.Icon;

const icon_count_max = interface.icon_count_max;

const IconTable = @This();

destroy_count: u32,
entries: [icon_count_max]?Icon.Source,
load_count: u32,

pub fn init(table: *IconTable) void {
    table.* = .{ .destroy_count = 0, .entries = @splat(null), .load_count = 0 };

    assert(table.live_count() == 0);
}

pub fn load(table: *IconTable, source: Icon.Source) CapacityError!Icon {
    assert(source.is_valid());
    assert(table.load_count >= table.destroy_count);

    const slot = table.find_empty_slot() orelse return error.IconsExhausted;

    table.entries[slot] = source;
    table.load_count += 1;

    return @fromBackingInt(slot);
}

pub fn destroy(table: *IconTable, icon: Icon) void {
    assert(@backingInt(icon) < icon_count_max);

    const slot = @backingInt(icon);

    if (table.entries[slot] == null) {
        return;
    }

    table.entries[slot] = null;
    table.destroy_count += 1;

    assert(table.entries[slot] == null);
}

pub fn get(table: *const IconTable, icon: Icon) ?Icon.Source {
    assert(@backingInt(icon) < icon_count_max);

    return table.entries[@backingInt(icon)];
}

pub fn live_count(table: *const IconTable) u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < icon_count_max) : (index += 1) {
        assert(index < icon_count_max);

        if (table.entries[index] != null) total += 1;
    }

    assert(total <= icon_count_max);

    return total;
}

pub fn counts(table: *const IconTable) struct { destroyed: u32, loaded: u32 } {
    return .{ .destroyed = table.destroy_count, .loaded = table.load_count };
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

test "load stores the source and hands back a live icon" {
    var table: IconTable = undefined;

    table.init();

    const icon = try table.load(.{ .stock = .application });

    try testing.expectEqual(Icon.Stock.application, table.get(icon).?.stock);
    try testing.expectEqual(@as(u32, 1), table.live_count());
}

test "a full icon table reports the exhaustion" {
    var table: IconTable = undefined;

    table.init();

    var index: u32 = 0;

    while (index < icon_count_max) : (index += 1) {
        _ = try table.load(.{ .stock = .application });
    }

    try testing.expectError(error.IconsExhausted, table.load(.{ .stock = .application }));
}

test "destroy frees the slot" {
    var table: IconTable = undefined;

    table.init();

    const icon = try table.load(.{ .stock = .application });

    table.destroy(icon);

    try testing.expectEqual(@as(u32, 0), table.live_count());
    try testing.expect(table.get(icon) == null);
    try testing.expectEqual(@as(u32, 1), table.counts().destroyed);
}
