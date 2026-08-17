const std = @import("std");

const contract = @import("../contract.zig");
const runtime = @import("runtime.zig");

const assert = std.debug.assert;

pub const Error = contract.TimerError;

pub const timer_max: u32 = 16;

comptime {
    assert(timer_max > 0);
}

const Entry = struct {
    id: u32,
    interval_ms: u32,
};

var entries: [timer_max]?Entry = [_]?Entry{null} ** timer_max;
var start_count: u32 = 0;
var stop_count: u32 = 0;
var fail_start: bool = false;

pub fn start(id: u32, interval_ms: u32) Error!void {
    if (interval_ms == 0) {
        return Error.InvalidInterval;
    }

    if (find_index(id) != null) {
        return Error.DuplicateId;
    }

    if (!runtime.is_open() or fail_start) {
        return Error.StartFailed;
    }

    const slot = find_empty_slot() orelse return Error.CapacityExceeded;

    assert(slot < timer_max);

    entries[slot] = .{ .id = id, .interval_ms = interval_ms };
    start_count += 1;

    assert(entries[slot] != null);
}

pub fn stop(id: u32) bool {
    const index = find_index(id) orelse return false;

    assert(index < timer_max);

    entries[index] = null;
    stop_count += 1;

    assert(entries[index] == null);

    return true;
}

pub fn stop_all() void {
    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

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

    assert(index < timer_max);

    return entries[index].?.interval_ms;
}

pub fn active_count() u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

        if (entries[index] != null) total += 1;
    }

    assert(total <= timer_max);

    return total;
}

pub fn counts() struct { started: u32, stopped: u32 } {
    return .{ .started = start_count, .stopped = stop_count };
}

pub fn set_fail_start(fail: bool) void {
    fail_start = fail;

    assert(fail_start == fail);
}

pub fn reset() void {
    entries = [_]?Entry{null} ** timer_max;
    start_count = 0;
    stop_count = 0;
    fail_start = false;

    assert(active_count() == 0);
}

fn find_empty_slot() ?u32 {
    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

        if (entries[index] == null) return index;
    }

    return null;
}

fn find_index(id: u32) ?u32 {
    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

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

    try testing.expectError(Error.StartFailed, start(1, 500));
}

test "start registers a running timer" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try start(1, 500);

    try testing.expect(is_running(1));
    try testing.expectEqual(@as(?u32, 500), interval_of(1));
    try testing.expectEqual(@as(u32, 1), active_count());
}

test "start rejects a zero interval" {
    reset();

    try testing.expectError(Error.InvalidInterval, start(1, 0));
}

test "start rejects a duplicate id" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try start(1, 500);

    try testing.expectError(Error.DuplicateId, start(1, 250));
}

test "start honors the injected failure" {
    reset();

    try open_runtime();
    defer runtime.reset();

    set_fail_start(true);

    try testing.expectError(Error.StartFailed, start(1, 500));
}

test "stop reports whether the timer existed" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try start(1, 500);

    try testing.expect(stop(1));
    try testing.expect(!stop(1));
    try testing.expectEqual(@as(u32, 0), active_count());
}

test "stop_all clears every live timer" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try start(1, 500);
    try start(2, 500);

    stop_all();

    try testing.expectEqual(@as(u32, 0), active_count());
    try testing.expectEqual(@as(u32, 2), counts().stopped);
}

test "start reports capacity exhaustion" {
    reset();

    try open_runtime();
    defer runtime.reset();

    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        try start(index, 100);
    }

    try testing.expectError(Error.CapacityExceeded, start(timer_max, 100));
}
