const std = @import("std");

const contract = @import("../contract.zig");
const tray = @import("tray.zig");

const assert = std.debug.assert;

const Notification = contract.Notification;
const PlatformError = contract.PlatformError;

comptime {
    assert(contract.notification_title_bytes_max < tray.title_max);
    assert(contract.notification_body_bytes_max < tray.info_max);
}

pub fn send(notification: Notification) PlatformError!void {
    assert(notification.is_valid());

    const live = tray.active() orelse return error.NotificationFailed;

    live.show_balloon(.{
        .body = notification.body,
        .icon = to_balloon_icon(notification.kind),
        .silent = notification.silent,
        .title = notification.title,
    }) catch {
        return error.NotificationFailed;
    };
}

fn to_balloon_icon(kind: Notification.Kind) tray.BalloonIcon {
    const result = switch (kind) {
        .err => tray.BalloonIcon.err,
        .info => tray.BalloonIcon.info,
        .none => tray.BalloonIcon.none,
        .warning => tray.BalloonIcon.warning,
    };

    return result;
}

const testing = std.testing;

test "to_balloon_icon maps every notification kind" {
    try testing.expectEqual(tray.BalloonIcon.err, to_balloon_icon(.err));
    try testing.expectEqual(tray.BalloonIcon.info, to_balloon_icon(.info));
    try testing.expectEqual(tray.BalloonIcon.none, to_balloon_icon(.none));
    try testing.expectEqual(tray.BalloonIcon.warning, to_balloon_icon(.warning));
}

test "send without a live tray reports the failure" {
    if (tray.is_created()) {
        return;
    }

    try testing.expectError(error.NotificationFailed, send(.{ .body = "b", .title = "t" }));
}
