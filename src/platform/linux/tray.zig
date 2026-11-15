const std = @import("std");

const Client = @import("dbus.zig").Client;
const IconTable = @import("icon_table.zig");
const interface = @import("../interface.zig");
const Menu = @import("menu.zig");
const variant = @import("dbus.zig").variant;
const wire = @import("dbus.zig").wire;

const assert = std.debug.assert;

const CreateOptions = interface.TrayCreateOptions;
const Icon = interface.Icon;
const PlatformError = interface.PlatformError;

const Tray = @This();

activation: [activation_token_bytes_max]u8,
activation_len: u32,
client: *Client,
created: bool,
icon_current: ?Icon,
icons: *const IconTable,
name: []const u8,
reply_storage: [reply_bytes_max]u8,
tooltip: [tooltip_bytes_max]u8,
tooltip_len: u32,

pub const ClaimError = error{
    MatchFailed,
    NameFailed,
};

pub const Outcome = enum {
    activate,
    context_menu,
    ignored,
    secondary_activate,
};

pub const interface_name = "org.kde.StatusNotifierItem";
pub const introspectable_interface = "org.freedesktop.DBus.Introspectable";
pub const object_path = "/StatusNotifierItem";
pub const properties_interface = "org.freedesktop.DBus.Properties";
pub const watcher_name = "org.kde.StatusNotifierWatcher";
pub const watcher_path = "/StatusNotifierWatcher";
pub const bus_interface = "org.freedesktop.DBus";
pub const owner_changed_member = "NameOwnerChanged";
pub const reply_bytes_overhead: u32 = 2 * 1024;
pub const bus_name_bytes_max: u32 = 128;
pub const instance_id_max: u32 = 32;

pub const watcher_match_rule = "type='signal'," ++
    "interface='org.freedesktop.DBus'," ++
    "member='NameOwnerChanged'," ++
    "arg0='" ++ watcher_name ++ "'";

pub const reply_bytes_max: u32 = interface.pixmap_bytes_max + reply_bytes_overhead;

const activation_token_bytes_max = interface.activation_token_bytes_max;
const tooltip_bytes_max = interface.tooltip_bytes_max;
const request_name_primary_owner: u32 = 1;
const request_name_in_queue: u32 = 2;
const request_name_exists: u32 = 3;
const request_name_already_owner: u32 = 4;

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

const introspection_preamble =
    \\<!DOCTYPE node PUBLIC "-//freedesktop//DTD D-BUS Object Introspection 1.0//EN"
    \\ "http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd">
    \\<node>
    \\  <interface name="org.freedesktop.DBus.Introspectable">
    \\    <method name="Introspect">
    \\      <arg name="xml_data" type="s" direction="out"/>
    \\    </method>
    \\  </interface>
;

const introspection_head =
    \\  <interface name="org.freedesktop.DBus.Properties">
    \\    <method name="Get">
    \\      <arg name="interface_name" type="s" direction="in"/>
    \\      <arg name="property_name" type="s" direction="in"/>
    \\      <arg name="value" type="v" direction="out"/>
    \\    </method>
    \\    <method name="GetAll">
    \\      <arg name="interface_name" type="s" direction="in"/>
    \\      <arg name="properties" type="a{sv}" direction="out"/>
    \\    </method>
    \\  </interface>
    \\  <interface name="org.kde.StatusNotifierItem">
    \\    <property name="Category" type="s" access="read"/>
    \\    <property name="IconName" type="s" access="read"/>
    \\    <property name="IconPixmap" type="a(iiay)" access="read"/>
    \\    <property name="Id" type="s" access="read"/>
    \\    <property name="ItemIsMenu" type="b" access="read"/>
    \\    <property name="Menu" type="o" access="read"/>
    \\    <property name="Status" type="s" access="read"/>
    \\    <property name="Title" type="s" access="read"/>
    \\    <property name="ToolTip" type="(sa(iiay)ss)" access="read"/>
    \\    <method name="ContextMenu">
    \\      <arg name="x" type="i" direction="in"/>
    \\      <arg name="y" type="i" direction="in"/>
    \\    </method>
;

