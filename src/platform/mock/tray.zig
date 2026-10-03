const std = @import("std");

const contract = @import("../contract.zig");
const icon = @import("icon.zig");
const record = @import("record.zig");
const runtime = @import("runtime.zig");

const assert = std.debug.assert;

pub const Error = contract.TrayError;

pub const CreateOptions = contract.TrayCreateOptions;

pub const tooltip_bytes_max: u32 = 128;

comptime {
    assert(tooltip_bytes_max > 1);
    assert(tooltip_bytes_max <= record.text_bytes_max);
}

var created: bool = false;
var current_id: u32 = 0;
var current_icon: ?icon.Handle = null;
var tooltip: record.Text = record.Text.empty();
var create_count: u32 = 0;
var destroy_count: u32 = 0;
var icon_count: u32 = 0;
var tooltip_count: u32 = 0;
var fail_create: bool = false;

pub fn create(options: CreateOptions) Error!void {
    if (options.tooltip.len >= tooltip_bytes_max) {
        return Error.InvalidTooltip;
    }

    if (created) {
        return Error.AlreadyCreated;
    }

    if (!runtime.is_open()) {
        return Error.RuntimeClosed;
    }

    if (fail_create) {
        return Error.CreationFailed;
    }

    created = true;
    current_id = options.id;
    current_icon = options.icon;
    create_count += 1;

    tooltip.set(options.tooltip);

    assert(created);
    assert(create_count > 0);
}

pub fn destroy() void {
    if (!created) {
        return;
    }

    created = false;
    current_icon = null;
    destroy_count += 1;

    assert(!created);
}

pub fn is_created() bool {
    return created;
}

pub fn set_icon(handle: icon.Handle) Error!void {
    if (!created) {
        return Error.NotCreated;
    }

    current_icon = handle;
    icon_count += 1;

    assert(current_icon != null);
}

pub fn set_tooltip(text: []const u8) Error!void {
    if (!created) {
        return Error.NotCreated;
    }

    if (text.len >= tooltip_bytes_max) {
        return Error.InvalidTooltip;
    }

    tooltip.set(text);
    tooltip_count += 1;

    assert(tooltip_count > 0);
}

pub fn current_tooltip() []const u8 {
    return tooltip.get();
}

pub fn icon_handle() ?icon.Handle {
    return current_icon;
}

pub fn id() u32 {
    return current_id;
}

pub fn counts() struct {
    created: u32,
    destroyed: u32,
    icons: u32,
    tooltips: u32,
} {
    return .{
        .created = create_count,
        .destroyed = destroy_count,
        .icons = icon_count,
        .tooltips = tooltip_count,
    };
}

pub fn set_fail_create(fail: bool) void {
    fail_create = fail;

    assert(fail_create == fail);
}

pub fn reset() void {
    created = false;
    current_id = 0;
    current_icon = null;
    tooltip = record.Text.empty();
    create_count = 0;
    destroy_count = 0;
    icon_count = 0;
    tooltip_count = 0;
    fail_create = false;

    assert(!created);
    assert(create_count == 0);
}

const testing = std.testing;

fn open_runtime() !void {
    runtime.reset();

    try runtime.open(.{ .name = "umbra" });
}

test "create records the tray configuration" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try create(.{ .icon = 3, .id = 7, .tooltip = "umbra" });

    try testing.expect(is_created());
    try testing.expectEqual(@as(u32, 7), id());
    try testing.expectEqual(@as(?icon.Handle, 3), icon_handle());
    try testing.expectEqualStrings("umbra", current_tooltip());
}

test "create requires an open runtime" {
    reset();
    runtime.reset();

    try testing.expectError(Error.RuntimeClosed, create(.{}));
}

test "create rejects a second tray" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try create(.{});

    try testing.expectError(Error.AlreadyCreated, create(.{}));
}

test "create rejects an oversized tooltip" {
    reset();

    try open_runtime();
    defer runtime.reset();

    const long: [tooltip_bytes_max]u8 = @splat('a');

    try testing.expectError(Error.InvalidTooltip, create(.{ .tooltip = &long }));
}

test "create honors the injected failure" {
    reset();

    try open_runtime();
    defer runtime.reset();

    set_fail_create(true);

    try testing.expectError(Error.CreationFailed, create(.{}));
    try testing.expect(!is_created());
}

test "set_icon and set_tooltip require a live tray" {
    reset();

    try testing.expectError(Error.NotCreated, set_icon(1));
    try testing.expectError(Error.NotCreated, set_tooltip("x"));
}

test "set_tooltip rejects an oversized tooltip" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try create(.{});

    const long: [tooltip_bytes_max]u8 = @splat('a');

    try testing.expectError(Error.InvalidTooltip, set_tooltip(&long));
}

test "set_icon and set_tooltip update the live tray" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try create(.{});
    try set_icon(9);
    try set_tooltip("updated");

    try testing.expectEqual(@as(?icon.Handle, 9), icon_handle());
    try testing.expectEqualStrings("updated", current_tooltip());
    try testing.expectEqual(@as(u32, 1), counts().icons);
    try testing.expectEqual(@as(u32, 1), counts().tooltips);
}

test "destroy is idempotent" {
    reset();

    try open_runtime();
    defer runtime.reset();

    try create(.{});

    destroy();
    destroy();

    try testing.expect(!is_created());
    try testing.expectEqual(@as(u32, 1), counts().destroyed);
}
