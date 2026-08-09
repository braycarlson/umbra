const std = @import("std");

const contract = @import("../contract.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

pub const Error = contract.NotificationError;

pub const Options = contract.NotificationOptions;

pub const sent_max: u32 = 16;

comptime {
    assert(sent_max > 0);
}

const Entry = struct {
    body: record.Text,
    kind: contract.NotificationKind,
    silent: bool,
    title: record.Text,
};

var entries: [sent_max]Entry = undefined;
var count: u32 = 0;
var send_count: u32 = 0;
var fail_send: bool = false;

pub fn send(options: Options) Error!void {
    if (!options.is_valid()) {
        return Error.InvalidNotification;
    }

    if (fail_send) {
        return Error.SendFailed;
    }

    send_count += 1;

    if (count >= sent_max) {
        return;
    }

    assert(count < sent_max);

    entries[count] = .{
        .body = record.Text.empty(),
        .kind = options.kind,
        .silent = options.silent,
        .title = record.Text.empty(),
    };

    entries[count].title.set(options.title);
    entries[count].body.set(options.body);

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

pub fn kind_at(index: u32) ?contract.NotificationKind {
    if (index >= count) {
        return null;
    }

    return entries[index].kind;
}

pub fn set_fail_send(fail: bool) void {
    fail_send = fail;

    assert(fail_send == fail);
}

pub fn reset() void {
    count = 0;
    send_count = 0;
    fail_send = false;

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
    try testing.expectEqual(contract.NotificationKind.warning, kind_at(0).?);
}

test "send rejects an incomplete notification" {
    reset();

    try testing.expectError(Error.InvalidNotification, send(.{ .body = "", .title = "t" }));
}

test "send honors the injected failure" {
    reset();
    set_fail_send(true);

    try testing.expectError(Error.SendFailed, send(.{ .body = "b", .title = "t" }));
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
