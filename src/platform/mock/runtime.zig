const std = @import("std");

const contract = @import("../contract.zig");
const fault = @import("fault.zig");
const menu = @import("menu.zig");
const record = @import("record.zig");
const timer = @import("timer.zig");
const tray = @import("tray.zig");
const watcher = @import("watcher.zig");

const assert = std.debug.assert;

const Options = contract.RuntimeOptions;
const PlatformError = contract.PlatformError;

var opened: bool = false;
var name: record.Text = record.Text.empty();
var open_count: u32 = 0;
var close_count: u32 = 0;

pub fn open(options: Options) PlatformError!void {
    assert(!opened);
    assert(options.is_valid());

    if (fault.is_armed(.runtime_open)) {
        return error.RuntimeOpenFailed;
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

pub fn reset() void {
    opened = false;
    name = record.Text.empty();
    open_count = 0;
    close_count = 0;

    assert(!opened);
    assert(open_count == 0);
}

const testing = std.testing;

test "open records the name and marks the runtime open" {
    reset();
    defer reset();

    try open(.{ .name = "umbra" });

    try testing.expect(is_open());
    try testing.expectEqualStrings("umbra", opened_name());
    try testing.expectEqual(@as(u32, 1), counts().opened);
}

test "open honors the injected failure" {
    reset();
    fault.reset();
    fault.arm(.runtime_open);
    defer fault.reset();

    try testing.expectError(error.RuntimeOpenFailed, open(.{ .name = "umbra" }));
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
