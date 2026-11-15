const std = @import("std");

const interface = @import("../interface.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

const Notification = interface.Notification;

const Notifier = @This();

count: u32,
entries: [sent_max]Entry,
send_count: u32,

const Entry = struct {
    body: record.Text,
    kind: Notification.Kind,
    silent: bool,
    title: record.Text,
};

pub const sent_max: u32 = 16;

comptime {
    assert(sent_max > 0);
    assert(interface.notification_body_bytes_max <= record.text_bytes_max);
}

pub fn init(notifier: *Notifier) void {
    notifier.count = 0;
    notifier.entries = undefined;
    notifier.send_count = 0;

    assert(notifier.recorded_count() == 0);
    assert(notifier.sent_count() == 0);
}

pub fn send(notifier: *Notifier, notification: Notification) void {
    assert(notification.is_valid());
    assert(notifier.count <= sent_max);

    notifier.send_count += 1;

    if (notifier.count == sent_max) {
        return;
    }

    notifier.entries[notifier.count] = .{
        .body = record.Text.empty(),
        .kind = notification.kind,
        .silent = notification.silent,
        .title = record.Text.empty(),
    };

    notifier.entries[notifier.count].title.set(notification.title);
    notifier.entries[notifier.count].body.set(notification.body);

    notifier.count += 1;

    assert(notifier.count <= sent_max);
}

pub fn sent_count(notifier: *const Notifier) u32 {
    return notifier.send_count;
}

pub fn recorded_count(notifier: *const Notifier) u32 {
    assert(notifier.count <= sent_max);

    return notifier.count;
}

pub fn title_at(notifier: *const Notifier, index: u32) []const u8 {
    assert(index < notifier.count);

    return notifier.entries[index].title.get();
}

pub fn body_at(notifier: *const Notifier, index: u32) []const u8 {
    assert(index < notifier.count);

    return notifier.entries[index].body.get();
}

pub fn kind_at(notifier: *const Notifier, index: u32) ?Notification.Kind {
    if (index >= notifier.count) {
        return null;
    }

    return notifier.entries[index].kind;
}

const testing = std.testing;

test "send records the notification" {
    var notifier: Notifier = undefined;

    notifier.init();
    notifier.send(.{ .body = "Body", .kind = .warning, .title = "Title" });

    try testing.expectEqual(@as(u32, 1), notifier.sent_count());
    try testing.expectEqualStrings("Title", notifier.title_at(0));
    try testing.expectEqualStrings("Body", notifier.body_at(0));
    try testing.expectEqual(Notification.Kind.warning, notifier.kind_at(0).?);
}

test "send keeps counting past the recording capacity" {
    var notifier: Notifier = undefined;

    notifier.init();

    var index: u32 = 0;

    while (index < sent_max + 2) : (index += 1) {
        notifier.send(.{ .body = "b", .title = "t" });
    }

    try testing.expectEqual(sent_max + 2, notifier.sent_count());
    try testing.expectEqual(sent_max, notifier.recorded_count());
}
