const std = @import("std");

const w32 = @import("win32.zig");

const interface = @import("../interface.zig");
const Window = @import("window.zig");

const assert = std.debug.assert;

const PlatformError = interface.PlatformError;

const interval_max = interface.timer_interval_ms_max;
const timer_slot_count = interface.timer_slot_count;

const TimerTable = @This();

entries: [timer_slot_count]?NativeTimer,
window: *const Window,

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

pub const NativeError = error{
    CreateFailed,
    StopFailed,
};

comptime {
    assert(timer_slot_count > 0);
    assert(interval_max == 0x7FFF_FFFF);
}

pub fn init(table: *TimerTable, window: *const Window) void {
    table.* = .{ .entries = @splat(null), .window = window };

    assert(table.active_count() == 0);
    assert(table.window == window);
}

pub fn start(table: *TimerTable, timer: interface.Timer) PlatformError!void {
    assert(timer.interval_ms > 0);
    assert(timer.interval_ms <= interval_max);
    assert(table.find_index(timer.id) == null);

    const hwnd = table.window.handle orelse return error.TimerStartFailed;
    const slot = table.find_empty_slot() orelse return error.TimerStartFailed;

    assert(slot < timer_slot_count);

    var native = NativeTimer.init(.{
        .hwnd = hwnd,
        .id = timer.id,
        .interval_ms = timer.interval_ms,
    });

    native.start() catch {
        return error.TimerStartFailed;
    };

    table.entries[slot] = native;

    assert(table.entries[slot] != null);
}

pub fn stop(table: *TimerTable, id: u32) bool {
    const index = find_index(table, id) orelse return false;

    assert(index < timer_slot_count);

    var stopped = true;

    if (table.entries[index]) |*timer| {
        timer.stop() catch {
            stopped = false;
        };
    }

    table.entries[index] = null;

    assert(table.entries[index] == null);

    return stopped;
}

pub fn stop_all(table: *TimerTable) void {
    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        assert(index < timer_slot_count);

        if (table.entries[index]) |*timer| {
            timer.stop() catch {
                table.entries[index] = null;
            };

            table.entries[index] = null;
        }
    }

    assert(table.active_count() == 0);
}

pub fn is_running(table: *const TimerTable, id: u32) bool {
    return find_index(table, id) != null;
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

        if (table.entries[index]) |timer| {
            if (timer.id == id) return index;
        }
    }

    return null;
}

pub const NativeTimer = struct {
    hwnd: ?w32.HWND,
    id: u32,
    interval_ms: u32,
    state: State,

    pub fn init(options: Options) NativeTimer {
        assert(options.interval_ms > 0);
        assert(options.interval_ms <= interval_max);

        const result = NativeTimer{
            .hwnd = options.hwnd,
            .id = options.id,
            .interval_ms = options.interval_ms,
            .state = .stopped,
        };

        assert(result.state == .stopped);

        return result;
    }

    pub fn is_running(timer: *const NativeTimer) bool {
        return timer.state == .running;
    }

    pub fn restart(timer: *NativeTimer) NativeError!void {
        assert(timer.interval_ms > 0);

        if (timer.state == .running) {
            try timer.stop();
        }

        try timer.start();

        assert(timer.state == .running);
    }

    pub fn set_interval(timer: *NativeTimer, interval_ms: u32) NativeError!void {
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

    pub fn start(timer: *NativeTimer) NativeError!void {
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

    pub fn stop(timer: *NativeTimer) NativeError!void {
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
    try testing.expectEqual(@as(u8, 0), @backingInt(State.running));
    try testing.expectEqual(@as(u8, 1), @backingInt(State.stopped));
}

test "a fresh timer starts stopped" {
    const timer = NativeTimer.init(.{ .hwnd = null, .id = 1, .interval_ms = 1000 });

    try testing.expectEqual(State.stopped, timer.state);
    try testing.expectEqual(@as(u32, 1), timer.id);
    try testing.expectEqual(@as(u32, 1000), timer.interval_ms);
    try testing.expect(timer.hwnd == null);
}

test "a stopped timer is not running" {
    const timer = NativeTimer.init(.{ .hwnd = null, .id = 1, .interval_ms = 1000 });

    try testing.expect(!timer.is_running());
}

test "a timer starts without a window handle" {
    var timer = NativeTimer.init(.{ .hwnd = null, .id = 1, .interval_ms = 1000 });

    try timer.start();

    try testing.expect(timer.is_running());
}

test "start requires an open window" {
    const window: Window = .closed;

    var table: TimerTable = undefined;

    table.init(&window);

    try testing.expectError(error.TimerStartFailed, table.start(.{ .id = 1, .interval_ms = 1000 }));
}

test "stopping a stopped timer is inert" {
    var timer = NativeTimer.init(.{ .hwnd = null, .id = 1, .interval_ms = 1000 });

    try timer.stop();

    try testing.expectEqual(State.stopped, timer.state);
}

test "Options defaults" {
    const options = Options{ .id = 1 };

    try testing.expectEqual(@as(u32, 0), options.coalesce_tolerance_ms);
    try testing.expect(options.hwnd == null);
    try testing.expectEqual(@as(u32, 1000), options.interval_ms);
}

test "Options custom values" {
    const options = Options{ .id = 42, .interval_ms = 500, .coalesce_tolerance_ms = 100 };

    try testing.expectEqual(@as(u32, 42), options.id);
    try testing.expectEqual(@as(u32, 500), options.interval_ms);
    try testing.expectEqual(@as(u32, 100), options.coalesce_tolerance_ms);
}
