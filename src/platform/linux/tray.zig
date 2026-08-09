const std = @import("std");

const client = @import("dbus/client.zig");
const contract = @import("../contract.zig");
const icon_mod = @import("icon.zig");
const menu = @import("menu.zig");
const runtime = @import("runtime.zig");
const variant = @import("dbus/variant.zig");
const wire = @import("dbus/wire.zig");

const assert = std.debug.assert;

pub const Error = contract.TrayError;

pub const CreateOptions = contract.TrayCreateOptions;

pub const interface_name = "org.kde.StatusNotifierItem";
pub const object_path = "/StatusNotifierItem";
pub const properties_interface = "org.freedesktop.DBus.Properties";
pub const watcher_name = "org.kde.StatusNotifierWatcher";
pub const watcher_path = "/StatusNotifierWatcher";
pub const bus_interface = "org.freedesktop.DBus";
pub const owner_changed_member = "NameOwnerChanged";

pub const tooltip_bytes_max: u32 = 128;
pub const reply_bytes_overhead: u32 = 2 * 1024;
pub const reply_bytes_max: u32 = contract.pixmap_bytes_max + reply_bytes_overhead;

const property_names = [_][]const u8{
    "Category",
    "IconName",
    "IconPixmap",
    "Id",
    "ItemIsMenu",
    "Menu",
    "Status",
    "Title",
    "ToolTip",
};

comptime {
    assert(tooltip_bytes_max > 1);
    assert(reply_bytes_max > contract.pixmap_bytes_max);
    assert(reply_bytes_overhead >= 2 * contract.path_bytes_max + 2 * tooltip_bytes_max);
    assert(reply_bytes_max <= client.send_bytes_max - client.header_bytes_max);
    assert(property_names.len == 9);
}

pub const Outcome = enum {
    activate,
    context_menu,
    ignored,
    secondary_activate,
};

var created: bool = false;
var current_id: u32 = 0;
var current_icon: ?icon_mod.Handle = null;
var tooltip: [tooltip_bytes_max]u8 = undefined;
var tooltip_len: u32 = 0;

var reply_storage: [reply_bytes_max]u8 = undefined;

pub fn create(options: CreateOptions) Error!void {
    if (options.tooltip.len >= tooltip_bytes_max) {
        return Error.InvalidTooltip;
    }

    if (created) {
        return Error.AlreadyCreated;
    }

    if (!runtime.is_open()) {
        return Error.RuntimeClosed;
    }

    current_id = options.id;
    current_icon = options.icon;

    copy_tooltip(options.tooltip);

    register() catch {
        return Error.CreationFailed;
    };

    created = true;

    assert(created);
}

pub fn destroy() void {
    if (!created) {
        return;
    }

    created = false;
    current_icon = null;

    assert(!created);
}

pub fn is_created() bool {
    return created;
}

pub fn set_icon(handle: icon_mod.Handle) Error!void {
    if (!created) {
        return Error.NotCreated;
    }

    current_icon = handle;

    emit("NewIcon");
}

pub fn set_tooltip(text: []const u8) Error!void {
    if (!created) {
        return Error.NotCreated;
    }

    if (text.len >= tooltip_bytes_max) {
        return Error.InvalidTooltip;
    }

    copy_tooltip(text);

    emit("NewToolTip");
}

pub fn current_tooltip() []const u8 {
    assert(tooltip_len <= tooltip_bytes_max);

    return tooltip[0..tooltip_len];
}

pub fn id() u32 {
    return current_id;
}

