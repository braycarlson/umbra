const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.menu;

pub const group_max: u32 = 32;
pub const item_max: u8 = 64;
pub const label_max: u32 = 128;

comptime {
    assert(group_max > 1);
    assert(item_max > 0);
    assert(label_max > 1);
}

pub const Error = platform.MenuError;

pub const ItemKind = platform.MenuItemKind;

pub const Item = struct {
    checked: bool,
    enabled: bool,
    group: [group_max]u8,
    group_len: u8,
    id: u32,
    kind: ItemKind,
    label: [label_max]u8,
    label_len: u16,
    visible: bool,

    pub fn action(id: u32, label: []const u8) Item {
        assert(label.len > 0);
        assert(label.len < label_max);

        var result = empty();

        result.id = id;
        result.kind = .action;

        copy_label(&result, label);

        return result;
    }

    pub fn radio(id: u32, label: []const u8, group_name: []const u8, initial: bool) Item {
        assert(label.len > 0);
        assert(label.len < label_max);
        assert(group_name.len > 0);
        assert(group_name.len < group_max);

        var result = empty();

        result.checked = initial;
        result.id = id;
        result.kind = .radio;

        copy_group(&result, group_name);
        copy_label(&result, label);

        return result;
    }

    pub fn separator() Item {
        var result = empty();

        result.kind = .separator;

        return result;
    }

    pub fn toggle(id: u32, label: []const u8, initial: bool) Item {
        assert(label.len > 0);
        assert(label.len < label_max);

        var result = empty();

        result.checked = initial;
        result.id = id;
        result.kind = .toggle;

        copy_label(&result, label);

        return result;
    }

    fn empty() Item {
        const result = Item{
            .checked = false,
            .enabled = true,
            .group = @splat(0),
            .group_len = 0,
            .id = 0,
            .kind = .action,
            .label = @splat(0),
            .label_len = 0,
            .visible = true,
        };

        return result;
    }

    pub fn get_group(item: *const Item) ?[]const u8 {
        if (item.group_len == 0) {
            return null;
        }

        assert(item.group_len <= group_max);

        return item.group[0..item.group_len];
    }

    pub fn get_label(item: *const Item) []const u8 {
        assert(item.label_len <= label_max);

        return item.label[0..item.label_len];
    }

    pub fn is_in_group(item: *const Item, group_name: []const u8) bool {
        if (item.group_len == 0 or group_name.len != item.group_len) {
            return false;
        }

        return std.mem.eql(u8, item.group[0..item.group_len], group_name);
    }

    pub fn set_group(item: *Item, group_name: []const u8) Error!void {
        if (group_name.len == 0 or group_name.len >= group_max) {
            return Error.InvalidLabel;
        }

        copy_group(item, group_name);
    }

    pub fn set_label(item: *Item, label: []const u8) Error!void {
        if (label.len == 0 or label.len >= label_max) {
            return Error.InvalidLabel;
        }

        copy_label(item, label);
    }
};

fn copy_group(item: *Item, group_name: []const u8) void {
    assert(group_name.len > 0);
    assert(group_name.len < group_max);

    @memcpy(item.group[0..group_name.len], group_name);

    item.group_len = @intCast(group_name.len);

    assert(item.group_len == group_name.len);
}

fn copy_label(item: *Item, label: []const u8) void {
    assert(label.len > 0);
    assert(label.len < label_max);

    @memcpy(item.label[0..label.len], label);

    item.label_len = @intCast(label.len);

    assert(item.label_len == label.len);
}

