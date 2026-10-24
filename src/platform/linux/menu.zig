const std = @import("std");

const client = @import("dbus/client.zig");
const contract = @import("../contract.zig");
const variant = @import("dbus/variant.zig");
const wire = @import("dbus/wire.zig");

const assert = std.debug.assert;

const Item = contract.MenuItem;
const PlatformError = contract.PlatformError;

pub const object_path = "/MenuBar";
pub const interface_name = "com.canonical.dbusmenu";
pub const properties_interface = "org.freedesktop.DBus.Properties";
pub const property_bytes_max: u32 = 512;
pub const revision_start: u32 = 1;
pub const version_current: u32 = 3;
pub const id_root: u32 = 0;
pub const id_synthetic_base: u32 = 1 << 30;

const menu_item_count_max = contract.menu_item_count_max;
const menu_label_bytes_max = contract.menu_label_bytes_max;
const layout_header_bytes: u32 = 128;
const layout_item_bytes_max: u32 = menu_label_bytes_max + 256;
const layout_bytes_max: u32 = layout_header_bytes + menu_item_count_max * layout_item_bytes_max;

const property_names = [_][]const u8{
    "IconThemePath",
    "Status",
    "TextDirection",
    "Version",
};

comptime {
    assert(menu_item_count_max > 0);
    assert(menu_label_bytes_max > 0);
    assert(object_path.len > 1);
    assert(property_bytes_max > 128);
    assert(version_current > 0);
    assert(property_names.len == 4);
    assert(id_synthetic_base > id_root);
    assert(contract.menu_item_id_max < id_synthetic_base);
    assert(id_synthetic_base + menu_item_count_max <= std.math.maxInt(i32));
    assert(layout_bytes_max <= client.send_bytes_max - client.header_bytes_max);
}

pub const Outcome = union(enum) {
    about_to_show,
    ignored,
    selected: u32,
};

const Entry = struct {
    checked: bool,
    enabled: bool,
    id: u32,
    kind: contract.MenuItemKind,
    label: [menu_label_bytes_max]u8,
    label_len: u32,

    fn get_label(entry: *const Entry) []const u8 {
        assert(entry.label_len <= menu_label_bytes_max);

        return entry.label[0..entry.label_len];
    }
};

var entries: [menu_item_count_max]Entry = undefined;
var count: u32 = 0;
var revision: u32 = revision_start;

pub fn build(items: []const Item) PlatformError!void {
    assert(items.len <= menu_item_count_max);

    var index: u32 = 0;

    while (index < items.len) : (index += 1) {
        assert(index < menu_item_count_max);

        const item = items[index];

        assert(item.is_valid());

        entries[index] = .{
            .checked = item.checked,
            .enabled = item.enabled,
            .id = effective_id(item.id, index),
            .kind = item.kind,
            .label = undefined,
            .label_len = 0,
        };

        copy_label(&entries[index], item.label);
    }

    count = @intCast(items.len);
    revision += 1;

    emit_layout_updated();

    assert(count <= menu_item_count_max);
    assert(no_entry_uses_root_id());
}

fn effective_id(id: u32, index: u32) u32 {
    assert(index < menu_item_count_max);
    assert(id < id_synthetic_base);

    if (id != id_root) {
        return id;
    }

    return id_synthetic_base + index;
}

fn no_entry_uses_root_id() bool {
    var index: u32 = 0;

    while (index < count) : (index += 1) {
        assert(index < menu_item_count_max);

        if (entries[index].id == id_root) {
            return false;
        }
    }

    return true;
}

pub fn destroy() void {
    count = 0;
    revision += 1;

    assert(count == 0);
}

pub fn item_count() u32 {
    assert(count <= menu_item_count_max);

    return count;
}