pub fn is_watcher_restart(message: client.Message) bool {
    const header = message.header;

    if (header.kind != .signal) {
        return false;
    }

    if (!std.mem.eql(u8, header.interface, bus_interface)) {
        return false;
    }

    if (!std.mem.eql(u8, header.member, owner_changed_member)) {
        return false;
    }

    var reader = wire.Reader.init(message.body);

    const changed = reader.take_string() catch return false;

    if (!std.mem.eql(u8, changed, watcher_name)) {
        return false;
    }

    _ = reader.take_string() catch return false;

    const owner = reader.take_string() catch return false;

    return owner.len > 0;
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

    if (std.mem.eql(u8, header.member, "Activate")) {
        reply_empty(header.serial, header.sender);

        return .activate;
    }

    if (std.mem.eql(u8, header.member, "SecondaryActivate")) {
        reply_empty(header.serial, header.sender);

        return .secondary_activate;
    }

    if (std.mem.eql(u8, header.member, "ContextMenu")) {
        reply_empty(header.serial, header.sender);

        return .context_menu;
    }

    if (std.mem.eql(u8, header.member, "Scroll")) {
        reply_empty(header.serial, header.sender);

        return .ignored;
    }

    client.reply_error(header.serial, header.sender, client.error_unknown_method, header.member);

    return .ignored;
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
        reply_all(header.serial, header.sender);

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
    var writer = wire.Writer.init(&reply_storage);

    write_property(&writer, property) catch {
        client.reply_error(serial, sender, client.error_failed, property);

        return;
    };

    _ = client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = client.next_serial(),
        .signature = "v",
    }, writer.bytes()) catch return;
}

fn write_property(writer: *wire.Writer, property: []const u8) wire.Error!void {
    if (std.mem.eql(u8, property, "Category")) {
        try variant.put_string_variant(writer, "ApplicationStatus");

        return;
    }

    if (std.mem.eql(u8, property, "Id") or std.mem.eql(u8, property, "Title")) {
        try variant.put_string_variant(writer, runtime.app_name());

        return;
    }

    if (std.mem.eql(u8, property, "Status")) {
        try variant.put_string_variant(writer, "Active");

        return;
    }

    if (std.mem.eql(u8, property, "IconName")) {
        try variant.put_string_variant(writer, icon_theme_name());

        return;
    }

    if (std.mem.eql(u8, property, "IconPixmap")) {
        try writer.put_signature("a(iiay)");
        try write_pixmap(writer);

        return;
    }

    if (std.mem.eql(u8, property, "Menu")) {
        try variant.put_object_variant(writer, menu.object_path);

        return;
    }

    if (std.mem.eql(u8, property, "ItemIsMenu")) {
        try variant.put_bool_variant(writer, false);

        return;
    }

    if (std.mem.eql(u8, property, "ToolTip")) {
        try writer.put_signature("(sa(iiay)ss)");
        try writer.pad_to(wire.align_of(wire.code_struct));
        try writer.put_string(icon_theme_name());
        try variant.put_empty_array(writer, wire.align_of(wire.code_struct));
        try writer.put_string(current_tooltip());
        try writer.put_string("");

        return;
    }

    try variant.put_string_variant(writer, "");
}

fn reply_all(serial: u32, sender: []const u8) void {
    var writer = wire.Writer.init(&reply_storage);

    write_all(&writer) catch {
        client.reply_error(serial, sender, client.error_failed, "GetAll");

        return;
    };

    _ = client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = client.next_serial(),
        .signature = "a{sv}",
    }, writer.bytes()) catch return;
}

fn write_all(writer: *wire.Writer) wire.Error!void {
    const marker = try writer.open_array(wire.align_of(wire.code_dict_entry));

    var index: u32 = 0;

    while (index < property_names.len) : (index += 1) {
        assert(index < property_names.len);

        try writer.pad_to(wire.align_of(wire.code_dict_entry));
        try writer.put_string(property_names[index]);
        try write_property(writer, property_names[index]);
    }

    try writer.close_array(marker);
}

fn write_pixmap(writer: *wire.Writer) wire.Error!void {
    const handle = current_icon orelse {
        try variant.put_pixmap_array(writer, &.{}, 0, 0);

        return;
    };

    const source = icon_mod.get(handle) orelse {
        try variant.put_pixmap_array(writer, &.{}, 0, 0);

        return;
    };

    switch (source) {
        .pixels => |pixmap| try variant.put_pixmap_array(
            writer,
            pixmap.argb,
            pixmap.width,
            pixmap.height,
        ),
        else => try variant.put_pixmap_array(writer, &.{}, 0, 0),
    }
}

pub fn icon_theme_name() []const u8 {
    const handle = current_icon orelse return "";
    const source = icon_mod.get(handle) orelse return "";

    const result = switch (source) {
        .file_path => |path| path,
        .stock => |stock| icon_mod.theme_name(stock),
        else => "",
    };

    return result;
}

