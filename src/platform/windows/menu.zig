const std = @import("std");

const w32 = @import("win32.zig");

const interface = @import("../interface.zig");
const Window = @import("window.zig");

const assert = std.debug.assert;

const Item = interface.MenuItem;
const PlatformError = interface.PlatformError;

const Menu = @This();

current: ?NativeMenu,
window: *const Window,

pub const label_units_max: u32 = interface.menu_label_bytes_max + 1;
const state_checked: u32 = 0x00000008;
const state_default_item: u32 = 0x00001000;
const state_disabled: u32 = 0x00000002;
const state_grayed: u32 = 0x00000001;
const state_hilite: u32 = 0x00000080;
const show_left_align: u32 = 0x0000;
const show_center_align: u32 = 0x0004;
const show_right_align: u32 = 0x0008;
const show_top_align: u32 = 0x0000;
const show_vcenter_align: u32 = 0x0010;
const show_bottom_align: u32 = 0x0020;
const show_no_notify: u32 = 0x0080;
const show_return_command: u32 = 0x0100;
const show_left_button: u32 = 0x0000;
const show_right_button: u32 = 0x0002;
const show_no_animate: u32 = 0x4000;
const show_layout_rtl: u32 = 0x8000;
const show_horizontal_animate: u32 = 0x0400;
const show_vertical_animate: u32 = 0x1000;
const show_recurse: u32 = 0x0001;
const iteration_max: u32 = 1000;

pub const CreateOptions = struct {
    popup: bool = true,
};

pub const ItemType = enum(u8) {
    bitmap = 0,
    owner_draw = 1,
    separator = 2,
    string = 3,
};

pub const ItemState = struct {
    checked: bool = false,
    default_item: bool = false,
    disabled: bool = false,
    grayed: bool = false,
    hilite: bool = false,

    pub fn to_uint(state: ItemState) u32 {
        var result: u32 = 0;

        if (state.checked) result |= state_checked;
        if (state.default_item) result |= state_default_item;
        if (state.disabled) result |= state_disabled;
        if (state.grayed) result |= state_grayed;
        if (state.hilite) result |= state_hilite;

        return result;
    }
};

pub const ItemOptions = struct {
    bitmap: ?w32.HBITMAP = null,
    checked_bitmap: ?w32.HBITMAP = null,
    data: u64 = 0,
    id: u32 = 0,
    item_type: ItemType = .string,
    label: []const u8 = "",
    state: ItemState = .{},
    sub: ?*const NativeMenu = null,
    unchecked_bitmap: ?w32.HBITMAP = null,
};

pub const ShowOptions = struct {
    bottom_align: bool = false,
    center_align: bool = false,
    exclude_rect: ?*const w32.RECT = null,
    horizontal_animate: bool = false,
    layout_rtl: bool = false,
    left_align: bool = true,
    left_button: bool = true,
    no_animate: bool = false,
    no_notify: bool = false,
    recurse: bool = false,
    return_command: bool = true,
    right_align: bool = false,
    right_button: bool = false,
    top_align: bool = true,
    vcenter_align: bool = false,
    vertical_animate: bool = false,
    x: ?i32 = null,
    y: ?i32 = null,

    pub fn to_flags(options: ShowOptions) u32 {
        if (options.x != null) assert(options.y != null);
        if (options.y != null) assert(options.x != null);

        var result: u32 = 0;

        if (options.left_align) result |= show_left_align;
        if (options.center_align) result |= show_center_align;
        if (options.right_align) result |= show_right_align;
        if (options.top_align) result |= show_top_align;
        if (options.vcenter_align) result |= show_vcenter_align;
        if (options.bottom_align) result |= show_bottom_align;
        if (options.no_notify) result |= show_no_notify;
        if (options.return_command) result |= show_return_command;
        if (options.left_button) result |= show_left_button;
        if (options.right_button) result |= show_right_button;
        if (options.no_animate) result |= show_no_animate;
        if (options.layout_rtl) result |= show_layout_rtl;
        if (options.horizontal_animate) result |= show_horizontal_animate;
        if (options.vertical_animate) result |= show_vertical_animate;
        if (options.recurse) result |= show_recurse;

        return result;
    }
};

pub const NativeError = error{
    CreationFailed,
    GetInfoFailed,
    InsertFailed,
    InvalidLabel,
    ModifyFailed,
    RemoveFailed,
};

