const std = @import("std");

const interface = @import("../interface.zig");
const sys = @import("sys.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

const CapacityError = interface.CapacityError;
const Listener = interface.Listener;
const PlatformError = interface.PlatformError;
const Watch = interface.Watch;

const Watcher = @This();

entries: [watch_count_max]?Entry,
epoll: *const sys.Epoll,
inotify_fd: ?sys.Fd,

const Entry = struct {
    context: *anyopaque,
    listener: Listener,
    parent: ?i32,
    path: [path_bytes_max]u8,
    path_length: u32,
    target: ?i32,

    fn get_name(entry: *const Entry) []const u8 {
        assert(entry.path_length > 0);
        assert(entry.path_length < path_bytes_max);

        return std.Io.Dir.path.basename(entry.path[0..entry.path_length]);
    }

    fn get_path(entry: *const Entry) [*:0]const u8 {
        assert(entry.path_length < path_bytes_max);
        assert(entry.path[entry.path_length] == 0);

        return @ptrCast(&entry.path);
    }
};

pub const event_bytes_max: u32 = 4096;
pub const event_count_max: u32 = 256;

const path_bytes_max = interface.path_bytes_max;
const watch_count_max = interface.watch_count_max;

const mask: u32 = linux.IN.CLOSE_WRITE | linux.IN.MODIFY | linux.IN.MOVED_TO |
    linux.IN.CREATE | linux.IN.DELETE;

const mask_parent: u32 = linux.IN.CREATE | linux.IN.MOVED_TO;

comptime {
    assert(watch_count_max > 0);
    assert(path_bytes_max > 0);
    assert(event_bytes_max >= 256);
    assert(event_count_max > 0);
    assert(mask & mask_parent == mask_parent);
}

pub fn init(watcher: *Watcher, epoll: *const sys.Epoll) void {
    watcher.* = .{ .entries = @splat(null), .epoll = epoll, .inotify_fd = null };

    assert(watcher.active_count() == 0);
    assert(watcher.epoll == epoll);
}

pub fn adopt(watcher: *const Watcher) void {
    assert(watcher.epoll.fd != null);

    if (watcher.inotify_fd) |fd| {
        watcher.epoll.register(fd, true);
    }
}

pub fn watch(
    watcher: *Watcher,
    target: []const u8,
    listener: Listener,
    context: *anyopaque,
) (CapacityError || PlatformError)!Watch {
    assert(target.len > 0);
    assert(target.len < path_bytes_max);

    try watcher.ensure_open();
    errdefer watcher.close_when_idle();

    const fd = watcher.inotify_fd orelse return error.WatchAddFailed;
    const slot = watcher.find_empty_slot() orelse return error.WatchesExhausted;

    assert(slot < watch_count_max);

    var entry = Entry{
        .context = context,
        .listener = listener,
        .parent = null,
        .path = undefined,
        .path_length = @intCast(target.len),
        .target = null,
    };

    @memcpy(entry.path[0..target.len], target);

    entry.path[target.len] = 0;
    entry.target = add(fd, entry.get_path(), mask) orelse return error.WatchAddFailed;
    entry.parent = add_parent(fd, target);

    watcher.entries[slot] = entry;

    assert(watcher.entries[slot] != null);

    return @fromBackingInt(slot);
}

pub fn unwatch(watcher: *Watcher, handle: Watch) void {
    assert(@backingInt(handle) < watch_count_max);

    const slot = @backingInt(handle);
    const entry = watcher.entries[slot] orelse return;

    watcher.entries[slot] = null;

    watcher.release(entry.target);
    watcher.release(entry.parent);

    if (watcher.active_count() == 0) {
        watcher.close();
    }

    assert(watcher.entries[slot] == null);
}

pub fn descriptor(watcher: *const Watcher) ?sys.Fd {
    return watcher.inotify_fd;
}

pub fn drain(watcher: *Watcher) u32 {
    const fd = watcher.inotify_fd orelse return 0;

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
        const start = offset + @sizeOf(linux.inotify_event);
        const size = @sizeOf(linux.inotify_event) + record.len;

        if (offset + size > count) {
            break;
        }

        const name = std.mem.sliceTo(buffer[start .. offset + size], 0);

        offset += size;

        if (record.wd < 0) {
            notified += watcher.notify_overflow();

            continue;
        }

        if (watcher.notify(record.wd, record.mask, name)) {
            notified += 1;
        }
    }

    return notified;
}

