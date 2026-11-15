const std = @import("std");

const Client = @import("dbus.zig").Client;
const interface = @import("../interface.zig");
const variant = @import("dbus.zig").variant;
const wire = @import("dbus.zig").wire;

const assert = std.debug.assert;

const Item = interface.MenuItem;
const PlatformError = interface.PlatformError;

const Menu = @This();

client: *Client,
count: u32,
entries: [menu_item_count_max]Entry,
layout_storage: [layout_bytes_max]u8,
revision: u32,

const Entry = struct {
    checked: bool,
    depth: u8,
    enabled: bool,
    id: u32,
    kind: interface.MenuItemKind,
    label: [menu_label_bytes_max]u8,
    label_len: u32,

    fn get_label(entry: *const Entry) []const u8 {
        assert(entry.label_len <= menu_label_bytes_max);

        return entry.label[0..entry.label_len];
    }
};

pub const Outcome = union(enum) {
    about_to_show,
    ignored,
    selected: u32,
};

const Request = struct {
    parent: u32,
    recursion: i32,
};

const Span = struct {
    depth: u8,
    end: u32,
    root: ?u32,
    start: u32,
};

pub const object_path = "/MenuBar";
pub const interface_name = "com.canonical.dbusmenu";
pub const properties_interface = "org.freedesktop.DBus.Properties";
pub const property_bytes_max: u32 = 512;
pub const revision_start: u32 = 1;
pub const version_current: u32 = 3;
pub const id_root: u32 = 0;
pub const id_synthetic_base: u32 = 1 << 30;

const menu_depth_max = interface.menu_depth_max;
const menu_item_count_max = interface.menu_item_count_max;
const menu_label_bytes_max = interface.menu_label_bytes_max;
const layout_header_bytes: u32 = 128;
const layout_item_bytes_max: u32 = menu_label_bytes_max + 256;
const layout_bytes_max: u32 = layout_header_bytes + menu_item_count_max * layout_item_bytes_max;
const layout_signature = "(ia{sv}av)";
const property_names = [_][]const u8{ "IconThemePath", "Status", "TextDirection", "Version" };

comptime {
    assert(menu_item_count_max > 0);
    assert(menu_label_bytes_max > 0);
    assert(object_path.len > 1);
    assert(property_bytes_max > 128);
    assert(version_current > 0);
    assert(property_names.len == 4);
    assert(id_synthetic_base > id_root);
    assert(interface.menu_item_id_max < id_synthetic_base);
    assert(id_synthetic_base + menu_item_count_max <= std.math.maxInt(i32));
    assert(layout_bytes_max <= Client.send_bytes_max - Client.header_bytes_max);
}

pub fn init(menu: *Menu, client: *Client) void {
    menu.client = client;
    menu.count = 0;
    menu.revision = revision_start;

    assert(menu.item_count() == 0);
    assert(menu.client == client);
}

pub fn build(menu: *Menu, items: []const Item) PlatformError!void {
    assert(items.len <= menu_item_count_max);
    assert(interface.is_valid_layout(items));

    if (menu.is_built(items)) {
        return;
    }

    var index: u32 = 0;

    while (index < items.len) : (index += 1) {
        assert(index < menu_item_count_max);

        const item = items[index];

        assert(item.is_valid());

        menu.entries[index] = .{
            .checked = item.checked,
            .depth = item.depth,
            .enabled = item.enabled,
            .id = effective_id(item.id, index),
            .kind = item.kind,
            .label = undefined,
            .label_len = 0,
        };

        copy_label(&menu.entries[index], item.label);
    }

    menu.count = @intCast(items.len);
    menu.revision += 1;

    menu.emit_layout_updated();

    assert(menu.count <= menu_item_count_max);
    assert(menu.no_entry_uses_root_id());
}

fn effective_id(id: u32, index: u32) u32 {
    assert(index < menu_item_count_max);
    assert(id < id_synthetic_base);

    if (id != id_root) {
        return id;
    }

    const result = id_synthetic_base + index;
    assert(result >= id_synthetic_base);

    return result;
}

fn is_built(menu: *const Menu, items: []const Item) bool {
    assert(items.len <= menu_item_count_max);
    assert(menu.count <= menu_item_count_max);

    if (items.len != menu.count) return false;

    for (items, menu.entries[0..menu.count], 0..) |*item, *entry, index| {
        if (entry.id != effective_id(item.id, @intCast(index))) return false;
        if (entry.kind != item.kind) return false;
        if (entry.depth != item.depth) return false;
        if (entry.checked != item.checked) return false;
        if (entry.enabled != item.enabled) return false;
        if (!std.mem.eql(u8, entry.get_label(), item.label)) return false;
    }

    return true;
}