fn apply_item_attributes(info: *w32.MENUITEMINFOW, options: ItemOptions) void {
    if (options.sub) |sub| assert(sub.is_valid());

    if (options.sub) |sub| {
        info.fMask |= w32.MIIM_SUBMENU;
        info.hSubMenu = sub.handle;
    }

    if (options.checked_bitmap) |bitmap| {
        info.fMask |= w32.MIIM_CHECKMARKS;
        info.hbmpChecked = bitmap;
    }

    if (options.unchecked_bitmap) |bitmap| {
        info.fMask |= w32.MIIM_CHECKMARKS;
        info.hbmpUnchecked = bitmap;
    }

    if (options.bitmap) |bitmap| {
        info.fMask |= w32.MIIM_BITMAP;
        info.hbmpItem = bitmap;
    }

    if (options.data != 0) {
        info.fMask |= w32.MIIM_DATA;
        info.dwItemData = options.data;
    }
}

pub const NativeMenu = struct {
    handle: w32.HMENU,
    owned: bool = true,

    pub fn create(options: CreateOptions) NativeError!NativeMenu {
        const handle = if (options.popup)
            w32.CreatePopupMenu()
        else
            w32.CreateMenu();

        if (handle == null) {
            return NativeError.CreationFailed;
        }

        assert(handle != null);

        const result = NativeMenu{ .handle = handle.?, .owned = true };

        return result;
    }

    pub fn clear(menu: *const NativeMenu) u32 {
        assert(menu.is_valid());

        var removed: u32 = 0;
        var iteration: u32 = 0;

        while (menu.count() > 0) {
            assert(iteration < iteration_max);

            if (iteration >= iteration_max) {
                break;
            }

            if (w32.DeleteMenu(menu.handle, 0, w32.MF_BYPOSITION) == 0) {
                break;
            }

            removed += 1;
            iteration += 1;
        }

        return removed;
    }

    pub fn count(menu: *const NativeMenu) u32 {
        assert(menu.is_valid());

        const raw_result = w32.GetMenuItemCount(menu.handle);

        if (raw_result < 0) {
            return 0;
        }

        const result: u32 = @intCast(raw_result);

        assert(result <= interface.menu_item_count_max);

        return result;
    }

    pub fn destroy(menu: *const NativeMenu) bool {
        if (!menu.owned) return true;
        if (!menu.is_valid()) return true;
        return w32.DestroyMenu(menu.handle) != 0;
    }

    pub fn insert(menu: *const NativeMenu, position: u32, options: ItemOptions) NativeError!void {
        assert(menu.is_valid());
        assert(position < interface.menu_item_count_max);
        assert(options.label.len < label_units_max);
        if (options.item_type != .separator) assert(options.id >= id_offset);

        var info = std.mem.zeroes(w32.MENUITEMINFOW);
        var label_wide: [label_units_max]u16 = undefined;

        info.cbSize = @sizeOf(w32.MENUITEMINFOW);

        if (options.item_type == .separator) {
            info.fMask = w32.MIIM_FTYPE;
            info.fType = w32.MFT_SEPARATOR;
        } else {
            info.fMask = w32.MIIM_FTYPE | w32.MIIM_ID | w32.MIIM_STATE | w32.MIIM_STRING;

            info.fType = switch (options.item_type) {
                .bitmap => w32.MFT_BITMAP,
                .owner_draw => w32.MFT_OWNERDRAW,
                .separator => w32.MFT_SEPARATOR,
                .string => w32.MFT_STRING,
            };

            info.fState = options.state.to_uint();
            info.wID = options.id;

            if (options.label.len > 0) {
                assert(options.label.len < label_units_max);

                const length = std.unicode.utf8ToUtf16Le(&label_wide, options.label) catch {
                    return NativeError.InvalidLabel;
                };

                if (length >= label_units_max) {
                    return NativeError.InvalidLabel;
                }

                label_wide[length] = 0;
                info.dwTypeData = @ptrCast(&label_wide);
                info.cch = @intCast(length);
            }
        }

        apply_item_attributes(&info, options);

        const status = w32.InsertMenuItemW(menu.handle, position, w32.TRUE, &info);

        if (status == 0) {
            return NativeError.InsertFailed;
        }
    }

    pub fn is_valid(menu: *const NativeMenu) bool {
        return @intFromPtr(menu.handle) != 0;
    }

    pub fn show(menu: *const NativeMenu, hwnd: w32.HWND, options: ShowOptions) u32 {
        assert(menu.is_valid());
        assert(w32.IsWindow(hwnd) != 0);
        if (options.x != null) assert(options.y != null);
        if (options.y != null) assert(options.x != null);

        const point = show_position(options);
        const flags: u32 = options.to_flags();

        _ = w32.SetForegroundWindow(hwnd);

        const command = w32.TrackPopupMenuEx(menu.handle, flags, point.x, point.y, hwnd, null);

        _ = w32.PostMessageW(hwnd, 0, 0, 0);

        const result: u32 = @intCast(command);

        if (result != 0) assert(result >= id_offset);

        return result;
    }

    fn show_position(options: ShowOptions) w32.POINT {
        if (options.x != null) assert(options.y != null);
        if (options.y != null) assert(options.x != null);

        const origin = w32.POINT{ .x = 0, .y = 0 };

        if (options.x) |x| {
            if (options.y) |y| {
                return .{ .x = x, .y = y };
            }
        }

        var point: w32.POINT = undefined;

        if (w32.GetCursorPos(&point) == 0) {
            return origin;
        }

        return point;
    }
};