pub const MenuManager = struct {
    count: u8,
    dirty: bool,
    items: [item_max]?Item,

    pub fn init() MenuManager {
        const result = MenuManager{
            .count = 0,
            .dirty = true,
            .items = @splat(null),
        };

        assert(result.count == 0);
        assert(result.dirty == true);

        return result;
    }

    pub fn deinit(manager: *MenuManager) void {
        backend.destroy();

        manager.clear();

        assert(manager.count == 0);
    }

    pub fn add(manager: *MenuManager, item: Item) Error!void {
        if (manager.count >= item_max) {
            return Error.CapacityExceeded;
        }

        manager.items[manager.count] = item;
        manager.count += 1;
        manager.dirty = true;

        assert(manager.count <= item_max);
    }

    pub fn add_action(manager: *MenuManager, id: u32, label: []const u8) Error!void {
        try manager.add(Item.action(id, label));
    }

    pub fn add_radio(
        manager: *MenuManager,
        id: u32,
        label: []const u8,
        group_name: []const u8,
        initial: bool,
    ) Error!void {
        try manager.add(Item.radio(id, label, group_name, initial));

        if (initial) {
            select_radio(manager, group_name, id);
        }
    }

    pub fn add_separator(manager: *MenuManager) Error!void {
        try manager.add(Item.separator());
    }

    pub fn add_toggle(manager: *MenuManager, id: u32, label: []const u8, initial: bool) Error!void {
        try manager.add(Item.toggle(id, label, initial));
    }

    pub fn build(manager: *MenuManager) Error!void {
        if (!manager.dirty) {
            return;
        }

        var staged: [item_max]platform.MenuItem = undefined;
        var staged_count: u8 = 0;
        var index: u8 = 0;

        while (index < manager.count) : (index += 1) {
            assert(index < item_max);

            if (manager.items[index]) |*item| {
                if (!item.visible) {
                    continue;
                }

                if (item.kind != .separator and item.get_label().len == 0) {
                    continue;
                }

                assert(staged_count < item_max);

                staged[staged_count] = .{
                    .checked = item.checked,
                    .enabled = item.enabled,
                    .id = item.id,
                    .kind = item.kind,
                    .label = item.get_label(),
                };

                staged_count += 1;
            }
        }

        backend.build(staged[0..staged_count]) catch {
            return Error.BuildFailed;
        };

        manager.dirty = false;

        assert(!manager.dirty);
    }

    pub fn clear(manager: *MenuManager) void {
        var index: u8 = 0;

        while (index < manager.count) : (index += 1) {
            assert(index < item_max);

            manager.items[index] = null;
        }

        manager.count = 0;
        manager.dirty = true;

        assert(manager.count == 0);
    }

    pub fn get_item(manager: *const MenuManager, id: u32) ?*const Item {
        var index: u8 = 0;

        while (index < manager.count) : (index += 1) {
            assert(index < item_max);

            if (manager.items[index]) |*item| {
                if (item.id == id) {
                    return item;
                }
            }
        }

        return null;
    }

    pub fn get_radio_selection(manager: *const MenuManager, group_name: []const u8) ?u32 {
        var index: u8 = 0;

        while (index < manager.count) : (index += 1) {
            assert(index < item_max);

            if (manager.items[index]) |*item| {
                if (item.kind == .radio and item.is_in_group(group_name) and item.checked) {
                    return item.id;
                }
            }
        }

        return null;
    }

    pub fn is_checked(manager: *const MenuManager, id: u32) bool {
        const item = manager.get_item(id) orelse return false;

        return item.checked;
    }

    pub fn is_empty(manager: *const MenuManager) bool {
        return manager.count == 0;
    }

    pub fn mark_dirty(manager: *MenuManager) void {
        manager.dirty = true;
    }

    pub fn set_checked(manager: *MenuManager, id: u32, checked: bool) Error!void {
        const item = get_item_mut(manager, id) orelse return Error.NotFound;

        if (item.kind == .radio and checked) {
            if (item.get_group()) |group_name| {
                select_radio(manager, group_name, id);
            }
        } else {
            item.checked = checked;
        }

        manager.dirty = true;
    }

    pub fn set_enabled(manager: *MenuManager, id: u32, enabled: bool) Error!void {
        const item = get_item_mut(manager, id) orelse return Error.NotFound;

        item.enabled = enabled;
        manager.dirty = true;
    }

    pub fn set_label(manager: *MenuManager, id: u32, label: []const u8) Error!void {
        const item = get_item_mut(manager, id) orelse return Error.NotFound;

        try item.set_label(label);

        manager.dirty = true;
    }

    pub fn set_visible(manager: *MenuManager, id: u32, visible: bool) Error!void {
        const item = get_item_mut(manager, id) orelse return Error.NotFound;

        item.visible = visible;
        manager.dirty = true;
    }

    pub fn toggle_item(manager: *MenuManager, id: u32) Error!bool {
        const item = get_item_mut(manager, id) orelse return Error.NotFound;

        if (item.kind == .toggle) {
            item.checked = !item.checked;
            manager.dirty = true;

            return item.checked;
        }

        if (item.kind == .radio and !item.checked) {
            if (item.get_group()) |group_name| {
                select_radio(manager, group_name, id);
                manager.dirty = true;

                return true;
            }
        }

        return item.checked;
    }
};

