const std = @import("std");

const w32 = @import("win32.zig");

const contract = @import("../contract.zig");
const window = @import("window.zig");

const assert = std.debug.assert;

const interval_max: u32 = 0x7FFFFFFF;

pub const State = enum(u8) {
    running = 0,
    stopped = 1,
};

pub const Options = struct {
    coalesce_tolerance_ms: u32 = 0,
    hwnd: ?w32.HWND = null,
    id: u32,
    interval_ms: u32 = 1000,
};

pub const Error = contract.TimerError;

pub const NativeError = error{
    CreateFailed,
    StopFailed,
};

pub const timer_max: u32 = 16;

comptime {
    assert(timer_max > 0);
}

var entries: [timer_max]?Timer = [_]?Timer{null} ** timer_max;

pub fn start(id: u32, interval_ms: u32) Error!void {
    if (interval_ms == 0 or interval_ms > interval_max) {
        return Error.InvalidInterval;
    }

    if (find_index(id) != null) {
        return Error.DuplicateId;
    }

    const hwnd = window.handle() orelse return Error.StartFailed;
    const slot = find_empty_slot() orelse return Error.CapacityExceeded;

    assert(slot < timer_max);

    var timer = Timer.init(.{ .hwnd = hwnd, .id = id, .interval_ms = interval_ms });

    timer.start() catch {
        return Error.StartFailed;
    };

    entries[slot] = timer;

    assert(entries[slot] != null);
}

pub fn stop(id: u32) bool {
    const index = find_index(id) orelse return false;

    assert(index < timer_max);

    var stopped = true;

    if (entries[index]) |*timer| {
        timer.stop() catch {
            stopped = false;
        };
    }

    entries[index] = null;

    assert(entries[index] == null);

    return stopped;
}

pub fn stop_all() void {
    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

        if (entries[index]) |*timer| {
            timer.stop() catch {
                entries[index] = null;
            };

            entries[index] = null;
        }
    }

    assert(active_count() == 0);
}

pub fn is_running(id: u32) bool {
    return find_index(id) != null;
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

        if (entries[index]) |timer| {
            if (timer.id == id) return index;
        }
    }

    return null;
}

pub const Timer = struct {
    hwnd: ?w32.HWND,
    id: u32,
    interval_ms: u32,
    state: State,

    pub fn init(options: Options) Timer {
        assert(options.interval_ms > 0);
        assert(options.interval_ms <= interval_max);

        const result = Timer{
            .hwnd = options.hwnd,
            .id = options.id,
            .interval_ms = options.interval_ms,
            .state = .stopped,
        };

        assert(result.state == .stopped);

        return result;
    }

    pub fn is_running(timer: *const Timer) bool {
        return timer.state == .running;
    }

    pub fn restart(timer: *Timer) NativeError!void {
        assert(timer.interval_ms > 0);

        if (timer.state == .running) {
            try timer.stop();
        }

        try timer.start();

        assert(timer.state == .running);
    }

    pub fn set_interval(timer: *Timer, interval_ms: u32) NativeError!void {
        assert(interval_ms > 0);
        assert(interval_ms <= interval_max);

        timer.interval_ms = interval_ms;

        if (timer.state == .running) {
            const status = w32.SetTimer(timer.hwnd, timer.id, interval_ms, null);

            if (status == 0) {
                return NativeError.CreateFailed;
            }
        }

        assert(timer.interval_ms == interval_ms);
    }

    pub fn start(timer: *Timer) NativeError!void {
        assert(timer.interval_ms > 0);

        if (timer.state == .running) {
            return;
        }

        const status = w32.SetTimer(timer.hwnd, timer.id, timer.interval_ms, null);

        if (status == 0) {
            return NativeError.CreateFailed;
        }

        timer.state = .running;

        assert(timer.state == .running);
    }

    pub fn stop(timer: *Timer) NativeError!void {
        if (timer.state != .running) {
            return;
        }

        const status = w32.KillTimer(timer.hwnd, timer.id);

        timer.state = .stopped;

        assert(timer.state == .stopped);

        if (status == 0) {
            return NativeError.StopFailed;
        }
    }
};

const testing = std.testing;

test "State enum values" {
    try testing.expectEqual(@as(u8, 0), @intFromEnum(State.running));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(State.stopped));
}

test "a fresh timer starts stopped" {
    const timer = Timer.init(.{
        .hwnd = null,
        .id = 1,
        .interval_ms = 1000,
    });

    try testing.expectEqual(State.stopped, timer.state);
    try testing.expectEqual(@as(u32, 1), timer.id);
    try testing.expectEqual(@as(u32, 1000), timer.interval_ms);
    try testing.expect(timer.hwnd == null);
}

test "a stopped timer is not running" {
    const timer = Timer.init(.{
        .hwnd = null,
        .id = 1,
        .interval_ms = 1000,
    });

    try testing.expect(!timer.is_running());
}

test "a timer starts without a window handle" {
    var timer = Timer.init(.{
        .hwnd = null,
        .id = 1,
        .interval_ms = 1000,
    });

    try timer.start();

    try testing.expect(timer.is_running());
}

test "start requires an open window" {
    if (window.is_open()) {
        return;
    }

    try testing.expectError(Error.StartFailed, start(1, 1000));
}

test "start rejects an invalid interval" {
    try testing.expectError(Error.InvalidInterval, start(1, 0));
    try testing.expectError(Error.InvalidInterval, start(1, interval_max + 1));
}

test "stopping a stopped timer is inert" {
    var timer = Timer.init(.{
        .hwnd = null,
        .id = 1,
        .interval_ms = 1000,
    });

    try timer.stop();

    try testing.expectEqual(State.stopped, timer.state);
}

test "Options defaults" {
    const options = Options{
        .id = 1,
    };

    try testing.expectEqual(@as(u32, 0), options.coalesce_tolerance_ms);
    try testing.expect(options.hwnd == null);
    try testing.expectEqual(@as(u32, 1000), options.interval_ms);
}

test "Options custom values" {
    const options = Options{
        .id = 42,
        .interval_ms = 500,
        .coalesce_tolerance_ms = 100,
    };

    try testing.expectEqual(@as(u32, 42), options.id);
    try testing.expectEqual(@as(u32, 500), options.interval_ms);
    try testing.expectEqual(@as(u32, 100), options.coalesce_tolerance_ms);
}
