const std = @import("std");

const contract = @import("../contract.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

pub const Error = contract.MenuError;

pub const Item = contract.MenuItem;

pub const item_max: u32 = 64;
pub const label_bytes_max: u32 = 128;

comptime {
    assert(item_max > 0);
    assert(label_bytes_max > 1);
    assert(label_bytes_max <= record.text_bytes_max);
}

const Entry = struct {
    checked: bool,
    enabled: bool,
    id: u32,
    kind: contract.MenuItemKind,
    label: record.Text,
};

var entries: [item_max]Entry = undefined;
var count: u32 = 0;
var build_count: u32 = 0;
var destroy_count: u32 = 0;
var fail_build: bool = false;

pub fn build(items: []const Item) Error!void {
    if (items.len > item_max) {
        return Error.CapacityExceeded;
    }

    if (fail_build) {
        return Error.BuildFailed;
    }

    var index: u32 = 0;

    while (index < items.len) : (index += 1) {
        assert(index < item_max);

        const item = items[index];

        if (!item.is_valid() or item.label.len >= label_bytes_max) {
            return Error.InvalidItem;
        }

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

    assert(count <= item_max);
}

pub fn destroy() void {
    count = 0;
    destroy_count += 1;

    assert(count == 0);
}

pub fn item_count() u32 {
    assert(count <= item_max);

    return count;
}

pub fn label_at(index: u32) []const u8 {
    assert(index < item_max);

    if (index >= count) {
        return "";
    }

    return entries[index].label.get();
}

pub fn id_at(index: u32) u32 {
    assert(index < item_max);

    if (index >= count) {
        return 0;
    }

    return entries[index].id;
}

pub fn checked_at(index: u32) bool {
    assert(index < item_max);

    if (index >= count) {
        return false;
    }

    return entries[index].checked;
}

pub fn counts() struct { built: u32, destroyed: u32 } {
    return .{ .built = build_count, .destroyed = destroy_count };
}

pub fn set_fail_build(fail: bool) void {
    fail_build = fail;

    assert(fail_build == fail);
}

pub fn reset() void {
    count = 0;
    build_count = 0;
    destroy_count = 0;
    fail_build = false;

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

test "build rejects an invalid item" {
    reset();

    const items = [_]Item{.{ .id = 1, .kind = .action, .label = "" }};

    try testing.expectError(Error.InvalidItem, build(&items));
}

test "build rejects an oversized label" {
    reset();

    const long = [_]u8{'a'} ** label_bytes_max;
    const items = [_]Item{.{ .id = 1, .kind = .action, .label = &long }};

    try testing.expectError(Error.InvalidItem, build(&items));
}

test "build honors the injected failure" {
    reset();
    set_fail_build(true);

    const items = [_]Item{.{ .id = 1, .kind = .action, .label = "Open" }};

    try testing.expectError(Error.BuildFailed, build(&items));
}

test "destroy empties the menu" {
    reset();

    const items = [_]Item{.{ .id = 1, .kind = .action, .label = "Open" }};

    try build(&items);

    destroy();

    try testing.expectEqual(@as(u32, 0), item_count());
    try testing.expectEqual(@as(u32, 1), counts().destroyed);
}
