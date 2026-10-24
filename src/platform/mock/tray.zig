const std = @import("std");

const contract = @import("../contract.zig");
const fault = @import("fault.zig");
const record = @import("record.zig");
const runtime = @import("runtime.zig");

const assert = std.debug.assert;

const CreateOptions = contract.TrayCreateOptions;
const Icon = contract.Icon;
const PlatformError = contract.PlatformError;

comptime {
    assert(contract.tooltip_bytes_max <= record.text_bytes_max);
}

var created: bool = false;
var icon_current: ?Icon = null;
var tooltip: record.Text = record.Text.empty();
var create_count: u32 = 0;
var destroy_count: u32 = 0;
var icon_count: u32 = 0;
var tooltip_count: u32 = 0;

pub fn create(options: CreateOptions) PlatformError!void {
    assert(!created);
    assert(runtime.is_open());
    assert(options.tooltip.len <= contract.tooltip_bytes_max);

    if (fault.is_armed(.tray_create)) {
        return error.TrayCreateFailed;
    }

    created = true;
    icon_current = options.icon;
    create_count += 1;

    tooltip.set(options.tooltip);

    assert(created);
}

pub fn destroy() void {
    if (!created) {
        return;
    }

    created = false;
    icon_current = null;
    destroy_count += 1;

    assert(!created);
}

pub fn is_created() bool {
    return created;
}

pub fn set_icon(icon: Icon) PlatformError!void {
    assert(created);

    icon_current = icon;
    icon_count += 1;
}

pub fn set_tooltip(text: []const u8) PlatformError!void {
    assert(created);
    assert(text.len <= contract.tooltip_bytes_max);

    tooltip.set(text);
    tooltip_count += 1;
}

pub fn tooltip_current() []const u8 {
    return tooltip.get();
}

pub fn icon_handle() ?Icon {
    return icon_current;
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

pub fn reset() void {
    created = false;
    icon_current = null;
    tooltip = record.Text.empty();
    create_count = 0;
    destroy_count = 0;
    icon_count = 0;
    tooltip_count = 0;

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

    const icon: Icon = @fromBackingInt(3);

    try create(.{ .icon = icon, .tooltip = "umbra" });

    try testing.expect(is_created());
    try testing.expectEqual(@as(?Icon, icon), icon_handle());
    try testing.expectEqualStrings("umbra", tooltip_current());
}

test "create honors the injected failure" {
    reset();
    fault.reset();

    try open_runtime();
    defer runtime.reset();

    fault.arm(.tray_create);
    defer fault.reset();

    try testing.expectError(error.TrayCreateFailed, create(.{}));
    try testing.expect(!is_created());
}

test "set_icon and set_tooltip update the live tray" {
    reset();

    try open_runtime();
    defer runtime.reset();

    const icon: Icon = @fromBackingInt(9);

    try create(.{});
    try set_icon(icon);
    try set_tooltip("updated");

    try testing.expectEqual(@as(?Icon, icon), icon_handle());
    try testing.expectEqualStrings("updated", tooltip_current());
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
