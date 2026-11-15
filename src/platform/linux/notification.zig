const std = @import("std");

const Client = @import("dbus.zig").Client;
const IconTable = @import("icon_table.zig");
const interface = @import("../interface.zig");
const variant = @import("dbus.zig").variant;
const wire = @import("dbus.zig").wire;

const assert = std.debug.assert;

const Icon = interface.Icon;
const Notification = interface.Notification;
const PlatformError = interface.PlatformError;

pub const service_name = "org.freedesktop.Notifications";
pub const service_path = "/org/freedesktop/Notifications";
pub const timeout_default: i32 = -1;
const message_bytes_max: u32 = 2 * 1024;

comptime {
    assert(timeout_default == -1);

    assert(message_bytes_max > interface.app_name_bytes_max +
        interface.notification_title_bytes_max +
        interface.notification_body_bytes_max);
}

pub fn send(client: *Client, name: []const u8, notification: Notification) PlatformError!void {
    assert(notification.is_valid());
    assert(name.len <= interface.app_name_bytes_max);

    if (!client.is_connected()) {
        return error.NotificationFailed;
    }

    var storage: [message_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    write_body(&writer, name, notification) catch {
        return error.NotificationFailed;
    };

    _ = client.send(.{
        .destination = service_name,
        .interface = service_name,
        .kind = .method_call,
        .member = "Notify",
        .path = service_path,
        .serial = client.next_serial(),
        .signature = "susssasa{sv}i",
    }, writer.bytes()) catch {
        return error.NotificationFailed;
    };
}

fn write_body(writer: *wire.Writer, name: []const u8, notification: Notification) wire.Error!void {
    assert(notification.is_valid());
    assert(name.len <= interface.app_name_bytes_max);

    try writer.put_string(name);
    try writer.put_u32(0);
    try writer.put_string(IconTable.theme_name(to_stock(notification.kind)));
    try writer.put_string(notification.title);
    try writer.put_string(notification.body);

    try variant.put_empty_array(writer, wire.align_of(wire.code_string));

    const hints = try writer.open_array(wire.align_of(wire.code_dict_entry));

    if (notification.silent) {
        try variant.put_dict_entry_bool(writer, "suppress-sound", true);
    }

    try variant.put_dict_entry_string(writer, "urgency-name", urgency_name(notification.kind));
    try writer.close_array(hints);

    try writer.put_i32(timeout_default);
}

fn to_stock(kind: Notification.Kind) Icon.Stock {
    const result = switch (kind) {
        .err => Icon.Stock.err,
        .info => Icon.Stock.information,
        .none => Icon.Stock.application,
        .warning => Icon.Stock.warning,
    };

    return result;
}

fn urgency_name(kind: Notification.Kind) []const u8 {
    const result = switch (kind) {
        .err => "critical",
        .info, .none => "normal",
        .warning => "normal",
    };

    assert(result.len > 0);

    return result;
}

const testing = std.testing;

test "send requires a live connection" {
    const client = try testing.allocator.create(Client);
    defer testing.allocator.destroy(client);

    client.init();

    const sent = send(client, "umbra", .{ .body = "b", .title = "t" });

    try testing.expectError(error.NotificationFailed, sent);
}

test "to_stock maps every notification kind" {
    try testing.expectEqual(Icon.Stock.err, to_stock(.err));
    try testing.expectEqual(Icon.Stock.information, to_stock(.info));
    try testing.expectEqual(Icon.Stock.application, to_stock(.none));
    try testing.expectEqual(Icon.Stock.warning, to_stock(.warning));
}

test "urgency_name marks errors critical" {
    try testing.expectEqualStrings("critical", urgency_name(.err));
    try testing.expectEqualStrings("normal", urgency_name(.info));
    try testing.expectEqualStrings("normal", urgency_name(.none));
    try testing.expectEqualStrings("normal", urgency_name(.warning));
}

test "write_body marshals the Notify arguments in order" {
    var storage: [message_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try write_body(&writer, "umbra", .{ .body = "Body", .kind = .err, .title = "Title" });

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqualStrings("umbra", try reader.take_string());

    try testing.expectEqual(@as(u32, 0), try reader.take_u32());
    try testing.expectEqualStrings("dialog-error", try reader.take_string());
    try testing.expectEqualStrings("Title", try reader.take_string());
    try testing.expectEqualStrings("Body", try reader.take_string());
}

test "a notification at every bound fits the message buffer" {
    const title: [interface.notification_title_bytes_max]u8 = @splat('t');
    const body: [interface.notification_body_bytes_max]u8 = @splat('b');
    const name: [interface.app_name_bytes_max]u8 = @splat('n');

    var storage: [message_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try write_body(&writer, &name, .{
        .body = &body,
        .kind = .warning,
        .silent = true,
        .title = &title,
    });

    try testing.expect(writer.bytes().len <= message_bytes_max);
}
