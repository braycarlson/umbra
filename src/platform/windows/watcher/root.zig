const std = @import("std");

const w32 = @import("../win32.zig");

const contract = @import("../../contract.zig");
const watcher_mod = @import("watcher.zig");
const window = @import("../window.zig");

const assert = std.debug.assert;

const Watcher = watcher_mod.Watcher;

pub const Callback = contract.WatchCallback;
pub const Handle = u32;

pub const Error = contract.WatcherError;

pub const handle_max: u32 = 4;

const change_message_name = std.unicode.utf8ToUtf16LeStringLiteral("UmbraWatcherChanged");

comptime {
    assert(handle_max > 0);
}

const Entry = struct {
    callback: Callback,
    context: ?*anyopaque,
    watcher: Watcher,
};

var entries: [handle_max]?Entry = [_]?Entry{null} ** handle_max;
var change_message: u32 = 0;

const trampolines: [handle_max]watcher_mod.Callback = blk: {
    var table: [handle_max]watcher_mod.Callback = undefined;
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        table[index] = make_trampoline(index);
    }

    break :blk table;
};

pub fn watch(target: []const u8, callback: Callback, context: ?*anyopaque) Error!Handle {
    if (target.len == 0) {
        return Error.InvalidPath;
    }

    try reap_failed();

    _ = register_change_message();

    const slot = find_empty_slot() orelse return Error.CapacityExceeded;

    assert(slot < handle_max);

    entries[slot] = .{ .callback = callback, .context = context, .watcher = Watcher.init() };
    errdefer entries[slot] = null;

    entries[slot].?.watcher.watch(target, trampolines[slot]) catch |err| {
        return translate(err);
    };

    assert(entries[slot] != null);

    return slot;
}

fn translate(err: watcher_mod.Error) Error {
    const result = switch (err) {
        watcher_mod.Error.InvalidPath => Error.InvalidPath,
        watcher_mod.Error.AlreadyWatching,
        watcher_mod.Error.DirectoryOpenFailed,
        watcher_mod.Error.EventCreationFailed,
        watcher_mod.Error.ThreadSpawnFailed,
        => Error.WatchFailed,
    };

    return result;
}

pub fn unwatch(handle: Handle) void {
    if (handle >= handle_max) {
        return;
    }

    if (entries[handle]) |*live| {
        live.watcher.deinit();
    }

    entries[handle] = null;

    assert(entries[handle] == null);
}

pub fn is_change(message: u32) bool {
    if (change_message == 0) {
        return false;
    }

    return message == change_message;
}

pub fn deliver(slot: u64) void {
    if (slot >= handle_max) {
        return;
    }

    const index: u32 = @intCast(slot);

    if (entries[index]) |*live| {
        live.callback(live.context);
    }
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

fn register_change_message() u32 {
    if (change_message != 0) {
        return change_message;
    }

    change_message = w32.RegisterWindowMessageW(change_message_name);

    return change_message;
}

fn post_change(slot: u32) void {
    assert(slot < handle_max);

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

fn reap_failed() Error!void {
    var index: u32 = 0;
    var failed = false;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

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
        return Error.WatchFailed;
    }
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

fn on_change(_: ?*anyopaque) void {}

test "watch rejects an empty path" {
    try testing.expectError(Error.InvalidPath, watch("", on_change, null));
}

test "unwatch ignores an out of range handle" {
    unwatch(handle_max);
    unwatch(handle_max + 1);

    try testing.expectEqual(@as(u32, 0), active_count());
}

test "every slot gets its own trampoline" {
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        var other: u32 = index + 1;

        while (other < handle_max) : (other += 1) {
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
    deliver(handle_max);
    deliver(handle_max + 1);

    try testing.expectEqual(@as(u32, 0), active_count());
}
