const std = @import("std");

const platform = @import("platform.zig");

const backend = platform.backend.watcher;

const CapacityError = platform.CapacityError;
const PlatformError = platform.PlatformError;
const RequestError = platform.RequestError;
const Watch = platform.Watch;

pub fn watch(
    path: []const u8,
    comptime Owner: type,
    owner: *Owner,
    comptime callback: fn (*Owner) void,
) (CapacityError || PlatformError || RequestError)!Watch {
    if (path.len == 0) return error.PathEmpty;
    if (path.len >= platform.path_bytes_max) return error.PathTooLong;
    if (!platform.is_valid_text(path)) return error.PathInvalid;

    const Listener = ListenerType(Owner, callback);
    return try backend.watch(path, Listener.invoke, owner);
}

pub fn unwatch(handle: Watch) void {
    backend.unwatch(handle);
}

fn ListenerType(comptime Owner: type, comptime callback: fn (*Owner) void) type {
    return struct {
        fn invoke(context: *anyopaque) void {
            const owner: *Owner = @ptrCast(@alignCast(context));

            callback(owner);
        }
    };
}

const testing = std.testing;

const mock = platform.mock;

const Reloader = struct {
    reloads: u32 = 0,

    fn on_change(reloader: *Reloader) void {
        reloader.reloads += 1;
    }
};

test watch {
    mock.reset();

    var reloader = Reloader{};

    const handle = try watch("config.zon", Reloader, &reloader, Reloader.on_change);
    defer unwatch(handle);

    try testing.expect(mock.watcher.fire(handle));
    try testing.expectEqual(@as(u32, 1), reloader.reloads);
    try testing.expectError(error.PathEmpty, watch("", Reloader, &reloader, Reloader.on_change));

    const long: [platform.path_bytes_max]u8 = @splat('a');
    const oversized = watch(&long, Reloader, &reloader, Reloader.on_change);
    const garbled = watch("\xC3\x28", Reloader, &reloader, Reloader.on_change);

    try testing.expectError(error.PathTooLong, oversized);
    try testing.expectError(error.PathInvalid, garbled);
}

test unwatch {
    mock.reset();

    var reloader = Reloader{};

    const handle = try watch("config.zon", Reloader, &reloader, Reloader.on_change);

    unwatch(handle);

    try testing.expect(!mock.watcher.fire(handle));
    try testing.expectEqual(@as(u32, 0), reloader.reloads);
    try testing.expectEqual(@as(u32, 0), mock.watcher.active_count());
}

test "a full watcher refuses another watch" {
    mock.reset();

    var reloader = Reloader{};
    var index: u8 = 0;

    while (index < platform.watch_count_max) : (index += 1) {
        _ = try watch("config.zon", Reloader, &reloader, Reloader.on_change);
    }

    const overflow = watch("config.zon", Reloader, &reloader, Reloader.on_change);

    try testing.expectError(error.WatchesExhausted, overflow);
}