pub fn handle_call(message: client.Message) Outcome {
    const header = message.header;

    if (std.mem.eql(u8, header.interface, properties_interface)) {
        handle_properties(message);

        return .ignored;
    }

    if (!std.mem.eql(u8, header.interface, interface_name)) {
        client.reply_error(
            header.serial,
            header.sender,
            client.error_unknown_interface,
            header.interface,
        );

        return .ignored;
    }

    if (std.mem.eql(u8, header.member, "GetLayout")) {
        reply_layout(header.serial, header.sender);

        return .ignored;
    }

    if (std.mem.eql(u8, header.member, "GetGroupProperties")) {
        reply_group_properties(header.serial, header.sender);

        return .ignored;
    }

    if (std.mem.eql(u8, header.member, "AboutToShow")) {
        reply_about_to_show(header.serial, header.sender);

        return .about_to_show;
    }

    if (std.mem.eql(u8, header.member, "Event")) {
        const selected = parse_event(message.body);

        reply_empty(header.serial, header.sender);

        if (selected) |id| {
            return .{ .selected = id };
        }

        return .ignored;
    }

    client.reply_error(header.serial, header.sender, client.error_unknown_method, header.member);

    return .ignored;
}

fn parse_event(body: []const u8) ?u32 {
    var reader = wire.Reader.init(body);

    const raw_id = reader.take_i32() catch return null;
    const kind = reader.take_string() catch return null;

    if (!std.mem.eql(u8, kind, "clicked")) {
        return null;
    }

    if (raw_id <= 0) {
        return null;
    }

    const result: u32 = @intCast(raw_id);
    return result;
}

fn copy_label(entry: *Entry, label: []const u8) void {
    assert(label.len <= menu_label_bytes_max);

    @memcpy(entry.label[0..label.len], label);

    entry.label_len = @intCast(label.len);

    assert(entry.label_len <= menu_label_bytes_max);
}

fn find(id: u32) ?*const Entry {
    var index: u32 = 0;

    while (index < count) : (index += 1) {
        assert(index < menu_item_count_max);

        if (entries[index].id == id) return &entries[index];
    }

    return null;
}

fn emit_layout_updated() void {
    if (!client.is_connected()) {
        return;
    }

    var storage: [32]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    writer.put_u32(revision) catch return;
    writer.put_i32(0) catch return;

    _ = client.send(.{
        .interface = interface_name,
        .kind = .signal,
        .member = "LayoutUpdated",
        .path = object_path,
        .serial = client.next_serial(),
        .signature = "ui",
    }, writer.bytes()) catch return;
}

fn reply_empty(serial: u32, sender: []const u8) void {
    _ = client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = client.next_serial(),
    }, &.{}) catch return;
}

fn reply_about_to_show(serial: u32, sender: []const u8) void {
    var storage: [16]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    writer.put_bool(false) catch return;

    _ = client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = client.next_serial(),
        .signature = "b",
    }, writer.bytes()) catch return;
}

fn handle_properties(message: client.Message) void {
    const header = message.header;

    var reader = wire.Reader.init(message.body);

    const target = reader.take_string() catch {
        client.reply_error(header.serial, header.sender, client.error_invalid_args, header.member);

        return;
    };

    if (!std.mem.eql(u8, target, interface_name)) {
        client.reply_error(header.serial, header.sender, client.error_unknown_interface, target);

        return;
    }

    if (std.mem.eql(u8, header.member, "GetAll")) {
        reply_all_properties(header.serial, header.sender);

        return;
    }

    if (!std.mem.eql(u8, header.member, "Get")) {
        client.reply_error(
            header.serial,
            header.sender,
            client.error_unknown_method,
            header.member,
        );

        return;
    }

    const property = reader.take_string() catch {
        client.reply_error(header.serial, header.sender, client.error_invalid_args, header.member);

        return;
    };

    reply_property(header.serial, header.sender, property);
}

fn reply_property(serial: u32, sender: []const u8, property: []const u8) void {
    var storage: [property_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    const known = write_property(&writer, property) catch return;

    if (!known) {
        client.reply_error(serial, sender, client.error_invalid_args, property);

        return;
    }

    _ = client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = client.next_serial(),
        .signature = "v",
    }, writer.bytes()) catch return;
}

