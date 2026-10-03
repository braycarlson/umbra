const std = @import("std");

const w32 = @import("win32.zig");

const contract = @import("../contract.zig");
const window = @import("window.zig");

const assert = std.debug.assert;

pub const label_max: u32 = 256;

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
    sub: ?*const Menu = null,
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

pub const Error = contract.MenuError;

pub const NativeError = error{
    CreationFailed,
    GetInfoFailed,
    InsertFailed,
    InvalidLabel,
    ModifyFailed,
    RemoveFailed,
};

fn apply_item_attributes(info: *w32.MENUITEMINFOW, options: ItemOptions) void {
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

pub const Menu = struct {
    handle: w32.HMENU,
    owned: bool = true,

    pub fn create(options: CreateOptions) NativeError!Menu {
        const handle = if (options.popup)
            w32.CreatePopupMenu()
        else
            w32.CreateMenu();

        if (handle == null) {
            return NativeError.CreationFailed;
        }

        assert(handle != null);

        const result = Menu{
            .handle = handle.?,
            .owned = true,
        };

        return result;
    }

    pub fn clear(menu: *const Menu) u32 {
        assert(menu.is_valid());

        var removed: u32 = 0;
        var iteration: u32 = 0;

        while (menu.count() > 0) {
            assert(iteration < iteration_max);

            if (iteration >= iteration_max) {
                break;
            }

            if (w32.DeleteMenu(menu.handle, 0, w32.MF_BYPOSITION) != 0) {
                removed += 1;
            } else {
                break;
            }

            iteration += 1;
        }

        return removed;
    }

    pub fn count(menu: *const Menu) u32 {
        assert(menu.is_valid());

        const raw_result = w32.GetMenuItemCount(menu.handle);

        if (raw_result < 0) {
            return 0;
        }

        const result: u32 = @intCast(raw_result);

        return result;
    }

    pub fn destroy(menu: *const Menu) bool {
        if (menu.owned and menu.is_valid()) {
            return w32.DestroyMenu(menu.handle) != 0;
        }

        return true;
    }

    pub fn insert(menu: *const Menu, position: u32, options: ItemOptions) NativeError!void {
        assert(menu.is_valid());

        var info = std.mem.zeroes(w32.MENUITEMINFOW);
        var label_wide: [label_max]u16 = undefined;

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
                assert(options.label.len < label_max);

                const length = std.unicode.utf8ToUtf16Le(&label_wide, options.label) catch {
                    return NativeError.InvalidLabel;
                };

                if (length >= label_max) {
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

    pub fn is_valid(menu: *const Menu) bool {
        return @intFromPtr(menu.handle) != 0;
    }

    pub fn show(menu: *const Menu, hwnd: w32.HWND, options: ShowOptions) u32 {
        assert(menu.is_valid());

        var x: i32 = 0;
        var y: i32 = 0;

        if (options.x != null and options.y != null) {
            x = options.x.?;
            y = options.y.?;
        } else {
            var point: w32.POINT = undefined;

            if (w32.GetCursorPos(&point) != 0) {
                x = point.x;
                y = point.y;
            }
        }

        const flags: u32 = options.to_flags();

        _ = w32.SetForegroundWindow(hwnd);

        const command = w32.TrackPopupMenuEx(menu.handle, flags, x, y, hwnd, null);

        _ = w32.PostMessageW(hwnd, 0, 0, 0);

        const result: u32 = @intCast(command);

        return result;
    }
};

pub const Item = contract.MenuItem;
pub const id_offset: u32 = 1000;
pub const item_max: u32 = 64;

var current: ?Menu = null;

comptime {
    assert(id_offset > 0);
    assert(item_max > 0);
}

pub fn build(items: []const Item) Error!void {
    if (items.len > item_max) {
        return Error.CapacityExceeded;
    }

    if (current == null) {
        current = Menu.create(.{}) catch {
            return Error.BuildFailed;
        };
    }

    assert(current != null);

    _ = current.?.clear();

    var position: u32 = 0;
    var index: u32 = 0;

    while (index < items.len) : (index += 1) {
        assert(index < item_max);

        const item = items[index];

        if (!item.is_valid() or item.label.len >= label_max) {
            return Error.InvalidItem;
        }

        if (item.kind == .separator) {
            current.?.insert(position, .{ .item_type = .separator }) catch {
                return Error.BuildFailed;
            };

            position += 1;

            continue;
        }

        const state = ItemState{
            .checked = item.checked,
            .disabled = !item.enabled,
        };

        current.?.insert(position, .{
            .id = item.id + id_offset,
            .label = item.label,
            .state = state,
        }) catch {
            return Error.BuildFailed;
        };

        position += 1;
    }

    assert(position <= items.len);
}

pub fn destroy() void {
    const handle = current orelse return;

    current = null;

    _ = handle.destroy();
}

pub fn track() ?u32 {
    const handle = current orelse return null;
    const hwnd = window.handle() orelse return null;

    const command = handle.show(hwnd, .{});

    if (command < id_offset) {
        return null;
    }

    return command - id_offset;
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
    const state = ItemState{
        .checked = true,
        .hilite = true,
    };

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
    const options = ShowOptions{
        .return_command = true,
        .right_button = true,
    };

    try testing.expectEqual(@as(u32, 0x0102), options.to_flags());
}