fn no_entry_uses_root_id(menu: *const Menu) bool {
    var index: u32 = 0;

    while (index < menu.count) : (index += 1) {
        assert(index < menu_item_count_max);

        if (menu.entries[index].id == id_root) {
            return false;
        }
    }

    return true;
}

pub fn destroy(menu: *Menu) void {
    menu.count = 0;
    menu.revision += 1;

    assert(menu.count == 0);
}

pub fn item_count(menu: *const Menu) u32 {
    assert(menu.count <= menu_item_count_max);

    return menu.count;
}

pub fn handle_call(menu: *Menu, message: Client.Message) Outcome {
    assert(message.header.kind == .method_call);

    const header = message.header;

    if (std.mem.eql(u8, header.interface, properties_interface)) {
        menu.handle_properties(message);

        return .ignored;
    }

    if (!std.mem.eql(u8, header.interface, interface_name)) {
        menu.client.reply_error(
            header.serial,
            header.sender,
            Client.error_unknown_interface,
            header.interface,
        );

        return .ignored;
    }

    if (std.mem.eql(u8, header.member, "GetLayout")) {
        menu.reply_layout(message);

        return .ignored;
    }

    if (std.mem.eql(u8, header.member, "GetGroupProperties")) {
        menu.reply_group_properties(header.serial, header.sender);

        return .ignored;
    }

    if (std.mem.eql(u8, header.member, "AboutToShow")) {
        return menu.about_to_show(message);
    }

    if (std.mem.eql(u8, header.member, "Event")) {
        const selected = menu.parse_event(message.body);

        menu.reply_empty(header.serial, header.sender);

        if (selected) |id| {
            return .{ .selected = id };
        }

        return .ignored;
    }

    menu.client.reply_error(
        header.serial,
        header.sender,
        Client.error_unknown_method,
        header.member,
    );

    return .ignored;
}

fn about_to_show(menu: *Menu, message: Client.Message) Outcome {
    assert(std.mem.eql(u8, message.header.member, "AboutToShow"));

    const header = message.header;
    var reader = wire.Reader.init(message.body);

    const id = reader.take_i32() catch {
        menu.client.reply_error(
            header.serial,
            header.sender,
            Client.error_invalid_args,
            header.member,
        );

        return .ignored;
    };

    menu.reply_about_to_show(header.serial, header.sender);

    if (id != id_root) {
        return .ignored;
    }

    return .about_to_show;
}

fn parse_event(menu: *const Menu, body: []const u8) ?u32 {
    assert(body.len <= wire.body_bytes_max);

    var reader = wire.Reader.init(body);

    const raw_id = reader.take_i32() catch return null;
    const kind = reader.take_string() catch return null;

    if (!std.mem.eql(u8, kind, "clicked")) {
        return null;
    }

    if (raw_id <= 0) {
        return null;
    }

    const index = menu.index_of(@intCast(raw_id)) orelse return null;
    const entry = &menu.entries[index];

    switch (entry.kind) {
        .separator, .submenu => return null,
        .action, .radio, .toggle => {},
    }

    const result = if (entry.id >= id_synthetic_base) id_root else entry.id;

    assert(result <= interface.menu_item_id_max);

    return result;
}

fn copy_label(entry: *Entry, label: []const u8) void {
    assert(label.len <= menu_label_bytes_max);

    @memcpy(entry.label[0..label.len], label);

    entry.label_len = @intCast(label.len);

    assert(entry.label_len <= menu_label_bytes_max);
}

fn index_of(menu: *const Menu, id: u32) ?u32 {
    var index: u32 = 0;

    while (index < menu.count) : (index += 1) {
        assert(index < menu_item_count_max);

        if (menu.entries[index].id == id) return index;
    }

    return null;
}

fn locate(menu: *const Menu, parent: u32) ?Span {
    assert(menu.count <= menu_item_count_max);
    assert(parent <= std.math.maxInt(i32));

    if (parent == id_root) {
        return .{ .depth = 0, .end = menu.count, .root = null, .start = 0 };
    }

    const root = menu.index_of(parent) orelse return null;
    const depth = menu.entries[root].depth + 1;
    var end = root + 1;

    while (end < menu.count) : (end += 1) {
        if (menu.entries[end].depth < depth) break;
    }

    assert(end <= menu.count);

    return .{ .depth = depth, .end = end, .root = root, .start = root + 1 };
}

