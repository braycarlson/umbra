const std = @import("std");

const contract = @import("../contract.zig");
const fault = @import("fault.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

const Notification = contract.Notification;
const PlatformError = contract.PlatformError;

pub const sent_max: u32 = 16;

comptime {
    assert(sent_max > 0);
    assert(contract.notification_body_bytes_max <= record.text_bytes_max);
}

const Entry = struct {
    body: record.Text,
    kind: Notification.Kind,
    silent: bool,
    title: record.Text,
};

var entries: [sent_max]Entry = undefined;
var count: u32 = 0;
var send_count: u32 = 0;

pub fn send(notification: Notification) PlatformError!void {
    assert(notification.is_valid());

    if (fault.is_armed(.notification_send)) {
        return error.NotificationFailed;
    }

    send_count += 1;

    if (count == sent_max) {
        return;
    }

    entries[count] = .{
        .body = record.Text.empty(),
        .kind = notification.kind,
        .silent = notification.silent,
        .title = record.Text.empty(),
    };

    entries[count].title.set(notification.title);
    entries[count].body.set(notification.body);

    count += 1;

    assert(count <= sent_max);
}

pub fn sent_count() u32 {
    return send_count;
}

pub fn recorded_count() u32 {
    assert(count <= sent_max);

    return count;
}

pub fn title_at(index: u32) []const u8 {
    if (index >= count) {
        return "";
    }

    return entries[index].title.get();
}

pub fn body_at(index: u32) []const u8 {
    if (index >= count) {
        return "";
    }

    return entries[index].body.get();
}

pub fn kind_at(index: u32) ?Notification.Kind {
    if (index >= count) {
        return null;
    }

    return entries[index].kind;
}

pub fn reset() void {
    count = 0;
    send_count = 0;

    assert(count == 0);
    assert(send_count == 0);
}

const testing = std.testing;

test "send records the notification" {
    reset();

    try send(.{ .body = "Body", .kind = .warning, .title = "Title" });

    try testing.expectEqual(@as(u32, 1), sent_count());
    try testing.expectEqualStrings("Title", title_at(0));
    try testing.expectEqualStrings("Body", body_at(0));
    try testing.expectEqual(Notification.Kind.warning, kind_at(0).?);
}

test "send honors the injected failure" {
    reset();
    fault.reset();
    fault.arm(.notification_send);
    defer fault.reset();

    try testing.expectError(error.NotificationFailed, send(.{ .body = "b", .title = "t" }));
    try testing.expectEqual(@as(u32, 0), sent_count());
}

test "send keeps counting past the recording capacity" {
    reset();

    var index: u32 = 0;

    while (index < sent_max + 2) : (index += 1) {
        try send(.{ .body = "b", .title = "t" });
    }

    try testing.expectEqual(sent_max + 2, sent_count());
    try testing.expectEqual(sent_max, recorded_count());
}
