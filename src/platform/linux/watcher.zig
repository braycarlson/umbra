const std = @import("std");

const contract = @import("../contract.zig");
const sys = @import("sys.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

pub const Error = contract.WatcherError;

pub const Callback = contract.WatchCallback;
pub const Handle = u32;

pub const handle_max: u32 = 8;
pub const path_bytes_max: u32 = contract.path_bytes_max;
pub const event_bytes_max: u32 = 4096;
pub const event_count_max: u32 = 256;

pub const Watch = *const fn (fd: sys.Fd, add: bool) void;

const mask: u32 = linux.IN.CLOSE_WRITE | linux.IN.MODIFY | linux.IN.MOVED_TO |
    linux.IN.CREATE | linux.IN.DELETE;

comptime {
    assert(handle_max > 0);
    assert(path_bytes_max > 0);
    assert(event_bytes_max >= 256);
    assert(event_count_max > 0);
}

const Entry = struct {
    callback: Callback,
    context: ?*anyopaque,
    descriptor: i32,
};

var inotify_fd: ?sys.Fd = null;
var entries: [handle_max]?Entry = [_]?Entry{null} ** handle_max;
var watch_hook: ?Watch = null;

pub fn set_watch(hook: ?Watch) void {
    watch_hook = hook;

    if (hook == null) {
        return;
    }

    if (inotify_fd) |fd| {
        hook.?(fd, true);
    }
}

pub fn watch(target: []const u8, callback: Callback, context: ?*anyopaque) Error!Handle {
    if (target.len == 0 or target.len >= path_bytes_max) {
        return Error.InvalidPath;
    }

    try ensure_open();
    errdefer close_when_idle();

    const fd = inotify_fd orelse return Error.WatchFailed;
    const slot = find_empty_slot() orelse return Error.CapacityExceeded;

    assert(slot < handle_max);

    var path: [path_bytes_max]u8 = undefined;

    @memcpy(path[0..target.len], target);

    path[target.len] = 0;

    const pointer: [*:0]const u8 = @ptrCast(&path);
    const raw = linux.inotify_add_watch(fd, pointer, mask);

    if (!sys.ok(raw)) {
        return Error.WatchFailed;
    }

    entries[slot] = .{ .callback = callback, .context = context, .descriptor = @intCast(raw) };

    assert(entries[slot] != null);

    return slot;
}

pub fn unwatch(handle: Handle) void {
    if (handle >= handle_max) {
        return;
    }

    const entry = entries[handle] orelse return;

    if (inotify_fd) |fd| {
        _ = linux.inotify_rm_watch(fd, entry.descriptor);
    }

    entries[handle] = null;

    if (active_count() == 0) {
        close();
    }

    assert(entries[handle] == null);
}

pub fn descriptor() ?sys.Fd {
    return inotify_fd;
}

pub fn drain() u32 {
    const fd = inotify_fd orelse return 0;

    var buffer: [event_bytes_max]u8 align(@alignOf(linux.inotify_event)) = undefined;

    const count = sys.read(fd, &buffer) catch {
        return 0;
    };

    var offset: u32 = 0;
    var notified: u32 = 0;
    var visited: u32 = 0;

    while (offset + @sizeOf(linux.inotify_event) <= count) : (visited += 1) {
        if (visited >= event_count_max) {
            break;
        }

        const record: *const linux.inotify_event = @ptrCast(@alignCast(&buffer[offset]));
        const size = @sizeOf(linux.inotify_event) + record.len;

        if (notify(record.wd)) {
            notified += 1;
        }

        offset += size;
    }

    return notified;
}

pub fn stop_all() void {
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

        unwatch(index);
    }

    assert(active_count() == 0);
    assert(inotify_fd == null);
}

pub fn active_count() u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

        if (entries[index] != null) total += 1;
    }

    assert(total <= handle_max);

    return total;
}

fn close_when_idle() void {
    if (active_count() > 0) {
        return;
    }

    close();
}

pub fn close() void {
    const fd = inotify_fd orelse return;

    if (watch_hook) |hook| {
        hook(fd, false);
    }

    sys.close(fd);

    inotify_fd = null;

    assert(inotify_fd == null);
}

fn ensure_open() Error!void {
    if (inotify_fd != null) {
        return;
    }

    const raw = linux.inotify_init1(linux.IN.CLOEXEC | linux.IN.NONBLOCK);

    if (!sys.ok(raw)) {
        return Error.WatchFailed;
    }

    inotify_fd = @intCast(raw);

    if (watch_hook) |hook| {
        hook(inotify_fd.?, true);
    }

    assert(inotify_fd != null);
}

fn notify(wd: i32) bool {
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

        if (entries[index]) |entry| {
            if (entry.descriptor == wd) {
                entry.callback(entry.context);

                return true;
            }
        }
    }

    return false;
}

fn find_empty_slot() ?Handle {
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

        if (entries[index] == null) return index;
    }

    return null;
}

const testing = std.testing;

var fired: u32 = 0;

fn on_change(_: ?*anyopaque) void {
    fired += 1;
}

test "watch rejects an empty path" {
    try testing.expectError(Error.InvalidPath, watch("", on_change, null));
}

test "watch rejects an oversized path" {
    const long = [_]u8{'a'} ** path_bytes_max;

    try testing.expectError(Error.InvalidPath, watch(&long, on_change, null));
}

test "watch reports a missing path" {
    try testing.expectError(
        Error.WatchFailed,
        watch("/nonexistent/wisp/target", on_change, null),
    );
}

test "watch registers an existing directory" {
    const handle = try watch(".", on_change, null);

    try testing.expectEqual(@as(u32, 1), active_count());
    try testing.expect(descriptor() != null);

    unwatch(handle);

    try testing.expectEqual(@as(u32, 0), active_count());
}

test "unwatch ignores an out of range handle" {
    unwatch(handle_max);
    unwatch(handle_max + 1);

    try testing.expectEqual(@as(u32, 0), active_count());
}