const introspection_tail =
    \\    <method name="SecondaryActivate">
    \\      <arg name="x" type="i" direction="in"/>
    \\      <arg name="y" type="i" direction="in"/>
    \\    </method>
    \\    <method name="Scroll">
    \\      <arg name="delta" type="i" direction="in"/>
    \\      <arg name="orientation" type="s" direction="in"/>
    \\    </method>
    \\    <method name="ProvideXdgActivationToken">
    \\      <arg name="token" type="s" direction="in"/>
    \\    </method>
    \\    <signal name="NewIcon"/>
    \\    <signal name="NewToolTip"/>
    \\  </interface>
    \\</node>
    \\
;

const introspection_item = introspection_preamble ++ "\n" ++ introspection_head ++ "\n" ++
    introspection_tail;

const introspection_root = introspection_preamble ++ "\n" ++
    "  <node name=\"" ++ object_path[1..] ++ "\"/>\n</node>\n";

const introspection_bytes_max: u32 = introspection_item.len + 8;

comptime {
    assert(tooltip_bytes_max > 0);
    assert(reply_bytes_max > interface.pixmap_bytes_max);
    assert(reply_bytes_overhead >= 2 * interface.path_bytes_max + 2 * tooltip_bytes_max);
    assert(reply_bytes_max <= Client.send_bytes_max - Client.header_bytes_max);
    assert(property_names.len == 9);
    assert(introspection_root.len < introspection_item.len);
    assert(introspection_bytes_max <= Client.send_bytes_max - Client.header_bytes_max);
    assert(bus_name_bytes_max > interface.app_name_bytes_max);
    assert(instance_id_max > 0);
    assert(request_name_primary_owner < request_name_in_queue);
    assert(request_name_exists < request_name_already_owner);
    assert(std.mem.find(u8, watcher_match_rule, watcher_name) != null);
}

pub fn init(tray: *Tray, client: *Client, icons: *const IconTable, name: []const u8) void {
    assert(name.len <= interface.app_name_bytes_max);
    assert(interface.is_valid_text(name));

    tray.activation_len = 0;
    tray.client = client;
    tray.created = false;
    tray.icon_current = null;
    tray.icons = icons;
    tray.name = name;
    tray.tooltip_len = 0;

    assert(!tray.is_created());
    assert(tray.activation_token().len == 0);
}

pub fn claim(tray: *Tray) ClaimError!void {
    assert(tray.client.is_connected());
    assert(!tray.created);

    try tray.claim_name();
    try tray.watch_watcher();
}

fn build_bus_name(buffer: []u8, pid: u32, id: u32) ?[]const u8 {
    assert(buffer.len > 0);
    assert(pid > 0);
    assert(id >= 1);
    assert(id <= instance_id_max);

    const result = std.mem.print(
        buffer,
        "org.kde.StatusNotifierItem-{d}-{d}",
        .{ pid, id },
    ) catch return null;

    return result;
}

fn claim_name(tray: *Tray) ClaimError!void {
    const pid: u32 = @intCast(std.os.linux.getpid());

    var storage: [bus_name_bytes_max]u8 = undefined;
    var instance: u32 = 1;

    while (instance <= instance_id_max) : (instance += 1) {
        const chosen = build_bus_name(&storage, pid, instance) orelse
            return ClaimError.NameFailed;

        const code = try tray.request_name(chosen);

        switch (code) {
            request_name_primary_owner, request_name_already_owner => return,
            request_name_exists, request_name_in_queue => {},
            else => return ClaimError.NameFailed,
        }
    }

    return ClaimError.NameFailed;
}

fn request_name(tray: *Tray, chosen: []const u8) ClaimError!u32 {
    assert(std.mem.startsWith(u8, chosen, "org.kde.StatusNotifierItem-"));

    var storage: [256]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    writer.put_string(chosen) catch {
        return ClaimError.NameFailed;
    };

    writer.put_u32(0) catch {
        return ClaimError.NameFailed;
    };

    const serial = tray.client.next_serial();

    _ = tray.client.send(.{
        .destination = "org.freedesktop.DBus",
        .interface = "org.freedesktop.DBus",
        .kind = .method_call,
        .member = "RequestName",
        .path = "/org/freedesktop/DBus",
        .serial = serial,
        .signature = "su",
    }, writer.bytes()) catch {
        return ClaimError.NameFailed;
    };

    const message = tray.client.wait_for_reply(serial) catch {
        return ClaimError.NameFailed;
    };

    if (message.header.kind != .method_return) {
        return ClaimError.NameFailed;
    }

    var reader = wire.Reader.init(message.body);

    const code = reader.take_u32() catch {
        return ClaimError.NameFailed;
    };

    return code;
}