fn register() !void {
    const serial = client.next_serial();

    var storage: [256]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_string(client.name());

    _ = try client.send(.{
        .destination = watcher_name,
        .interface = watcher_name,
        .kind = .method_call,
        .member = "RegisterStatusNotifierItem",
        .path = watcher_path,
        .serial = serial,
        .signature = "s",
    }, writer.bytes());

    const reply = (try client.wait_for_reply(serial)) orelse return error.RegisterFailed;

    if (reply.header.kind != .method_return) {
        return error.RegisterFailed;
    }
}

fn emit(member: []const u8) void {
    if (!client.is_connected()) {
        return;
    }

    _ = client.send(.{
        .interface = interface_name,
        .kind = .signal,
        .member = member,
        .path = object_path,
        .serial = client.next_serial(),
    }, &.{}) catch return;
}

fn copy_tooltip(text: []const u8) void {
    assert(text.len < tooltip_bytes_max);

    @memcpy(tooltip[0..text.len], text);

    tooltip_len = @intCast(text.len);

    assert(tooltip_len < tooltip_bytes_max);
}

fn reply_empty(serial: u32, sender: []const u8) void {
    if (!client.is_connected()) {
        return;
    }

    _ = client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = client.next_serial(),
    }, &.{}) catch return;
}

fn reset() void {
    created = false;
    current_id = 0;
    current_icon = null;
    tooltip_len = 0;

    assert(!created);
}

const testing = std.testing;

test "create requires an open runtime" {
    reset();

    try testing.expectError(Error.RuntimeClosed, create(.{}));
}

test "set_icon and set_tooltip require a created tray" {
    reset();

    try testing.expectError(Error.NotCreated, set_icon(0));
    try testing.expectError(Error.NotCreated, set_tooltip("x"));
}

test "icon_theme_name is empty without an icon" {
    reset();

    try testing.expectEqualStrings("", icon_theme_name());
}

test "icon_theme_name maps a stock icon to a theme name" {
    reset();

    const handle = try icon_mod.load(.{ .stock = .shield });

    current_icon = handle;

    try testing.expectEqualStrings("security-high", icon_theme_name());

    icon_mod.destroy(handle);
    reset();
}

test "write_property marshals the documented properties" {
    reset();

    var storage: [reply_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try write_property(&writer, "Category");

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqualStrings("s", try reader.take_signature());
    try testing.expectEqualStrings("ApplicationStatus", try reader.take_string());
}

test "write_property falls back to an empty string" {
    reset();

    var storage: [reply_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try write_property(&writer, "Unknown");

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqualStrings("s", try reader.take_signature());
    try testing.expectEqualStrings("", try reader.take_string());
}

test "write_all marshals a non empty property dictionary" {
    reset();

    var storage: [reply_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try write_all(&writer);

    var reader = wire.Reader.init(writer.bytes());
    const length = try reader.take_u32();

    try testing.expect(length > 0);
}

fn contains_key(bytes: []const u8, key: []const u8) bool {
    assert(key.len > 0);

    var encoded: [64]u8 = undefined;

    if (key.len + 5 > encoded.len) {
        return false;
    }

    std.mem.writeInt(u32, encoded[0..4], @intCast(key.len), .little);
    @memcpy(encoded[4 .. 4 + key.len], key);

    encoded[4 + key.len] = 0;

    return std.mem.indexOf(u8, bytes, encoded[0 .. key.len + 5]) != null;
}

test "write_all advertises every property that write_property answers" {
    reset();

    var storage: [reply_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try write_all(&writer);

    const bytes = writer.bytes();

    var index: u32 = 0;

    while (index < property_names.len) : (index += 1) {
        assert(index < property_names.len);

        try testing.expect(contains_key(bytes, property_names[index]));
    }

    try testing.expect(!contains_key(bytes, "Absent"));
}

test "an oversized tooltip is an error rather than a truncation" {
    reset();

    const long = [_]u8{'a'} ** tooltip_bytes_max;

    try testing.expectError(Error.InvalidTooltip, create(.{ .tooltip = &long }));
    try testing.expectError(Error.NotCreated, set_tooltip(&long));
    try testing.expectEqual(@as(u32, 0), tooltip_len);
}
