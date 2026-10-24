const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.menu;

const CapacityError = platform.CapacityError;
const PlatformError = platform.PlatformError;
const RequestError = platform.RequestError;

const menu_group_bytes_max = platform.menu_group_bytes_max;
const menu_item_count_max = platform.menu_item_count_max;
const menu_item_id_max = platform.menu_item_id_max;
const menu_label_bytes_max = platform.menu_label_bytes_max;

pub const Menu = struct {
    count: u8,
    dirty: bool,
    items: [menu_item_count_max]Item,

    pub const Item = struct {
        checked: bool,
        enabled: bool,
        group: [menu_group_bytes_max]u8,
        group_len: u8,
        id: u32,
        kind: Kind,
        label: [menu_label_bytes_max]u8,
        label_len: u8,
        visible: bool,

        pub const Kind = platform.MenuItemKind;

        pub const Radio = struct {
            checked: bool = false,
            group: []const u8,
        };

        pub const Toggle = struct {
            checked: bool = false,
        };

        pub fn action(id: u32, label: []const u8) Item {
            var result = empty(id, .action);

            result.set_label(label);

            return result;
        }

        pub fn radio(id: u32, label: []const u8, options: Radio) Item {
            assert(options.group.len > 0);
            assert(options.group.len <= menu_group_bytes_max);

            var result = empty(id, .radio);

            result.checked = options.checked;
            result.group_len = @intCast(options.group.len);

            @memcpy(result.group[0..options.group.len], options.group);

            result.set_label(label);

            return result;
        }

        pub fn separator() Item {
            return empty(0, .separator);
        }

        pub fn toggle(id: u32, label: []const u8, options: Toggle) Item {
            var result = empty(id, .toggle);

            result.checked = options.checked;

            result.set_label(label);

            return result;
        }

        pub fn get_group(item: *const Item) ?[]const u8 {
            if (item.group_len == 0) {
                return null;
            }

            assert(item.group_len <= menu_group_bytes_max);

            return item.group[0..item.group_len];
        }

        pub fn get_label(item: *const Item) []const u8 {
            assert(item.label_len <= menu_label_bytes_max);

            return item.label[0..item.label_len];
        }

        pub fn is_in_group(item: *const Item, group: []const u8) bool {
            const own = item.get_group() orelse return false;
            return std.mem.eql(u8, own, group);
        }

        fn empty(id: u32, kind: Kind) Item {
            assert(id <= menu_item_id_max);

            const result = Item{
                .checked = false,
                .enabled = true,
                .group = @splat(0),
                .group_len = 0,
                .id = id,
                .kind = kind,
                .label = @splat(0),
                .label_len = 0,
                .visible = true,
            };

            return result;
        }

        fn set_label(item: *Item, label: []const u8) void {
            assert(label.len > 0);
            assert(label.len <= menu_label_bytes_max);
            assert(platform.is_valid_text(label));

            @memcpy(item.label[0..label.len], label);

            item.label_len = @intCast(label.len);
        }
    };

    pub const Change = struct {
        checked: ?bool = null,
        enabled: ?bool = null,
        label: ?[]const u8 = null,
        visible: ?bool = null,
    };

    pub fn init() Menu {
        const result = Menu{
            .count = 0,
            .dirty = true,
            .items = undefined,
        };

        assert(result.is_empty());

        return result;
    }

    pub fn deinit(menu: *Menu) void {
        backend.destroy();

        menu.clear();

        assert(menu.is_empty());
    }

    pub fn add(menu: *Menu, item: Item) CapacityError!void {
        assert(menu.count <= menu_item_count_max);

        if (menu.count == menu_item_count_max) return error.ItemsExhausted;

        menu.items[menu.count] = item;
        menu.count += 1;
        menu.dirty = true;

        if (item.kind == .radio) {
            if (item.checked) {
                menu.select_radio(item.get_group().?, item.id);
            }
        }
    }

    pub fn build(menu: *Menu) PlatformError!void {
        if (!menu.dirty) {
            return;
        }

        var staged: [menu_item_count_max]platform.MenuItem = undefined;
        var staged_count: u8 = 0;

        for (menu.items[0..menu.count]) |*item| {
            if (!item.visible) {
                continue;
            }

            staged[staged_count] = .{
                .checked = item.checked,
                .enabled = item.enabled,
                .id = item.id,
                .kind = item.kind,
                .label = item.get_label(),
            };

            staged_count += 1;
        }

        try backend.build(staged[0..staged_count]);

        menu.dirty = false;
    }

    pub fn clear(menu: *Menu) void {
        menu.count = 0;
        menu.dirty = true;

        assert(menu.is_empty());
    }

    pub fn get_item(menu: *const Menu, id: u32) ?*const Item {
        for (menu.items[0..menu.count]) |*item| {
            if (item.id == id) {
                return item;
            }
        }

        return null;
    }

    pub fn is_checked(menu: *const Menu, id: u32) bool {
        const item = menu.get_item(id) orelse return false;
        return item.checked;
    }

    pub fn is_empty(menu: *const Menu) bool {
        return menu.count == 0;
    }

    pub fn update(menu: *Menu, id: u32, change: Change) (CapacityError || RequestError)!void {
        const item = menu.find_mut(id) orelse return error.ItemUnknown;

        if (change.label) |label| {
            if (label.len == 0) return error.LabelEmpty;
            if (label.len > menu_label_bytes_max) return error.LabelTooLong;
            if (!platform.is_valid_text(label)) return error.LabelInvalid;

            item.set_label(label);
        }

        if (change.checked) |checked| {
            if (item.kind == .radio) {
                if (checked) {
                    menu.select_radio(item.get_group().?, id);
                } else {
                    item.checked = false;
                }
            } else {
                item.checked = checked;
            }
        }

        if (change.enabled) |enabled| item.enabled = enabled;
        if (change.visible) |visible| item.visible = visible;

        menu.dirty = true;
    }

    fn find_mut(menu: *Menu, id: u32) ?*Item {
        for (menu.items[0..menu.count]) |*item| {
            if (item.id == id) {
                return item;
            }
        }

        return null;
    }

    fn select_radio(menu: *Menu, group: []const u8, selected: u32) void {
        assert(group.len > 0);

        for (menu.items[0..menu.count]) |*item| {
            if (item.kind == .radio) {
                if (item.is_in_group(group)) {
                    item.checked = item.id == selected;
                }
            }
        }
    }
};