fn emit_layout_updated(menu: *Menu) void {
    if (!menu.client.is_connected()) {
        return;
    }

    var storage: [32]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    writer.put_u32(menu.revision) catch return;
    writer.put_i32(0) catch return;

    _ = menu.client.send(.{
        .interface = interface_name,
        .kind = .signal,
        .member = "LayoutUpdated",
        .path = object_path,
        .serial = menu.client.next_serial(),
        .signature = "ui",
    }, writer.bytes()) catch return;
}

fn reply_empty(menu: *Menu, serial: u32, sender: []const u8) void {
    assert(serial != 0);
    assert(sender.len <= wire.string_bytes_max);

    _ = menu.client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = menu.client.next_serial(),
    }, &.{}) catch return;
}

fn reply_about_to_show(menu: *Menu, serial: u32, sender: []const u8) void {
    assert(serial != 0);
    assert(sender.len <= wire.string_bytes_max);

    var storage: [16]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    writer.put_bool(false) catch return;

    _ = menu.client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = menu.client.next_serial(),
        .signature = "b",
    }, writer.bytes()) catch return;
}

fn handle_properties(menu: *Menu, message: Client.Message) void {
    assert(std.mem.eql(u8, message.header.interface, properties_interface));

    const header = message.header;

    var reader = wire.Reader.init(message.body);

    const target = reader.take_string() catch {
        menu.client.reply_error(
            header.serial,
            header.sender,
            Client.error_invalid_args,
            header.member,
        );

        return;
    };

    if (!std.mem.eql(u8, target, interface_name)) {
        menu.client.reply_error(
            header.serial,
            header.sender,
            Client.error_unknown_interface,
            target,
        );

        return;
    }

    if (std.mem.eql(u8, header.member, "GetAll")) {
        menu.reply_all_properties(header.serial, header.sender);

        return;
    }

    if (!std.mem.eql(u8, header.member, "Get")) {
        menu.client.reply_error(
            header.serial,
            header.sender,
            Client.error_unknown_method,
            header.member,
        );

        return;
    }

    const property = reader.take_string() catch {
        menu.client.reply_error(
            header.serial,
            header.sender,
            Client.error_invalid_args,
            header.member,
        );

        return;
    };

    menu.reply_property(header.serial, header.sender, property);
}

fn reply_property(menu: *Menu, serial: u32, sender: []const u8, property: []const u8) void {
    assert(serial != 0);
    assert(sender.len <= wire.string_bytes_max);
    assert(property.len <= wire.string_bytes_max);

    var storage: [property_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    const known = write_property(&writer, property) catch return;

    if (!known) {
        menu.client.reply_error(serial, sender, Client.error_invalid_args, property);

        return;
    }

    _ = menu.client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = menu.client.next_serial(),
        .signature = "v",
    }, writer.bytes()) catch return;
}

fn reply_all_properties(menu: *Menu, serial: u32, sender: []const u8) void {
    assert(serial != 0);
    assert(sender.len <= wire.string_bytes_max);

    var storage: [property_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    write_all_properties(&writer) catch return;

    _ = menu.client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = menu.client.next_serial(),
        .signature = "a{sv}",
    }, writer.bytes()) catch return;
}

fn write_all_properties(writer: *wire.Writer) wire.Error!void {
    const marker = try writer.open_array(wire.align_of(wire.code_dict_entry));

    var index: u32 = 0;

    while (index < property_names.len) : (index += 1) {
        assert(index < property_names.len);

        try writer.pad_to(wire.align_of(wire.code_dict_entry));
        try writer.put_string(property_names[index]);

        const known = try write_property(writer, property_names[index]);

        assert(known);
    }

    try writer.close_array(marker);
}

fn write_property(writer: *wire.Writer, property: []const u8) wire.Error!bool {
    assert(property.len <= wire.string_bytes_max);

    if (std.mem.eql(u8, property, "IconThemePath")) {
        try writer.put_signature("as");
        try variant.put_empty_array(writer, wire.align_of(wire.code_string));

        return true;
    }

    if (std.mem.eql(u8, property, "Status")) {
        try variant.put_string(writer, "normal");

        return true;
    }

    if (std.mem.eql(u8, property, "TextDirection")) {
        try variant.put_string(writer, "ltr");

        return true;
    }

    if (std.mem.eql(u8, property, "Version")) {
        try variant.put_u32(writer, version_current);

        return true;
    }

    return false;
}

