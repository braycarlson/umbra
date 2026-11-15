const std = @import("std");

const interface = @import("../interface.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

const CapacityError = interface.CapacityError;
const Listener = interface.Listener;
const Watch = interface.Watch;

const watch_count_max = interface.watch_count_max;

const Watcher = @This();

entries: [watch_count_max]?Entry,
unwatch_count: u32,
watch_count: u32,

const Entry = struct {
    context: *anyopaque,
    listener: Listener,
    path: record.Text,
};

comptime {
    assert(interface.path_bytes_max <= record.text_bytes_max);
}

pub fn init(watcher: *Watcher) void {
    watcher.* = .{ .entries = @splat(null), .unwatch_count = 0, .watch_count = 0 };

    assert(watcher.active_count() == 0);
}

pub fn watch(
    watcher: *Watcher,
    path: []const u8,
    listener: Listener,
    context: *anyopaque,
) CapacityError!Watch {
    assert(path.len > 0);
    assert(path.len < interface.path_bytes_max);

    const slot = watcher.find_empty_slot() orelse return error.WatchesExhausted;

    watcher.entries[slot] = .{
        .context = context,
        .listener = listener,
        .path = record.Text.empty(),
    };

    watcher.entries[slot].?.path.set(path);

    watcher.watch_count += 1;

    return @fromBackingInt(slot);
}

pub fn unwatch(watcher: *Watcher, handle: Watch) void {
    assert(@backingInt(handle) < watch_count_max);

    const slot = @backingInt(handle);

    if (watcher.entries[slot] == null) {
        return;
    }

    watcher.entries[slot] = null;
    watcher.unwatch_count += 1;

    assert(watcher.entries[slot] == null);
}

pub fn fire(watcher: *const Watcher, handle: Watch) bool {
    assert(@backingInt(handle) < watch_count_max);

    const entry = watcher.entries[@backingInt(handle)] orelse return false;

    entry.listener(entry.context);

    return true;
}

pub fn path_of(watcher: *const Watcher, handle: Watch) []const u8 {
    assert(@backingInt(handle) < watch_count_max);

    if (watcher.entries[@backingInt(handle)]) |*entry| {
        return entry.path.get();
    }

    return "";
}

pub fn stop_all(watcher: *Watcher) void {
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        watcher.unwatch(@fromBackingInt(index));
    }

    assert(watcher.active_count() == 0);
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

pub fn counts(watcher: *const Watcher) struct { unwatched: u32, watched: u32 } {
    return .{ .unwatched = watcher.unwatch_count, .watched = watcher.watch_count };
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
    const fired: *u32 = @ptrCast(@alignCast(context));

    fired.* += 1;
}

test "watch registers the path and fire reaches the listener" {
    var watcher: Watcher = undefined;
    var fired: u32 = 0;

    watcher.init();

    const handle = try watcher.watch("config.json", on_change, &fired);

    try testing.expectEqualStrings("config.json", watcher.path_of(handle));
    try testing.expect(watcher.fire(handle));
    try testing.expectEqual(@as(u32, 1), fired);
}

test "unwatch releases the slot" {
    var watcher: Watcher = undefined;
    var fired: u32 = 0;

    watcher.init();

    const handle = try watcher.watch("config.json", on_change, &fired);

    watcher.unwatch(handle);

    try testing.expectEqual(@as(u32, 0), watcher.active_count());
    try testing.expect(!watcher.fire(handle));
}