fn watch_watcher(tray: *Tray) ClaimError!void {
    var storage: [256]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    writer.put_string(watcher_match_rule) catch {
        return ClaimError.MatchFailed;
    };

    const serial = tray.client.next_serial();

    _ = tray.client.send(.{
        .destination = "org.freedesktop.DBus",
        .interface = "org.freedesktop.DBus",
        .kind = .method_call,
        .member = "AddMatch",
        .path = "/org/freedesktop/DBus",
        .serial = serial,
        .signature = "s",
    }, writer.bytes()) catch {
        return ClaimError.MatchFailed;
    };

    const message = tray.client.wait_for_reply(serial) catch {
        return ClaimError.MatchFailed;
    };

    if (message.header.kind != .method_return) {
        return ClaimError.MatchFailed;
    }
}

pub fn activation_clear(tray: *Tray) void {
    tray.activation_len = 0;

    assert(tray.activation_token().len == 0);
}

pub fn activation_token(tray: *const Tray) []const u8 {
    assert(tray.activation_len <= activation_token_bytes_max);

    return tray.activation[0..tray.activation_len];
}

pub fn create(tray: *Tray, options: CreateOptions) PlatformError!void {
    assert(!tray.created);
    assert(tray.client.is_connected());
    assert(options.tooltip.len <= tooltip_bytes_max);

    tray.icon_current = options.icon;

    tray.copy_tooltip(options.tooltip);

    tray.register() catch {
        return error.TrayCreateFailed;
    };

    tray.created = true;

    assert(tray.created);
}

pub fn destroy(tray: *Tray) void {
    if (!tray.created) {
        return;
    }

    tray.created = false;
    tray.icon_current = null;

    tray.activation_clear();

    assert(!tray.created);
}

pub fn is_created(tray: *const Tray) bool {
    return tray.created;
}

pub fn set_icon(tray: *Tray, icon: Icon) PlatformError!void {
    assert(tray.created);

    tray.icon_current = icon;

    tray.emit("NewIcon");
}

pub fn set_tooltip(tray: *Tray, text: []const u8) PlatformError!void {
    assert(tray.created);
    assert(text.len <= tooltip_bytes_max);

    tray.copy_tooltip(text);

    tray.emit("NewToolTip");
}

