const std = @import("std");

const icon_module = @import("ui/icon.zig");
const menu_module = @import("ui/menu.zig");
const platform = @import("platform.zig");

const assert = std.debug.assert;

const CapacityError = platform.CapacityError;
const Icon = platform.Icon;
const IconSet = icon_module.IconSet;
const Menu = menu_module.Menu;
const RequestError = platform.RequestError;

pub const IconBuilder = struct {
    deferred_error: ?(CapacityError || RequestError),
    icons: *IconSet,

    pub fn init(icons: *IconSet) IconBuilder {
        return IconBuilder{
            .deferred_error = null,
            .icons = icons,
        };
    }

    pub fn pixels(builder: IconBuilder, name: []const u8, pixmap: Icon.Pixmap) IconBuilder {
        assert(pixmap.is_valid());

        return builder.add(name, .{ .pixels = pixmap });
    }

    pub fn stock(builder: IconBuilder, name: []const u8, kind: Icon.Stock) IconBuilder {
        assert(kind.is_valid());

        return builder.add(name, .{ .stock = kind });
    }

    pub fn done(builder: IconBuilder) (CapacityError || RequestError)!*IconSet {
        if (builder.deferred_error) |err| {
            return err;
        }

        return builder.icons;
    }

    fn add(builder: IconBuilder, name: []const u8, source: Icon.Source) IconBuilder {
        assert(name.len > 0);

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

pub const MenuBuilder = struct {
    deferred_error: ?CapacityError,
    menu: *Menu,

    pub fn init(menu: *Menu) MenuBuilder {
        return MenuBuilder{
            .deferred_error = null,
            .menu = menu,
        };
    }

    pub fn action(builder: MenuBuilder, id: u32, label: []const u8) MenuBuilder {
        return builder.add(.action(id, label));
    }

    pub fn radio(
        builder: MenuBuilder,
        id: u32,
        label: []const u8,
        options: Menu.Item.Radio,
    ) MenuBuilder {
        return builder.add(.radio(id, label, options));
    }

    pub fn separator(builder: MenuBuilder) MenuBuilder {
        return builder.add(.separator());
    }

    pub fn toggle(
        builder: MenuBuilder,
        id: u32,
        label: []const u8,
        options: Menu.Item.Toggle,
    ) MenuBuilder {
        return builder.add(.toggle(id, label, options));
    }

    pub fn done(builder: MenuBuilder) CapacityError!*Menu {
        if (builder.deferred_error) |err| {
            return err;
        }

        return builder.menu;
    }

    fn add(builder: MenuBuilder, item: Menu.Item) MenuBuilder {
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

const testing = std.testing;

test IconBuilder {
    var icons = IconSet.init();
    defer icons.deinit();

    const argb: [16]u8 = @splat(0);

    const built = try IconBuilder.init(&icons)
        .stock("default", .application)
        .pixels("drawn", Icon.Pixmap.init(&argb, 2, 2))
        .done();

    try testing.expectEqual(&icons, built);
    try testing.expectEqual(@as(u8, 2), icons.count);
}

test MenuBuilder {
    var menu = Menu.init();
    defer menu.deinit();

    const built = try MenuBuilder.init(&menu)
        .action(100, "Open")
        .separator()
        .toggle(200, "Enable Feature", .{ .checked = true })
        .toggle(201, "Show Notifications", .{})
        .separator()
        .radio(300, "Small", .{ .group = "size" })
        .radio(301, "Medium", .{ .checked = true, .group = "size" })
        .separator()
        .action(999, "Exit")
        .done();

    try testing.expectEqual(&menu, built);
    try testing.expectEqual(@as(u8, 9), menu.count);
    try testing.expect(menu.is_checked(200));
    try testing.expect(!menu.is_checked(201));
    try testing.expect(!menu.is_checked(300));
    try testing.expect(menu.is_checked(301));
}

test "an icon builder keeps the first error and skips the rest" {
    var icons = IconSet.init();
    defer icons.deinit();

    const result = IconBuilder.init(&icons)
        .stock("icon", .application)
        .stock("icon", .shield)
        .stock("other", .shield)
        .done();

    try testing.expectError(error.IconDuplicate, result);
    try testing.expectEqual(@as(u8, 1), icons.count);
}

test "a radio added checked clears the rest of its group" {
    var menu = Menu.init();
    defer menu.deinit();

    _ = try MenuBuilder.init(&menu)
        .radio(1, "Option 1", .{ .checked = true, .group = "group" })
        .radio(2, "Option 2", .{ .checked = true, .group = "group" })
        .radio(3, "Option 3", .{ .group = "group" })
        .done();

    try testing.expect(!menu.is_checked(1));
    try testing.expect(menu.is_checked(2));
    try testing.expect(!menu.is_checked(3));
}
