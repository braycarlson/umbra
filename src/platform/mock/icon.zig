const std = @import("std");

const contract = @import("../contract.zig");

const assert = std.debug.assert;

pub const Error = contract.IconError;

pub const Source = contract.IconSource;
pub const Handle = contract.IconHandle;

pub const supports_resource: bool = true;

pub const handle_max: u32 = 32;

comptime {
    assert(handle_max > 0);
}

var entries: [handle_max]?Source = @splat(null);
var load_count: u32 = 0;
var destroy_count: u32 = 0;
var fail_load: bool = false;

pub fn load(source: Source) Error!Handle {
    if (!source.is_valid()) {
        return Error.InvalidSource;
    }

    if (fail_load) {
        return Error.LoadFailed;
    }

    const slot = find_empty_slot() orelse return Error.CapacityExceeded;

    assert(slot < handle_max);

    entries[slot] = source;
    load_count += 1;

    assert(entries[slot] != null);

    return slot;
}

pub fn destroy(handle: Handle) void {
    if (handle >= handle_max) {
        return;
    }

    if (entries[handle] == null) {
        return;
    }

    entries[handle] = null;
    destroy_count += 1;

    assert(entries[handle] == null);
}

pub fn get(handle: Handle) ?Source {
    if (handle >= handle_max) {
        return null;
    }

    return entries[handle];
}

pub fn live_count() u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

        if (entries[index] != null) total += 1;
    }

    assert(total <= handle_max);

    return total;
}

pub fn counts() struct { destroyed: u32, loaded: u32 } {
    return .{ .destroyed = destroy_count, .loaded = load_count };
}

pub fn set_fail_load(fail: bool) void {
    fail_load = fail;

    assert(fail_load == fail);
}

pub fn reset() void {
    entries = @splat(null);
    load_count = 0;
    destroy_count = 0;
    fail_load = false;

    assert(live_count() == 0);
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

test "load stores the source and hands back a live handle" {
    reset();

    const handle = try load(.{ .stock = .application });
    const stored = get(handle);

    try testing.expect(stored != null);
    try testing.expectEqual(Source{ .stock = .application }, stored.?);
    try testing.expectEqual(@as(u32, 1), live_count());
}

test "load rejects an invalid source" {
    reset();

    try testing.expectError(Error.InvalidSource, load(.{ .resource = 0 }));
}

test "load honors the injected failure" {
    reset();
    set_fail_load(true);

    try testing.expectError(Error.LoadFailed, load(.{ .stock = .shield }));
}

test "destroy frees the slot" {
    reset();

    const handle = try load(.{ .stock = .application });

    destroy(handle);

    try testing.expectEqual(@as(u32, 0), live_count());
    try testing.expect(get(handle) == null);
    try testing.expectEqual(@as(u32, 1), counts().destroyed);
}

test "load reports capacity exhaustion" {
    reset();

    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        _ = try load(.{ .stock = .application });
    }

    try testing.expectError(Error.CapacityExceeded, load(.{ .stock = .application }));
}
