const std = @import("std");

const contract = @import("../contract.zig");
const tray = @import("tray.zig");

pub const Error = contract.BalloonError;

pub const Options = struct {
    body: []const u8,
    kind: contract.NotificationKind = .info,
    silent: bool = false,
    title: []const u8,

    pub fn is_valid(options: *const Options) bool {
        return options.title.len > 0 and options.body.len > 0 and options.kind.is_valid();
    }
};

pub fn show(options: Options) Error!void {
    if (!options.is_valid()) {
        return Error.InvalidBalloon;
    }

    if (options.title.len >= tray.title_max or options.body.len >= tray.info_max) {
        return Error.InvalidBalloon;
    }

    const live = tray.active() orelse return Error.NotCreated;

    live.show_balloon(.{
        .body = options.body,
        .icon = to_balloon_icon(options.kind),
        .silent = options.silent,
        .title = options.title,
    }) catch {
        return Error.ShowFailed;
    };
}

pub fn hide() Error!void {
    const live = tray.active() orelse return Error.NotCreated;

    live.hide_balloon() catch {
        return Error.HideFailed;
    };
}

fn to_balloon_icon(kind: contract.NotificationKind) tray.BalloonIcon {
    const result = switch (kind) {
        .err => tray.BalloonIcon.err,
        .info => tray.BalloonIcon.info,
        .none => tray.BalloonIcon.none,
        .warning => tray.BalloonIcon.warning,
    };

    return result;
}

const testing = std.testing;

test "to_balloon_icon maps every neutral kind" {
    try testing.expectEqual(tray.BalloonIcon.err, to_balloon_icon(.err));
    try testing.expectEqual(tray.BalloonIcon.info, to_balloon_icon(.info));
    try testing.expectEqual(tray.BalloonIcon.none, to_balloon_icon(.none));
    try testing.expectEqual(tray.BalloonIcon.warning, to_balloon_icon(.warning));
}

test "show rejects an incomplete balloon" {
    try testing.expectError(Error.InvalidBalloon, show(.{ .body = "b", .title = "" }));
    try testing.expectError(Error.InvalidBalloon, show(.{ .body = "", .title = "t" }));
}

test "show rejects an oversized balloon" {
    const long_title = [_]u8{'a'} ** tray.title_max;

    try testing.expectError(Error.InvalidBalloon, show(.{ .body = "b", .title = &long_title }));
}

test "show and hide require a live tray" {
    try testing.expect(!tray.is_created());
    try testing.expectError(Error.NotCreated, show(.{ .body = "b", .title = "t" }));
    try testing.expectError(Error.NotCreated, hide());
}