fn reply_layout(menu: *Menu, message: Client.Message) void {
    assert(message.header.serial != 0);
    assert(message.header.sender.len <= wire.string_bytes_max);

    const header = message.header;

    const request = parse_layout_request(message.body) orelse {
        menu.client.reply_error(
            header.serial,
            header.sender,
            Client.error_invalid_args,
            header.member,
        );

        return;
    };

    const span = menu.locate(request.parent) orelse {
        menu.client.reply_error(
            header.serial,
            header.sender,
            Client.error_invalid_args,
            header.member,
        );

        return;
    };

    var writer = wire.Writer.init(&menu.layout_storage);

    menu.write_layout(&writer, span, request.recursion) catch return;

    _ = menu.client.send(.{
        .destination = header.sender,
        .kind = .method_return,
        .reply_serial = header.serial,
        .serial = menu.client.next_serial(),
        .signature = "u(ia{sv}av)",
    }, writer.bytes()) catch return;
}

fn parse_layout_request(body: []const u8) ?Request {
    assert(body.len <= wire.body_bytes_max);

    var reader = wire.Reader.init(body);
    const parent = reader.take_i32() catch return null;
    const recursion = reader.take_i32() catch return null;

    if (parent < 0) return null;

    return .{ .parent = @intCast(parent), .recursion = recursion };
}

fn write_layout(
    menu: *const Menu,
    writer: *wire.Writer,
    span: Span,
    recursion: i32,
) wire.Error!void {
    assert(span.start <= span.end);
    assert(span.end <= menu.count);

    try writer.put_u32(menu.revision);
    try writer.pad_to(wire.align_of(wire.code_struct));

    if (span.root) |root| {
        try writer.put_i32(@intCast(menu.entries[root].id));
        try write_properties(writer, &menu.entries[root]);
    } else {
        try writer.put_i32(0);

        const properties = try writer.open_array(wire.align_of(wire.code_dict_entry));

        try variant.put_dict_entry_string(writer, "children-display", "submenu");
        try writer.close_array(properties);
    }

    try write_children(menu, writer, span, recursion);
}

fn write_children(
    menu: *const Menu,
    writer: *wire.Writer,
    span: Span,
    recursion: i32,
) wire.Error!void {
    assert(span.start <= span.end);
    assert(span.end <= menu.count);

    var markers: [menu_depth_max + 2]wire.ArrayMarker = undefined;
    var open: u32 = 1;

    markers[0] = try writer.open_array(wire.align_of(wire.code_variant));

    for (menu.entries[span.start..span.end]) |*entry| {
        assert(entry.depth >= span.depth);

        const level = entry.depth - span.depth;

        if (recursion >= 0) {
            if (level >= recursion) continue;
        }

        assert(open > level);

        while (open > level + 1) {
            open -= 1;

            try writer.close_array(markers[open]);
        }

        assert(open < markers.len);

        try writer.put_signature(layout_signature);
        try writer.pad_to(wire.align_of(wire.code_struct));
        try writer.put_i32(@intCast(entry.id));
        try write_properties(writer, entry);

        markers[open] = try writer.open_array(wire.align_of(wire.code_variant));
        open += 1;
    }

    while (open > 0) {
        open -= 1;

        try writer.close_array(markers[open]);
    }
}

fn write_properties(writer: *wire.Writer, entry: *const Entry) wire.Error!void {
    const properties = try writer.open_array(wire.align_of(wire.code_dict_entry));

    if (entry.kind == .separator) {
        try variant.put_dict_entry_string(writer, "type", "separator");
    } else {
        try variant.put_dict_entry_string(writer, "label", entry.get_label());
        try variant.put_dict_entry_bool(writer, "enabled", entry.enabled);
        try variant.put_dict_entry_bool(writer, "visible", true);
    }

    switch (entry.kind) {
        .action, .separator => {},
        .radio => try write_toggle(writer, "radio", entry.checked),
        .submenu => try variant.put_dict_entry_string(writer, "children-display", "submenu"),
        .toggle => try write_toggle(writer, "checkmark", entry.checked),
    }

    try writer.close_array(properties);
}

fn write_toggle(writer: *wire.Writer, toggle_type: []const u8, checked: bool) wire.Error!void {
    assert(toggle_type.len > 0);

    try variant.put_dict_entry_string(writer, "toggle-type", toggle_type);
    try variant.put_dict_entry_i32(writer, "toggle-state", if (checked) 1 else 0);
}

fn reply_group_properties(menu: *Menu, serial: u32, sender: []const u8) void {
    assert(serial != 0);
    assert(sender.len <= wire.string_bytes_max);

    var writer = wire.Writer.init(&menu.layout_storage);

    menu.write_group_properties(&writer) catch return;

    _ = menu.client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = menu.client.next_serial(),
        .signature = "a(ia{sv})",
    }, writer.bytes()) catch return;
}

