const std = @import("std");

const client = @import("dbus/client.zig");
const contract = @import("../contract.zig");
const variant = @import("dbus/variant.zig");
const wire = @import("dbus/wire.zig");

const assert = std.debug.assert;

pub const Error = contract.MenuError;

pub const Item = contract.MenuItem;

pub const item_max: u32 = 64;
pub const label_bytes_max: u32 = 128;
pub const object_path = "/MenuBar";
pub const interface_name = "com.canonical.dbusmenu";
pub const properties_interface = "org.freedesktop.DBus.Properties";
pub const property_bytes_max: u32 = 512;
pub const revision_start: u32 = 1;
pub const version_current: u32 = 3;
pub const id_root: u32 = 0;
pub const id_synthetic_base: u32 = 1 << 30;

const property_names = [_][]const u8{
    "IconThemePath",
    "Status",
    "TextDirection",
    "Version",
};

comptime {
    assert(item_max > 0);
    assert(label_bytes_max > 1);
    assert(object_path.len > 1);
    assert(property_bytes_max > 128);
    assert(version_current > 0);
    assert(property_names.len == 4);
    assert(id_synthetic_base > id_root);
    assert(id_synthetic_base + item_max <= std.math.maxInt(i32));
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
    label: [label_bytes_max]u8,
    label_len: u32,

    fn get_label(entry: *const Entry) []const u8 {
        assert(entry.label_len <= label_bytes_max);

        return entry.label[0..entry.label_len];
    }
};

var entries: [item_max]Entry = undefined;
var count: u32 = 0;
var revision: u32 = revision_start;

pub fn build(items: []const Item) Error!void {
    if (items.len > item_max) {
        return Error.CapacityExceeded;
    }

    var index: u32 = 0;

    while (index < items.len) : (index += 1) {
        assert(index < item_max);

        const item = items[index];

        if (!item.is_valid()) {
            return Error.InvalidItem;
        }

        if (item.label.len >= label_bytes_max) {
            return Error.InvalidItem;
        }

        if (item.id >= id_synthetic_base) {
            return Error.InvalidItem;
        }

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

    assert(count <= item_max);
    assert(no_entry_uses_root_id());
}

fn effective_id(id: u32, index: u32) u32 {
    assert(index < item_max);
    assert(id < id_synthetic_base);

    if (id != id_root) {
        return id;
    }

    return id_synthetic_base + index;
}

fn no_entry_uses_root_id() bool {
    var index: u32 = 0;

    while (index < count) : (index += 1) {
        assert(index < item_max);

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

pub fn is_built() bool {
    return count > 0;
}

pub fn item_count() u32 {
    assert(count <= item_max);

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
    assert(label.len < label_bytes_max);

    @memcpy(entry.label[0..label.len], label);

    entry.label_len = @intCast(label.len);

    assert(entry.label_len < label_bytes_max);
}

fn find(id: u32) ?*const Entry {
    var index: u32 = 0;

    while (index < count) : (index += 1) {
        assert(index < item_max);

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

pub const layout_bytes_max: u32 = 8 * 1024;

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
        assert(index < item_max);

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
        assert(index < item_max);

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

test "build rejects an invalid item" {
    destroy();

    const items = [_]Item{.{ .id = 1, .kind = .action, .label = "" }};

    try testing.expectError(Error.InvalidItem, build(&items));
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

test "build rejects an id inside the synthetic range" {
    destroy();

    const items = [_]Item{.{ .id = id_synthetic_base, .kind = .action, .label = "Open" }};

    try testing.expectError(Error.InvalidItem, build(&items));
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
