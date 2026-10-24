const std = @import("std");

const w32 = @import("../win32.zig");

const contract = @import("../../contract.zig");
const watcher_mod = @import("watcher.zig");
const window = @import("../window.zig");

const assert = std.debug.assert;

const CapacityError = contract.CapacityError;
const Listener = contract.Listener;
const PlatformError = contract.PlatformError;
const Watch = contract.Watch;
const Watcher = watcher_mod.Watcher;

const watch_count_max = contract.watch_count_max;

const change_message_name = std.unicode.utf8ToUtf16LeStringLiteral("UmbraWatcherChanged");

comptime {
    assert(watch_count_max > 0);
}

const Entry = struct {
    context: *anyopaque,
    listener: Listener,
    watcher: Watcher,
};

var entries: [watch_count_max]?Entry = @splat(null);
var change_message: u32 = 0;

const trampolines: [watch_count_max]watcher_mod.Callback = blk: {
    var table: [watch_count_max]watcher_mod.Callback = undefined;
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        table[index] = make_trampoline(index);
    }

    break :blk table;
};

pub fn watch(
    target: []const u8,
    listener: Listener,
    context: *anyopaque,
) (CapacityError || PlatformError)!Watch {
    assert(target.len > 0);
    assert(target.len < contract.path_bytes_max);

    try reap_failed();

    _ = register_change_message();

    const slot = find_empty_slot() orelse return error.WatchesExhausted;

    assert(slot < watch_count_max);

    entries[slot] = .{ .context = context, .listener = listener, .watcher = Watcher.init() };
    errdefer entries[slot] = null;

    entries[slot].?.watcher.watch(target, trampolines[slot]) catch {
        return error.WatchAddFailed;
    };

    assert(entries[slot] != null);

    return @fromBackingInt(slot);
}

pub fn unwatch(handle: Watch) void {
    const slot = @backingInt(handle);

    if (slot >= watch_count_max) {
        return;
    }

    if (entries[slot]) |*live| {
        live.watcher.deinit();
    }

    entries[slot] = null;

    assert(entries[slot] == null);
}

pub fn is_change(message: u32) bool {
    if (change_message == 0) {
        return false;
    }

    return message == change_message;
}

pub fn deliver(slot: u64) void {
    if (slot >= watch_count_max) {
        return;
    }

    const index: u32 = @intCast(slot);

    if (entries[index]) |*live| {
        live.listener(live.context);
    }
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

fn register_change_message() u32 {
    if (change_message != 0) {
        return change_message;
    }

    change_message = w32.RegisterWindowMessageW(change_message_name);

    return change_message;
}

fn post_change(slot: u32) void {
    assert(slot < watch_count_max);

    if (change_message == 0) {
        return;
    }

    _ = window.post(change_message, slot, 0);
}

fn make_trampoline(comptime slot: u32) watcher_mod.Callback {
    const Trampoline = struct {
        fn invoke() void {
            post_change(slot);
        }
    };

    return &Trampoline.invoke;
}

fn reap_failed() PlatformError!void {
    var index: u32 = 0;
    var failed = false;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        if (entries[index]) |*live| {
            if (!live.watcher.has_failed()) {
                continue;
            }

            live.watcher.deinit();

            entries[index] = null;
            failed = true;
        }
    }

    if (failed) {
        return error.WatchAddFailed;
    }
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

test "unwatch ignores an out of range handle" {
    unwatch(@fromBackingInt(watch_count_max));
    unwatch(@fromBackingInt(watch_count_max + 1));

    try testing.expectEqual(@as(u32, 0), active_count());
}

test "every slot gets its own trampoline" {
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        var other: u32 = index + 1;

        while (other < watch_count_max) : (other += 1) {
            try testing.expect(trampolines[index] != trampolines[other]);
        }
    }
}

test "is_change is false before the message is registered" {
    if (change_message != 0) {
        return;
    }

    try testing.expect(!is_change(0));
    try testing.expect(!is_change(0xC000));
}

test "deliver ignores a slot beyond the table" {
    deliver(watch_count_max);
    deliver(watch_count_max + 1);

    try testing.expectEqual(@as(u32, 0), active_count());
}
