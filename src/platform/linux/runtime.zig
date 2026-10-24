const std = @import("std");

const client = @import("dbus/client.zig");
const contract = @import("../contract.zig");
const menu = @import("menu.zig");
const timer = @import("timer.zig");
const tray = @import("tray.zig");
const watcher = @import("watcher.zig");
const wire = @import("dbus/wire.zig");

const assert = std.debug.assert;

const Options = contract.RuntimeOptions;
const PlatformError = contract.PlatformError;

const OpenError = error{
    ConnectFailed,
    MatchFailed,
    NameFailed,
};

pub const bus_name_bytes_max: u32 = 128;
pub const instance_id_max: u32 = 32;

pub const watcher_match_rule = "type='signal'," ++
    "interface='org.freedesktop.DBus'," ++
    "member='NameOwnerChanged'," ++
    "arg0='" ++ tray.watcher_name ++ "'";

const app_name_bytes_max = contract.app_name_bytes_max;

const request_name_primary_owner: u32 = 1;
const request_name_in_queue: u32 = 2;
const request_name_exists: u32 = 3;
const request_name_already_owner: u32 = 4;

comptime {
    assert(app_name_bytes_max > 0);
    assert(bus_name_bytes_max > app_name_bytes_max);
    assert(instance_id_max > 0);
    assert(request_name_primary_owner < request_name_in_queue);
    assert(request_name_exists < request_name_already_owner);
    assert(std.mem.find(u8, watcher_match_rule, tray.watcher_name) != null);
}

var opened: bool = false;
var name_storage: [app_name_bytes_max]u8 = undefined;
var name_len: u32 = 0;

pub fn open(options: Options) PlatformError!void {
    assert(!opened);
    assert(options.is_valid());

    connect(options) catch {
        return error.RuntimeOpenFailed;
    };

    opened = true;

    assert(opened);
}

fn connect(options: Options) OpenError!void {
    copy_name(options.name);

    client.connect() catch {
        return OpenError.ConnectFailed;
    };

    errdefer client.disconnect();

    try claim_name();
    try watch_watcher();
}

pub fn close() void {
    if (!opened) {
        return;
    }

    tray.destroy();
    menu.destroy();
    timer.stop_all();
    watcher.stop_all();

    client.disconnect();

    opened = false;

    assert(!opened);
    assert(!tray.is_created());
}

pub fn is_open() bool {
    return opened;
}

pub fn app_name() []const u8 {
    assert(name_len <= app_name_bytes_max);

    return name_storage[0..name_len];
}

fn build_bus_name(buffer: []u8, pid: u32, id: u32) ?[]const u8 {
    const result = std.mem.print(
        buffer,
        "org.kde.StatusNotifierItem-{d}-{d}",
        .{ pid, id },
    ) catch return null;

    return result;
}

fn claim_name() OpenError!void {
    const pid: u32 = @intCast(std.os.linux.getpid());

    var storage: [bus_name_bytes_max]u8 = undefined;
    var instance: u32 = 1;

    while (instance <= instance_id_max) : (instance += 1) {
        const chosen = build_bus_name(&storage, pid, instance) orelse
            return OpenError.NameFailed;

        const code = try request_name(chosen);

        switch (code) {
            request_name_primary_owner, request_name_already_owner => return,
            request_name_exists, request_name_in_queue => {},
            else => return OpenError.NameFailed,
        }
    }

    return OpenError.NameFailed;
}

fn request_name(chosen: []const u8) OpenError!u32 {
    var storage: [256]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    writer.put_string(chosen) catch {
        return OpenError.NameFailed;
    };

    writer.put_u32(0) catch {
        return OpenError.NameFailed;
    };

    const serial = client.next_serial();

    _ = client.send(.{
        .destination = "org.freedesktop.DBus",
        .interface = "org.freedesktop.DBus",
        .kind = .method_call,
        .member = "RequestName",
        .path = "/org/freedesktop/DBus",
        .serial = serial,
        .signature = "su",
    }, writer.bytes()) catch {
        return OpenError.NameFailed;
    };

    const message = client.wait_for_reply(serial) catch {
        return OpenError.NameFailed;
    };

    if (message.header.kind != .method_return) {
        return OpenError.NameFailed;
    }

    var reader = wire.Reader.init(message.body);

    const code = reader.take_u32() catch {
        return OpenError.NameFailed;
    };

    return code;
}

fn watch_watcher() OpenError!void {
    var storage: [256]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    writer.put_string(watcher_match_rule) catch {
        return OpenError.MatchFailed;
    };

    const serial = client.next_serial();

    _ = client.send(.{
        .destination = "org.freedesktop.DBus",
        .interface = "org.freedesktop.DBus",
        .kind = .method_call,
        .member = "AddMatch",
        .path = "/org/freedesktop/DBus",
        .serial = serial,
        .signature = "s",
    }, writer.bytes()) catch {
        return OpenError.MatchFailed;
    };

    const message = client.wait_for_reply(serial) catch {
        return OpenError.MatchFailed;
    };

    if (message.header.kind != .method_return) {
        return OpenError.MatchFailed;
    }
}

fn copy_name(name: []const u8) void {
    assert(name.len <= app_name_bytes_max);

    @memcpy(name_storage[0..name.len], name);

    name_len = @intCast(name.len);

    assert(name_len == name.len);
}

fn reset() void {
    opened = false;
    name_len = 0;

    assert(!opened);
}

const testing = std.testing;

test "build_bus_name follows the status notifier convention" {
    var storage: [bus_name_bytes_max]u8 = undefined;
    const built = build_bus_name(&storage, 4242, 1);

    try testing.expect(built != null);
    try testing.expectEqualStrings("org.kde.StatusNotifierItem-4242-1", built.?);
}

test "build_bus_name reports an undersized buffer" {
    var storage: [4]u8 = undefined;

    try testing.expect(build_bus_name(&storage, 4242, 1) == null);
}

test "app_name is empty before open" {
    reset();

    try testing.expectEqualStrings("", app_name());
}

test "the name storage holds the full application name bound" {
    reset();

    const longest: [app_name_bytes_max]u8 = @splat('a');

    copy_name(&longest);

    try testing.expectEqualStrings(&longest, app_name());

    reset();
}