pub fn is_watcher_restart(message: Client.Message) bool {
    assert(message.body.len <= wire.body_bytes_max);

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

pub fn handle_call(tray: *Tray, message: Client.Message) Outcome {
    assert(message.header.kind == .method_call);

    const header = message.header;

    if (std.mem.eql(u8, header.interface, properties_interface)) {
        tray.handle_properties(message);

        return .ignored;
    }

    if (std.mem.eql(u8, header.interface, introspectable_interface)) {
        tray.reply_introspection(message);

        return .ignored;
    }

    if (!std.mem.eql(u8, header.interface, interface_name)) {
        tray.client.reply_error(
            header.serial,
            header.sender,
            Client.error_unknown_interface,
            header.interface,
        );

        return .ignored;
    }

    if (std.mem.eql(u8, header.member, "Activate")) {
        tray.reply_empty(header.serial, header.sender);

        return .activate;
    }

    if (std.mem.eql(u8, header.member, "SecondaryActivate")) {
        tray.reply_empty(header.serial, header.sender);

        return .secondary_activate;
    }

    if (std.mem.eql(u8, header.member, "ContextMenu")) {
        tray.reply_empty(header.serial, header.sender);

        return .context_menu;
    }

    if (std.mem.eql(u8, header.member, "ProvideXdgActivationToken")) {
        tray.provide_activation(message);

        return .ignored;
    }

    if (std.mem.eql(u8, header.member, "Scroll")) {
        tray.reply_empty(header.serial, header.sender);

        return .ignored;
    }

    tray.client.reply_error(
        header.serial,
        header.sender,
        Client.error_unknown_method,
        header.member,
    );

    return .ignored;
}

fn provide_activation(tray: *Tray, message: Client.Message) void {
    assert(std.mem.eql(u8, message.header.member, "ProvideXdgActivationToken"));

    const header = message.header;

    tray.activation_clear();

    const token = provide_activation_parse(message.body) orelse {
        tray.client.reply_error(
            header.serial,
            header.sender,
            Client.error_invalid_args,
            header.member,
        );

        return;
    };

    @memcpy(tray.activation[0..token.len], token);

    tray.activation_len = @intCast(token.len);

    assert(std.mem.eql(u8, tray.activation_token(), token));

    tray.reply_empty(header.serial, header.sender);
}

fn provide_activation_parse(body: []const u8) ?[]const u8 {
    assert(body.len <= Client.receive_bytes_max);

    var reader = wire.Reader.init(body);

    const token = reader.take_string() catch return null;
    if (token.len > activation_token_bytes_max) return null;
    if (!interface.is_valid_text(token)) return null;

    assert(token.len <= activation_token_bytes_max);

    return token;
}

fn reply_introspection(tray: *Tray, message: Client.Message) void {
    assert(std.mem.eql(u8, message.header.interface, introspectable_interface));
    assert(message.header.serial != 0);

    const header = message.header;

    if (!std.mem.eql(u8, header.member, "Introspect")) {
        tray.client.reply_error(
            header.serial,
            header.sender,
            Client.error_unknown_method,
            header.member,
        );

        return;
    }

    const document = introspection_of(header.path) orelse {
        tray.client.reply_error(
            header.serial,
            header.sender,
            Client.error_unknown_object,
            header.path,
        );

        return;
    };

    var storage: [introspection_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    writer.put_string(document) catch return;

    _ = tray.client.send(.{
        .destination = header.sender,
        .kind = .method_return,
        .reply_serial = header.serial,
        .serial = tray.client.next_serial(),
        .signature = "s",
    }, writer.bytes()) catch return;
}

fn introspection_of(path: []const u8) ?[]const u8 {
    assert(path.len <= wire.string_bytes_max);

    if (std.mem.eql(u8, path, object_path)) return introspection_item;
    if (std.mem.eql(u8, path, "/")) return introspection_root;

    return null;
}

fn tooltip_current(tray: *const Tray) []const u8 {
    assert(tray.tooltip_len <= tooltip_bytes_max);

    return tray.tooltip[0..tray.tooltip_len];
}

fn handle_properties(tray: *Tray, message: Client.Message) void {
    assert(std.mem.eql(u8, message.header.interface, properties_interface));

    const header = message.header;

    var reader = wire.Reader.init(message.body);

    const target = reader.take_string() catch {
        tray.client.reply_error(
            header.serial,
            header.sender,
            Client.error_invalid_args,
            header.member,
        );

        return;
    };

    if (!std.mem.eql(u8, target, interface_name)) {
        tray.client.reply_error(
            header.serial,
            header.sender,
            Client.error_unknown_interface,
            target,
        );

        return;
    }

    if (std.mem.eql(u8, header.member, "GetAll")) {
        tray.reply_all(header.serial, header.sender);

        return;
    }

    if (!std.mem.eql(u8, header.member, "Get")) {
        tray.client.reply_error(
            header.serial,
            header.sender,
            Client.error_unknown_method,
            header.member,
        );

        return;
    }

    const property = reader.take_string() catch {
        tray.client.reply_error(
            header.serial,
            header.sender,
            Client.error_invalid_args,
            header.member,
        );

        return;
    };

    tray.reply_property(header.serial, header.sender, property);
}

fn reply_property(tray: *Tray, serial: u32, sender: []const u8, property: []const u8) void {
    assert(serial != 0);
    assert(sender.len <= wire.string_bytes_max);
    assert(property.len <= wire.string_bytes_max);

    var writer = wire.Writer.init(&tray.reply_storage);

    tray.write_property(&writer, property) catch {
        tray.client.reply_error(serial, sender, Client.error_failed, property);

        return;
    };

    _ = tray.client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = tray.client.next_serial(),
        .signature = "v",
    }, writer.bytes()) catch return;
}

