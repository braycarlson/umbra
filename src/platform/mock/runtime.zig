const std = @import("std");

const contract = @import("../contract.zig");
const menu = @import("menu.zig");
const record = @import("record.zig");
const timer = @import("timer.zig");
const tray = @import("tray.zig");
const watcher = @import("watcher.zig");

const assert = std.debug.assert;

pub const Error = contract.RuntimeError;

pub const Options = contract.RuntimeOptions;

pub const name_bytes_max: u32 = 64;

comptime {
    assert(name_bytes_max > 1);
}

var opened: bool = false;
var name: record.Text = record.Text.empty();
var open_count: u32 = 0;
var close_count: u32 = 0;
var fail_open: bool = false;

pub fn open(options: Options) Error!void {
    if (opened) {
        return Error.AlreadyOpen;
    }

    if (!options.is_valid() or options.name.len >= name_bytes_max) {
        return Error.InvalidOptions;
    }

    if (fail_open) {
        return Error.OpenFailed;
    }

    name.set(options.name);

    opened = true;
    open_count += 1;

    assert(opened);
    assert(open_count > 0);
}

pub fn close() void {
    if (!opened) {
        return;
    }

    tray.destroy();
    menu.destroy();
    timer.stop_all();
    watcher.stop_all();

    opened = false;
    close_count += 1;

    assert(!opened);
    assert(!tray.is_created());
}

pub fn is_open() bool {
    return opened;
}

pub fn opened_name() []const u8 {
    return name.get();
}

pub fn counts() struct { closed: u32, opened: u32 } {
    return .{ .closed = close_count, .opened = open_count };
}

pub fn set_fail_open(fail: bool) void {
    fail_open = fail;

    assert(fail_open == fail);
}

pub fn reset() void {
    opened = false;
    name = record.Text.empty();
    open_count = 0;
    close_count = 0;
    fail_open = false;

    assert(!opened);
    assert(open_count == 0);
}

const testing = std.testing;

test "open records the name and marks the runtime open" {
    reset();

    try open(.{ .name = "umbra" });

    try testing.expect(is_open());
    try testing.expectEqualStrings("umbra", opened_name());
    try testing.expectEqual(@as(u32, 1), counts().opened);
}

test "open rejects a second call" {
    reset();

    try open(.{ .name = "umbra" });

    try testing.expectError(Error.AlreadyOpen, open(.{ .name = "umbra" }));
}

test "open rejects an empty name" {
    reset();

    try testing.expectError(Error.InvalidOptions, open(.{ .name = "" }));
}

test "open rejects an oversized name" {
    reset();

    const long = [_]u8{'a'} ** name_bytes_max;

    try testing.expectError(Error.InvalidOptions, open(.{ .name = &long }));
}

test "open honors the injected failure" {
    reset();
    set_fail_open(true);

    try testing.expectError(Error.OpenFailed, open(.{ .name = "umbra" }));
    try testing.expect(!is_open());
}

test "close is idempotent" {
    reset();

    try open(.{ .name = "umbra" });

    close();
    close();

    try testing.expect(!is_open());
    try testing.expectEqual(@as(u32, 1), counts().closed);
}
