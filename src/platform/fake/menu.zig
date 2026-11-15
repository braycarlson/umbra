const std = @import("std");

const interface = @import("../interface.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

const Item = interface.MenuItem;

const menu_item_count_max = interface.menu_item_count_max;

const Menu = @This();

build_count: u32,
count: u32,
destroy_count: u32,
entries: [menu_item_count_max]Entry,

const Entry = struct {
    checked: bool,
    depth: u8,
    enabled: bool,
    id: u32,
    kind: interface.MenuItemKind,
    label: record.Text,
};

comptime {
    assert(interface.menu_label_bytes_max <= record.text_bytes_max);
}

pub fn init(menu: *Menu) void {
    menu.build_count = 0;
    menu.count = 0;
    menu.destroy_count = 0;
    menu.entries = undefined;

    assert(menu.item_count() == 0);
    assert(menu.counts().built == 0);
}

pub fn build(menu: *Menu, items: []const Item) void {
    assert(items.len <= menu_item_count_max);
    assert(interface.is_valid_layout(items));

    var index: u32 = 0;

    while (index < items.len) : (index += 1) {
        assert(index < menu_item_count_max);

        const item = items[index];

        assert(item.is_valid());

        menu.entries[index] = .{
            .checked = item.checked,
            .depth = item.depth,
            .enabled = item.enabled,
            .id = item.id,
            .kind = item.kind,
            .label = record.Text.empty(),
        };

        menu.entries[index].label.set(item.label);
    }

    menu.count = @intCast(items.len);
    menu.build_count += 1;

    assert(menu.count <= menu_item_count_max);
}

pub fn destroy(menu: *Menu) void {
    menu.count = 0;
    menu.destroy_count += 1;

    assert(menu.count == 0);
}

pub fn item_count(menu: *const Menu) u32 {
    assert(menu.count <= menu_item_count_max);

    return menu.count;
}

pub fn label_at(menu: *const Menu, index: u32) []const u8 {
    assert(index < menu.count);

    return menu.entries[index].label.get();
}

pub fn id_at(menu: *const Menu, index: u32) u32 {
    assert(index < menu.count);

    return menu.entries[index].id;
}

pub fn depth_at(menu: *const Menu, index: u32) u8 {
    assert(index < menu.count);

    return menu.entries[index].depth;
}

pub fn enabled_at(menu: *const Menu, index: u32) bool {
    assert(index < menu.count);

    return menu.entries[index].enabled;
}

pub fn checked_at(menu: *const Menu, index: u32) bool {
    if (index >= menu.count) {
        return false;
    }

    return menu.entries[index].checked;
}

pub fn counts(menu: *const Menu) struct { built: u32, destroyed: u32 } {
    return .{ .built = menu.build_count, .destroyed = menu.destroy_count };
}

const testing = std.testing;

test "build records every item" {
    var menu: Menu = undefined;

    menu.init();

    const items = [_]Item{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .kind = .separator },
        .{ .id = 2, .checked = true, .kind = .toggle, .label = "Enabled" },
    };

    menu.build(&items);

    try testing.expectEqual(@as(u32, 3), menu.item_count());
    try testing.expectEqualStrings("Open", menu.label_at(0));
    try testing.expectEqualStrings("", menu.label_at(1));
    try testing.expectEqual(@as(u32, 2), menu.id_at(2));
    try testing.expect(menu.checked_at(2));
    try testing.expectEqual(@as(u32, 1), menu.counts().built);
}

test "build records the depth of each nested item" {
    var menu: Menu = undefined;

    menu.init();

    const items = [_]Item{
        .{ .id = 1, .kind = .submenu, .label = "More" },
        .{ .depth = 1, .enabled = false, .id = 2, .kind = .action, .label = "Inside" },
        .{ .id = 3, .kind = .action, .label = "Exit" },
    };

    menu.build(&items);

    try testing.expectEqual(@as(u8, 0), menu.depth_at(0));
    try testing.expectEqual(@as(u8, 1), menu.depth_at(1));
    try testing.expectEqual(@as(u8, 0), menu.depth_at(2));
    try testing.expect(menu.enabled_at(0));
    try testing.expect(!menu.enabled_at(1));
}

test "destroy empties the menu" {
    var menu: Menu = undefined;

    menu.init();

    const items = [_]Item{.{ .id = 1, .kind = .action, .label = "Open" }};

    menu.build(&items);

    menu.destroy();

    try testing.expectEqual(@as(u32, 0), menu.item_count());
    try testing.expectEqual(@as(u32, 1), menu.counts().destroyed);
}
