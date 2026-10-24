const std = @import("std");

const contract = @import("../contract.zig");
const sys = @import("sys.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

const CapacityError = contract.CapacityError;
const Listener = contract.Listener;
const PlatformError = contract.PlatformError;
const Watch = contract.Watch;

pub const Hook = *const fn (fd: sys.Fd, add: bool) void;
pub const event_bytes_max: u32 = 4096;
pub const event_count_max: u32 = 256;

const path_bytes_max = contract.path_bytes_max;
const watch_count_max = contract.watch_count_max;

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

var inotify_fd: ?sys.Fd = null;
var entries: [watch_count_max]?Entry = @splat(null);
var hook_installed: ?Hook = null;

pub fn set_hook(hook: ?Hook) void {
    hook_installed = hook;

    if (hook == null) {
        return;
    }

    if (inotify_fd) |fd| {
        hook.?(fd, true);
    }
}

pub fn watch(
    target: []const u8,
    listener: Listener,
    context: *anyopaque,
) (CapacityError || PlatformError)!Watch {
    assert(target.len > 0);
    assert(target.len < path_bytes_max);

    try ensure_open();
    errdefer close_when_idle();

    const fd = inotify_fd orelse return error.WatchAddFailed;
    const slot = find_empty_slot() orelse return error.WatchesExhausted;

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

    entries[slot] = entry;

    assert(entries[slot] != null);

    return @fromBackingInt(slot);
}

pub fn unwatch(handle: Watch) void {
    const slot = @backingInt(handle);

    if (slot >= watch_count_max) {
        return;
    }

    const entry = entries[slot] orelse return;

    entries[slot] = null;

    release(entry.target);
    release(entry.parent);

    if (active_count() == 0) {
        close();
    }

    assert(entries[slot] == null);
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
        const start = offset + @sizeOf(linux.inotify_event);
        const size = @sizeOf(linux.inotify_event) + record.len;

        if (offset + size > count) {
            break;
        }

        const name = std.mem.sliceTo(buffer[start .. offset + size], 0);

        if (notify(record.wd, record.mask, name)) {
            notified += 1;
        }

        offset += size;
    }

    return notified;
}

pub fn stop_all() void {
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        unwatch(@fromBackingInt(index));
    }

    assert(active_count() == 0);
    assert(inotify_fd == null);
}

pub fn active_count() u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        if (entries[index] != null) total += 1;
    }

    assert(total <= watch_count_max);

    return total;
}

fn close_when_idle() void {
    if (active_count() > 0) {
        return;
    }

    close();
}

fn close() void {
    const fd = inotify_fd orelse return;

    if (hook_installed) |hook| {
        hook(fd, false);
    }

    sys.close(fd);

    inotify_fd = null;

    assert(inotify_fd == null);
}

fn ensure_open() PlatformError!void {
    if (inotify_fd != null) {
        return;
    }

    const raw = linux.inotify_init1(linux.IN.CLOEXEC | linux.IN.NONBLOCK);

    if (!sys.ok(raw)) {
        return error.WatchAddFailed;
    }

    inotify_fd = @intCast(raw);

    if (hook_installed) |hook| {
        hook(inotify_fd.?, true);
    }

    assert(inotify_fd != null);
}

fn add(fd: sys.Fd, path: [*:0]const u8, bits: u32) ?i32 {
    const raw = linux.inotify_add_watch(fd, path, bits | linux.IN.MASK_ADD);

    if (!sys.ok(raw)) {
        return null;
    }

    return @intCast(raw);
}

fn add_parent(fd: sys.Fd, target: []const u8) ?i32 {
    const directory = std.Io.Dir.path.dirname(target) orelse return null;

    assert(directory.len < path_bytes_max);

    var path: [path_bytes_max]u8 = undefined;

    @memcpy(path[0..directory.len], directory);

    path[directory.len] = 0;

    return add(fd, @ptrCast(&path), mask_parent);
}

fn is_same(watched: ?i32, wd: i32) bool {
    const value = watched orelse return false;
    return value == wd;
}

fn is_used(wd: i32) bool {
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        const entry = entries[index] orelse continue;
        if (is_same(entry.target, wd)) return true;
        if (is_same(entry.parent, wd)) return true;
    }

    return false;
}

fn notify(wd: i32, bits: u32, name: []const u8) bool {
    var matched = false;
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        const entry = if (entries[index]) |*slot| slot else continue;
        const from_target = is_same(entry.target, wd);
        const from_parent = is_same(entry.parent, wd) and std.mem.eql(u8, entry.get_name(), name);

        if (from_target) {
            if (bits & linux.IN.IGNORED != 0) entry.target = null;
        } else {
            if (!from_parent) continue;
        }

        if (from_parent) {
            rearm(entry);
        } else {
            if (entry.target == null) rearm(entry);
        }

        entry.listener(entry.context);

        matched = true;
    }

    return matched;
}

fn rearm(entry: *Entry) void {
    const fd = inotify_fd orelse return;
    const previous = entry.target;

    entry.target = add(fd, entry.get_path(), mask);

    const stale = previous orelse return;
    if (is_same(entry.target, stale)) return;

    release(stale);
}

fn release(watched: ?i32) void {
    const wd = watched orelse return;
    const fd = inotify_fd orelse return;

    if (is_used(wd)) return;

    _ = linux.inotify_rm_watch(fd, wd);
}

fn find_empty_slot() ?u32 {
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        if (entries[index] == null) return index;
    }

    return null;
}

const testing = std.testing;

