const std = @import("std");

const platform_module = @import("../platform.zig");

const assert = std.debug.assert;

const CapacityError = platform_module.CapacityError;
const PlatformError = platform_module.PlatformError;
const RequestError = platform_module.RequestError;

const timer_count_max = platform_module.timer_count_max;
const timer_id_max = platform_module.timer_id_max;
const timer_interval_ms_max = platform_module.timer_interval_ms_max;

const Entry = struct {
    id: u32,
    interval_ms: u32,
    tick_count: u64,
};

pub fn TimerSetType(comptime Platform: type) type {
    return struct {
        count: u8,
        entries: [timer_count_max]?Entry,
        platform: *Platform,

        const TimerSet = @This();

        pub const Timer = platform_module.Timer;

        pub fn init(platform: *Platform) TimerSet {
            const result = TimerSet{ .count = 0, .entries = @splat(null), .platform = platform };

            assert(result.count == 0);

            return result;
        }

        pub fn deinit(timers: *TimerSet) void {
            for (&timers.entries) |*slot| {
                if (slot.*) |entry| {
                    _ = timers.platform.timer_stop(entry.id);
                }

                slot.* = null;
            }

            timers.count = 0;

            assert(timers.count == 0);
        }

        pub fn is_running(timers: *const TimerSet, id: u32) bool {
            assert(id <= timer_id_max);

            return timers.find(id) != null;
        }

        pub fn start(
            timers: *TimerSet,
            timer: Timer,
        ) (CapacityError || PlatformError || RequestError)!void {
            if (timer.interval_ms == 0) return error.IntervalInvalid;
            if (timer.interval_ms > timer_interval_ms_max) return error.IntervalTooLong;
            if (timer.id > timer_id_max) return error.TimerReserved;
            if (timers.find(timer.id) != null) return error.TimerDuplicate;

            const slot = timers.find_empty() orelse return error.TimersExhausted;

            assert(slot < timer_count_max);

            try timers.platform.timer_start(timer);

            timers.entries[slot] = .{
                .id = timer.id,
                .interval_ms = timer.interval_ms,
                .tick_count = 0,
            };

            timers.count += 1;

            assert(timers.count <= timer_count_max);
        }

        pub fn stop(timers: *TimerSet, id: u32) RequestError!void {
            assert(id <= timer_id_max);

            const index = timers.find(id) orelse return error.TimerUnknown;

            assert(timers.count > 0);

            _ = timers.platform.timer_stop(id);

            timers.entries[index] = null;
            timers.count -= 1;
        }

        pub fn tick(timers: *TimerSet, id: u32) u64 {
            assert(id <= timer_id_max);

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
                if (entry.id != id) continue;

                const result: u8 = @intCast(index);
                assert(result < timer_count_max);

                return result;
            }

            return null;
        }

        fn find_empty(timers: *const TimerSet) ?u8 {
            for (timers.entries, 0..) |slot, index| {
                if (slot != null) continue;

                const result: u8 = @intCast(index);
                assert(timers.entries[result] == null);

                return result;
            }

            return null;
        }
    };
}

const testing = std.testing;

const Fake = platform_module.Fake;
const FakeTimerSet = TimerSetType(Fake);

test TimerSetType {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "timers" });
    defer fake.deinit();

    var timers = FakeTimerSet.init(&fake);
    defer timers.deinit();

    try timers.start(.{ .id = 7, .interval_ms = 1000 });

    try testing.expect(timers.is_running(7));
    try testing.expectEqual(@as(u64, 1), timers.tick(7));
    try testing.expectEqual(@as(u64, 2), timers.tick(7));

    try timers.stop(7);

    try testing.expect(!timers.is_running(7));
}

test "a timer set names the fault in each refused timer" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "timers" });
    defer fake.deinit();

    var timers = FakeTimerSet.init(&fake);
    defer timers.deinit();

    try timers.start(.{ .id = 1, .interval_ms = 10 });

    const distant = FakeTimerSet.Timer{ .id = 3, .interval_ms = timer_interval_ms_max + 1 };

    try testing.expectError(error.IntervalInvalid, timers.start(.{ .id = 2, .interval_ms = 0 }));
    try testing.expectError(error.IntervalTooLong, timers.start(distant));
    try testing.expectError(error.TimerDuplicate, timers.start(.{ .id = 1, .interval_ms = 10 }));
    try testing.expectError(error.TimerUnknown, timers.stop(999));
}

test "a timer set the platform refuses reports the refusal" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "timers" });
    defer fake.deinit();

    fake.fault.arm(.timer_start);

    var timers = FakeTimerSet.init(&fake);
    defer timers.deinit();

    try testing.expectError(error.TimerStartFailed, timers.start(.{ .id = 1, .interval_ms = 10 }));
    try testing.expect(!timers.is_running(1));
}

test "a full timer set refuses another timer" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "timers" });
    defer fake.deinit();

    var timers = FakeTimerSet.init(&fake);
    defer timers.deinit();

    var id: u32 = 0;

    while (id < timer_count_max) : (id += 1) {
        try timers.start(.{ .id = id, .interval_ms = 10 });
    }

    try testing.expectError(error.TimersExhausted, timers.start(.{ .id = 99, .interval_ms = 10 }));
}

test "a tick for an unknown timer id is ignored" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "timers" });
    defer fake.deinit();

    var timers = FakeTimerSet.init(&fake);
    defer timers.deinit();

    try testing.expectEqual(@as(u64, 0), timers.tick(999));
}
