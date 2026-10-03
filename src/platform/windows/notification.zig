const std = @import("std");

const balloon = @import("balloon.zig");
const contract = @import("../contract.zig");

const assert = std.debug.assert;

pub const Error = contract.NotificationError;

pub const Options = contract.NotificationOptions;

pub fn send(options: Options) Error!void {
    if (!options.is_valid()) {
        return Error.InvalidNotification;
    }

    balloon.show(.{
        .body = options.body,
        .kind = options.kind,
        .silent = options.silent,
        .title = options.title,
    }) catch |err| {
        return translate(err);
    };
}

fn translate(err: balloon.Error) Error {
    const result = switch (err) {
        balloon.Error.InvalidBalloon => Error.InvalidNotification,
        balloon.Error.HideFailed,
        balloon.Error.NotCreated,
        balloon.Error.ShowFailed,
        => Error.SendFailed,
    };

    return result;
}

const testing = std.testing;

test "send rejects an incomplete notification" {
    try testing.expectError(Error.InvalidNotification, send(.{ .body = "", .title = "t" }));
    try testing.expectError(Error.InvalidNotification, send(.{ .body = "b", .title = "" }));
}

test "translate maps every balloon failure" {
    try testing.expectEqual(Error.InvalidNotification, translate(balloon.Error.InvalidBalloon));
    try testing.expectEqual(Error.SendFailed, translate(balloon.Error.NotCreated));
    try testing.expectEqual(Error.SendFailed, translate(balloon.Error.ShowFailed));
    try testing.expectEqual(Error.SendFailed, translate(balloon.Error.HideFailed));

    assert(@typeInfo(balloon.Error).error_set.error_names.?.len == 4);
}