const testing = std.testing;

test Menu {
    var menu = Menu.init();
    defer menu.deinit();

    try menu.add(.action(1, "About"));
    try menu.add(.toggle(2, "Enabled", .{ .checked = true }));
    try menu.add(.separator());
    try menu.add(.radio(3, "Small", .{ .checked = true, .group = "size" }));
    try menu.add(.radio(4, "Large", .{ .group = "size" }));

    try testing.expect(menu.is_checked(2));
    try testing.expect(menu.is_checked(3));

    try menu.update(4, .{ .checked = true });

    try testing.expect(!menu.is_checked(3));
    try testing.expect(menu.is_checked(4));

    try menu.build();

    try testing.expect(!menu.dirty);
}

test "an update changes only the fields it names" {
    var menu = Menu.init();
    defer menu.deinit();

    try menu.add(.toggle(1, "Toggle", .{}));
    try menu.update(1, .{ .enabled = false, .label = "Renamed" });

    const item = menu.get_item(1) orelse return error.MissingItem;

    try testing.expect(!item.enabled);
    try testing.expect(item.visible);
    try testing.expect(!item.checked);
    try testing.expectEqualStrings("Renamed", item.get_label());
}

test "an update names the fault in each refused change" {
    var menu = Menu.init();
    defer menu.deinit();

    const long: [menu_label_bytes_max + 1]u8 = @splat('a');

    try menu.add(.action(1, "Original"));

    try testing.expectError(error.ItemUnknown, menu.update(999, .{ .checked = true }));
    try testing.expectError(error.LabelEmpty, menu.update(1, .{ .label = "" }));
    try testing.expectError(error.LabelTooLong, menu.update(1, .{ .label = &long }));
    try testing.expectError(error.LabelInvalid, menu.update(1, .{ .label = "\xFF" }));
    try testing.expectEqualStrings("Original", menu.get_item(1).?.get_label());
}

test "a full menu refuses another item" {
    var menu = Menu.init();
    defer menu.deinit();

    var index: u8 = 0;

    while (index < menu_item_count_max) : (index += 1) {
        try menu.add(.action(index, "Item"));
    }

    try testing.expectError(error.ItemsExhausted, menu.add(.action(255, "Overflow")));
}

test "a hidden item stays out of the built menu but keeps its state" {
    var menu = Menu.init();
    defer menu.deinit();

    try menu.add(.action(1, "Shown"));
    try menu.add(.action(2, "Hidden"));
    try menu.update(2, .{ .visible = false });
    try menu.build();

    try testing.expect(!menu.get_item(2).?.visible);
    try testing.expectEqual(@as(u8, 2), menu.count);
}

test "clearing a menu removes every item" {
    var menu = Menu.init();
    defer menu.deinit();

    try menu.add(.action(1, "Action 1"));
    try menu.add(.action(2, "Action 2"));

    menu.clear();

    try testing.expect(menu.is_empty());
    try testing.expect(menu.get_item(1) == null);
}