fn write_property(tray: *const Tray, writer: *wire.Writer, property: []const u8) wire.Error!void {
    assert(property.len <= wire.string_bytes_max);

    if (std.mem.eql(u8, property, "Category")) {
        try variant.put_string(writer, "ApplicationStatus");

        return;
    }

    if (std.mem.eql(u8, property, "Id")) {
        try variant.put_string(writer, tray.name);

        return;
    }

    if (std.mem.eql(u8, property, "Title")) {
        try variant.put_string(writer, tray.name);

        return;
    }

    if (std.mem.eql(u8, property, "Status")) {
        try variant.put_string(writer, "Active");

        return;
    }

    if (std.mem.eql(u8, property, "IconName")) {
        try variant.put_string(writer, tray.icon_theme_name());

        return;
    }

    if (std.mem.eql(u8, property, "IconPixmap")) {
        try writer.put_signature("a(iiay)");
        try tray.write_pixmap(writer);

        return;
    }

    if (std.mem.eql(u8, property, "Menu")) {
        try variant.put_object(writer, Menu.object_path);

        return;
    }

    if (std.mem.eql(u8, property, "ItemIsMenu")) {
        try variant.put_bool(writer, true);

        return;
    }

    if (std.mem.eql(u8, property, "ToolTip")) {
        try writer.put_signature("(sa(iiay)ss)");
        try writer.pad_to(wire.align_of(wire.code_struct));
        try writer.put_string(tray.icon_theme_name());
        try variant.put_empty_array(writer, wire.align_of(wire.code_struct));
        try writer.put_string(tray.tooltip_current());
        try writer.put_string("");

        return;
    }

    try variant.put_string(writer, "");
}

fn reply_all(tray: *Tray, serial: u32, sender: []const u8) void {
    assert(serial != 0);
    assert(sender.len <= wire.string_bytes_max);

    var writer = wire.Writer.init(&tray.reply_storage);

    tray.write_all(&writer) catch {
        tray.client.reply_error(serial, sender, Client.error_failed, "GetAll");

        return;
    };

    _ = tray.client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = tray.client.next_serial(),
        .signature = "a{sv}",
    }, writer.bytes()) catch return;
}

fn write_all(tray: *const Tray, writer: *wire.Writer) wire.Error!void {
    const marker = try writer.open_array(wire.align_of(wire.code_dict_entry));

    var index: u32 = 0;

    while (index < property_names.len) : (index += 1) {
        assert(index < property_names.len);

        try writer.pad_to(wire.align_of(wire.code_dict_entry));
        try writer.put_string(property_names[index]);
        try tray.write_property(writer, property_names[index]);
    }

    try writer.close_array(marker);
}

fn write_pixmap(tray: *const Tray, writer: *wire.Writer) wire.Error!void {
    const icon = tray.icon_current orelse {
        try variant.put_pixmap_array(writer, &.{}, 0, 0);

        return;
    };

    const source = tray.icons.get(icon) orelse {
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
        .file_path, .stock => try variant.put_pixmap_array(writer, &.{}, 0, 0),
    }
}

fn icon_theme_name(tray: *const Tray) []const u8 {
    const icon = tray.icon_current orelse return "";
    const source = tray.icons.get(icon) orelse return "";

    const result = switch (source) {
        .file_path => |path| path,
        .pixels => "",
        .stock => |stock| IconTable.theme_name(stock),
    };

    return result;
}

fn register(tray: *Tray) !void {
    const serial = tray.client.next_serial();

    var storage: [256]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try writer.put_string(tray.client.name());

    _ = try tray.client.send(.{
        .destination = watcher_name,
        .interface = watcher_name,
        .kind = .method_call,
        .member = "RegisterStatusNotifierItem",
        .path = watcher_path,
        .serial = serial,
        .signature = "s",
    }, writer.bytes());

    const reply = try tray.client.wait_for_reply(serial);

    if (reply.header.kind != .method_return) {
        return error.RegisterFailed;
    }
}

fn emit(tray: *Tray, member: []const u8) void {
    assert(std.mem.startsWith(u8, member, "New"));

    if (!tray.client.is_connected()) {
        return;
    }

    _ = tray.client.send(.{
        .interface = interface_name,
        .kind = .signal,
        .member = member,
        .path = object_path,
        .serial = tray.client.next_serial(),
    }, &.{}) catch return;
}

fn copy_tooltip(tray: *Tray, text: []const u8) void {
    assert(text.len <= tooltip_bytes_max);

    @memcpy(tray.tooltip[0..text.len], text);

    tray.tooltip_len = @intCast(text.len);

    assert(tray.tooltip_len <= tooltip_bytes_max);
}

