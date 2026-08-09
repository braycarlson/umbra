const std = @import("std");

const contract = @import("../contract.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

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

var title: record.Text = record.Text.empty();
var body: record.Text = record.Text.empty();
var kind: contract.NotificationKind = .info;
var visible: bool = false;
var show_count: u32 = 0;
var hide_count: u32 = 0;
var fail_show: bool = false;

pub fn show(options: Options) Error!void {
    if (!options.is_valid()) {
        return Error.InvalidBalloon;
    }

    if (fail_show) {
        return Error.ShowFailed;
    }

    title.set(options.title);
    body.set(options.body);

    kind = options.kind;
    visible = true;
    show_count += 1;

    assert(visible);
    assert(show_count > 0);
}

pub fn hide() Error!void {
    visible = false;
    hide_count += 1;

    assert(!visible);
}

pub fn is_visible() bool {
    return visible;
}

pub fn current_title() []const u8 {
    return title.get();
}

pub fn current_body() []const u8 {
    return body.get();
}

pub fn current_kind() contract.NotificationKind {
    return kind;
}

pub fn counts() struct { hidden: u32, shown: u32 } {
    return .{ .hidden = hide_count, .shown = show_count };
}

pub fn set_fail_show(fail: bool) void {
    fail_show = fail;

    assert(fail_show == fail);
}

pub fn reset() void {
    title = record.Text.empty();
    body = record.Text.empty();
    kind = .info;
    visible = false;
    show_count = 0;
    hide_count = 0;
    fail_show = false;

    assert(!visible);
    assert(show_count == 0);
}

const testing = std.testing;

test "show records the balloon" {
    reset();

    try show(.{ .body = "Body", .kind = .err, .title = "Title" });

    try testing.expect(is_visible());
    try testing.expectEqualStrings("Title", current_title());
    try testing.expectEqualStrings("Body", current_body());
    try testing.expectEqual(contract.NotificationKind.err, current_kind());
}

test "show rejects an incomplete balloon" {
    reset();

    try testing.expectError(Error.InvalidBalloon, show(.{ .body = "b", .title = "" }));
}

test "show honors the injected failure" {
    reset();
    set_fail_show(true);

    try testing.expectError(Error.ShowFailed, show(.{ .body = "b", .title = "t" }));
}

test "hide clears the balloon" {
    reset();

    try show(.{ .body = "b", .title = "t" });
    try hide();

    try testing.expect(!is_visible());
    try testing.expectEqual(@as(u32, 1), counts().hidden);
}