const Parent = struct {
    menu: NativeMenu,
    position: u32,
};

pub const id_offset: u32 = 1000;

comptime {
    assert(id_offset > 0);
    assert(label_units_max > interface.menu_label_bytes_max);
    assert(interface.menu_item_id_max + id_offset <= std.math.maxInt(i32));
}

pub fn init(menu: *Menu, window: *const Window) void {
    menu.* = .{ .current = null, .window = window };

    assert(menu.current == null);
    assert(menu.window == window);
}

pub fn build(menu: *Menu, items: []const Item) PlatformError!void {
    assert(items.len <= interface.menu_item_count_max);
    assert(interface.is_valid_layout(items));

    if (menu.current == null) {
        menu.current = NativeMenu.create(.{}) catch {
            return error.MenuBuildFailed;
        };
    }

    assert(menu.current != null);

    _ = menu.current.?.clear();

    var parents: [interface.menu_depth_max + 1]Parent = undefined;

    parents[0] = .{ .menu = menu.current.?, .position = 0 };

    for (items) |*item| {
        assert(item.is_valid());
        assert(item.depth <= interface.menu_depth_max);

        const parent = &parents[item.depth];

        if (item.kind == .submenu) {
            const submenu = try insert_submenu(parent, item);

            parents[item.depth + 1] = .{ .menu = submenu, .position = 0 };
        } else {
            try insert_item(parent, item);
        }

        parent.position += 1;
    }

    assert(parents[0].position <= items.len);
}

fn insert_item(parent: *const Parent, item: *const Item) PlatformError!void {
    assert(item.kind != .submenu);
    assert(parent.position < interface.menu_item_count_max);

    const options = switch (item.kind) {
        .separator => ItemOptions{ .item_type = .separator },
        .action, .radio, .toggle => ItemOptions{
            .id = item.id + id_offset,
            .label = item.label,
            .state = .{ .checked = item.checked, .disabled = !item.enabled },
        },
        .submenu => unreachable,
    };

    parent.menu.insert(parent.position, options) catch {
        return error.MenuBuildFailed;
    };
}

fn insert_submenu(parent: *const Parent, item: *const Item) PlatformError!NativeMenu {
    assert(item.kind == .submenu);
    assert(item.depth < interface.menu_depth_max);
    assert(parent.position < interface.menu_item_count_max);

    const submenu = NativeMenu.create(.{}) catch {
        return error.MenuBuildFailed;
    };

    parent.menu.insert(parent.position, .{
        .id = item.id + id_offset,
        .label = item.label,
        .state = .{ .disabled = !item.enabled },
        .sub = &submenu,
    }) catch {
        _ = submenu.destroy();

        return error.MenuBuildFailed;
    };

    return submenu;
}

pub fn destroy(menu: *Menu) void {
    const handle = menu.current orelse return;

    menu.current = null;

    _ = handle.destroy();

    assert(menu.current == null);
}

pub fn track(menu: *const Menu) ?u32 {
    const handle = menu.current orelse return null;
    const hwnd = menu.window.handle orelse return null;
    const command = handle.show(hwnd, .{});

    if (command < id_offset) {
        return null;
    }

    const result = command - id_offset;

    assert(result <= interface.menu_item_id_max);

    return result;
}

const testing = std.testing;

test "ItemType enum values" {
    try testing.expectEqual(@as(u8, 0), @backingInt(ItemType.bitmap));
    try testing.expectEqual(@as(u8, 1), @backingInt(ItemType.owner_draw));
    try testing.expectEqual(@as(u8, 2), @backingInt(ItemType.separator));
    try testing.expectEqual(@as(u8, 3), @backingInt(ItemType.string));
}

test "ItemState defaults to unchecked enabled" {
    const state = ItemState{};

    try testing.expect(!state.checked);
    try testing.expect(!state.default_item);
    try testing.expect(!state.disabled);
    try testing.expect(!state.grayed);
    try testing.expect(!state.hilite);
}

test "a default item state converts to no bits" {
    const state = ItemState{};

    try testing.expectEqual(@as(u32, 0), state.to_uint());
}

test "an item state carries its checked flag" {
    const state = ItemState{ .checked = true };

    try testing.expectEqual(@as(u32, 0x0008), state.to_uint());
}

