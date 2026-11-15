const std = @import("std");

const w32 = @import("win32.zig");

const interface = @import("../interface.zig");
const Monitor = @import("watcher/monitor.zig");
const Window = @import("window.zig");

const assert = std.debug.assert;

const CapacityError = interface.CapacityError;
const Listener = interface.Listener;
const PlatformError = interface.PlatformError;
const Watch = interface.Watch;

const watch_count_max = interface.watch_count_max;

const Watcher = @This();

change_message: u32,
entries: [watch_count_max]?Entry,
window: *const Window,

const Entry = struct {
    context: *anyopaque,
    listener: Listener,
    monitor: Monitor,
};

const change_message_name = std.unicode.utf8ToUtf16LeStringLiteral("UmbraWatcherChanged");

comptime {
    assert(watch_count_max > 0);
}

const trampolines: [watch_count_max]Monitor.Callback = blk: {
    var table: [watch_count_max]Monitor.Callback = undefined;
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        table[index] = make_trampoline(index);
    }

    break :blk table;
};

pub fn init(watcher: *Watcher, window: *const Window) void {
    watcher.* = .{ .change_message = 0, .entries = @splat(null), .window = window };

    assert(watcher.active_count() == 0);
    assert(watcher.window == window);
}

pub fn watch(
    watcher: *Watcher,
    target: []const u8,
    listener: Listener,
    context: *anyopaque,
) (CapacityError || PlatformError)!Watch {
    assert(target.len > 0);
    assert(target.len < interface.path_bytes_max);

    try watcher.reap_failed();

    _ = watcher.register_change_message();

    const slot = watcher.find_empty_slot() orelse return error.WatchesExhausted;

    assert(slot < watch_count_max);

    watcher.entries[slot] = .{
        .context = context,
        .listener = listener,
        .monitor = Monitor.init(),
    };

    errdefer watcher.entries[slot] = null;

    watcher.entries[slot].?.monitor.watch(target, trampolines[slot], watcher) catch {
        return error.WatchAddFailed;
    };

    assert(watcher.entries[slot] != null);

    return @fromBackingInt(slot);
}

pub fn unwatch(watcher: *Watcher, handle: Watch) void {
    assert(@backingInt(handle) < watch_count_max);

    const slot = @backingInt(handle);

    if (watcher.entries[slot]) |*live| {
        live.monitor.deinit();
    }

    watcher.entries[slot] = null;

    assert(watcher.entries[slot] == null);
}

pub fn is_change(watcher: *const Watcher, message: u32) bool {
    if (watcher.change_message == 0) {
        return false;
    }

    return message == watcher.change_message;
}

pub fn deliver(watcher: *const Watcher, slot: u64) bool {
    if (slot >= watch_count_max) {
        return false;
    }

    const index: u32 = @intCast(slot);

    if (watcher.entries[index]) |*live| {
        live.listener(live.context);

        return true;
    }

    return false;
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

fn register_change_message(watcher: *Watcher) u32 {
    if (watcher.change_message != 0) {
        return watcher.change_message;
    }

    watcher.change_message = w32.RegisterWindowMessageW(change_message_name);

    return watcher.change_message;
}

fn post_change(watcher: *const Watcher, slot: u32) void {
    assert(slot < watch_count_max);

    if (watcher.change_message == 0) {
        return;
    }

    _ = watcher.window.post(watcher.change_message, slot, 0);
}

fn make_trampoline(comptime slot: u32) Monitor.Callback {
    comptime assert(slot < watch_count_max);

    const Trampoline = struct {
        fn invoke(context: *anyopaque) void {
            const watcher: *const Watcher = @ptrCast(@alignCast(context));

            watcher.post_change(slot);
        }
    };

    return &Trampoline.invoke;
}

fn reap_failed(watcher: *Watcher) PlatformError!void {
    var index: u32 = 0;
    var failed = false;

    while (index < watch_count_max) : (index += 1) {
        assert(index < watch_count_max);

        if (watcher.entries[index]) |*live| {
            if (!live.monitor.has_failed()) {
                continue;
            }

            live.monitor.deinit();

            watcher.entries[index] = null;
            failed = true;
        }
    }

    if (failed) {
        return error.WatchAddFailed;
    }
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

test "every slot gets its own trampoline" {
    var index: u32 = 0;

    while (index < watch_count_max) : (index += 1) {
        var other: u32 = index + 1;

        while (other < watch_count_max) : (other += 1) {
            try testing.expect(trampolines[index] != trampolines[other]);
        }
    }
}

test "deliver ignores a slot beyond the table" {
    const window: Window = .closed;

    var watcher: Watcher = undefined;

    watcher.init(&window);

    try testing.expect(!watcher.deliver(watch_count_max));
    try testing.expect(!watcher.deliver(watch_count_max + 1));

    try testing.expectEqual(@as(u32, 0), watcher.active_count());
}

test "is_change is false before the message is registered" {
    const window: Window = .closed;

    var watcher: Watcher = undefined;

    watcher.init(&window);

    try testing.expect(!watcher.is_change(0));
    try testing.expect(!watcher.is_change(0xC000));
}
