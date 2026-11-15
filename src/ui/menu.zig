const std = @import("std");

const platform_module = @import("../platform.zig");

const assert = std.debug.assert;

const CapacityError = platform_module.CapacityError;
const PlatformError = platform_module.PlatformError;
const RequestError = platform_module.RequestError;

const menu_depth_max = platform_module.menu_depth_max;
const menu_group_bytes_max = platform_module.menu_group_bytes_max;
const menu_item_count_max = platform_module.menu_item_count_max;
const menu_item_id_max = platform_module.menu_item_id_max;
const menu_label_bytes_max = platform_module.menu_label_bytes_max;

pub fn MenuType(comptime Platform: type) type {
    return struct {
        count: u8,
        depth: u8,
        dirty: bool,
        items: [menu_item_count_max]Item,
        platform: *Platform,

        const Menu = @This();

        pub const Item = struct {
            checked: bool,
            depth: u8,
            enabled: bool,
            group: [menu_group_bytes_max]u8,
            group_len: u8,
            id: u32,
            kind: Kind,
            label: [menu_label_bytes_max]u8,
            label_len: u8,
            visible: bool,

            pub const Kind = platform_module.MenuItemKind;

            pub const Radio = struct {
                checked: bool = false,
                group: []const u8,
            };

            pub const Toggle = struct {
                checked: bool = false,
            };

            pub fn action(id: u32, label: []const u8) Item {
                assert(id <= menu_item_id_max);
                assert(label.len > 0);
                assert(label.len <= menu_label_bytes_max);

                var result = empty(id, .action);

                result.set_label(label);

                return result;
            }

            pub fn radio(id: u32, label: []const u8, options: Radio) Item {
                assert(id <= menu_item_id_max);
                assert(label.len > 0);
                assert(label.len <= menu_label_bytes_max);
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

            pub fn submenu(id: u32, label: []const u8) Item {
                assert(id <= menu_item_id_max);
                assert(label.len > 0);
                assert(label.len <= menu_label_bytes_max);

                var result = empty(id, .submenu);

                result.set_label(label);

                return result;
            }

            pub fn toggle(id: u32, label: []const u8, options: Toggle) Item {
                assert(id <= menu_item_id_max);
                assert(label.len > 0);
                assert(label.len <= menu_label_bytes_max);

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
                assert(group.len > 0);
                assert(group.len <= menu_group_bytes_max);

                const own = item.get_group() orelse return false;
                return std.mem.eql(u8, own, group);
            }

            fn empty(id: u32, kind: Kind) Item {
                assert(id <= menu_item_id_max);

                const result = Item{
                    .checked = false,
                    .depth = 0,
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
                assert(platform_module.is_valid_text(label));

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

        pub fn init(platform: *Platform) Menu {
            const result = Menu{
                .count = 0,
                .depth = 0,
                .dirty = true,
                .items = undefined,
                .platform = platform,
            };

            assert(result.is_empty());

            return result;
        }

        pub fn deinit(menu: *Menu) void {
            menu.platform.menu_destroy();

            menu.clear();

            assert(menu.is_empty());
        }

        pub fn add(menu: *Menu, item: Item) CapacityError!void {
            assert(menu.count <= menu_item_count_max);
            assert(menu.depth <= menu_depth_max);
            assert(item.id <= menu_item_id_max);
            if (item.kind == .radio) assert(item.group_len > 0);

            if (menu.count == menu_item_count_max) return error.ItemsExhausted;

            if (item.kind == .submenu) {
                if (menu.depth == menu_depth_max) return error.MenuTooDeep;
            }

            menu.items[menu.count] = item;
            menu.items[menu.count].depth = menu.depth;
            menu.count += 1;
            menu.dirty = true;

            if (item.kind == .submenu) {
                menu.depth += 1;
            }

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

            var staged: [menu_item_count_max]platform_module.MenuItem = undefined;
            const staged_count = menu.stage(&staged);

            assert(staged_count <= menu.count);
            assert(platform_module.is_valid_layout(staged[0..staged_count]));

            try menu.platform.menu_build(staged[0..staged_count]);

            menu.dirty = false;
        }

        pub fn clear(menu: *Menu) void {
            menu.count = 0;
            menu.depth = 0;
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
            assert(id <= menu_item_id_max);

            const item = menu.get_item(id) orelse return false;
            return item.checked;
        }

        pub fn is_empty(menu: *const Menu) bool {
            return menu.count == 0;
        }

        pub fn submenu_end(menu: *Menu) void {
            assert(menu.depth > 0);
            assert(menu.depth <= menu_depth_max);

            menu.depth -= 1;

            assert(menu.depth < menu_depth_max);
        }

        pub fn update(menu: *Menu, id: u32, change: Change) (CapacityError || RequestError)!void {
            assert(id <= menu_item_id_max);
            assert(!std.meta.eql(change, Change{}));

            const item = menu.find_mut(id) orelse return error.ItemUnknown;

            if (change.label) |label| {
                if (label.len == 0) return error.LabelEmpty;
                if (label.len > menu_label_bytes_max) return error.LabelTooLong;
                if (!platform_module.is_valid_text(label)) return error.LabelInvalid;

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

        fn is_enabled(menu: *const Menu, index: u8) bool {
            assert(index < menu.count);

            const item = &menu.items[index];
            if (!item.enabled) return false;
            if (item.kind != .submenu) return true;

            for (menu.items[index + 1 .. menu.count]) |*child| {
                if (child.depth <= item.depth) return false;
                if (child.depth > item.depth + 1) continue;
                if (child.visible) return true;
            }

            return false;
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

        fn stage(menu: *const Menu, staged: *[menu_item_count_max]platform_module.MenuItem) u8 {
            assert(menu.count <= menu_item_count_max);

            var hidden_depth: ?u8 = null;
            var result: u8 = 0;

            for (menu.items[0..menu.count], 0..) |*item, index| {
                if (hidden_depth) |depth| {
                    if (item.depth > depth) continue;
                }

                hidden_depth = null;

                if (!item.visible) {
                    hidden_depth = item.depth;

                    continue;
                }

                staged[result] = .{
                    .checked = item.checked,
                    .depth = item.depth,
                    .enabled = menu.is_enabled(@intCast(index)),
                    .id = item.id,
                    .kind = item.kind,
                    .label = item.get_label(),
                };

                result += 1;
            }

            assert(result <= menu.count);

            return result;
        }
    };
}

const testing = std.testing;

const Fake = platform_module.Fake;
const FakeMenu = MenuType(Fake);

test MenuType {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    try menu.add(.action(1, "About"));
    try menu.add(.toggle(2, "Enabled", .{ .checked = true }));
    try menu.add(.separator());
    try menu.add(.submenu(5, "Size"));
    try menu.add(.radio(3, "Small", .{ .checked = true, .group = "size" }));
    try menu.add(.radio(4, "Large", .{ .group = "size" }));

    menu.submenu_end();

    try testing.expect(menu.is_checked(2));
    try testing.expect(menu.is_checked(3));
    try testing.expectEqual(@as(u8, 1), menu.get_item(4).?.depth);

    try menu.update(4, .{ .checked = true });

    try testing.expect(!menu.is_checked(3));
    try testing.expect(menu.is_checked(4));

    try menu.build();

    try testing.expect(!menu.dirty);
}

test "an update changes only the fields it names" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
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
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
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
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    var index: u8 = 0;

    while (index < menu_item_count_max) : (index += 1) {
        try menu.add(.action(index, "Item"));
    }

    try testing.expectError(error.ItemsExhausted, menu.add(.action(255, "Overflow")));
}

test "a hidden item stays out of the built menu but keeps its state" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    try menu.add(.action(1, "Shown"));
    try menu.add(.action(2, "Hidden"));
    try menu.update(2, .{ .visible = false });
    try menu.build();

    try testing.expect(!menu.get_item(2).?.visible);
    try testing.expectEqual(@as(u8, 2), menu.count);
}

test "clearing a menu removes every item" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    try menu.add(.action(1, "Action 1"));
    try menu.add(.submenu(2, "More"));
    try menu.add(.action(3, "Action 3"));

    menu.clear();

    try testing.expect(menu.is_empty());
    try testing.expect(menu.get_item(1) == null);
    try testing.expectEqual(@as(u8, 0), menu.depth);
}

test "a submenu holds the items added until it ends, one level deeper" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    try menu.add(.action(1, "Open"));
    try menu.add(.submenu(2, "Size"));
    try menu.add(.radio(3, "Small", .{ .checked = true, .group = "size" }));
    try menu.add(.submenu(4, "Large"));
    try menu.add(.radio(5, "Wide", .{ .group = "size" }));

    menu.submenu_end();
    menu.submenu_end();

    try menu.add(.action(6, "Exit"));

    const depths = [_]u8{ 0, 0, 1, 1, 2, 0 };

    for (menu.items[0..menu.count], depths) |*item, depth| {
        try testing.expectEqual(depth, item.depth);
    }

    try testing.expectEqual(@as(u8, 0), menu.depth);
}

test "a submenu past the depth limit is refused and leaves the menu as it was" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    var level: u8 = 0;

    while (level < menu_depth_max) : (level += 1) {
        try menu.add(.submenu(level + 1, "Deeper"));
    }

    try testing.expectError(error.MenuTooDeep, menu.add(.submenu(99, "Deepest")));
    try testing.expectEqual(menu_depth_max, menu.count);
    try testing.expectEqual(menu_depth_max, menu.depth);

    try menu.add(.action(100, "Leaf"));
    try menu.build();

    try testing.expectEqual(menu_depth_max, menu.get_item(100).?.depth);
    try testing.expectEqual(@as(u32, menu_depth_max + 1), fake.menu.item_count());
}

test "a hidden submenu takes every item inside it out of the built menu" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    try menu.add(.action(1, "Open"));
    try menu.add(.submenu(2, "Hidden"));
    try menu.add(.action(3, "Inside"));
    try menu.add(.submenu(4, "Nested"));
    try menu.add(.action(5, "Deep inside"));

    menu.submenu_end();
    menu.submenu_end();

    try menu.add(.action(6, "Exit"));
    try menu.update(2, .{ .visible = false });
    try menu.build();

    try testing.expectEqual(@as(u32, 2), fake.menu.item_count());
    try testing.expectEqual(@as(u32, 1), fake.menu.id_at(0));
    try testing.expectEqual(@as(u32, 6), fake.menu.id_at(1));
}

test "a submenu with nothing visible inside it builds disabled" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "menu" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    try menu.add(.submenu(1, "Empty"));

    menu.submenu_end();

    try menu.add(.submenu(2, "Hidden inside"));
    try menu.add(.action(3, "Hidden"));

    menu.submenu_end();

    try menu.add(.submenu(4, "Shown inside"));
    try menu.add(.action(5, "Shown"));

    menu.submenu_end();

    try menu.update(3, .{ .visible = false });
    try menu.build();

    try testing.expectEqual(@as(u32, 4), fake.menu.item_count());
    try testing.expect(!fake.menu.enabled_at(0));
    try testing.expect(!fake.menu.enabled_at(1));
    try testing.expect(fake.menu.enabled_at(2));
    try testing.expectEqual(@as(u8, 1), fake.menu.depth_at(3));
}