test "an item state carries its disabled flag" {
    const state = ItemState{ .disabled = true };

    try testing.expectEqual(@as(u32, 0x0002), state.to_uint());
}

test "an item state carries its grayed flag" {
    const state = ItemState{ .grayed = true };

    try testing.expectEqual(@as(u32, 0x0001), state.to_uint());
}

test "an item state carries its highlight flag" {
    const state = ItemState{ .hilite = true };

    try testing.expectEqual(@as(u32, 0x0080), state.to_uint());
}

test "an item state carries its default item flag" {
    const state = ItemState{ .default_item = true };

    try testing.expectEqual(@as(u32, 0x1000), state.to_uint());
}

test "an item state combines several flags" {
    const state = ItemState{ .checked = true, .hilite = true };

    try testing.expectEqual(@as(u32, 0x0088), state.to_uint());
}

test "ItemOptions defaults" {
    const options = ItemOptions{};

    try testing.expectEqual(ItemType.string, options.item_type);
    try testing.expectEqual(@as(u32, 0), options.id);
    try testing.expectEqual(@as(usize, 0), options.label.len);
    try testing.expect(options.sub == null);
    try testing.expect(!options.state.checked);
    try testing.expect(!options.state.disabled);
}

test "ShowOptions defaults" {
    const options = ShowOptions{};

    try testing.expect(!options.center_align);
    try testing.expect(!options.right_align);
    try testing.expect(!options.vcenter_align);
    try testing.expect(!options.bottom_align);
    try testing.expect(!options.no_notify);
    try testing.expect(options.return_command);
    try testing.expect(!options.recurse);
    try testing.expect(!options.horizontal_animate);
    try testing.expect(!options.vertical_animate);
    try testing.expect(!options.no_animate);
    try testing.expect(options.left_button);
    try testing.expect(!options.right_button);
    try testing.expect(options.x == null);
    try testing.expect(options.y == null);
}

test "default show options convert to the default flags" {
    const options = ShowOptions{};

    try testing.expectEqual(@as(u32, 0x0100), options.to_flags());
}

test "show options carry the return command flag" {
    const options = ShowOptions{ .return_command = true };

    try testing.expectEqual(@as(u32, 0x0100), options.to_flags());
}

test "show options carry the centre align flag" {
    const options = ShowOptions{ .center_align = true };

    try testing.expectEqual(@as(u32, 0x0104), options.to_flags());
}

test "show options combine several flags" {
    const options = ShowOptions{ .return_command = true, .right_button = true };

    try testing.expectEqual(@as(u32, 0x0102), options.to_flags());
}

test "a menu at every bound builds its whole layout" {
    const label: [interface.menu_label_bytes_max]u8 = @splat('m');

    var items: [interface.menu_item_count_max]Item = undefined;
    var index: u32 = 0;

    while (index < interface.menu_item_count_max) : (index += 1) {
        items[index] = .{
            .checked = true,
            .id = interface.menu_item_id_max - index,
            .kind = .toggle,
            .label = &label,
        };
    }

    const window: Window = .closed;

    var menu: Menu = undefined;

    menu.init(&window);

    try menu.build(&items);

    try testing.expectEqual(@as(u32, interface.menu_item_count_max), menu.current.?.count());

    menu.destroy();
}

test "a nested menu builds each submenu inside the item that opens it" {
    const items = [_]Item{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .id = 2, .kind = .submenu, .label = "Level" },
        .{ .depth = 1, .id = 3, .kind = .radio, .label = "10%" },
        .{ .depth = 1, .id = 4, .kind = .submenu, .label = "Finer" },
        .{ .depth = 2, .id = 5, .kind = .radio, .label = "15%" },
        .{ .depth = 1, .id = 6, .kind = .radio, .label = "20%" },
        .{ .kind = .separator },
        .{ .id = 7, .kind = .action, .label = "Exit" },
    };

    const window: Window = .closed;

    var menu: Menu = undefined;

    menu.init(&window);

    try menu.build(&items);
    try menu.build(&items);
    defer menu.destroy();

    const root = menu.current orelse return error.MenuMissing;
    const level = w32.GetSubMenu(root.handle, 1) orelse return error.SubmenuMissing;
    const finer = w32.GetSubMenu(level, 1) orelse return error.SubmenuMissing;

    try testing.expectEqual(@as(u32, 4), root.count());
    try testing.expectEqual(@as(i32, 3), w32.GetMenuItemCount(level));
    try testing.expectEqual(@as(i32, 1), w32.GetMenuItemCount(finer));
    try testing.expect(w32.GetSubMenu(root.handle, 0) == null);
    try testing.expect(w32.GetSubMenu(level, 0) == null);
}
