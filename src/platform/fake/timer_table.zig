const std = @import("std");

const interface = @import("../interface.zig");

const assert = std.debug.assert;

const PlatformError = interface.PlatformError;
const Timer = interface.Timer;

const timer_slot_count = interface.timer_slot_count;

const TimerTable = @This();

entries: [timer_slot_count]?Timer,
start_count: u32,
stop_count: u32,

pub fn init(table: *TimerTable) void {
    table.* = .{ .entries = @splat(null), .start_count = 0, .stop_count = 0 };

    assert(table.active_count() == 0);
}

pub fn start(table: *TimerTable, timer: Timer) PlatformError!void {
    assert(timer.interval_ms > 0);
    assert(timer.interval_ms <= interface.timer_interval_ms_max);
    assert(table.find_index(timer.id) == null);

    const slot = table.find_empty_slot() orelse return error.TimerStartFailed;

    assert(slot < timer_slot_count);

    table.entries[slot] = timer;
    table.start_count += 1;

    assert(table.entries[slot] != null);
}

pub fn stop(table: *TimerTable, id: u32) bool {
    const index = find_index(table, id) orelse return false;

    assert(index < timer_slot_count);

    table.entries[index] = null;
    table.stop_count += 1;

    assert(table.entries[index] == null);

    return true;
}

pub fn stop_all(table: *TimerTable) void {
    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        assert(index < timer_slot_count);

        if (table.entries[index]) |entry| {
            _ = table.stop(entry.id);
        }
    }

    assert(table.active_count() == 0);
}

pub fn is_running(table: *const TimerTable, id: u32) bool {
    return find_index(table, id) != null;
}

pub fn interval_of(table: *const TimerTable, id: u32) ?u32 {
    const index = find_index(table, id) orelse return null;

    assert(index < timer_slot_count);

    return table.entries[index].?.interval_ms;
}

pub fn active_count(table: *const TimerTable) u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        assert(index < timer_slot_count);

        if (table.entries[index] != null) total += 1;
    }

    assert(total <= timer_slot_count);

    return total;
}

pub fn counts(table: *const TimerTable) struct { started: u32, stopped: u32 } {
    return .{ .started = table.start_count, .stopped = table.stop_count };
}

fn find_empty_slot(table: *const TimerTable) ?u32 {
    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        assert(index < timer_slot_count);

        if (table.entries[index] == null) return index;
    }

    return null;
}

fn find_index(table: *const TimerTable, id: u32) ?u32 {
    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        assert(index < timer_slot_count);

        if (table.entries[index]) |entry| {
            if (entry.id == id) return index;
        }
    }

    return null;
}

const testing = std.testing;

test "a full timer table refuses the next start" {
    var table: TimerTable = undefined;

    table.init();

    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        try table.start(.{ .id = index, .interval_ms = 500 });
    }

    const overflow = table.start(.{ .id = timer_slot_count, .interval_ms = 500 });

    try testing.expectError(error.TimerStartFailed, overflow);
}

test "start registers a running timer" {
    var table: TimerTable = undefined;

    table.init();

    try table.start(.{ .id = 1, .interval_ms = 500 });

    try testing.expect(table.is_running(1));
    try testing.expectEqual(@as(?u32, 500), table.interval_of(1));
    try testing.expectEqual(@as(u32, 1), table.active_count());
}

test "stop reports whether the timer existed" {
    var table: TimerTable = undefined;

    table.init();

    try table.start(.{ .id = 1, .interval_ms = 500 });

    try testing.expect(table.stop(1));
    try testing.expect(!table.stop(1));
    try testing.expectEqual(@as(u32, 0), table.active_count());
}

test "stop_all clears every live timer" {
    var table: TimerTable = undefined;

    table.init();

    try table.start(.{ .id = 1, .interval_ms = 500 });
    try table.start(.{ .id = 2, .interval_ms = 500 });

    table.stop_all();

    try testing.expectEqual(@as(u32, 0), table.active_count());
    try testing.expectEqual(@as(u32, 2), table.counts().stopped);
}
