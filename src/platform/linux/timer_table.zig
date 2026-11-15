const std = @import("std");

const interface = @import("../interface.zig");
const sys = @import("sys.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

const PlatformError = interface.PlatformError;
const Timer = interface.Timer;

const timer_slot_count = interface.timer_slot_count;

const TimerTable = @This();

entries: [timer_slot_count]?Entry,
epoll: *const sys.Epoll,

const Entry = struct {
    fd: sys.Fd,
    id: u32,
    interval_ms: u32,
};

comptime {
    assert(timer_slot_count > 0);
}

pub fn init(table: *TimerTable, epoll: *const sys.Epoll) void {
    table.* = .{ .entries = @splat(null), .epoll = epoll };

    assert(table.active_count() == 0);
    assert(table.epoll == epoll);
}

pub fn adopt(table: *const TimerTable) void {
    assert(table.epoll.fd != null);

    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        assert(index < timer_slot_count);

        if (table.entries[index]) |entry| {
            table.epoll.register(entry.fd, true);
        }
    }
}

pub fn start(table: *TimerTable, timer: Timer) PlatformError!void {
    assert(timer.interval_ms > 0);
    assert(timer.interval_ms <= interface.timer_interval_ms_max);
    assert(table.find_index(timer.id) == null);

    const slot = table.find_empty_slot() orelse return error.TimerStartFailed;

    assert(slot < timer_slot_count);

    const raw = linux.timerfd_create(.MONOTONIC, .{ .CLOEXEC = true, .NONBLOCK = true });

    if (!sys.ok(raw)) {
        return error.TimerStartFailed;
    }

    const fd: sys.Fd = @intCast(raw);
    errdefer sys.close(fd);

    const seconds: isize = @intCast(timer.interval_ms / 1_000);
    const nanoseconds: isize = @intCast((timer.interval_ms % 1_000) * 1_000_000);

    const spec = linux.itimerspec{
        .it_interval = .{ .sec = seconds, .nsec = nanoseconds },
        .it_value = .{ .sec = seconds, .nsec = nanoseconds },
    };

    const status = linux.timerfd_settime(fd, .{}, &spec, null);

    if (!sys.ok(status)) {
        return error.TimerStartFailed;
    }

    table.entries[slot] = .{ .fd = fd, .id = timer.id, .interval_ms = timer.interval_ms };

    table.epoll.register(fd, true);

    assert(table.entries[slot] != null);
}

pub fn stop(table: *TimerTable, id: u32) bool {
    const index = find_index(table, id) orelse return false;

    assert(index < timer_slot_count);

    const entry = table.entries[index].?;

    table.epoll.register(entry.fd, false);

    sys.close(entry.fd);

    table.entries[index] = null;

    assert(table.entries[index] == null);

    return true;
}

pub fn stop_all(table: *TimerTable) void {
    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        assert(index < timer_slot_count);

        if (table.entries[index]) |entry| {
            table.epoll.register(entry.fd, false);

            sys.close(entry.fd);

            table.entries[index] = null;
        }
    }

    assert(table.active_count() == 0);
}

pub fn id_of(table: *const TimerTable, fd: sys.Fd) ?u32 {
    assert(fd >= 0);

    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        assert(index < timer_slot_count);

        if (table.entries[index]) |entry| {
            if (entry.fd == fd) return entry.id;
        }
    }

    return null;
}

pub fn drain(fd: sys.Fd) u64 {
    assert(fd >= 0);

    var expirations: [8]u8 = undefined;

    const count = sys.read(fd, &expirations) catch {
        return 0;
    };

    if (count < expirations.len) {
        return 0;
    }

    return std.mem.readInt(u64, &expirations, .little);
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

        if (table.entries[index]) |entry| {
            if (entry.id == id) return index;
        }
    }

    return null;
}

const testing = std.testing;

const ready_wait_ms: i32 = 1_000;

fn fd_of(table: *const TimerTable, id: u32) sys.Fd {
    const index = find_index(table, id).?;

    assert(index < timer_slot_count);

    return table.entries[index].?.fd;
}

fn expect_ready(epoll: *const sys.Epoll, fd: sys.Fd) !void {
    assert(epoll.fd != null);
    assert(fd >= 0);

    var ready: [1]linux.epoll_event = undefined;

    const count = epoll.wait(&ready, ready_wait_ms) orelse return error.WaitFailed;

    try testing.expectEqual(@as(u32, 1), count);
    try testing.expectEqual(fd, ready[0].data.fd);
}

test "start and stop drive a real timerfd" {
    var epoll: sys.Epoll = .closed;
    var table: TimerTable = undefined;

    table.init(&epoll);

    try table.start(.{ .id = 1, .interval_ms = 10 });

    try testing.expect(table.is_running(1));
    try testing.expectEqual(@as(u32, 1), table.active_count());
    try testing.expect(table.stop(1));
    try testing.expect(!table.stop(1));
    try testing.expectEqual(@as(u32, 0), table.active_count());
}

test "adopt registers timers started before the loop" {
    var epoll: sys.Epoll = .closed;
    var table: TimerTable = undefined;

    table.init(&epoll);

    try table.start(.{ .id = 7, .interval_ms = 10 });

    try epoll.open();
    defer epoll.close();

    table.adopt();

    try expect_ready(&epoll, fd_of(&table, 7));
    try testing.expect(table.stop(7));
}

test "a timer started while the loop is open registers at once" {
    var epoll: sys.Epoll = .closed;
    var table: TimerTable = undefined;

    table.init(&epoll);

    try epoll.open();
    defer epoll.close();

    try table.start(.{ .id = 8, .interval_ms = 10 });
    try expect_ready(&epoll, fd_of(&table, 8));
    try testing.expect(table.stop(8));
}

test "id_of maps a descriptor back to its timer" {
    var epoll: sys.Epoll = .closed;
    var table: TimerTable = undefined;

    table.init(&epoll);

    try table.start(.{ .id = 4, .interval_ms = 25 });

    var found: ?u32 = null;
    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        if (table.entries[index]) |entry| {
            found = table.id_of(entry.fd);
        }
    }

    try testing.expectEqual(@as(?u32, 4), found);

    _ = table.stop(4);
}

test "a full timer table reports the failed start" {
    var epoll: sys.Epoll = .closed;
    var table: TimerTable = undefined;

    table.init(&epoll);

    var index: u32 = 0;

    while (index < timer_slot_count) : (index += 1) {
        try table.start(.{ .id = index, .interval_ms = 1_000 });
    }

    const overflow = table.start(.{ .id = timer_slot_count, .interval_ms = 1_000 });

    try testing.expectError(error.TimerStartFailed, overflow);

    table.stop_all();
}