fn get_item_mut(manager: *MenuManager, id: u32) ?*Item {
    var index: u8 = 0;

    while (index < manager.count) : (index += 1) {
        assert(index < item_max);

        if (manager.items[index]) |*item| {
            if (item.id == id) {
                return item;
            }
        }
    }

    return null;
}

fn select_radio(manager: *MenuManager, group_name: []const u8, selected_id: u32) void {
    assert(group_name.len > 0);

    var index: u8 = 0;

    while (index < manager.count) : (index += 1) {
        assert(index < item_max);

        if (manager.items[index]) |*item| {
            if (item.kind == .radio and item.is_in_group(group_name)) {
                item.checked = item.id == selected_id;
            }
        }
    }
}

const testing = std.testing;

test "ItemKind is the neutral menu item kind" {
    try testing.expectEqual(platform.MenuItemKind, ItemKind);
    try testing.expect(ItemKind.action.is_valid());
    try testing.expect(ItemKind.separator.is_valid());
}

test "an action item carries its label and id" {
    const item = Item.action(1, "Test");

    try testing.expectEqual(@as(u32, 1), item.id);
    try testing.expectEqual(ItemKind.action, item.kind);
    try testing.expectEqualStrings("Test", item.get_label());
    try testing.expect(item.enabled);
    try testing.expect(item.visible);
    try testing.expect(!item.checked);
}

test "a toggle item starts from the checked flag it is given" {
    const item = Item.toggle(2, "Toggle", true);

    try testing.expectEqual(@as(u32, 2), item.id);
    try testing.expectEqual(ItemKind.toggle, item.kind);
    try testing.expectEqualStrings("Toggle", item.get_label());
    try testing.expect(item.checked);
}

test "a toggle item can start unchecked" {
    const item = Item.toggle(3, "Toggle", false);

    try testing.expect(!item.checked);
}

test "a radio item carries its group" {
    const item = Item.radio(4, "Option", "group1", true);

    try testing.expectEqual(@as(u32, 4), item.id);
    try testing.expectEqual(ItemKind.radio, item.kind);
    try testing.expectEqualStrings("Option", item.get_label());
    try testing.expect(item.checked);

    const group = item.get_group();

    try testing.expect(group != null);
    try testing.expectEqualStrings("group1", group.?);
}

test "a separator item carries no label" {
    const item = Item.separator();

    try testing.expectEqual(ItemKind.separator, item.kind);
}

test "relabelling an item replaces its label" {
    var item = Item.action(1, "Old");

    try item.set_label("New Label");

    try testing.expectEqualStrings("New Label", item.get_label());
}

test "an item rejects an empty label" {
    var item = Item.action(1, "Original");

    try testing.expectError(Error.InvalidLabel, item.set_label(""));
    try testing.expectEqualStrings("Original", item.get_label());
}

test "regrouping an item replaces its group" {
    var item = Item.radio(1, "Option", "old", false);

    try item.set_group("newgroup");

    const group = item.get_group();

    try testing.expect(group != null);
    try testing.expectEqualStrings("newgroup", group.?);
}

test "an item belongs to its own group" {
    const item = Item.radio(1, "Option", "mygroup", false);

    try testing.expect(item.is_in_group("mygroup"));
}

test "an item does not belong to another group" {
    const item = Item.radio(1, "Option", "mygroup", false);

    try testing.expect(!item.is_in_group("other"));
}

test "a group name matches only in full" {
    const item = Item.radio(1, "Option", "mygroup", false);

    try testing.expect(!item.is_in_group("my"));
    try testing.expect(!item.is_in_group("mygroupx"));
}

test "a fresh menu holds no items" {
    const manager = MenuManager.init();

    try testing.expect(manager.is_empty());
    try testing.expectEqual(@as(u8, 0), manager.count);
    try testing.expect(manager.dirty);
}

test "an added item is held by the menu" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add(Item.action(1, "Test"));

    try testing.expect(!manager.is_empty());
    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "a full menu refuses another item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    var index: u8 = 0;

    while (index < item_max) : (index += 1) {
        assert(index < item_max);

        try manager.add(Item.action(index, "Item"));
    }

    const result = manager.add(Item.action(255, "Overflow"));

    try testing.expectError(Error.CapacityExceeded, result);
}

test "a menu adds an action item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_action(1, "Action");

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expectEqual(ItemKind.action, item.?.kind);
}