pub fn stop_all(watcher: *Watcher) void {
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        watcher.unwatch(@fromBackingInt(index));
    }

    assert(watcher.active_count() == 0);
    assert(watcher.inotify_fd == null);
}

pub fn active_count(watcher: *const Watcher) u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        if (watcher.entries[index] != null) total += 1;
    }

    assert(total <= watch_count_max);

    return total;
}

fn close_when_idle(watcher: *Watcher) void {
    if (watcher.active_count() > 0) {
        return;
    }

    watcher.close();
}

fn close(watcher: *Watcher) void {
    const fd = watcher.inotify_fd orelse return;

    watcher.epoll.register(fd, false);

    sys.close(fd);

    watcher.inotify_fd = null;

    assert(watcher.inotify_fd == null);
}

fn ensure_open(watcher: *Watcher) PlatformError!void {
    if (watcher.inotify_fd != null) {
        return;
    }

    const raw = linux.inotify_init1(linux.IN.CLOEXEC | linux.IN.NONBLOCK);

    if (!sys.ok(raw)) {
        return error.WatchAddFailed;
    }

    watcher.inotify_fd = @intCast(raw);

    watcher.epoll.register(watcher.inotify_fd.?, true);

    assert(watcher.inotify_fd != null);
}

fn add(fd: sys.Fd, path: [*:0]const u8, bits: u32) ?i32 {
    assert(fd >= 0);
    assert(path[0] != 0);
    assert(bits != 0);
    assert(bits & linux.IN.MASK_ADD == 0);

    const raw = linux.inotify_add_watch(fd, path, bits | linux.IN.MASK_ADD);

    if (!sys.ok(raw)) {
        return null;
    }

    const result: i32 = @intCast(raw);

    assert(result >= 0);

    return result;
}

fn add_parent(fd: sys.Fd, target: []const u8) ?i32 {
    assert(fd >= 0);
    assert(target.len > 0);
    assert(target.len < path_bytes_max);

    const directory = std.Io.Dir.path.dirname(target) orelse return null;

    assert(directory.len < path_bytes_max);

    var path: [path_bytes_max]u8 = undefined;

    @memcpy(path[0..directory.len], directory);

    path[directory.len] = 0;

    const result = add(fd, @ptrCast(&path), mask_parent);

    if (result) |wd| assert(wd >= 0);

    return result;
}

fn is_same(watched: ?i32, wd: i32) bool {
    if (watched) |value| assert(value >= 0);
    assert(wd >= 0);

    const value = watched orelse return false;
    return value == wd;
}

fn is_used(watcher: *const Watcher, wd: i32) bool {
    assert(wd >= 0);

    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        const entry = watcher.entries[index] orelse continue;
        if (is_same(entry.target, wd)) return true;
        if (is_same(entry.parent, wd)) return true;
    }

    return false;
}

fn notify(watcher: *Watcher, wd: i32, bits: u32, name: []const u8) bool {
    assert(wd >= 0);
    assert(name.len < event_bytes_max);

    var matched = false;
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        const entry = if (watcher.entries[index]) |*slot| slot else continue;
        const from_target = is_same(entry.target, wd);
        const from_parent = is_same(entry.parent, wd) and std.mem.eql(u8, entry.get_name(), name);

        if (from_target) {
            if (bits & linux.IN.IGNORED != 0) entry.target = null;
        } else {
            if (!from_parent) continue;
        }

        if (from_parent) {
            watcher.rearm(entry);
        } else {
            if (entry.target == null) watcher.rearm(entry);
        }

        entry.listener(entry.context);

        matched = true;
    }

    return matched;
}

fn notify_overflow(watcher: *Watcher) u32 {
    var notified: u32 = 0;
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        const entry = if (watcher.entries[index]) |*slot| slot else continue;

        watcher.rearm(entry);
        entry.listener(entry.context);

        notified += 1;
    }

    assert(notified <= watch_count_max);

    return notified;
}

