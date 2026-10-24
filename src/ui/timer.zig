const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.timer;

const CapacityError = platform.CapacityError;
const PlatformError = platform.PlatformError;
const RequestError = platform.RequestError;

const timer_count_max = platform.timer_count_max;
const timer_interval_ms_max = platform.timer_interval_ms_max;

const Entry = struct {
    id: u32,
    interval_ms: u32,
    tick_count: u64,
};

pub const TimerSet = struct {
    count: u8,
    entries: [timer_count_max]?Entry,

    pub const Timer = platform.Timer;

    pub fn init() TimerSet {
        const result = TimerSet{
            .count = 0,
            .entries = @splat(null),
        };

        assert(result.count == 0);

        return result;
    }

    pub fn deinit(timers: *TimerSet) void {
        for (&timers.entries) |*slot| {
            if (slot.*) |entry| {
                _ = backend.stop(entry.id);
            }

            slot.* = null;
        }

        timers.count = 0;

        assert(timers.count == 0);
    }

    pub fn is_running(timers: *const TimerSet, id: u32) bool {
        return timers.find(id) != null;
    }

    pub fn start(
        timers: *TimerSet,
        timer: Timer,
    ) (CapacityError || PlatformError || RequestError)!void {
        if (timer.interval_ms == 0) return error.IntervalInvalid;
        if (timer.interval_ms > timer_interval_ms_max) return error.IntervalTooLong;
        if (timers.find(timer.id) != null) return error.TimerDuplicate;

        const slot = timers.find_empty() orelse return error.TimersExhausted;

        assert(slot < timer_count_max);

        try backend.start(timer);

        timers.entries[slot] = .{
            .id = timer.id,
            .interval_ms = timer.interval_ms,
            .tick_count = 0,
        };

        timers.count += 1;

        assert(timers.count <= timer_count_max);
    }

    pub fn stop(timers: *TimerSet, id: u32) RequestError!void {
        const index = timers.find(id) orelse return error.TimerUnknown;

        assert(timers.count > 0);

        _ = backend.stop(id);

        timers.entries[index] = null;
        timers.count -= 1;
    }

    pub fn tick(timers: *TimerSet, id: u32) u64 {
        const index = timers.find(id) orelse return 0;

        if (timers.entries[index]) |*entry| {
            entry.tick_count += 1;

            return entry.tick_count;
        }

        return 0;
    }

    fn find(timers: *const TimerSet, id: u32) ?u8 {
        for (timers.entries, 0..) |slot, index| {
            const entry = slot orelse continue;
            if (entry.id == id) return @intCast(index);
        }

        return null;
    }

    fn find_empty(timers: *const TimerSet) ?u8 {
        for (timers.entries, 0..) |slot, index| {
            if (slot == null) return @intCast(index);
        }

        return null;
    }
};

const testing = std.testing;

const mock = platform.mock;

fn open_runtime() !void {
    mock.reset();

    try mock.runtime.open(.{ .name = "timers" });
}

test TimerSet {
    try open_runtime();
    defer mock.runtime.close();

    var timers = TimerSet.init();
    defer timers.deinit();

    try timers.start(.{ .id = 7, .interval_ms = 1000 });

    try testing.expect(timers.is_running(7));
    try testing.expectEqual(@as(u64, 1), timers.tick(7));
    try testing.expectEqual(@as(u64, 2), timers.tick(7));

    try timers.stop(7);

    try testing.expect(!timers.is_running(7));
}

test "a timer set names the fault in each refused timer" {
    try open_runtime();
    defer mock.runtime.close();

    var timers = TimerSet.init();
    defer timers.deinit();

    try timers.start(.{ .id = 1, .interval_ms = 10 });

    const distant = TimerSet.Timer{ .id = 3, .interval_ms = timer_interval_ms_max + 1 };

    try testing.expectError(error.IntervalInvalid, timers.start(.{ .id = 2, .interval_ms = 0 }));
    try testing.expectError(error.IntervalTooLong, timers.start(distant));
    try testing.expectError(error.TimerDuplicate, timers.start(.{ .id = 1, .interval_ms = 10 }));
    try testing.expectError(error.TimerUnknown, timers.stop(999));
}

test "a timer set started before the runtime opens reports the platform refusal" {
    mock.reset();

    var timers = TimerSet.init();
    defer timers.deinit();

    try testing.expectError(error.TimerStartFailed, timers.start(.{ .id = 1, .interval_ms = 10 }));
    try testing.expect(!timers.is_running(1));
}

test "a full timer set refuses another timer" {
    try open_runtime();
    defer mock.runtime.close();

    var timers = TimerSet.init();
    defer timers.deinit();

    var id: u32 = 0;

    while (id < timer_count_max) : (id += 1) {
        try timers.start(.{ .id = id, .interval_ms = 10 });
    }

    try testing.expectError(error.TimersExhausted, timers.start(.{ .id = 99, .interval_ms = 10 }));
}

test "a tick for an unknown timer id is ignored" {
    var timers = TimerSet.init();
    defer timers.deinit();

    try testing.expectEqual(@as(u64, 0), timers.tick(999));
}