fn reply_all_properties(serial: u32, sender: []const u8) void {
    var storage: [property_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    write_all_properties(&writer) catch return;

    _ = client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = client.next_serial(),
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
    if (std.mem.eql(u8, property, "IconThemePath")) {
        try writer.put_signature("as");
        try variant.put_empty_array(writer, wire.align_of(wire.code_string));

        return true;
    }

    if (std.mem.eql(u8, property, "Status")) {
        try variant.put_string_variant(writer, "normal");

        return true;
    }

    if (std.mem.eql(u8, property, "TextDirection")) {
        try variant.put_string_variant(writer, "ltr");

        return true;
    }

    if (std.mem.eql(u8, property, "Version")) {
        try variant.put_u32_variant(writer, version_current);

        return true;
    }

    return false;
}

var layout_storage: [layout_bytes_max]u8 = undefined;

fn reply_layout(serial: u32, sender: []const u8) void {
    var writer = wire.Writer.init(&layout_storage);

    write_layout(&writer) catch return;

    _ = client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = client.next_serial(),
        .signature = "u(ia{sv}av)",
    }, writer.bytes()) catch return;
}

fn write_layout(writer: *wire.Writer) wire.Error!void {
    try writer.put_u32(revision);
    try writer.pad_to(wire.align_of(wire.code_struct));
    try writer.put_i32(0);

    const root_properties = try writer.open_array(wire.align_of(wire.code_dict_entry));

    try variant.put_dict_entry_string(writer, "children-display", "submenu");
    try writer.close_array(root_properties);

    const children = try writer.open_array(wire.align_of(wire.code_variant));

    var index: u32 = 0;

    while (index < count) : (index += 1) {
        assert(index < menu_item_count_max);

        try writer.put_signature("(ia{sv}av)");
        try write_item(writer, &entries[index]);
    }

    try writer.close_array(children);
}

fn write_item(writer: *wire.Writer, entry: *const Entry) wire.Error!void {
    try writer.pad_to(wire.align_of(wire.code_struct));
    try writer.put_i32(@intCast(entry.id));

    const properties = try writer.open_array(wire.align_of(wire.code_dict_entry));

    if (entry.kind == .separator) {
        try variant.put_dict_entry_string(writer, "type", "separator");
    } else {
        try variant.put_dict_entry_string(writer, "label", entry.get_label());
        try variant.put_dict_entry_bool(writer, "enabled", entry.enabled);
        try variant.put_dict_entry_bool(writer, "visible", true);
    }

    if (entry.kind == .toggle) {
        try variant.put_dict_entry_string(writer, "toggle-type", "checkmark");
        try variant.put_dict_entry_i32(writer, "toggle-state", if (entry.checked) 1 else 0);
    }

    if (entry.kind == .radio) {
        try variant.put_dict_entry_string(writer, "toggle-type", "radio");
        try variant.put_dict_entry_i32(writer, "toggle-state", if (entry.checked) 1 else 0);
    }

    try writer.close_array(properties);

    try variant.put_empty_array(writer, wire.align_of(wire.code_variant));
}

fn reply_group_properties(serial: u32, sender: []const u8) void {
    var writer = wire.Writer.init(&layout_storage);

    write_group_properties(&writer) catch return;

    _ = client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = client.next_serial(),
        .signature = "a(ia{sv})",
    }, writer.bytes()) catch return;
}

fn write_group_properties(writer: *wire.Writer) wire.Error!void {
    const outer = try writer.open_array(wire.align_of(wire.code_struct));

    var index: u32 = 0;

    while (index < count) : (index += 1) {
        assert(index < menu_item_count_max);

        const entry = &entries[index];

        try writer.pad_to(wire.align_of(wire.code_struct));
        try writer.put_i32(@intCast(entry.id));

        const properties = try writer.open_array(wire.align_of(wire.code_dict_entry));

        if (entry.kind == .separator) {
            try variant.put_dict_entry_string(writer, "type", "separator");
        } else {
            try variant.put_dict_entry_string(writer, "label", entry.get_label());
            try variant.put_dict_entry_bool(writer, "enabled", entry.enabled);
        }

        try writer.close_array(properties);
    }

    try writer.close_array(outer);
}