fn write_group_properties(menu: *const Menu, writer: *wire.Writer) wire.Error!void {
    const outer = try writer.open_array(wire.align_of(wire.code_struct));

    var index: u32 = 0;

    while (index < menu.count) : (index += 1) {
        assert(index < menu_item_count_max);

        const entry = &menu.entries[index];

        try writer.pad_to(wire.align_of(wire.code_struct));
        try writer.put_i32(@intCast(entry.id));
        try write_properties(writer, entry);
    }

    try writer.close_array(outer);
}

const testing = std.testing;

const Layout = struct {
    count: u32,
    nodes: [menu_item_count_max]Node,
    root: Node,
};

const Node = struct {
    depth: u8,
    id: i32,
    label: []const u8,
    submenu: bool,
};

const property_count_max: u32 = 8;

const Fixture = struct {
    client: Client,
    menu: Menu,

    fn create() !*Fixture {
        const fixture = try testing.allocator.create(Fixture);

        fixture.client.init();
        fixture.menu.init(&fixture.client);

        assert(!fixture.client.is_connected());
        assert(fixture.menu.item_count() == 0);

        return fixture;
    }

    fn destroy(fixture: *Fixture) void {
        assert(!fixture.client.is_connected());

        testing.allocator.destroy(fixture);
    }
};

const nested_items = [_]Item{
    .{ .checked = true, .id = 1, .kind = .toggle, .label = "Dim" },
    .{ .id = 2, .kind = .submenu, .label = "Level" },
    .{ .depth = 1, .id = 3, .kind = .radio, .label = "10%" },
    .{ .depth = 1, .id = 4, .kind = .submenu, .label = "Finer" },
    .{ .depth = 2, .id = 5, .kind = .radio, .label = "15%" },
    .{ .depth = 1, .id = 6, .kind = .radio, .label = "20%" },
    .{ .kind = .separator },
    .{ .id = 7, .kind = .action, .label = "Exit" },
};

fn call(member: []const u8, body: []const u8) Client.Message {
    assert(member.len > 0);
    assert(body.len <= wire.body_bytes_max);

    var header = wire.Header.empty();

    header.body_length = @intCast(body.len);
    header.interface = interface_name;
    header.kind = .method_call;
    header.member = member;
    header.path = object_path;
    header.serial = 1;

    return .{ .body = body, .header = header };
}

fn decode_array_end(reader: *wire.Reader, element_alignment: u32) !u32 {
    assert(element_alignment == 1 or element_alignment == 4 or element_alignment == 8);
    assert(reader.offset <= reader.buffer.len);

    const length = try reader.take_u32();

    try reader.skip_to(element_alignment);

    const result = reader.offset + length;
    if (result > reader.buffer.len) return error.Truncated;

    assert(result <= reader.buffer.len);

    return result;
}

fn decode_layout(bytes: []const u8, layout: *Layout) !void {
    assert(bytes.len > 0);
    assert(bytes.len <= layout_bytes_max);

    var reader = wire.Reader.init(bytes);

    _ = try reader.take_u32();

    layout.count = 0;
    layout.root = try decode_node(&reader, 0);

    var ends: [menu_depth_max + 2]u32 = undefined;
    var open: u32 = 1;

    ends[0] = try decode_array_end(&reader, wire.align_of(wire.code_variant));

    for (0..2 * menu_item_count_max + 1) |_| {
        if (open == 0) break;

        if (reader.offset == ends[open - 1]) {
            open -= 1;

            continue;
        }

        const signature = try reader.take_signature();

        if (!std.mem.eql(u8, signature, layout_signature)) return error.SignatureUnexpected;
        if (layout.count == menu_item_count_max) return error.NodesExhausted;
        if (open == ends.len) return error.LayoutTooDeep;

        layout.nodes[layout.count] = try decode_node(&reader, @intCast(open - 1));
        layout.count += 1;
        ends[open] = try decode_array_end(&reader, wire.align_of(wire.code_variant));
        open += 1;
    }

    if (open != 0) return error.LayoutUnfinished;
    if (reader.offset != bytes.len) return error.LayoutTrailing;
}

fn decode_node(reader: *wire.Reader, depth: u8) !Node {
    try reader.skip_to(wire.align_of(wire.code_struct));

    var result = Node{ .depth = depth, .id = try reader.take_i32(), .label = "", .submenu = false };
    const end = try decode_array_end(reader, wire.align_of(wire.code_dict_entry));

    for (0..property_count_max) |_| {
        if (reader.offset == end) break;

        try reader.skip_to(wire.align_of(wire.code_dict_entry));

        const key = try reader.take_string();
        const signature = try reader.take_signature();

        if (signature.len != 1) return error.SignatureUnexpected;

        switch (signature[0]) {
            'b' => _ = try reader.take_u32(),
            'i' => _ = try reader.take_i32(),
            's' => {
                const value = try reader.take_string();

                if (std.mem.eql(u8, key, "label")) result.label = value;
                if (std.mem.eql(u8, key, "children-display")) result.submenu = true;
            },
            else => return error.SignatureUnexpected,
        }
    }

    if (reader.offset != end) return error.PropertiesUnfinished;

    return result;
}

