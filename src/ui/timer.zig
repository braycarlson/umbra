const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.timer;

pub const timer_max: u8 = 16;

pub const Error = platform.TimerError;

comptime {
    assert(timer_max > 0);
}

pub const Handle = struct {
    id: u32,
    manager: *TimerManager,

    pub fn get_tick_count(handle: *const Handle) u64 {
        return handle.manager.get_tick_count(handle.id);
    }

    pub fn reset_tick_count(handle: *const Handle) void {
        handle.manager.reset_tick_count(handle.id);
    }

    pub fn stop(handle: *const Handle) Error!void {
        try handle.manager.stop(handle.id);
    }
};

pub const Entry = struct {
    id: u32,
    interval_ms: u32,
    tick_count: u64,

    pub fn init(id: u32, interval_ms: u32) Entry {
        assert(interval_ms > 0);

        const result = Entry{
            .id = id,
            .interval_ms = interval_ms,
            .tick_count = 0,
        };

        assert(result.tick_count == 0);

        return result;
    }
};

pub const TimerManager = struct {
    count: u8,
    entries: [timer_max]?Entry,

    pub fn init() TimerManager {
        const result = TimerManager{
            .count = 0,
            .entries = [_]?Entry{null} ** timer_max,
        };

        assert(result.count == 0);

        return result;
    }

    pub fn deinit(manager: *TimerManager) void {
        manager.stop_all();

        assert(manager.count == 0);
    }

    pub fn get_interval(manager: *const TimerManager, id: u32) ?u32 {
        const index = find_index(manager, id) orelse return null;

        assert(index < timer_max);

        return manager.entries[index].?.interval_ms;
    }

    pub fn get_tick_count(manager: *const TimerManager, id: u32) u64 {
        const index = find_index(manager, id) orelse return 0;

        assert(index < timer_max);

        return manager.entries[index].?.tick_count;
    }

    pub fn handle_tick(manager: *TimerManager, id: u32) u64 {
        const index = find_index(manager, id) orelse return 0;

        assert(index < timer_max);

        if (manager.entries[index]) |*entry| {
            entry.tick_count += 1;

            return entry.tick_count;
        }

        return 0;
    }

    pub fn is_running(manager: *const TimerManager, id: u32) bool {
        return find_index(manager, id) != null;
    }

    pub fn reset_tick_count(manager: *TimerManager, id: u32) void {
        const index = find_index(manager, id) orelse return;

        assert(index < timer_max);

        if (manager.entries[index]) |*entry| {
            entry.tick_count = 0;
        }
    }

    pub fn start(timer_manager: *TimerManager, id: u32, interval_ms: u32) Error!Handle {
        if (interval_ms == 0) {
            return Error.InvalidInterval;
        }

        if (timer_manager.count >= timer_max) {
            return Error.CapacityExceeded;
        }

        if (find_index(timer_manager, id) != null) {
            return Error.DuplicateId;
        }

        const slot = find_empty_slot(timer_manager) orelse return Error.NoSlotAvailable;

        assert(slot < timer_max);

        backend.start(id, interval_ms) catch {
            return Error.StartFailed;
        };

        timer_manager.entries[slot] = Entry.init(id, interval_ms);
        timer_manager.count += 1;

        assert(timer_manager.count <= timer_max);

        const result = Handle{
            .id = id,
            .manager = timer_manager,
        };

        return result;
    }

    pub fn stop(manager: *TimerManager, id: u32) Error!void {
        const index = find_index(manager, id) orelse return Error.NotFound;

        assert(index < timer_max);
        assert(manager.count > 0);

        _ = backend.stop(id);

        manager.entries[index] = null;
        manager.count -= 1;

        assert(manager.entries[index] == null);
    }

    pub fn stop_all(manager: *TimerManager) void {
        var index: u8 = 0;

        while (index < timer_max) : (index += 1) {
            assert(index < timer_max);

            if (manager.entries[index]) |entry| {
                _ = backend.stop(entry.id);

                manager.entries[index] = null;
            }
        }

        manager.count = 0;

        assert(manager.count == 0);
    }
};

fn find_empty_slot(manager: *const TimerManager) ?u8 {
    var index: u8 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

        if (manager.entries[index] == null) return index;
    }

    return null;
}

fn find_index(manager: *const TimerManager, id: u32) ?u8 {
    var index: u8 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

        if (manager.entries[index]) |entry| {
            if (entry.id == id) return index;
        }
    }

    return null;
}

const testing = std.testing;

test "a fresh timer entry starts at zero ticks" {
    const entry = Entry.init(1, 1000);

    try testing.expectEqual(@as(u64, 0), entry.tick_count);
    try testing.expectEqual(@as(u32, 1), entry.id);
    try testing.expectEqual(@as(u32, 1000), entry.interval_ms);
}

test "a fresh timer manager holds no timers" {
    const manager = TimerManager.init();

    try testing.expectEqual(@as(u8, 0), manager.count);
}

test "an unknown timer id reports no ticks" {
    const manager = TimerManager.init();

    try testing.expectEqual(@as(u64, 0), manager.get_tick_count(999));
}

test "an unknown timer id is not running" {
    const manager = TimerManager.init();

    try testing.expect(!manager.is_running(999));
}

test "a timer manager rejects a zero interval" {
    var manager = TimerManager.init();
    defer manager.deinit();

    try testing.expectError(Error.InvalidInterval, manager.start(1, 0));
}

test "stopping an unknown timer id is reported" {
    var manager = TimerManager.init();
    defer manager.deinit();

    try testing.expectError(Error.NotFound, manager.stop(999));
}

test "stopping every timer on an empty manager is inert" {
    var manager = TimerManager.init();

    manager.stop_all();

    try testing.expectEqual(@as(u8, 0), manager.count);
}

test "a tick for an unknown timer id is ignored" {
    var manager = TimerManager.init();
    defer manager.deinit();

    try testing.expectEqual(@as(u64, 0), manager.handle_tick(999));
}

test "resetting an unknown timer id is ignored" {
    var manager = TimerManager.init();
    defer manager.deinit();

    manager.reset_tick_count(999);

    try testing.expectEqual(@as(u8, 0), manager.count);
}