const testing = std.testing;

test "build stores every item" {
    destroy();

    const items = [_]Item{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .kind = .separator },
        .{ .id = 2, .checked = true, .kind = .toggle, .label = "Enabled" },
    };

    try build(&items);

    try testing.expectEqual(@as(u32, 3), item_count());
    try testing.expect(find(1) != null);
    try testing.expect(find(2) != null);
    try testing.expect(find(99) == null);
}

test "build never exports the reserved root id" {
    destroy();

    const items = [_]Item{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .kind = .separator },
        .{ .kind = .separator },
        .{ .id = 2, .kind = .action, .label = "Exit" },
    };

    try build(&items);

    try testing.expectEqual(@as(u32, 4), item_count());
    try testing.expectEqual(@as(u32, 1), entries[0].id);
    try testing.expectEqual(id_synthetic_base + 1, entries[1].id);
    try testing.expectEqual(id_synthetic_base + 2, entries[2].id);
    try testing.expectEqual(@as(u32, 2), entries[3].id);
    try testing.expect(no_entry_uses_root_id());

    destroy();
}

test "write_layout marshals the built menu" {
    destroy();

    const items = [_]Item{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .kind = .separator },
        .{ .id = 2, .checked = true, .kind = .toggle, .label = "Enabled" },
    };

    try build(&items);

    var storage: [layout_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try write_layout(&writer);

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqual(revision, try reader.take_u32());
    try reader.skip_to(8);
    try testing.expectEqual(@as(i32, 0), try reader.take_i32());
}

test "a menu at every bound marshals its whole layout" {
    destroy();

    const label: [menu_label_bytes_max]u8 = @splat('m');

    var items: [menu_item_count_max]Item = undefined;
    var index: u32 = 0;

    while (index < menu_item_count_max) : (index += 1) {
        items[index] = .{
            .checked = true,
            .id = contract.menu_item_id_max - index,
            .kind = .toggle,
            .label = &label,
        };
    }

    try build(&items);

    var layout: [layout_bytes_max]u8 = undefined;
    var layout_writer = wire.Writer.init(&layout);

    try write_layout(&layout_writer);

    var groups: [layout_bytes_max]u8 = undefined;
    var groups_writer = wire.Writer.init(&groups);

    try write_group_properties(&groups_writer);

    destroy();
}

test "write_group_properties marshals every item" {
    destroy();

    const items = [_]Item{.{ .id = 5, .kind = .action, .label = "Quit" }};

    try build(&items);

    var storage: [layout_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try write_group_properties(&writer);

    var reader = wire.Reader.init(writer.bytes());
    const length = try reader.take_u32();

    try testing.expect(length > 0);
}

test "parse_event accepts a clicked event" {
    var storage: [64]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_i32(4);
    try writer.put_string("clicked");

    try testing.expectEqual(@as(?u32, 4), parse_event(writer.bytes()));
}

test "parse_event rejects other events" {
    var storage: [64]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_i32(4);
    try writer.put_string("hovered");

    try testing.expectEqual(@as(?u32, null), parse_event(writer.bytes()));
}

test "parse_event rejects a non positive id" {
    var storage: [64]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_i32(0);
    try writer.put_string("clicked");

    try testing.expectEqual(@as(?u32, null), parse_event(writer.bytes()));
}

test "destroy empties the menu" {
    destroy();

    const items = [_]Item{.{ .id = 1, .kind = .action, .label = "Open" }};

    try build(&items);

    destroy();

    try testing.expectEqual(@as(u32, 0), item_count());
}
