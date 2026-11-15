const std = @import("std");

const icon_module = @import("ui.zig").icon;
const menu_module = @import("ui.zig").menu;
const platform = @import("platform.zig");

const assert = std.debug.assert;

const CapacityError = platform.CapacityError;
const Icon = platform.Icon;
const IconSetType = icon_module.IconSetType;
const MenuType = menu_module.MenuType;
const RequestError = platform.RequestError;

pub fn IconBuilderType(comptime Platform: type) type {
    return struct {
        deferred_error: ?(CapacityError || RequestError),
        icons: *IconSet,

        const IconBuilder = @This();
        const IconSet = IconSetType(Platform);

        pub fn init(icons: *IconSet) IconBuilder {
            return IconBuilder{ .deferred_error = null, .icons = icons };
        }

        pub fn pixels(builder: IconBuilder, name: []const u8, pixmap: Icon.Pixmap) IconBuilder {
            assert(builder.icons.count <= platform.icon_count_max);
            assert(name.len > 0);
            assert(pixmap.is_valid());

            return builder.add(name, .{ .pixels = pixmap });
        }

        pub fn stock(builder: IconBuilder, name: []const u8, kind: Icon.Stock) IconBuilder {
            assert(builder.icons.count <= platform.icon_count_max);
            assert(name.len > 0);
            assert(kind.is_valid());

            return builder.add(name, .{ .stock = kind });
        }

        pub fn done(builder: IconBuilder) (CapacityError || RequestError)!*IconSet {
            assert(builder.icons.count <= platform.icon_count_max);

            if (builder.deferred_error) |err| {
                return err;
            }

            return builder.icons;
        }

        fn add(builder: IconBuilder, name: []const u8, source: Icon.Source) IconBuilder {
            assert(builder.icons.count <= platform.icon_count_max);
            assert(name.len > 0);
            assert(source.is_valid());

            if (builder.deferred_error != null) {
                return builder;
            }

            var result = builder;

            result.icons.add(name, source) catch |err| {
                result.deferred_error = err;
            };

            return result;
        }
    };
}

pub fn MenuBuilderType(comptime Platform: type) type {
    return struct {
        deferred_error: ?CapacityError,
        menu: *Menu,

        const Menu = MenuType(Platform);
        const MenuBuilder = @This();

        pub fn init(menu: *Menu) MenuBuilder {
            return MenuBuilder{ .deferred_error = null, .menu = menu };
        }

        pub fn action(builder: MenuBuilder, id: u32, label: []const u8) MenuBuilder {
            assert(builder.menu.count <= platform.menu_item_count_max);
            assert(id <= platform.menu_item_id_max);
            assert(label.len > 0);
            assert(label.len <= platform.menu_label_bytes_max);

            return builder.add(.action(id, label));
        }

        pub fn radio(
            builder: MenuBuilder,
            id: u32,
            label: []const u8,
            options: Menu.Item.Radio,
        ) MenuBuilder {
            assert(builder.menu.count <= platform.menu_item_count_max);
            assert(id <= platform.menu_item_id_max);
            assert(label.len > 0);
            assert(label.len <= platform.menu_label_bytes_max);
            assert(options.group.len > 0);
            assert(options.group.len <= platform.menu_group_bytes_max);

            return builder.add(.radio(id, label, options));
        }

        pub fn separator(builder: MenuBuilder) MenuBuilder {
            assert(builder.menu.count <= platform.menu_item_count_max);

            return builder.add(.separator());
        }

        pub fn submenu_begin(builder: MenuBuilder, id: u32, label: []const u8) MenuBuilder {
            assert(builder.menu.count <= platform.menu_item_count_max);
            assert(id <= platform.menu_item_id_max);
            assert(label.len > 0);
            assert(label.len <= platform.menu_label_bytes_max);

            return builder.add(.submenu(id, label));
        }

        pub fn submenu_end(builder: MenuBuilder) MenuBuilder {
            assert(builder.menu.count <= platform.menu_item_count_max);
            assert(builder.menu.depth <= platform.menu_depth_max);

            if (builder.deferred_error != null) {
                return builder;
            }

            builder.menu.submenu_end();

            return builder;
        }

        pub fn toggle(
            builder: MenuBuilder,
            id: u32,
            label: []const u8,
            options: Menu.Item.Toggle,
        ) MenuBuilder {
            assert(builder.menu.count <= platform.menu_item_count_max);
            assert(id <= platform.menu_item_id_max);
            assert(label.len > 0);
            assert(label.len <= platform.menu_label_bytes_max);

            return builder.add(.toggle(id, label, options));
        }

        pub fn done(builder: MenuBuilder) CapacityError!*Menu {
            assert(builder.menu.count <= platform.menu_item_count_max);

            if (builder.deferred_error) |err| {
                return err;
            }

            return builder.menu;
        }

        fn add(builder: MenuBuilder, item: Menu.Item) MenuBuilder {
            assert(builder.menu.count <= platform.menu_item_count_max);
            assert(item.id <= platform.menu_item_id_max);
            if (item.kind == .radio) assert(item.group_len > 0);

            if (builder.deferred_error != null) {
                return builder;
            }

            var result = builder;

            result.menu.add(item) catch |err| {
                result.deferred_error = err;
            };

            return result;
        }
    };
}

