const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.notification;

pub const body_max: u32 = 256;
pub const title_max: u32 = 64;

pub const Error = platform.NotificationError;

pub const Icon = platform.NotificationKind;

comptime {
    assert(body_max > title_max);
    assert(title_max > 1);
}

pub const Notification = struct {
    body: [body_max]u8,
    body_len: u16,
    icon: Icon,
    silent: bool,
    title: [title_max]u8,
    title_len: u16,

    pub fn init(title: []const u8, body: []const u8) Notification {
        assert(title.len > 0);
        assert(title.len < title_max);
        assert(body.len > 0);
        assert(body.len < body_max);

        var result = Notification{
            .body = [_]u8{0} ** body_max,
            .body_len = 0,
            .icon = .info,
            .silent = false,
            .title = [_]u8{0} ** title_max,
            .title_len = 0,
        };

        copy_title(&result, title);
        copy_body(&result, body);

        assert(result.title_len > 0);
        assert(result.body_len > 0);

        return result;
    }

    pub fn err(title: []const u8, body: []const u8) Notification {
        var result = Notification.init(title, body);

        result.icon = .err;

        return result;
    }

    pub fn info(title: []const u8, body: []const u8) Notification {
        var result = Notification.init(title, body);

        result.icon = .info;

        return result;
    }

    pub fn warning(title: []const u8, body: []const u8) Notification {
        var result = Notification.init(title, body);

        result.icon = .warning;

        return result;
    }

    pub fn get_body(notification: *const Notification) []const u8 {
        assert(notification.body_len <= body_max);

        return notification.body[0..notification.body_len];
    }

    pub fn get_title(notification: *const Notification) []const u8 {
        assert(notification.title_len <= title_max);

        return notification.title[0..notification.title_len];
    }

    pub fn is_valid(notification: *const Notification) bool {
        return notification.title_len > 0 and notification.body_len > 0;
    }

    pub fn set_body(notification: *Notification, body: []const u8) Error!void {
        if (body.len == 0 or body.len >= body_max) {
            return Error.InvalidNotification;
        }

        copy_body(notification, body);
    }

    pub fn set_title(notification: *Notification, title: []const u8) Error!void {
        if (title.len == 0 or title.len >= title_max) {
            return Error.InvalidNotification;
        }

        copy_title(notification, title);
    }

    pub fn with_icon(notification: Notification, icon: Icon) Notification {
        var result = notification;

        result.icon = icon;

        return result;
    }

    pub fn with_silent(notification: Notification, silent: bool) Notification {
        var result = notification;

        result.silent = silent;

        return result;
    }
};

fn copy_body(notification: *Notification, body: []const u8) void {
    assert(body.len > 0);
    assert(body.len < body_max);

    @memcpy(notification.body[0..body.len], body);

    notification.body_len = @intCast(body.len);

    assert(notification.body_len == body.len);
}

fn copy_title(notification: *Notification, title: []const u8) void {
    assert(title.len > 0);
    assert(title.len < title_max);

    @memcpy(notification.title[0..title.len], title);

    notification.title_len = @intCast(title.len);

    assert(notification.title_len == title.len);
}

pub const NotificationManager = struct {
    sent: u32,

    pub fn init() NotificationManager {
        const result = NotificationManager{ .sent = 0 };

        assert(result.sent == 0);

        return result;
    }

    pub fn deinit(manager: *NotificationManager) void {
        manager.sent = 0;

        assert(manager.sent == 0);
    }

    pub fn sent_count(manager: *const NotificationManager) u32 {
        return manager.sent;
    }

    pub fn send(manager: *NotificationManager, notification: *const Notification) Error!void {
        if (!notification.is_valid()) {
            return Error.InvalidNotification;
        }

        backend.send(.{
            .body = notification.get_body(),
            .kind = notification.icon,
            .silent = notification.silent,
            .title = notification.get_title(),
        }) catch {
            return Error.SendFailed;
        };

        manager.sent += 1;

        assert(manager.sent > 0);
    }

    pub fn send_error(
        manager: *NotificationManager,
        title: []const u8,
        body: []const u8,
    ) Error!void {
        const notification = Notification.err(title, body);

        try manager.send(&notification);
    }

    pub fn send_simple(
        manager: *NotificationManager,
        title: []const u8,
        body: []const u8,
    ) Error!void {
        const notification = Notification.info(title, body);

        try manager.send(&notification);
    }

    pub fn send_warning(
        manager: *NotificationManager,
        title: []const u8,
        body: []const u8,
    ) Error!void {
        const notification = Notification.warning(title, body);

        try manager.send(&notification);
    }
};

const testing = std.testing;

test "Icon is the neutral notification kind" {
    try testing.expectEqual(platform.NotificationKind, Icon);
    try testing.expect(Icon.info.is_valid());
    try testing.expect(Icon.none.is_valid());
}

test "a notification carries the title and body it was built from" {
    const notification = Notification.init("Title", "Body");

    try testing.expectEqualStrings("Title", notification.get_title());
    try testing.expectEqualStrings("Body", notification.get_body());
    try testing.expectEqual(Icon.info, notification.icon);
    try testing.expect(!notification.silent);
}

test "Notification constructors pick the icon" {
    try testing.expectEqual(Icon.err, Notification.err("Error", "Body").icon);
    try testing.expectEqual(Icon.info, Notification.info("Info", "Body").icon);
    try testing.expectEqual(Icon.warning, Notification.warning("Warning", "Body").icon);
}

test "a notification rejects an empty title" {
    var notification = Notification.init("Original", "Body");

    try testing.expectError(Error.InvalidNotification, notification.set_title(""));
    try testing.expectEqualStrings("Original", notification.get_title());

    try notification.set_title("Renamed");

    try testing.expectEqualStrings("Renamed", notification.get_title());
}

test "a notification rejects an empty body" {
    var notification = Notification.init("Title", "Original");

    try testing.expectError(Error.InvalidNotification, notification.set_body(""));
    try testing.expectEqualStrings("Original", notification.get_body());

    const long = [_]u8{'a'} ** body_max;

    try testing.expectError(Error.InvalidNotification, notification.set_body(&long));
}

test "Notification chaining preserves every field" {
    const notification = Notification.init("Title", "Body")
        .with_icon(.err)
        .with_silent(true);

    try testing.expectEqual(Icon.err, notification.icon);
    try testing.expect(notification.silent);
    try testing.expectEqualStrings("Title", notification.get_title());
    try testing.expectEqualStrings("Body", notification.get_body());
}

test "a notification needs both a title and a body to be valid" {
    var notification = Notification.init("Title", "Body");

    try testing.expect(notification.is_valid());

    notification.title_len = 0;

    try testing.expect(!notification.is_valid());

    notification = Notification.init("Title", "Body");
    notification.body_len = 0;

    try testing.expect(!notification.is_valid());
}

test "sending an invalid notification is rejected" {
    var manager = NotificationManager.init();
    defer manager.deinit();

    var notification = Notification.init("Title", "Body");

    notification.title_len = 0;

    try testing.expectError(Error.InvalidNotification, manager.send(&notification));
    try testing.expectEqual(@as(u32, 0), manager.sent_count());
}
