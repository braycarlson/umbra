const std = @import("std");
const testing = std.testing;

const wisp = @import("wisp");

const IconBuilder = wisp.IconBuilder;
const IconManager = wisp.IconManager;
const MenuBuilder = wisp.MenuBuilder;
const MenuManager = wisp.MenuManager;

test "IconBuilder.init creates builder with manager" {
    var manager = IconManager.init();
    defer manager.deinit();

    const builder = IconBuilder.init(&manager);

    try testing.expectEqual(&manager, builder.manager);
}

test "IconBuilder.resource adds resource icon" {
    var manager = IconManager.init();
    defer manager.deinit();

    _ = IconBuilder.init(&manager)
        .resource("icon1", 100);

    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "IconBuilder.system adds system icon" {
    var manager = IconManager.init();
    defer manager.deinit();

    _ = IconBuilder.init(&manager)
        .system("app", wisp.IconSystem.application);

    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "IconBuilder.done returns manager pointer" {
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
        .system("app", wisp.IconSystem.application)
        .done();

    try testing.expectEqual(@as(u8, 3), manager.count);
}

test "MenuBuilder.init creates builder with manager" {
    var manager = MenuManager.init();
    defer manager.deinit();

    const builder = MenuBuilder.init(&manager);

    try testing.expectEqual(&manager, builder.manager);
}

test "MenuBuilder.action adds action item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = MenuBuilder.init(&manager)
        .action(1, "Test Action");

    try testing.expectEqual(@as(u8, 1), manager.count);

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expectEqual(wisp.MenuItemKind.action, item.?.kind);
}

test "MenuBuilder.separator adds separator" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = MenuBuilder.init(&manager)
        .separator();

    try testing.expectEqual(@as(u8, 1), manager.count);
}

test "MenuBuilder.toggle adds toggle item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = MenuBuilder.init(&manager)
        .toggle(1, "Toggle", true);

    try testing.expectEqual(@as(u8, 1), manager.count);

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expectEqual(wisp.MenuItemKind.toggle, item.?.kind);
    try testing.expect(item.?.checked);
}

test "MenuBuilder.radio adds radio item" {
    var manager = MenuManager.init();
    defer manager.deinit();

    _ = MenuBuilder.init(&manager)
        .radio(1, "Option 1", "group", true);

    try testing.expectEqual(@as(u8, 1), manager.count);

    const item = manager.get_item(1);

    try testing.expect(item != null);
    try testing.expectEqual(wisp.MenuItemKind.radio, item.?.kind);
}

test "MenuBuilder.done returns manager pointer" {
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