const testing = std.testing;

const Fake = platform.Fake;
const FakeIconBuilder = IconBuilderType(Fake);
const FakeIconSet = IconSetType(Fake);
const FakeMenu = MenuType(Fake);
const FakeMenuBuilder = MenuBuilderType(Fake);

test IconBuilderType {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "builder" });
    defer fake.deinit();

    var icons = FakeIconSet.init(&fake);
    defer icons.deinit();

    const argb: [16]u8 = @splat(0);

    const built = try FakeIconBuilder.init(&icons)
        .stock("default", .application)
        .pixels("drawn", Icon.Pixmap.init(&argb, 2, 2))
        .done();

    try testing.expectEqual(&icons, built);
    try testing.expectEqual(@as(u8, 2), icons.count);
}

test MenuBuilderType {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "builder" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    const built = try FakeMenuBuilder.init(&menu)
        .action(100, "Open")
        .separator()
        .toggle(200, "Enable Feature", .{ .checked = true })
        .toggle(201, "Show Notifications", .{})
        .separator()
        .submenu_begin(300, "Size")
        .radio(301, "Small", .{ .group = "size" })
        .radio(302, "Medium", .{ .checked = true, .group = "size" })
        .submenu_end()
        .separator()
        .action(999, "Exit")
        .done();

    try testing.expectEqual(&menu, built);
    try testing.expectEqual(@as(u8, 10), menu.count);
    try testing.expect(menu.is_checked(200));
    try testing.expect(!menu.is_checked(201));
    try testing.expect(!menu.is_checked(301));
    try testing.expect(menu.is_checked(302));
    try testing.expectEqual(@as(u8, 1), menu.get_item(302).?.depth);
    try testing.expectEqual(@as(u8, 0), menu.get_item(999).?.depth);
}

test "a submenu end after a refused submenu is skipped with it" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "builder" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    var builder = FakeMenuBuilder.init(&menu);
    var index: u8 = 0;

    while (index < platform.menu_item_count_max) : (index += 1) {
        builder = builder.action(index, "Item");
    }

    const result = builder
        .submenu_begin(500, "Overflow")
        .action(501, "Inside")
        .submenu_end()
        .done();

    try testing.expectError(error.ItemsExhausted, result);
    try testing.expectEqual(@as(u8, 0), menu.depth);
}

test "a submenu past the depth limit fails the build and skips its end" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "builder" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    var builder = FakeMenuBuilder.init(&menu);
    var level: u8 = 0;

    while (level < platform.menu_depth_max) : (level += 1) {
        builder = builder.submenu_begin(level + 1, "Deeper");
    }

    const result = builder
        .submenu_begin(99, "Deepest")
        .submenu_end()
        .done();

    try testing.expectError(error.MenuTooDeep, result);
    try testing.expectEqual(platform.menu_depth_max, menu.depth);
}

test "an icon builder keeps the first error and skips the rest" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "builder" });
    defer fake.deinit();

    var icons = FakeIconSet.init(&fake);
    defer icons.deinit();

    const result = FakeIconBuilder.init(&icons)
        .stock("icon", .application)
        .stock("icon", .shield)
        .stock("other", .shield)
        .done();

    try testing.expectError(error.IconDuplicate, result);
    try testing.expectEqual(@as(u8, 1), icons.count);
}

test "a radio added checked clears the rest of its group" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "builder" });
    defer fake.deinit();

    var menu = FakeMenu.init(&fake);
    defer menu.deinit();

    _ = try FakeMenuBuilder.init(&menu)
        .radio(1, "Option 1", .{ .checked = true, .group = "group" })
        .radio(2, "Option 2", .{ .checked = true, .group = "group" })
        .radio(3, "Option 3", .{ .group = "group" })
        .done();

    try testing.expect(!menu.is_checked(1));
    try testing.expect(menu.is_checked(2));
    try testing.expect(!menu.is_checked(3));
}