fn rearm(watcher: *const Watcher, entry: *Entry) void {
    const fd = watcher.inotify_fd orelse return;
    const previous = entry.target;

    entry.target = add(fd, entry.get_path(), mask);

    const stale = previous orelse return;
    if (is_same(entry.target, stale)) return;

    watcher.release(stale);
}

fn release(watcher: *const Watcher, watched: ?i32) void {
    if (watched) |wd| assert(wd >= 0);

    const wd = watched orelse return;
    const fd = watcher.inotify_fd orelse return;

    if (watcher.is_used(wd)) return;

    _ = linux.inotify_rm_watch(fd, wd);
}

fn find_empty_slot(watcher: *const Watcher) ?u32 {
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        if (watcher.entries[index] == null) return index;
    }

    return null;
}

const testing = std.testing;

fn on_change(context: *anyopaque) void {
    const count: *u32 = @ptrCast(@alignCast(context));

    count.* += 1;
}

fn path_in(temporary: *const testing.TmpDir, name: []const u8, buffer: []u8) ![]const u8 {
    assert(name.len > 0);
    assert(std.mem.findScalar(u8, name, '/') == null);
    assert(buffer.len > name.len);

    var real: [path_bytes_max]u8 = undefined;
    const length = try temporary.dir.realPath(testing.io, &real);

    return std.mem.print(buffer, "{s}/{s}", .{ real[0..length], name });
}

fn expect_fired(watcher: *Watcher, fired: *u32) !void {
    try testing.expect(watcher.drain() > 0);
    try testing.expect(fired.* > 0);

    fired.* = 0;
}

test "watch reports a missing path" {
    var epoll: sys.Epoll = .closed;
    var watcher: Watcher = undefined;

    watcher.init(&epoll);
    defer watcher.stop_all();

    var fired: u32 = 0;

    try testing.expectError(
        error.WatchAddFailed,
        watcher.watch("/nonexistent/umbra/target", on_change, &fired),
    );
}

test "watch registers an existing directory" {
    var epoll: sys.Epoll = .closed;
    var watcher: Watcher = undefined;

    watcher.init(&epoll);
    defer watcher.stop_all();

    var fired: u32 = 0;
    const handle = try watcher.watch(".", on_change, &fired);

    try testing.expectEqual(@as(u32, 1), watcher.active_count());
    try testing.expect(watcher.descriptor() != null);

    watcher.unwatch(handle);

    try testing.expectEqual(@as(u32, 0), watcher.active_count());
}

test "a full watcher refuses another path" {
    var epoll: sys.Epoll = .closed;
    var watcher: Watcher = undefined;

    watcher.init(&epoll);
    defer watcher.stop_all();

    var fired: u32 = 0;
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        _ = try watcher.watch(".", on_change, &fired);
    }

    try testing.expectError(error.WatchesExhausted, watcher.watch(".", on_change, &fired));

    watcher.stop_all();
}

test "a replace through a rename and the edit after it both reach the callback" {
    var epoll: sys.Epoll = .closed;
    var watcher: Watcher = undefined;

    watcher.init(&epoll);
    defer watcher.stop_all();

    const io = testing.io;
    var fired: u32 = 0;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    var buffer: [path_bytes_max]u8 = undefined;
    const target = try path_in(&temporary, "config.zon", &buffer);

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "first" });

    const handle = try watcher.watch(target, on_change, &fired);
    defer watcher.unwatch(handle);

    fired = 0;

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon.swap", .data = "second" });
    try temporary.dir.rename("config.zon.swap", temporary.dir, "config.zon", io);
    try expect_fired(&watcher, &fired);

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "third" });
    try expect_fired(&watcher, &fired);

    try temporary.dir.writeFile(io, .{ .sub_path = "sibling.zon", .data = "other" });
    try testing.expectEqual(@as(u32, 0), watcher.drain());
    try testing.expectEqual(@as(u32, 0), fired);
}

