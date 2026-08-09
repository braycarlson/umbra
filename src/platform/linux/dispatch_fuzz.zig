const std = @import("std");

const client = @import("dbus/client.zig");
const fuzz = @import("../../testing/fuzz.zig");
const menu = @import("menu.zig");
const tray = @import("tray.zig");
const wire = @import("dbus/wire.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const body_bytes_max: u32 = 512;

const interfaces = [_][]const u8{
    "com.canonical.dbusmenu",
    "org.freedesktop.DBus.Introspectable",
    "org.freedesktop.DBus.Properties",
    "org.kde.StatusNotifierItem",
    "",
};

const members = [_][]const u8{
    "AboutToShow",
    "Activate",
    "ContextMenu",
    "Event",
    "Get",
    "GetAll",
    "GetGroupProperties",
    "GetLayout",
    "Set",
    "Unknown",
    "",
};

comptime {
    assert(body_bytes_max > 0);
    assert(interfaces.len > 1);
    assert(members.len > 1);
}

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        var storage: [body_bytes_max]u8 = undefined;
        const body = build_body(random, &storage);
        const message = build_message(random, body);

        check_menu(message);
        check_tray(message);
    }

    assert(event == args.events_max);
}

fn build_body(random: std.Random, storage: []u8) []const u8 {
    assert(storage.len > 0);

    if (random.boolean()) {
        const filled = fuzz.random_bytes(random, storage);

        return filled;
    }

    var writer = wire.Writer.init(storage);

    const shape = random.uintLessThan(u8, 4);

    if (shape == 0) {
        writer.put_i32(random.int(i32)) catch return writer.bytes();
        writer.put_string("clicked") catch return writer.bytes();

        return writer.bytes();
    }

    if (shape == 1) {
        writer.put_string(tray.interface_name) catch return writer.bytes();
        writer.put_string("IconPixmap") catch return writer.bytes();

        return writer.bytes();
    }

    if (shape == 2) {
        writer.put_string(menu.interface_name) catch return writer.bytes();
        writer.put_string("Version") catch return writer.bytes();

        return writer.bytes();
    }

    writer.put_string(fuzz.random_from_slice(random, []const u8, &interfaces)) catch {
        return writer.bytes();
    };

    return writer.bytes();
}

fn build_message(random: std.Random, body: []const u8) client.Message {
    var header = wire.Header.empty();

    header.body_length = @intCast(body.len);
    header.interface = fuzz.random_from_slice(random, []const u8, &interfaces);
    header.kind = .method_call;
    header.member = fuzz.random_from_slice(random, []const u8, &members);
    header.path = if (random.boolean()) menu.object_path else tray.object_path;
    header.sender = if (random.boolean()) ":1.42" else "";
    header.serial = 1 + random.uintLessThan(u32, 1024);

    return client.Message{ .body = body, .header = header };
}

fn check_menu(message: client.Message) void {
    const outcome = menu.handle_call(message);
    const known = std.mem.eql(u8, message.header.interface, menu.interface_name);

    switch (outcome) {
        .about_to_show, .selected => assert(known),
        .ignored => {},
    }

    if (outcome == .selected) {
        assert(outcome.selected > 0);
    }
}

fn check_tray(message: client.Message) void {
    const outcome = tray.handle_call(message);
    const known = std.mem.eql(u8, message.header.interface, tray.interface_name);

    if (!known) {
        assert(outcome == .ignored);
    }
}

const testing = std.testing;

test "dispatch fuzzer survives a fixed seed" {
    try main(testing.allocator, .{ .events_max = fuzz.events_max_smoke, .seed = 123 });
}

test "hostile property bodies never escape the dispatchers" {
    const hostile = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x01, 0x02 };

    var header = wire.Header.empty();

    header.interface = "org.freedesktop.DBus.Properties";
    header.kind = .method_call;
    header.member = "Get";
    header.path = tray.object_path;
    header.serial = 1;

    const message = client.Message{ .body = &hostile, .header = header };

    check_tray(message);

    header.path = menu.object_path;
    header.member = "Event";

    const second = client.Message{ .body = &hostile, .header = header };

    check_menu(second);

    try testing.expect(!menu.is_built());
}