fn reply_empty(tray: *Tray, serial: u32, sender: []const u8) void {
    assert(serial != 0);
    assert(sender.len <= wire.string_bytes_max);

    if (!tray.client.is_connected()) {
        return;
    }

    _ = tray.client.send(.{
        .destination = sender,
        .kind = .method_return,
        .reply_serial = serial,
        .serial = tray.client.next_serial(),
    }, &.{}) catch return;
}

const testing = std.testing;

const Fixture = struct {
    client: Client,
    icons: IconTable,
    tray: Tray,

    fn create() !*Fixture {
        const fixture = try testing.allocator.create(Fixture);

        fixture.client.init();
        fixture.icons.init();
        fixture.tray.init(&fixture.client, &fixture.icons, "umbra");

        assert(!fixture.client.is_connected());
        assert(!fixture.tray.is_created());

        return fixture;
    }

    fn destroy(fixture: *Fixture) void {
        assert(!fixture.client.is_connected());

        testing.allocator.destroy(fixture);
    }
};

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

test "icon_theme_name is empty without an icon" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;

    try testing.expectEqualStrings("", tray.icon_theme_name());
}

test "icon_theme_name maps a stock icon to a theme name" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;
    const icon = try fixture.icons.load(.{ .stock = .shield });

    tray.icon_current = icon;

    try testing.expectEqualStrings("security-high", tray.icon_theme_name());

    fixture.icons.destroy(icon);
}

test "write_property marshals the documented properties" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;

    var storage: [reply_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try tray.write_property(&writer, "Category");

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqualStrings("s", try reader.take_signature());
    try testing.expectEqualStrings("ApplicationStatus", try reader.take_string());
}

test "write_property falls back to an empty string" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;

    var storage: [reply_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try tray.write_property(&writer, "Unknown");

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqualStrings("s", try reader.take_signature());
    try testing.expectEqualStrings("", try reader.take_string());
}

test "write_all marshals a non empty property dictionary" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;

    var storage: [reply_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try tray.write_all(&writer);

    var reader = wire.Reader.init(writer.bytes());
    const length = try reader.take_u32();

    try testing.expect(length > 0);
}

fn contains_key(bytes: []const u8, key: []const u8) bool {
    assert(bytes.len <= wire.body_bytes_max);
    assert(key.len > 0);

    var encoded: [64]u8 = undefined;

    if (key.len + 5 > encoded.len) {
        return false;
    }

    std.mem.writeInt(u32, encoded[0..4], @intCast(key.len), .little);
    @memcpy(encoded[4 .. 4 + key.len], key);

    encoded[4 + key.len] = 0;

    return std.mem.find(u8, bytes, encoded[0 .. key.len + 5]) != null;
}

test "write_all advertises every property that write_property answers" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;

    var storage: [reply_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try tray.write_all(&writer);

    const bytes = writer.bytes();

    var index: u32 = 0;

    while (index < property_names.len) : (index += 1) {
        assert(index < property_names.len);

        try testing.expect(contains_key(bytes, property_names[index]));
    }

    try testing.expect(!contains_key(bytes, "Absent"));
}

test "the tooltip holds the full bound" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;
    const longest: [tooltip_bytes_max]u8 = @splat('a');

    tray.copy_tooltip(&longest);

    try testing.expectEqualStrings(&longest, tray.tooltip_current());
}

test "introspection advertises no activation so a host opens the menu on the first click" {
    const item = "<interface name=\"" ++ interface_name ++ "\">";

    try testing.expect(std.mem.find(u8, introspection_item, "\"Activate\"") == null);
    try testing.expect(std.mem.find(u8, introspection_item, item) != null);
}

