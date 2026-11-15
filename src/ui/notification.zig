const std = @import("std");

const platform_module = @import("../platform.zig");

const assert = std.debug.assert;

const CapacityError = platform_module.CapacityError;
const PlatformError = platform_module.PlatformError;
const RequestError = platform_module.RequestError;

pub fn NotifierType(comptime Platform: type) type {
    return struct {
        platform: *Platform,
        sent: u32,

        const Notifier = @This();

        pub const Notification = platform_module.Notification;

        pub fn init(platform: *Platform) Notifier {
            const result = Notifier{ .platform = platform, .sent = 0 };

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
            assert(notification.kind.is_valid());

            try notification.validate();
            try notifier.platform.notification_send(notification);

            notifier.sent += 1;

            assert(notifier.sent > 0);
        }

        pub fn sent_count(notifier: *const Notifier) u32 {
            return notifier.sent;
        }
    };
}

const testing = std.testing;

const Fake = platform_module.Fake;
const FakeNotifier = NotifierType(Fake);

test NotifierType {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "notifier" });
    defer fake.deinit();

    var notifier = FakeNotifier.init(&fake);
    defer notifier.deinit();

    try notifier.send(.{ .body = "Application is running", .title = "Started" });
    try notifier.send(.{ .body = "Disk almost full", .kind = .warning, .title = "Storage" });

    try testing.expectEqual(@as(u32, 2), notifier.sent_count());
}

test "a refused notification is not counted as sent" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "notifier" });
    defer fake.deinit();

    var notifier = FakeNotifier.init(&fake);
    defer notifier.deinit();

    try testing.expectError(error.TitleEmpty, notifier.send(.{ .body = "Body", .title = "" }));
    try testing.expectError(error.BodyInvalid, notifier.send(.{ .body = "\xFF", .title = "t" }));
    try testing.expectEqual(@as(u32, 0), notifier.sent_count());
}
