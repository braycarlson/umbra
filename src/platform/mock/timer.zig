const std = @import("std");

const contract = @import("../contract.zig");
const fault = @import("fault.zig");
const runtime = @import("runtime.zig");

const assert = std.debug.assert;

const PlatformError = contract.PlatformError;
const Timer = contract.Timer;

const timer_count_max = contract.timer_count_max;

var entries: [timer_count_max]?Timer = @splat(null);
var start_count: u32 = 0;
var stop_count: u32 = 0;

pub fn start(timer: Timer) PlatformError!void {
    assert(timer.interval_ms > 0);
    assert(timer.interval_ms <= contract.timer_interval_ms_max);
    assert(find_index(timer.id) == null);

    if (!runtime.is_open()) return error.TimerStartFailed;
    if (fault.is_armed(.timer_start)) return error.TimerStartFailed;

    const slot = find_empty_slot() orelse return error.TimerStartFailed;

    assert(slot < timer_count_max);

    entries[slot] = timer;
    start_count += 1;

    assert(entries[slot] != null);
}

pub fn stop(id: u32) bool {
    const index = find_index(id) orelse return false;

    assert(index < timer_count_max);

    entries[index] = null;
    stop_count += 1;

    assert(entries[index] == null);

    return true;
}

pub fn stop_all() void {
    var index: u32 = 0;

    while (index < timer_count_max) : (index += 1) {
        assert(index < timer_count_max);

        if (entries[index]) |entry| {
            _ = stop(entry.id);
        }
    }

    assert(active_count() == 0);
}

pub fn is_running(id: u32) bool {
    return find_index(id) != null;
}

pub fn interval_of(id: u32) ?u32 {
    const index = find_index(id) orelse return null;

    assert(index < timer_count_max);

    return entries[index].?.interval_ms;
}

pub fn active_count() u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < timer_count_max) : (index += 1) {
        assert(index < timer_count_max);

        if (entries[index] != null) total += 1;
    }

    assert(total <= timer_count_max);

    return total;
}

pub fn counts() struct { started: u32, stopped: u32 } {
    return .{ .started = start_count, .stopped = stop_count };
}

pub fn reset() void {
    entries = @splat(null);
    start_count = 0;
    stop_count = 0;

    assert(active_count() == 0);
}

fn find_empty_slot() ?u32 {
    var index: u32 = 0;

    while (index < timer_count_max) : (index += 1) {
        assert(index < timer_count_max);

        if (entries[index] == null) return index;
    }

    return null;
}

fn find_index(id: u32) ?u32 {
    var index: u32 = 0;

    while (index < timer_count_max) : (index += 1) {
        assert(index < timer_count_max);

        if (entries[index]) |entry| {
            if (entry.id == id) return index;
        }
    }

    return null;
}

const testing = std.testing;

fn open_runtime() !void {
    runtime.reset();

    try runtime.open(.{ .name = "umbra" });
}

test "start requires an open runtime" {
    reset();
    runtime.reset();

    try testing.expectError(error.TimerStartFailed, start(.{ .id = 1, .interval_ms = 500 }));
}

test "start registers a running timer" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try start(.{ .id = 1, .interval_ms = 500 });

    try testing.expect(is_running(1));
    try testing.expectEqual(@as(?u32, 500), interval_of(1));
    try testing.expectEqual(@as(u32, 1), active_count());
}

test "start honors the injected failure" {
    reset();
    fault.reset();

    try open_runtime();
    defer runtime.reset();

    fault.arm(.timer_start);
    defer fault.reset();

    try testing.expectError(error.TimerStartFailed, start(.{ .id = 1, .interval_ms = 500 }));
}

test "stop reports whether the timer existed" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try start(.{ .id = 1, .interval_ms = 500 });

    try testing.expect(stop(1));
    try testing.expect(!stop(1));
    try testing.expectEqual(@as(u32, 0), active_count());
}

test "stop_all clears every live timer" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try start(.{ .id = 1, .interval_ms = 500 });
    try start(.{ .id = 2, .interval_ms = 500 });

    stop_all();

    try testing.expectEqual(@as(u32, 0), active_count());
    try testing.expectEqual(@as(u32, 2), counts().stopped);
}
