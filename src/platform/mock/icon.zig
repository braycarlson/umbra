const std = @import("std");

const contract = @import("../contract.zig");
const fault = @import("fault.zig");

const assert = std.debug.assert;

const CapacityError = contract.CapacityError;
const Icon = contract.Icon;
const PlatformError = contract.PlatformError;

const icon_count_max = contract.icon_count_max;

var entries: [icon_count_max]?Icon.Source = @splat(null);
var load_count: u32 = 0;
var destroy_count: u32 = 0;

pub fn load(source: Icon.Source) (CapacityError || PlatformError)!Icon {
    assert(source.is_valid());

    if (fault.is_armed(.icon_load)) {
        return error.IconLoadFailed;
    }

    const slot = find_empty_slot() orelse return error.IconsExhausted;

    entries[slot] = source;
    load_count += 1;

    return @fromBackingInt(slot);
}

pub fn destroy(icon: Icon) void {
    const slot = @backingInt(icon);

    if (slot >= icon_count_max) {
        return;
    }

    if (entries[slot] == null) {
        return;
    }

    entries[slot] = null;
    destroy_count += 1;

    assert(entries[slot] == null);
}

pub fn get(icon: Icon) ?Icon.Source {
    const slot = @backingInt(icon);

    if (slot >= icon_count_max) {
        return null;
    }

    return entries[slot];
}

pub fn live_count() u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < icon_count_max) : (index += 1) {
        assert(index < icon_count_max);

        if (entries[index] != null) total += 1;
    }

    assert(total <= icon_count_max);

    return total;
}

pub fn counts() struct { destroyed: u32, loaded: u32 } {
    return .{ .destroyed = destroy_count, .loaded = load_count };
}

pub fn reset() void {
    entries = @splat(null);
    load_count = 0;
    destroy_count = 0;

    assert(live_count() == 0);
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

test "load stores the source and hands back a live icon" {
    reset();

    const icon = try load(.{ .stock = .application });

    try testing.expectEqual(Icon.Stock.application, get(icon).?.stock);
    try testing.expectEqual(@as(u32, 1), live_count());
}

test "load honors the injected failure" {
    reset();
    fault.reset();
    fault.arm(.icon_load);
    defer fault.reset();

    try testing.expectError(error.IconLoadFailed, load(.{ .stock = .shield }));
}

test "a full icon table reports the exhaustion" {
    reset();

    var index: u32 = 0;

    while (index < icon_count_max) : (index += 1) {
        _ = try load(.{ .stock = .application });
    }

    try testing.expectError(error.IconsExhausted, load(.{ .stock = .application }));
}

test "destroy frees the slot" {
    reset();

    const icon = try load(.{ .stock = .application });

    destroy(icon);

    try testing.expectEqual(@as(u32, 0), live_count());
    try testing.expect(get(icon) == null);
    try testing.expectEqual(@as(u32, 1), counts().destroyed);
}
