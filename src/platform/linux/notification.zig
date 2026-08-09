const std = @import("std");

const client = @import("dbus/client.zig");
const contract = @import("../contract.zig");
const icon_mod = @import("icon.zig");
const runtime = @import("runtime.zig");
const variant = @import("dbus/variant.zig");
const wire = @import("dbus/wire.zig");

const assert = std.debug.assert;

pub const Error = contract.NotificationError;

pub const Options = contract.NotificationOptions;

pub const service_name = "org.freedesktop.Notifications";
pub const service_path = "/org/freedesktop/Notifications";
pub const body_bytes_max: u32 = 2 * 1024;
pub const timeout_default: i32 = -1;

comptime {
    assert(body_bytes_max > 256);
    assert(timeout_default == -1);
}

var body_storage: [body_bytes_max]u8 = undefined;

pub fn send(options: Options) Error!void {
    if (!options.is_valid()) {
        return Error.InvalidNotification;
    }

    if (!client.is_connected()) {
        return Error.SendFailed;
    }

    var writer = wire.Writer.init(&body_storage);

    write_body(&writer, options) catch {
        return Error.SendFailed;
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
        return Error.SendFailed;
    };
}

fn write_body(writer: *wire.Writer, options: Options) wire.Error!void {
    try writer.put_string(runtime.app_name());
    try writer.put_u32(0);
    try writer.put_string(icon_mod.theme_name(to_stock(options.kind)));
    try writer.put_string(options.title);
    try writer.put_string(options.body);

    try variant.put_empty_array(writer, wire.align_of(wire.code_string));

    const hints = try writer.open_array(wire.align_of(wire.code_dict_entry));

    if (options.silent) {
        try variant.put_dict_entry_bool(writer, "suppress-sound", true);
    }

    try variant.put_dict_entry_string(writer, "urgency-name", urgency_name(options.kind));
    try writer.close_array(hints);

    try writer.put_i32(timeout_default);
}

fn to_stock(kind: contract.NotificationKind) contract.Stock {
    const result = switch (kind) {
        .err => contract.Stock.err,
        .info => contract.Stock.information,
        .none => contract.Stock.application,
        .warning => contract.Stock.warning,
    };

    return result;
}

fn urgency_name(kind: contract.NotificationKind) []const u8 {
    const result = switch (kind) {
        .err => "critical",
        .info, .none => "normal",
        .warning => "normal",
    };

    assert(result.len > 0);

    return result;
}

const testing = std.testing;

test "send rejects an incomplete notification" {
    try testing.expectError(Error.InvalidNotification, send(.{ .body = "", .title = "t" }));
    try testing.expectError(Error.InvalidNotification, send(.{ .body = "b", .title = "" }));
}

test "send requires a live connection" {
    if (client.is_connected()) {
        return;
    }

    try testing.expectError(Error.SendFailed, send(.{ .body = "b", .title = "t" }));
}

test "to_stock maps every notification kind" {
    try testing.expectEqual(contract.Stock.err, to_stock(.err));
    try testing.expectEqual(contract.Stock.information, to_stock(.info));
    try testing.expectEqual(contract.Stock.application, to_stock(.none));
    try testing.expectEqual(contract.Stock.warning, to_stock(.warning));
}

test "urgency_name marks errors critical" {
    try testing.expectEqualStrings("critical", urgency_name(.err));
    try testing.expectEqualStrings("normal", urgency_name(.info));
    try testing.expectEqualStrings("normal", urgency_name(.none));
    try testing.expectEqualStrings("normal", urgency_name(.warning));
}

test "write_body marshals the Notify arguments in order" {
    var storage: [body_bytes_max]u8 = undefined;
    var writer = wire.Writer.init(&storage);

    try write_body(&writer, .{ .body = "Body", .kind = .err, .title = "Title" });

    var reader = wire.Reader.init(writer.bytes());

    _ = try reader.take_string();

    try testing.expectEqual(@as(u32, 0), try reader.take_u32());
    try testing.expectEqualStrings("dialog-error", try reader.take_string());
    try testing.expectEqualStrings("Title", try reader.take_string());
    try testing.expectEqualStrings("Body", try reader.take_string());
}
