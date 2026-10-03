const std = @import("std");

const contract = @import("../contract.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

pub const Error = contract.WatcherError;

pub const Callback = contract.WatchCallback;
pub const Handle = u32;

pub const handle_max: u32 = 8;
pub const path_bytes_max: u32 = contract.path_bytes_max;

comptime {
    assert(handle_max > 0);
    assert(path_bytes_max > 0);
    assert(path_bytes_max <= record.text_bytes_max);
}

const Entry = struct {
    callback: Callback,
    context: ?*anyopaque,
    path: record.Text,
};

var entries: [handle_max]?Entry = @splat(null);
var watch_count: u32 = 0;
var unwatch_count: u32 = 0;
var fail_watch: bool = false;

pub fn watch(path: []const u8, callback: Callback, context: ?*anyopaque) Error!Handle {
    if (path.len == 0 or path.len >= path_bytes_max) {
        return Error.InvalidPath;
    }

    if (fail_watch) {
        return Error.WatchFailed;
    }

    const slot = find_empty_slot() orelse return Error.CapacityExceeded;

    assert(slot < handle_max);

    entries[slot] = .{ .callback = callback, .context = context, .path = record.Text.empty() };
    entries[slot].?.path.set(path);

    watch_count += 1;

    assert(entries[slot] != null);

    return slot;
}

pub fn unwatch(handle: Handle) void {
    if (handle >= handle_max) {
        return;
    }

    if (entries[handle] == null) {
        return;
    }

    entries[handle] = null;
    unwatch_count += 1;

    assert(entries[handle] == null);
}

pub fn fire(handle: Handle) bool {
    if (handle >= handle_max) {
        return false;
    }

    const entry = entries[handle] orelse return false;

    entry.callback(entry.context);

    return true;
}

pub fn path_of(handle: Handle) []const u8 {
    if (handle >= handle_max) {
        return "";
    }

    if (entries[handle]) |*entry| {
        return entry.path.get();
    }

    return "";
}

pub fn stop_all() void {
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

        unwatch(index);
    }

    assert(active_count() == 0);
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

pub fn counts() struct { unwatched: u32, watched: u32 } {
    return .{ .unwatched = unwatch_count, .watched = watch_count };
}

pub fn set_fail_watch(fail: bool) void {
    fail_watch = fail;

    assert(fail_watch == fail);
}

pub fn reset() void {
    entries = @splat(null);
    watch_count = 0;
    unwatch_count = 0;
    fail_watch = false;

    assert(active_count() == 0);
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

test "watch registers the path" {
    reset();

    const handle = try watch("config.json", on_change, null);

    try testing.expectEqualStrings("config.json", path_of(handle));
    try testing.expectEqual(@as(u32, 1), active_count());
}

test "watch rejects an empty path" {
    reset();

    try testing.expectError(Error.InvalidPath, watch("", on_change, null));
}

test "watch rejects an oversized path" {
    reset();

    const long: [path_bytes_max]u8 = @splat('a');

    try testing.expectError(Error.InvalidPath, watch(&long, on_change, null));
}

test "watch honors the injected failure" {
    reset();
    set_fail_watch(true);

    try testing.expectError(Error.WatchFailed, watch("config.json", on_change, null));
}

test "fire invokes the registered callback" {
    reset();

    fired = 0;

    const handle = try watch("config.json", on_change, null);

    try testing.expect(fire(handle));
    try testing.expectEqual(@as(u32, 1), fired);
}

test "unwatch releases the slot" {
    reset();

    const handle = try watch("config.json", on_change, null);

    unwatch(handle);

    try testing.expectEqual(@as(u32, 0), active_count());
    try testing.expect(!fire(handle));
}