fn read_layout(
    menu: *const Menu,
    storage: []u8,
    parent: u32,
    recursion: i32,
    layout: *Layout,
) !void {
    assert(storage.len >= layout_bytes_max);
    assert(parent <= std.math.maxInt(i32));
    assert(recursion >= -1);

    var writer = wire.Writer.init(storage);
    const span = menu.locate(parent) orelse return error.ParentUnknown;

    try menu.write_layout(&writer, span, recursion);
    try decode_layout(writer.bytes(), layout);
}

test "a nested menu marshals each item under its submenu at its own depth" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    try menu.build(&nested_items);
    defer menu.destroy();

    var storage: [layout_bytes_max]u8 = undefined;
    var layout: Layout = undefined;

    try read_layout(menu, &storage, id_root, -1, &layout);

    try testing.expectEqual(@as(i32, id_root), layout.root.id);
    try testing.expect(layout.root.submenu);
    try testing.expectEqual(@as(u32, nested_items.len), layout.count);

    for (layout.nodes[0..layout.count], &nested_items, 0..) |node, item, index| {
        try testing.expectEqual(@as(i32, @intCast(menu.entries[index].id)), node.id);
        try testing.expectEqual(item.depth, node.depth);
        try testing.expectEqualStrings(item.label, node.label);
        try testing.expectEqual(item.kind == .submenu, node.submenu);
    }
}

test "a layout request for a submenu serves only the items inside it" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    try menu.build(&nested_items);
    defer menu.destroy();

    var storage: [layout_bytes_max]u8 = undefined;
    var layout: Layout = undefined;

    try read_layout(menu, &storage, 2, -1, &layout);

    const expected = [_]Node{
        .{ .depth = 0, .id = 3, .label = "10%", .submenu = false },
        .{ .depth = 0, .id = 4, .label = "Finer", .submenu = true },
        .{ .depth = 1, .id = 5, .label = "15%", .submenu = false },
        .{ .depth = 0, .id = 6, .label = "20%", .submenu = false },
    };

    try testing.expectEqual(@as(i32, 2), layout.root.id);
    try testing.expectEqualStrings("Level", layout.root.label);
    try testing.expect(layout.root.submenu);
    try testing.expectEqual(@as(u32, expected.len), layout.count);

    for (layout.nodes[0..layout.count], expected) |node, wanted| {
        try testing.expectEqual(wanted.depth, node.depth);
        try testing.expectEqual(wanted.id, node.id);
        try testing.expectEqualStrings(wanted.label, node.label);
        try testing.expectEqual(wanted.submenu, node.submenu);
    }

    try read_layout(menu, &storage, 3, -1, &layout);

    try testing.expectEqual(@as(i32, 3), layout.root.id);
    try testing.expectEqual(@as(u32, 0), layout.count);
    try testing.expectError(error.ParentUnknown, read_layout(menu, &storage, 99, -1, &layout));
}

test "a recursion depth limits how many levels a layout serves" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    try menu.build(&nested_items);
    defer menu.destroy();

    var storage: [layout_bytes_max]u8 = undefined;
    var layout: Layout = undefined;

    try read_layout(menu, &storage, id_root, 0, &layout);

    try testing.expectEqual(@as(u32, 0), layout.count);

    try read_layout(menu, &storage, id_root, 1, &layout);

    try testing.expectEqual(@as(u32, 4), layout.count);

    for (layout.nodes[0..layout.count]) |node| {
        try testing.expectEqual(@as(u8, 0), node.depth);
    }

    try read_layout(menu, &storage, id_root, 2, &layout);

    try testing.expectEqual(@as(u32, nested_items.len - 1), layout.count);

    try read_layout(menu, &storage, 2, 1, &layout);

    try testing.expectEqual(@as(u32, 3), layout.count);
}

test "a layout request names its parent and depth or is refused" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    try menu.build(&nested_items);
    defer menu.destroy();

    var storage: [64]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_i32(4);
    try writer.put_i32(-1);

    const request = parse_layout_request(writer.bytes()) orelse return error.RequestMissing;

    try testing.expectEqual(@as(u32, 4), request.parent);
    try testing.expectEqual(@as(i32, -1), request.recursion);
    try testing.expect(parse_layout_request(writer.bytes()[0..4]) == null);

    writer.reset();

    try writer.put_i32(-3);
    try writer.put_i32(1);

    try testing.expect(parse_layout_request(writer.bytes()) == null);
    try testing.expectEqual(Outcome.ignored, menu.handle_call(call("GetLayout", writer.bytes())));
}

