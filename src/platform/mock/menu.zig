const std = @import("std");

const contract = @import("../contract.zig");
const fault = @import("fault.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

const Item = contract.MenuItem;
const PlatformError = contract.PlatformError;

const menu_item_count_max = contract.menu_item_count_max;

comptime {
    assert(contract.menu_label_bytes_max <= record.text_bytes_max);
}

const Entry = struct {
    checked: bool,
    enabled: bool,
    id: u32,
    kind: contract.MenuItemKind,
    label: record.Text,
};

var entries: [menu_item_count_max]Entry = undefined;
var count: u32 = 0;
var build_count: u32 = 0;
var destroy_count: u32 = 0;

pub fn build(items: []const Item) PlatformError!void {
    assert(items.len <= menu_item_count_max);

    if (fault.is_armed(.menu_build)) {
        return error.MenuBuildFailed;
    }

    var index: u32 = 0;

    while (index < items.len) : (index += 1) {
        assert(index < menu_item_count_max);

        const item = items[index];

        assert(item.is_valid());

        entries[index] = .{
            .checked = item.checked,
            .enabled = item.enabled,
            .id = item.id,
            .kind = item.kind,
            .label = record.Text.empty(),
        };

        entries[index].label.set(item.label);
    }

    count = @intCast(items.len);
    build_count += 1;

    assert(count <= menu_item_count_max);
}

pub fn destroy() void {
    count = 0;
    destroy_count += 1;

    assert(count == 0);
}

pub fn item_count() u32 {
    assert(count <= menu_item_count_max);

    return count;
}

pub fn label_at(index: u32) []const u8 {
    if (index >= count) {
        return "";
    }

    return entries[index].label.get();
}

pub fn id_at(index: u32) u32 {
    if (index >= count) {
        return 0;
    }

    return entries[index].id;
}

pub fn checked_at(index: u32) bool {
    if (index >= count) {
        return false;
    }

    return entries[index].checked;
}

pub fn counts() struct { built: u32, destroyed: u32 } {
    return .{ .built = build_count, .destroyed = destroy_count };
}

pub fn reset() void {
    count = 0;
    build_count = 0;
    destroy_count = 0;

    assert(count == 0);
    assert(build_count == 0);
}

const testing = std.testing;

test "build records every item" {
    reset();

    const items = [_]Item{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .kind = .separator },
        .{ .id = 2, .checked = true, .kind = .toggle, .label = "Enabled" },
    };

    try build(&items);

    try testing.expectEqual(@as(u32, 3), item_count());
    try testing.expectEqualStrings("Open", label_at(0));
    try testing.expectEqualStrings("", label_at(1));
    try testing.expectEqual(@as(u32, 2), id_at(2));
    try testing.expect(checked_at(2));
    try testing.expectEqual(@as(u32, 1), counts().built);
}

test "build honors the injected failure" {
    reset();
    fault.reset();
    fault.arm(.menu_build);
    defer fault.reset();

    const items = [_]Item{.{ .id = 1, .kind = .action, .label = "Open" }};

    try testing.expectError(error.MenuBuildFailed, build(&items));
}

test "destroy empties the menu" {
    reset();

    const items = [_]Item{.{ .id = 1, .kind = .action, .label = "Open" }};

    try build(&items);

    destroy();

    try testing.expectEqual(@as(u32, 0), item_count());
    try testing.expectEqual(@as(u32, 1), counts().destroyed);
}