test "introspection describes each property and method the item answers" {
    const methods = [_][]const u8{
        "ContextMenu",
        "ProvideXdgActivationToken",
        "Scroll",
        "SecondaryActivate",
    };

    for (property_names) |name| {
        var buffer: [64]u8 = undefined;
        const tag = try std.mem.print(&buffer, "<property name=\"{s}\"", .{name});

        try testing.expect(std.mem.find(u8, introspection_item, tag) != null);
    }

    for (methods) |name| {
        var buffer: [64]u8 = undefined;
        const tag = try std.mem.print(&buffer, "<method name=\"{s}\">", .{name});

        try testing.expect(std.mem.find(u8, introspection_item, tag) != null);
    }

    const opened = std.mem.count(u8, introspection_item, "<method ");
    const closed = std.mem.count(u8, introspection_item, "</method>");

    try testing.expectEqual(opened, closed);
    try testing.expect(std.mem.endsWith(u8, introspection_item, "</node>\n"));
}

test "the item reports itself as a menu" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;

    var storage: [reply_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try tray.write_property(&writer, "ItemIsMenu");

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqualStrings("b", try reader.take_signature());
    try testing.expectEqual(@as(u32, 1), try reader.take_u32());
}

test "introspection describes the item only at its own path and the root only leads to it" {
    const item = "<interface name=\"" ++ interface_name ++ "\">";
    const root = introspection_of("/") orelse return error.RootMissing;

    try testing.expect(std.mem.find(u8, root, item) == null);
    try testing.expect(std.mem.find(u8, root, "<node name=\"StatusNotifierItem\"/>") != null);
    try testing.expect(std.mem.endsWith(u8, root, "</node>\n"));
    try testing.expectEqualStrings(introspection_item, introspection_of(object_path).?);
    try testing.expect(introspection_of(Menu.object_path) == null);
    try testing.expect(introspection_of(object_path ++ "/child") == null);
}

test "the item answers introspection and refuses any other introspectable member" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;

    var introspect = method_call("Introspect", &.{});
    var unknown = method_call("Describe", &.{});

    introspect.header.interface = introspectable_interface;
    unknown.header.interface = introspectable_interface;

    try testing.expectEqual(Outcome.ignored, tray.handle_call(introspect));
    try testing.expectEqual(Outcome.ignored, tray.handle_call(unknown));
}

fn method_call(member: []const u8, body: []const u8) Client.Message {
    assert(member.len > 0);
    assert(body.len <= Client.receive_bytes_max);

    var header = wire.Header.empty();

    header.body_length = @intCast(body.len);
    header.interface = interface_name;
    header.kind = .method_call;
    header.member = member;
    header.path = object_path;
    header.serial = 1;

    return .{ .body = body, .header = header };
}

fn provide(tray: *Tray, storage: []u8, token: []const u8) !Outcome {
    assert(storage.len >= token.len + 5);

    var writer = wire.Writer.init(storage);

    try writer.put_string(token);

    return tray.handle_call(method_call("ProvideXdgActivationToken", writer.bytes()));
}

test "a tray host's activation token is held until it is cleared" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;
    const token = "gnome-shell/Solopass/2541-0-fedora_TIME51234";

    var storage: [activation_token_bytes_max + 8]u8 = undefined;

    try testing.expectEqual(Outcome.ignored, try provide(tray, &storage, token));
    try testing.expectEqualStrings(token, tray.activation_token());

    tray.activation_clear();

    try testing.expectEqualStrings("", tray.activation_token());

    const longest: [activation_token_bytes_max]u8 = @splat('t');

    _ = try provide(tray, &storage, &longest);

    try testing.expectEqualStrings(&longest, tray.activation_token());

    tray.created = true;

    tray.destroy();

    try testing.expectEqualStrings("", tray.activation_token());
}

test "a refused activation token drops the one held before it" {
    const fixture = try Fixture.create();
    defer fixture.destroy();

    const tray = &fixture.tray;
    const token = "kwin-17";
    const long: [activation_token_bytes_max + 1]u8 = @splat('t');
    const malformed = [_]u8{ 0xFF, 0xFF, 0xFF, 0x7F, 'a' };

    var storage: [activation_token_bytes_max + 8]u8 = undefined;

    _ = try provide(tray, &storage, token);
    _ = try provide(tray, &storage, &long);

    try testing.expectEqualStrings("", tray.activation_token());

    _ = try provide(tray, &storage, token);
    _ = try provide(tray, &storage, "a\x00b");

    try testing.expectEqualStrings("", tray.activation_token());

    _ = try provide(tray, &storage, token);
    _ = tray.handle_call(method_call("ProvideXdgActivationToken", &malformed));

    try testing.expectEqualStrings("", tray.activation_token());
}
