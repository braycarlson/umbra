const std = @import("std");

const Client = @import("dbus/client.zig");
const fuzz = @import("../../testing/fuzz.zig");
const IconTable = @import("icon_table.zig");
const interface = @import("../interface.zig");
const Menu = @import("menu.zig");
const Tray = @import("tray.zig");
const wire = @import("dbus/wire.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

pub const body_bytes_max: u32 = 512;

const menu_rebuild_odds: u32 = 64;

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
    "ProvideXdgActivationToken",
    "Set",
    "Unknown",
    "",
};

comptime {
    assert(body_bytes_max > 0);
    assert(menu_rebuild_odds > 1);
    assert(interfaces.len > 1);
    assert(members.len > 1);
}

const Dispatchers = struct {
    client: Client,
    icons: IconTable,
    menu: Menu,
    tray: Tray,

    fn init(dispatchers: *Dispatchers) void {
        dispatchers.client.init();
        dispatchers.icons.init();
        dispatchers.menu.init(&dispatchers.client);
        dispatchers.tray.init(&dispatchers.client, &dispatchers.icons, "umbra");

        assert(!dispatchers.client.is_connected());
        assert(dispatchers.menu.item_count() == 0);
    }
};

pub fn main(gpa: Allocator, args: fuzz.Arguments) !void {
    assert(args.events_max >= 1);

    const dispatchers = try gpa.create(Dispatchers);
    defer gpa.destroy(dispatchers);

    dispatchers.init();

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();
    const menu = &dispatchers.menu;
    const tray = &dispatchers.tray;

    try build_menu(menu, random);
    defer menu.destroy();

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        if (random.uintLessThan(u32, menu_rebuild_odds) == 0) try build_menu(menu, random);

        var storage: [body_bytes_max]u8 = undefined;
        const body = build_body(random, &storage);
        const message = build_message(random, body);

        check_menu(menu, message);
        check_tray(tray, message);
    }

    assert(event == args.events_max);
}

fn build_menu(menu: *Menu, random: std.Random) interface.PlatformError!void {
    var items: [interface.menu_item_count_max]interface.MenuItem = undefined;
    const count = random.uintAtMost(u32, interface.menu_item_count_max);
    var depth_next_max: u8 = 0;

    for (items[0..count], 0..) |*item, index| {
        const depth = random.uintAtMost(u8, depth_next_max);
        const kind = random_kind(random, depth);

        item.* = .{
            .checked = random.boolean(),
            .depth = depth,
            .enabled = random.boolean(),
            .id = @intCast(index + 1),
            .kind = kind,
            .label = "Item",
        };

        depth_next_max = if (kind == .submenu) depth + 1 else depth;
    }

    assert(interface.is_valid_layout(items[0..count]));

    try menu.build(items[0..count]);
}

fn random_id(random: std.Random) i32 {
    if (random.boolean()) return random.int(i32);

    const result = random.intRangeAtMost(i32, -1, interface.menu_item_count_max + 1);

    assert(result >= -1);
    assert(result <= interface.menu_item_count_max + 1);

    return result;
}

fn random_kind(random: std.Random, depth: u8) interface.MenuItemKind {
    assert(depth <= interface.menu_depth_max);

    const result = random.enumValueWithIndex(interface.MenuItemKind, u32);

    if (result == .submenu) {
        if (depth == interface.menu_depth_max) return .action;
    }

    return result;
}

fn build_body(random: std.Random, storage: []u8) []const u8 {
    assert(storage.len > 0);

    if (random.boolean()) {
        const filled = fuzz.random_bytes(random, storage);
        return filled;
    }

    var writer = wire.Writer.init(storage);

    const shape = random.uintLessThan(u8, 5);

    if (shape == 0) {
        writer.put_i32(random_id(random)) catch return writer.bytes();
        writer.put_string("clicked") catch return writer.bytes();

        return writer.bytes();
    }

    if (shape == 3) {
        const recursion = random.intRangeAtMost(i32, -2, interface.menu_depth_max + 1);

        writer.put_i32(random_id(random)) catch return writer.bytes();
        writer.put_i32(recursion) catch return writer.bytes();

        return writer.bytes();
    }

    if (shape == 1) {
        writer.put_string(Tray.interface_name) catch return writer.bytes();
        writer.put_string("IconPixmap") catch return writer.bytes();

        return writer.bytes();
    }

    if (shape == 2) {
        writer.put_string(Menu.interface_name) catch return writer.bytes();
        writer.put_string("Version") catch return writer.bytes();

        return writer.bytes();
    }

    writer.put_string(fuzz.random_from_slice(random, []const u8, &interfaces)) catch {
        return writer.bytes();
    };

    return writer.bytes();
}

fn build_message(random: std.Random, body: []const u8) Client.Message {
    assert(body.len <= body_bytes_max);

    var header = wire.Header.empty();

    header.body_length = @intCast(body.len);
    header.interface = fuzz.random_from_slice(random, []const u8, &interfaces);
    header.kind = .method_call;
    header.member = fuzz.random_from_slice(random, []const u8, &members);
    header.path = if (random.boolean()) Menu.object_path else Tray.object_path;
    header.sender = if (random.boolean()) ":1.42" else "";
    header.serial = 1 + random.uintLessThan(u32, 1024);

    return Client.Message{ .body = body, .header = header };
}

fn check_menu(menu: *Menu, message: Client.Message) void {
    assert(message.header.kind == .method_call);
    assert(message.body.len <= body_bytes_max);

    const outcome = menu.handle_call(message);
    const known = std.mem.eql(u8, message.header.interface, Menu.interface_name);

    switch (outcome) {
        .about_to_show, .selected => assert(known),
        .ignored => {},
    }

    if (outcome == .selected) {
        assert(outcome.selected > 0);
    }
}

fn check_tray(tray: *Tray, message: Client.Message) void {
    assert(message.header.kind == .method_call);
    assert(message.body.len <= body_bytes_max);

    const outcome = tray.handle_call(message);
    const known = std.mem.eql(u8, message.header.interface, Tray.interface_name);

    if (!known) {
        assert(outcome == .ignored);
    }

    const token = tray.activation_token();

    assert(token.len <= interface.activation_token_bytes_max);
    assert(interface.is_valid_text(token));
}

const testing = std.testing;

test "dispatch fuzzer survives a fixed seed" {
    try main(testing.allocator, .{ .events_max = fuzz.events_max_smoke, .seed = 123 });
}

test "hostile property bodies never escape the dispatchers" {
    const dispatchers = try testing.allocator.create(Dispatchers);
    defer testing.allocator.destroy(dispatchers);

    dispatchers.init();

    const hostile = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x01, 0x02 };

    var header = wire.Header.empty();

    header.interface = "org.freedesktop.DBus.Properties";
    header.kind = .method_call;
    header.member = "Get";
    header.path = Tray.object_path;
    header.serial = 1;

    const message = Client.Message{ .body = &hostile, .header = header };

    check_tray(&dispatchers.tray, message);

    header.path = Menu.object_path;
    header.member = "Event";

    const second = Client.Message{ .body = &hostile, .header = header };

    check_menu(&dispatchers.menu, second);

    try testing.expectEqual(@as(u32, 0), dispatchers.menu.item_count());
}
