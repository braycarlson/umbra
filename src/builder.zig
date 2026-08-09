const std = @import("std");

const platform = @import("platform.zig");
const ui = @import("ui/root.zig");

const assert = std.debug.assert;

const IconError = ui.IconError;
const IconManager = ui.IconManager;
const MenuError = ui.MenuError;
const MenuManager = ui.MenuManager;

pub const IconBuilder = struct {
    deferred_error: ?IconError,
    manager: *IconManager,

    pub fn init(manager: *IconManager) IconBuilder {
        return IconBuilder{
            .deferred_error = null,
            .manager = manager,
        };
    }

    pub fn file(builder: IconBuilder, name: []const u8, file_path: []const u8) IconBuilder {
        assert(name.len > 0);
        assert(file_path.len > 0);

        if (builder.deferred_error != null) {
            return builder;
        }

        var result = builder;

        result.manager.add_file(name, file_path) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn pixels(builder: IconBuilder, name: []const u8, pixmap: ui.IconPixmap) IconBuilder {
        assert(name.len > 0);
        assert(pixmap.is_valid());

        if (builder.deferred_error != null) {
            return builder;
        }

        var result = builder;

        result.manager.add_pixels(name, pixmap) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn resource(builder: IconBuilder, name: []const u8, id: u32) IconBuilder {
        if (comptime !platform.capabilities.icon_resource) {
            @compileError("wisp: IconBuilder.resource requires the icon_resource capability");
        }

        assert(name.len > 0);
        assert(id > 0);

        if (builder.deferred_error != null) {
            return builder;
        }

        var result = builder;

        result.manager.add_resource(name, id) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn stock(builder: IconBuilder, name: []const u8, kind: ui.IconStock) IconBuilder {
        assert(name.len > 0);

        if (builder.deferred_error != null) {
            return builder;
        }

        var result = builder;

        result.manager.add_stock(name, kind) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn done(builder: IconBuilder) IconError!*IconManager {
        if (builder.deferred_error) |err| {
            return err;
        }

        return builder.manager;
    }
};

pub const MenuBuilder = struct {
    deferred_error: ?MenuError,
    manager: *MenuManager,

    pub fn init(manager: *MenuManager) MenuBuilder {
        return MenuBuilder{
            .deferred_error = null,
            .manager = manager,
        };
    }

    pub fn action(builder: MenuBuilder, id: u32, label: []const u8) MenuBuilder {
        assert(label.len > 0);

        if (builder.deferred_error != null) {
            return builder;
        }

        var result = builder;

        result.manager.add_action(id, label) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn separator(builder: MenuBuilder) MenuBuilder {
        if (builder.deferred_error != null) {
            return builder;
        }

        var result = builder;

        result.manager.add_separator() catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn toggle(builder: MenuBuilder, id: u32, label: []const u8, initial: bool) MenuBuilder {
        assert(label.len > 0);

        if (builder.deferred_error != null) {
            return builder;
        }

        var result = builder;

        result.manager.add_toggle(id, label, initial) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn radio(
        builder: MenuBuilder,
        id: u32,
        label: []const u8,
        group: []const u8,
        initial: bool,
    ) MenuBuilder {
        assert(label.len > 0);
        assert(group.len > 0);

        if (builder.deferred_error != null) {
            return builder;
        }

        var result = builder;

        result.manager.add_radio(id, label, group, initial) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn done(builder: MenuBuilder) MenuError!*MenuManager {
        if (builder.deferred_error) |err| {
            return err;
        }

        return builder.manager;
    }
};

const testing = std.testing;

test "an icon builder carries the manager it was built from" {
    var manager = IconManager.init();
    defer manager.deinit();

    const builder = IconBuilder.init(&manager);

    try testing.expectEqual(&manager, builder.manager);
}

test "an icon builder adds a resource icon" {
    var manager = IconManager.init();
    defer manager.deinit();

    _ = IconBuilder.init(&manager)
        .resource("icon1", 100);

    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "an icon builder adds a stock icon" {
    var manager = IconManager.init();
    defer manager.deinit();

    _ = IconBuilder.init(&manager)
        .stock("app", .application);

    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "an icon builder adds a file icon" {
    var manager = IconManager.init();
    defer manager.deinit();

    _ = IconBuilder.init(&manager)
        .file("custom", "icon.ico");

    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "an icon builder adds a pixmap icon" {
    var manager = IconManager.init();
    defer manager.deinit();

    const argb = [_]u8{0} ** 16;

    _ = IconBuilder.init(&manager)
        .pixels("pixels", ui.IconPixmap.init(&argb, 2, 2));

    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "finishing an icon builder gives back the manager" {
    var manager = IconManager.init();
    defer manager.deinit();

    const result = try IconBuilder.init(&manager).done();

    try testing.expectEqual(&manager, result);
}

test "IconBuilder chaining works" {
    var manager = IconManager.init();
    defer manager.deinit();

    _ = try IconBuilder.init(&manager)
        .resource("icon1", 100)
        .resource("icon2", 101)
        .stock("app", .application)
        .done();

    try testing.expectEqual(@as(u8, 3), manager.count);
}

test "a menu builder carries the manager it was built from" {
    var manager = MenuManager.init();
    defer manager.deinit();

    const builder = MenuBuilder.init(&manager);

    try testing.expectEqual(&manager, builder.manager);
}

test "a menu builder adds an action item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = MenuBuilder.init(&manager)
        .action(1, "Test Action");

    try testing.expectEqual(@as(u8, 1), manager.count);

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expectEqual(ui.MenuItemKind.action, item.?.kind);
}

test "a menu builder adds a separator" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = MenuBuilder.init(&manager)
        .separator();

    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "a menu builder adds a toggle item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = MenuBuilder.init(&manager)
        .toggle(1, "Toggle", true);

    try testing.expectEqual(@as(u8, 1), manager.count);

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expectEqual(ui.MenuItemKind.toggle, item.?.kind);
    try testing.expect(item.?.checked);
}

test "a menu builder adds a radio item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = MenuBuilder.init(&manager)
        .radio(1, "Option 1", "group", true);

    try testing.expectEqual(@as(u8, 1), manager.count);

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expectEqual(ui.MenuItemKind.radio, item.?.kind);
}

test "finishing a menu builder gives back the manager" {
    var manager = MenuManager.init();
    defer manager.deinit();

    const result = try MenuBuilder.init(&manager).done();

    try testing.expectEqual(&manager, result);
}

test "MenuBuilder chaining works" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = try MenuBuilder.init(&manager)
        .action(1, "Action 1")
        .action(2, "Action 2")
        .separator()
        .toggle(3, "Toggle", false)
        .separator()
        .radio(4, "Option A", "group", true)
        .radio(5, "Option B", "group", false)
        .done();

    try testing.expectEqual(@as(u8, 7), manager.count);
}

test "MenuBuilder radio group selection" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = try MenuBuilder.init(&manager)
        .radio(1, "Option 1", "group", false)
        .radio(2, "Option 2", "group", true)
        .radio(3, "Option 3", "group", false)
        .done();

    try testing.expect(!manager.is_checked(1));
    try testing.expect(manager.is_checked(2));
    try testing.expect(!manager.is_checked(3));
}

test "IconBuilder surfaces duplicate name error" {
    var manager = IconManager.init();
    defer manager.deinit();

    const result = IconBuilder.init(&manager)
        .resource("icon", 100)
        .resource("icon", 101)
        .done();

    try testing.expectError(error.DuplicateName, result);
    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "MenuBuilder complex menu structure" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = try MenuBuilder.init(&manager)
        .action(100, "Open")
        .action(101, "Save")
        .separator()
        .toggle(200, "Enable Feature", true)
        .toggle(201, "Show Notifications", false)
        .separator()
        .radio(300, "Small", "size", false)
        .radio(301, "Medium", "size", true)
        .radio(302, "Large", "size", false)
        .separator()
        .action(999, "Exit")
        .done();

    try testing.expectEqual(@as(u8, 11), manager.count);

    try testing.expect(manager.is_checked(200));
    try testing.expect(!manager.is_checked(201));

    const selection = manager.get_radio_selection("size");

    try testing.expect(selection != null);
    try testing.expectEqual(@as(u32, 301), selection.?);
}