test "a file deleted and created again is still watched" {
    var epoll: sys.Epoll = .closed;
    var watcher: Watcher = undefined;

    watcher.init(&epoll);
    defer watcher.stop_all();

    const io = testing.io;
    var fired: u32 = 0;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    var buffer: [path_bytes_max]u8 = undefined;
    const target = try path_in(&temporary, "config.zon", &buffer);

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "first" });

    const handle = try watcher.watch(target, on_change, &fired);
    defer watcher.unwatch(handle);

    fired = 0;

    try temporary.dir.deleteFile(io, "config.zon");
    try expect_fired(&watcher, &fired);

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "second" });
    try expect_fired(&watcher, &fired);

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "third" });
    try expect_fired(&watcher, &fired);
}

test "a file moved aside and written anew is still watched" {
    var epoll: sys.Epoll = .closed;
    var watcher: Watcher = undefined;

    watcher.init(&epoll);
    defer watcher.stop_all();

    const io = testing.io;
    var fired: u32 = 0;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    var buffer: [path_bytes_max]u8 = undefined;
    const target = try path_in(&temporary, "config.zon", &buffer);

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "first" });

    const handle = try watcher.watch(target, on_change, &fired);
    defer watcher.unwatch(handle);

    fired = 0;

    try temporary.dir.rename("config.zon", temporary.dir, "config.zon~", io);
    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "second" });
    try expect_fired(&watcher, &fired);

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "third" });
    try expect_fired(&watcher, &fired);

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon~", .data = "backup" });
    try testing.expectEqual(@as(u32, 0), watcher.drain());
    try testing.expectEqual(@as(u32, 0), fired);
}

test "a symlinked file follows edits to its target, in place and replaced" {
    var epoll: sys.Epoll = .closed;
    var watcher: Watcher = undefined;

    watcher.init(&epoll);
    defer watcher.stop_all();

    const io = testing.io;
    var fired: u32 = 0;
    var store = testing.tmpDir(.{});
    defer store.cleanup();

    var links = testing.tmpDir(.{});
    defer links.cleanup();

    var store_buffer: [path_bytes_max]u8 = undefined;
    var link_buffer: [path_bytes_max]u8 = undefined;
    const stored = try path_in(&store, "target.zon", &store_buffer);
    const link = try path_in(&links, "config.zon", &link_buffer);

    try store.dir.writeFile(io, .{ .sub_path = "target.zon", .data = "first" });
    try links.dir.symLink(io, stored, "config.zon", .{});

    const handle = try watcher.watch(link, on_change, &fired);
    defer watcher.unwatch(handle);

    fired = 0;

    try store.dir.writeFile(io, .{ .sub_path = "target.zon", .data = "second" });
    try expect_fired(&watcher, &fired);

    try store.dir.writeFile(io, .{ .sub_path = "target.zon.swap", .data = "third" });
    try store.dir.rename("target.zon.swap", store.dir, "target.zon", io);
    try expect_fired(&watcher, &fired);

    try store.dir.writeFile(io, .{ .sub_path = "target.zon", .data = "fourth" });
    try expect_fired(&watcher, &fired);
}

test "unwatching one file keeps a second file in the same directory watched" {
    var epoll: sys.Epoll = .closed;
    var watcher: Watcher = undefined;

    watcher.init(&epoll);
    defer watcher.stop_all();

    const io = testing.io;
    var fired: u32 = 0;
    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    var buffer_first: [path_bytes_max]u8 = undefined;
    var buffer_second: [path_bytes_max]u8 = undefined;
    const target_first = try path_in(&temporary, "first.zon", &buffer_first);
    const target_second = try path_in(&temporary, "second.zon", &buffer_second);

    try temporary.dir.writeFile(io, .{ .sub_path = "first.zon", .data = "first" });
    try temporary.dir.writeFile(io, .{ .sub_path = "second.zon", .data = "second" });

    const first = try watcher.watch(target_first, on_change, &fired);
    const second = try watcher.watch(target_second, on_change, &fired);
    defer watcher.unwatch(second);

    watcher.unwatch(first);

    fired = 0;

    try temporary.dir.writeFile(io, .{ .sub_path = "second.zon.swap", .data = "replaced" });
    try temporary.dir.rename("second.zon.swap", temporary.dir, "second.zon", io);
    try expect_fired(&watcher, &fired);
}
