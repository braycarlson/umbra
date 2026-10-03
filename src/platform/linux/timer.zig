const std = @import("std");

const contract = @import("../contract.zig");
const sys = @import("sys.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

pub const Error = contract.TimerError;

pub const timer_max: u32 = 16;

pub const Watch = *const fn (fd: sys.Fd, add: bool) void;

comptime {
    assert(timer_max > 0);
}

const Entry = struct {
    fd: sys.Fd,
    id: u32,
    interval_ms: u32,
};

var entries: [timer_max]?Entry = @splat(null);
var watch_hook: ?Watch = null;

pub fn set_watch(hook: ?Watch) void {
    watch_hook = hook;

    if (hook == null) {
        return;
    }

    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

        if (entries[index]) |entry| {
            hook.?(entry.fd, true);
        }
    }
}

pub fn start(id: u32, interval_ms: u32) Error!void {
    if (interval_ms == 0) {
        return Error.InvalidInterval;
    }

    if (find_index(id) != null) {
        return Error.DuplicateId;
    }

    const slot = find_empty_slot() orelse return Error.CapacityExceeded;

    assert(slot < timer_max);

    const raw = linux.timerfd_create(.MONOTONIC, .{ .CLOEXEC = true, .NONBLOCK = true });

    if (!sys.ok(raw)) {
        return Error.StartFailed;
    }

    const fd: sys.Fd = @intCast(raw);
    errdefer sys.close(fd);

    const seconds: isize = @intCast(interval_ms / 1_000);
    const nanoseconds: isize = @intCast((interval_ms % 1_000) * 1_000_000);

    const spec = linux.itimerspec{
        .it_interval = .{ .sec = seconds, .nsec = nanoseconds },
        .it_value = .{ .sec = seconds, .nsec = nanoseconds },
    };

    const status = linux.timerfd_settime(fd, .{}, &spec, null);

    if (!sys.ok(status)) {
        return Error.StartFailed;
    }

    entries[slot] = .{ .fd = fd, .id = id, .interval_ms = interval_ms };

    if (watch_hook) |hook| {
        hook(fd, true);
    }

    assert(entries[slot] != null);
}

pub fn stop(id: u32) bool {
    const index = find_index(id) orelse return false;

    assert(index < timer_max);

    const entry = entries[index].?;

    if (watch_hook) |hook| {
        hook(entry.fd, false);
    }

    sys.close(entry.fd);

    entries[index] = null;

    assert(entries[index] == null);

    return true;
}

pub fn stop_all() void {
    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

        if (entries[index]) |entry| {
            if (watch_hook) |hook| {
                hook(entry.fd, false);
            }

            sys.close(entry.fd);

            entries[index] = null;
        }
    }

    assert(active_count() == 0);
}

pub fn id_of(fd: sys.Fd) ?u32 {
    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        assert(index < timer_max);

        if (entries[index]) |entry| {
            if (entry.fd == fd) return entry.id;
        }
    }

    return null;
}

pub fn drain(fd: sys.Fd) u64 {
    var expirations: [8]u8 = undefined;

    const count = sys.read(fd, &expirations) catch {
        return 0;
    };

    if (count < expirations.len) {
        return 0;
    }

    return std.mem.readInt(u64, &expirations, .little);
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

        if (entries[index]) |entry| {
            if (entry.id == id) return index;
        }
    }

    return null;
}

const testing = std.testing;

var watched: u32 = 0;
var unwatched: u32 = 0;

fn count_watch(_: sys.Fd, add: bool) void {
    if (add) {
        watched += 1;

        return;
    }

    unwatched += 1;
}

test "start rejects a zero interval" {
    stop_all();

    try testing.expectError(Error.InvalidInterval, start(1, 0));
}

test "start and stop drive a real timerfd" {
    stop_all();
    set_watch(null);

    try start(1, 10);

    try testing.expect(is_running(1));
    try testing.expectEqual(@as(u32, 1), active_count());
    try testing.expect(stop(1));
    try testing.expect(!stop(1));
    try testing.expectEqual(@as(u32, 0), active_count());
}

test "start rejects a duplicate id" {
    stop_all();
    set_watch(null);

    try start(1, 10);

    try testing.expectError(Error.DuplicateId, start(1, 20));

    _ = stop(1);
}

test "set_watch adopts timers registered before the loop" {
    stop_all();
    set_watch(null);

    watched = 0;
    unwatched = 0;

    try start(7, 10);

    try testing.expectEqual(@as(u32, 0), watched);

    set_watch(count_watch);

    try testing.expectEqual(@as(u32, 1), watched);

    _ = stop(7);

    try testing.expectEqual(@as(u32, 1), unwatched);

    set_watch(null);
}

test "set_watch registers timers started after the loop" {
    stop_all();

    watched = 0;
    unwatched = 0;

    set_watch(count_watch);

    try start(8, 10);

    try testing.expectEqual(@as(u32, 1), watched);

    _ = stop(8);

    set_watch(null);
}

test "id_of maps a descriptor back to its timer" {
    stop_all();
    set_watch(null);

    try start(4, 25);

    var found: ?u32 = null;
    var index: u32 = 0;

    while (index < timer_max) : (index += 1) {
        if (entries[index]) |entry| {
            found = id_of(entry.fd);
        }
    }

    try testing.expectEqual(@as(?u32, 4), found);

    _ = stop(4);
}