test "only the root menu about to show reports that the menu shows" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    try menu.build(&nested_items);
    defer menu.destroy();

    var storage: [16]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_i32(0);

    const root = menu.handle_call(call("AboutToShow", writer.bytes()));

    writer.reset();

    try writer.put_i32(2);

    const submenu = menu.handle_call(call("AboutToShow", writer.bytes()));
    const garbled = menu.handle_call(call("AboutToShow", &.{}));

    try testing.expectEqual(Outcome.about_to_show, root);
    try testing.expectEqual(Outcome.ignored, submenu);
    try testing.expectEqual(Outcome.ignored, garbled);
}

test "a click on a submenu selects nothing and a click inside it selects the item" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    try menu.build(&nested_items);
    defer menu.destroy();

    var storage: [64]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_i32(2);
    try writer.put_string("clicked");

    try testing.expectEqual(@as(?u32, null), menu.parse_event(writer.bytes()));

    writer.reset();

    try writer.put_i32(5);
    try writer.put_string("clicked");

    try testing.expectEqual(@as(?u32, 5), menu.parse_event(writer.bytes()));
}

test "group properties carry the same properties as the layout" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    try menu.build(&nested_items);
    defer menu.destroy();

    var storage: [layout_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try menu.write_group_properties(&writer);

    var reader = wire.Reader.init(writer.bytes());
    const end = try decode_array_end(&reader, wire.align_of(wire.code_struct));
    var found: u32 = 0;

    for (0..nested_items.len + 1) |_| {
        if (reader.offset == end) break;

        const node = try decode_node(&reader, 0);
        const item = &nested_items[found];

        try testing.expectEqual(@as(i32, @intCast(menu.entries[found].id)), node.id);
        try testing.expectEqualStrings(item.label, node.label);
        try testing.expectEqual(item.kind == .submenu, node.submenu);

        found += 1;
    }

    try testing.expectEqual(@as(u32, nested_items.len), found);
}

test "build stores every item" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    const items = [_]Item{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .kind = .separator },
        .{ .id = 2, .checked = true, .kind = .toggle, .label = "Enabled" },
    };

    try menu.build(&items);

    try testing.expectEqual(@as(u32, 3), menu.item_count());
    try testing.expect(menu.index_of(1) != null);
    try testing.expect(menu.index_of(2) != null);
    try testing.expect(menu.index_of(99) == null);
}

test "rebuilding an unchanged menu publishes no new layout and any change publishes one" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    defer menu.destroy();

    try menu.build(&nested_items);

    const published = menu.revision;

    try menu.build(&nested_items);

    try testing.expectEqual(published, menu.revision);

    const last = nested_items.len - 1;
    var changes: [5][nested_items.len]Item = @splat(nested_items);

    changes[0][last].checked = true;
    changes[1][last].enabled = false;
    changes[2][last].id = 9;
    changes[3][last].kind = .toggle;
    changes[4][last].label = "Quit";

    for (&changes) |*changed| {
        const before = menu.revision;

        try menu.build(changed);

        try testing.expectEqual(before + 1, menu.revision);

        try menu.build(&nested_items);

        try testing.expectEqual(before + 2, menu.revision);
    }
}

test "build never exports the reserved root id" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    const items = [_]Item{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .kind = .separator },
        .{ .kind = .separator },
        .{ .id = 2, .kind = .action, .label = "Exit" },
    };

    try menu.build(&items);

    try testing.expectEqual(@as(u32, 4), menu.item_count());
    try testing.expectEqual(@as(u32, 1), menu.entries[0].id);
    try testing.expectEqual(id_synthetic_base + 1, menu.entries[1].id);
    try testing.expectEqual(id_synthetic_base + 2, menu.entries[2].id);
    try testing.expectEqual(@as(u32, 2), menu.entries[3].id);
    try testing.expect(menu.no_entry_uses_root_id());

    menu.destroy();
}

test "write_layout marshals the built menu" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    const items = [_]Item{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .kind = .separator },
        .{ .id = 2, .checked = true, .kind = .toggle, .label = "Enabled" },
    };

    try menu.build(&items);

    var storage: [layout_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try menu.write_layout(&writer, menu.locate(id_root).?, -1);

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqual(menu.revision, try reader.take_u32());
    try reader.skip_to(8);
    try testing.expectEqual(@as(i32, 0), try reader.take_i32());
}