fn on_change(context: *anyopaque) void {
    const count: *u32 = @ptrCast(@alignCast(context));

    count.* += 1;
}

fn path_in(directory: *const testing.TmpDir, name: []const u8, buffer: []u8) ![]const u8 {
    var real: [path_bytes_max]u8 = undefined;
    const length = try directory.dir.realPath(testing.io, &real);

    return std.fmt.bufPrint(buffer, "{s}/{s}", .{ real[0..length], name });
}

fn expect_fired(fired: *u32) !void {
    try testing.expect(drain() > 0);
    try testing.expect(fired.* > 0);

    fired.* = 0;
}

test "watch reports a missing path" {
    var fired: u32 = 0;

    try testing.expectError(
        error.WatchAddFailed,
        watch("/nonexistent/umbra/target", on_change, &fired),
    );
}

test "watch registers an existing directory" {
    var fired: u32 = 0;
    const handle = try watch(".", on_change, &fired);

    try testing.expectEqual(@as(u32, 1), active_count());
    try testing.expect(descriptor() != null);

    unwatch(handle);

    try testing.expectEqual(@as(u32, 0), active_count());
}

test "a full watcher refuses another path" {
    var fired: u32 = 0;
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        _ = try watch(".", on_change, &fired);
    }

    try testing.expectError(error.WatchesExhausted, watch(".", on_change, &fired));

    stop_all();
}

test "a replace through a rename and the edit after it both reach the callback" {
    const io = testing.io;
    var fired: u32 = 0;
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();

    var buffer: [path_bytes_max]u8 = undefined;
    const target = try path_in(&directory, "config.zon", &buffer);

    try directory.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "first" });

    const handle = try watch(target, on_change, &fired);
    defer unwatch(handle);

    fired = 0;

    try directory.dir.writeFile(io, .{ .sub_path = "config.zon.swap", .data = "second" });
    try directory.dir.rename("config.zon.swap", directory.dir, "config.zon", io);
    try expect_fired(&fired);

    try directory.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "third" });
    try expect_fired(&fired);

    try directory.dir.writeFile(io, .{ .sub_path = "sibling.zon", .data = "other" });
    try testing.expectEqual(@as(u32, 0), drain());
    try testing.expectEqual(@as(u32, 0), fired);
}

test "a file deleted and created again is still watched" {
    const io = testing.io;
    var fired: u32 = 0;
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();

    var buffer: [path_bytes_max]u8 = undefined;
    const target = try path_in(&directory, "config.zon", &buffer);

    try directory.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "first" });

    const handle = try watch(target, on_change, &fired);
    defer unwatch(handle);

    fired = 0;

    try directory.dir.deleteFile(io, "config.zon");
    try expect_fired(&fired);

    try directory.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "second" });
    try expect_fired(&fired);

    try directory.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "third" });
    try expect_fired(&fired);
}

test "a file moved aside and written anew is still watched" {
    const io = testing.io;
    var fired: u32 = 0;
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();

    var buffer: [path_bytes_max]u8 = undefined;
    const target = try path_in(&directory, "config.zon", &buffer);

    try directory.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "first" });

    const handle = try watch(target, on_change, &fired);
    defer unwatch(handle);

    fired = 0;

    try directory.dir.rename("config.zon", directory.dir, "config.zon~", io);
    try directory.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "second" });
    try expect_fired(&fired);

    try directory.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "third" });
    try expect_fired(&fired);

    try directory.dir.writeFile(io, .{ .sub_path = "config.zon~", .data = "backup" });
    try testing.expectEqual(@as(u32, 0), drain());
    try testing.expectEqual(@as(u32, 0), fired);
}

test "a symlinked file follows edits to its target, in place and replaced" {
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

    const handle = try watch(link, on_change, &fired);
    defer unwatch(handle);

    fired = 0;

    try store.dir.writeFile(io, .{ .sub_path = "target.zon", .data = "second" });
    try expect_fired(&fired);

    try store.dir.writeFile(io, .{ .sub_path = "target.zon.swap", .data = "third" });
    try store.dir.rename("target.zon.swap", store.dir, "target.zon", io);
    try expect_fired(&fired);

    try store.dir.writeFile(io, .{ .sub_path = "target.zon", .data = "fourth" });
    try expect_fired(&fired);
}

test "unwatching one file keeps a second file in the same directory watched" {
    const io = testing.io;
    var fired: u32 = 0;
    var directory = testing.tmpDir(.{});
    defer directory.cleanup();

    var buffer_first: [path_bytes_max]u8 = undefined;
    var buffer_second: [path_bytes_max]u8 = undefined;
    const target_first = try path_in(&directory, "first.zon", &buffer_first);
    const target_second = try path_in(&directory, "second.zon", &buffer_second);

    try directory.dir.writeFile(io, .{ .sub_path = "first.zon", .data = "first" });
    try directory.dir.writeFile(io, .{ .sub_path = "second.zon", .data = "second" });

    const first = try watch(target_first, on_change, &fired);
    const second = try watch(target_second, on_change, &fired);
    defer unwatch(second);

    unwatch(first);

    fired = 0;

    try directory.dir.writeFile(io, .{ .sub_path = "second.zon.swap", .data = "replaced" });
    try directory.dir.rename("second.zon.swap", directory.dir, "second.zon", io);
    try expect_fired(&fired);
}

test "unwatch ignores an out of range handle" {
    unwatch(@fromBackingInt(watch_count_max));
    unwatch(@fromBackingInt(watch_count_max + 1));

    try testing.expectEqual(@as(u32, 0), active_count());
}
