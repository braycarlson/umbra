const std = @import("std");

const contract = @import("../contract.zig");
const fault = @import("fault.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

const CapacityError = contract.CapacityError;
const Listener = contract.Listener;
const PlatformError = contract.PlatformError;
const Watch = contract.Watch;

const watch_count_max = contract.watch_count_max;

comptime {
    assert(contract.path_bytes_max <= record.text_bytes_max);
}

const Entry = struct {
    context: *anyopaque,
    listener: Listener,
    path: record.Text,
};

var entries: [watch_count_max]?Entry = @splat(null);
var watch_count: u32 = 0;
var unwatch_count: u32 = 0;

pub fn watch(
    path: []const u8,
    listener: Listener,
    context: *anyopaque,
) (CapacityError || PlatformError)!Watch {
    assert(path.len > 0);
    assert(path.len < contract.path_bytes_max);

    if (fault.is_armed(.watcher_watch)) {
        return error.WatchAddFailed;
    }

    const slot = find_empty_slot() orelse return error.WatchesExhausted;

    entries[slot] = .{ .context = context, .listener = listener, .path = record.Text.empty() };

    entries[slot].?.path.set(path);

    watch_count += 1;

    return @fromBackingInt(slot);
}

pub fn unwatch(handle: Watch) void {
    const slot = @backingInt(handle);

    if (slot >= watch_count_max) {
        return;
    }

    if (entries[slot] == null) {
        return;
    }

    entries[slot] = null;
    unwatch_count += 1;

    assert(entries[slot] == null);
}

pub fn fire(handle: Watch) bool {
    const slot = @backingInt(handle);

    if (slot >= watch_count_max) {
        return false;
    }

    const entry = entries[slot] orelse return false;

    entry.listener(entry.context);

    return true;
}

pub fn path_of(handle: Watch) []const u8 {
    const slot = @backingInt(handle);

    if (slot >= watch_count_max) {
        return "";
    }

    if (entries[slot]) |*entry| {
        return entry.path.get();
    }

    return "";
}

pub fn stop_all() void {
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        unwatch(@fromBackingInt(index));
    }

    assert(active_count() == 0);
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

pub fn counts() struct { unwatched: u32, watched: u32 } {
    return .{ .unwatched = unwatch_count, .watched = watch_count };
}

pub fn reset() void {
    entries = @splat(null);
    watch_count = 0;
    unwatch_count = 0;

    assert(active_count() == 0);
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
    const fired: *u32 = @ptrCast(@alignCast(context));

    fired.* += 1;
}

test "watch registers the path and fire reaches the listener" {
    reset();

    var fired: u32 = 0;

    const handle = try watch("config.json", on_change, &fired);

    try testing.expectEqualStrings("config.json", path_of(handle));
    try testing.expect(fire(handle));
    try testing.expectEqual(@as(u32, 1), fired);
}

test "watch honors the injected failure" {
    reset();
    fault.reset();
    fault.arm(.watcher_watch);
    defer fault.reset();

    var fired: u32 = 0;

    try testing.expectError(error.WatchAddFailed, watch("config.json", on_change, &fired));
}

test "unwatch releases the slot" {
    reset();

    var fired: u32 = 0;

    const handle = try watch("config.json", on_change, &fired);

    unwatch(handle);

    try testing.expectEqual(@as(u32, 0), active_count());
    try testing.expect(!fire(handle));
}
