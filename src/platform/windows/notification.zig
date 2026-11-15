const std = @import("std");

const IconTable = @import("icon_table.zig");
const interface = @import("../interface.zig");
const Tray = @import("tray.zig");
const Window = @import("window.zig");

const assert = std.debug.assert;

const Notification = interface.Notification;
const PlatformError = interface.PlatformError;

comptime {
    assert(interface.notification_title_bytes_max < Tray.title_max);
    assert(interface.notification_body_bytes_max < Tray.info_max);
}

pub fn send(tray: *const Tray, notification: Notification) PlatformError!void {
    assert(notification.is_valid());

    const live = tray.current orelse return error.NotificationFailed;

    live.show_balloon(.{
        .body = notification.body,
        .icon = to_balloon_icon(notification.kind),
        .silent = notification.silent,
        .title = notification.title,
    }) catch {
        return error.NotificationFailed;
    };
}

fn to_balloon_icon(kind: Notification.Kind) Tray.BalloonIcon {
    const result = switch (kind) {
        .err => Tray.BalloonIcon.err,
        .info => Tray.BalloonIcon.info,
        .none => Tray.BalloonIcon.none,
        .warning => Tray.BalloonIcon.warning,
    };

    return result;
}

const testing = std.testing;

test "to_balloon_icon maps every notification kind" {
    try testing.expectEqual(Tray.BalloonIcon.err, to_balloon_icon(.err));
    try testing.expectEqual(Tray.BalloonIcon.info, to_balloon_icon(.info));
    try testing.expectEqual(Tray.BalloonIcon.none, to_balloon_icon(.none));
    try testing.expectEqual(Tray.BalloonIcon.warning, to_balloon_icon(.warning));
}

test "send without a live tray reports the failure" {
    const window: Window = .closed;

    var icons: IconTable = undefined;
    var tray: Tray = undefined;

    icons.init();
    tray.init(&icons, &window);

    try testing.expectError(error.NotificationFailed, send(&tray, .{ .body = "b", .title = "t" }));
}