test "a menu at every bound marshals its whole layout" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;
    const label: [menu_label_bytes_max]u8 = @splat('m');

    var items: [menu_item_count_max]Item = undefined;
    var index: u32 = 0;

    while (index < menu_item_count_max) : (index += 1) {
        items[index] = .{
            .checked = true,
            .id = interface.menu_item_id_max - index,
            .kind = .toggle,
            .label = &label,
        };
    }

    try menu.build(&items);

    var layout: [layout_bytes_max]u8 = undefined;
    var layout_writer = wire.Writer.init(&layout);

    try menu.write_layout(&layout_writer, menu.locate(id_root).?, -1);

    var groups: [layout_bytes_max]u8 = undefined;
    var groups_writer = wire.Writer.init(&groups);

    try menu.write_group_properties(&groups_writer);

    menu.destroy();
}

test "a menu nested to the depth limit at every bound marshals each layout it serves" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;
    const label: [menu_label_bytes_max]u8 = @splat('m');

    var items: [menu_item_count_max]Item = undefined;
    var index: u32 = 0;

    while (index < menu_item_count_max) : (index += 1) {
        const opens = index < menu_depth_max;

        items[index] = .{
            .checked = true,
            .depth = @intCast(@min(index, menu_depth_max)),
            .id = interface.menu_item_id_max - index,
            .kind = if (opens) .submenu else .toggle,
            .label = &label,
        };
    }

    try menu.build(&items);
    defer menu.destroy();

    var storage: [layout_bytes_max]u8 = undefined;
    var layout: Layout = undefined;

    try read_layout(menu, &storage, id_root, -1, &layout);

    try testing.expectEqual(@as(u32, menu_item_count_max), layout.count);

    index = 0;

    while (index < menu_depth_max) : (index += 1) {
        try read_layout(menu, &storage, items[index].id, -1, &layout);

        try testing.expectEqual(menu_item_count_max - index - 1, layout.count);
    }

    var groups: [layout_bytes_max]u8 = undefined;
    var groups_writer = wire.Writer.init(&groups);

    try menu.write_group_properties(&groups_writer);
}

test "write_group_properties marshals every item" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;
    const items = [_]Item{.{ .id = 5, .kind = .action, .label = "Quit" }};

    try menu.build(&items);

    var storage: [layout_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try menu.write_group_properties(&writer);

    var reader = wire.Reader.init(writer.bytes());
    const length = try reader.take_u32();

    try testing.expect(length > 0);
}

test "parse_event accepts a clicked event for a built item" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;
    const items = [_]Item{.{ .id = 4, .kind = .action, .label = "Open" }};

    try menu.build(&items);
    defer menu.destroy();

    var storage: [64]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_i32(4);
    try writer.put_string("clicked");

    try testing.expectEqual(@as(?u32, 4), menu.parse_event(writer.bytes()));
}

test "parse_event maps a synthetic id back to zero and refuses ids the menu never built" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    const items = [_]Item{
        .{ .id = 0, .kind = .action, .label = "Zero" },
        .{ .kind = .separator },
        .{ .id = 9, .kind = .action, .label = "Nine" },
    };

    try menu.build(&items);
    defer menu.destroy();

    const clicks = [_]struct { id: i32, expected: ?u32 }{
        .{ .id = @intCast(id_synthetic_base), .expected = 0 },
        .{ .id = @intCast(id_synthetic_base + 1), .expected = null },
        .{ .id = 9, .expected = 9 },
        .{ .id = 10, .expected = null },
        .{ .id = @intCast(id_synthetic_base + items.len), .expected = null },
    };

    for (clicks) |click| {
        var storage: [64]u8 = undefined;
        var writer = wire.Writer.init(&storage);

        try writer.put_i32(click.id);
        try writer.put_string("clicked");

        try testing.expectEqual(click.expected, menu.parse_event(writer.bytes()));
    }
}

test "parse_event rejects other events" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    var storage: [64]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_i32(4);
    try writer.put_string("hovered");

    try testing.expectEqual(@as(?u32, null), menu.parse_event(writer.bytes()));
}

test "parse_event rejects a non positive id" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;

    var storage: [64]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_i32(0);
    try writer.put_string("clicked");

    try testing.expectEqual(@as(?u32, null), menu.parse_event(writer.bytes()));
}

test "destroy empties the menu" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const menu = &fixture.menu;
    const items = [_]Item{.{ .id = 1, .kind = .action, .label = "Open" }};

    try menu.build(&items);

    menu.destroy();

    try testing.expectEqual(@as(u32, 0), menu.item_count());
}
