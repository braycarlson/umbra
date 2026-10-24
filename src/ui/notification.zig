const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.notification;

const CapacityError = platform.CapacityError;
const PlatformError = platform.PlatformError;
const RequestError = platform.RequestError;

pub const Notifier = struct {
    sent: u32,

    pub const Notification = platform.Notification;

    pub fn init() Notifier {
        const result = Notifier{ .sent = 0 };

        assert(result.sent == 0);

        return result;
    }

    pub fn deinit(notifier: *Notifier) void {
        notifier.sent = 0;

        assert(notifier.sent == 0);
    }

    pub fn send(
        notifier: *Notifier,
        notification: Notification,
    ) (CapacityError || PlatformError || RequestError)!void {
        try notification.validate();
        try backend.send(notification);

        notifier.sent += 1;

        assert(notifier.sent > 0);
    }

    pub fn sent_count(notifier: *const Notifier) u32 {
        return notifier.sent;
    }
};

const testing = std.testing;

test Notifier {
    var notifier = Notifier.init();
    defer notifier.deinit();

    try notifier.send(.{ .body = "Application is running", .title = "Started" });
    try notifier.send(.{ .body = "Disk almost full", .kind = .warning, .title = "Storage" });

    try testing.expectEqual(@as(u32, 2), notifier.sent_count());
}

test "a refused notification is not counted as sent" {
    var notifier = Notifier.init();
    defer notifier.deinit();

    try testing.expectError(error.TitleEmpty, notifier.send(.{ .body = "Body", .title = "" }));
    try testing.expectError(error.BodyInvalid, notifier.send(.{ .body = "\xFF", .title = "t" }));
    try testing.expectEqual(@as(u32, 0), notifier.sent_count());
}