test "a menu adds a toggle item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_toggle(1, "Toggle", true);

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expectEqual(ItemKind.toggle, item.?.kind);
    try testing.expect(item.?.checked);
}

test "a menu adds a radio item and selects it in its group" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_radio(1, "Option 1", "group", true);
    try manager.add_radio(2, "Option 2", "group", false);
    try manager.add_radio(3, "Option 3", "group", false);

    try testing.expect(manager.is_checked(1));
    try testing.expect(!manager.is_checked(2));
    try testing.expect(!manager.is_checked(3));
}

test "a menu adds a separator" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_separator();

    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "a menu returns an item by id" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_action(42, "Test");

    const item = manager.get_item(42);

    try testing.expect(item != null);
    try testing.expectEqual(@as(u32, 42), item.?.id);
}

test "a menu returns nothing for an unknown id" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_action(1, "Test");

    const item = manager.get_item(999);

    try testing.expect(item == null);
}

test "a menu reports the checked state of an item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_toggle(1, "Checked", true);
    try manager.add_toggle(2, "Unchecked", false);

    try testing.expect(manager.is_checked(1));
    try testing.expect(!manager.is_checked(2));
}

test "checking an item updates its state" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_toggle(1, "Toggle", false);

    try testing.expect(!manager.is_checked(1));

    try manager.set_checked(1, true);

    try testing.expect(manager.is_checked(1));
}

test "checking an unknown id is reported" {
    var manager = MenuManager.init();
    defer manager.deinit();

    const result = manager.set_checked(999, true);

    try testing.expectError(Error.NotFound, result);
}

test "checking a radio item clears the rest of its group" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_radio(1, "Option 1", "group", true);
    try manager.add_radio(2, "Option 2", "group", false);

    try testing.expect(manager.is_checked(1));
    try testing.expect(!manager.is_checked(2));

    try manager.set_checked(2, true);

    try testing.expect(!manager.is_checked(1));
    try testing.expect(manager.is_checked(2));
}

test "enabling an item updates its state" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_action(1, "Action");

    try manager.set_enabled(1, false);

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expect(!item.?.enabled);
}

test "enabling an unknown id is reported" {
    var manager = MenuManager.init();
    defer manager.deinit();

    const result = manager.set_enabled(999, false);

    try testing.expectError(Error.NotFound, result);
}

test "relabelling through the menu replaces the item label" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_action(1, "Old");

    try manager.set_label(1, "New");

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expectEqualStrings("New", item.?.get_label());
}

test "hiding an item updates its visibility" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_action(1, "Action");

    try manager.set_visible(1, false);

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expect(!item.?.visible);
}

test "toggling a toggle item flips it" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_toggle(1, "Toggle", false);

    const result1 = try manager.toggle_item(1);

    try testing.expect(result1);
    try testing.expect(manager.is_checked(1));

    const result2 = try manager.toggle_item(1);

    try testing.expect(!result2);
    try testing.expect(!manager.is_checked(1));
}

test "toggling a radio item selects it within its group" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_radio(1, "Option 1", "group", true);
    try manager.add_radio(2, "Option 2", "group", false);

    _ = try manager.toggle_item(2);

    try testing.expect(!manager.is_checked(1));
    try testing.expect(manager.is_checked(2));
}

test "a menu reports the selected radio of a group" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_radio(1, "Option 1", "group", false);
    try manager.add_radio(2, "Option 2", "group", true);
    try manager.add_radio(3, "Option 3", "group", false);

    const selection = manager.get_radio_selection("group");

    try testing.expect(selection != null);
    try testing.expectEqual(@as(u32, 2), selection.?);
}

test "a group with no selection reports nothing" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_radio(1, "Option 1", "group", false);
    try manager.add_radio(2, "Option 2", "group", false);

    const selection = manager.get_radio_selection("group");

    try testing.expect(selection == null);
}

test "clearing a menu removes every item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    try manager.add_action(1, "Action 1");
    try manager.add_action(2, "Action 2");
    try manager.add_action(3, "Action 3");

    try testing.expectEqual(@as(u8, 3), manager.count);

    manager.clear();

    try testing.expect(manager.is_empty());
    try testing.expectEqual(@as(u8, 0), manager.count);
}

test "marking a menu dirty raises its flag" {
    var manager = MenuManager.init();
    defer manager.deinit();

    manager.dirty = false;
    manager.mark_dirty();

    try testing.expect(manager.dirty);
}
