const std = @import("std");

const w32 = @import("win32").everything;

pub const label_max: u16 = 256;

const state_checked: u32 = 0x00000008;
const state_default_item: u32 = 0x00001000;
const state_disabled: u32 = 0x00000002;
const state_grayed: u32 = 0x00000001;
const state_hilite: u32 = 0x00000080;
const state_enabled_mask: u32 = 0x00000003;

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

const type_separator: u32 = 0x00000800;
const type_bitmap: u32 = 0x00000004;
const type_owner_draw: u32 = 0x00000100;

const invalid_menu_state: u32 = 0xFFFFFFFF;
const invalid_menu_id: u32 = 0xFFFFFFFF;

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

    pub fn from_uint(value: u32) ItemState {
        const result = ItemState{
            .checked = (value & state_checked) != 0,
            .default_item = (value & state_default_item) != 0,
            .disabled = (value & state_disabled) != 0,
            .grayed = (value & state_grayed) != 0,
            .hilite = (value & state_hilite) != 0,
        };

        return result;
    }

    pub fn to_uint(self: ItemState) u32 {
        var result: u32 = 0;

        if (self.checked) result |= state_checked;
        if (self.default_item) result |= state_default_item;
        if (self.disabled) result |= state_disabled;
        if (self.grayed) result |= state_grayed;
        if (self.hilite) result |= state_hilite;

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

    pub fn to_flags(self: ShowOptions) u32 {
        var result: u32 = 0;

        if (self.left_align) result |= show_left_align;
        if (self.center_align) result |= show_center_align;
        if (self.right_align) result |= show_right_align;
        if (self.top_align) result |= show_top_align;
        if (self.vcenter_align) result |= show_vcenter_align;
        if (self.bottom_align) result |= show_bottom_align;
        if (self.no_notify) result |= show_no_notify;
        if (self.return_command) result |= show_return_command;
        if (self.left_button) result |= show_left_button;
        if (self.right_button) result |= show_right_button;
        if (self.no_animate) result |= show_no_animate;
        if (self.layout_rtl) result |= show_layout_rtl;
        if (self.horizontal_animate) result |= show_horizontal_animate;
        if (self.vertical_animate) result |= show_vertical_animate;
        if (self.recurse) result |= show_recurse;

        return result;
    }
};

pub const ItemInfo = struct {
    checked_bitmap: ?w32.HBITMAP,
    data: u64,
    id: u32,
    item_type: ItemType,
    label: [label_max]u8,
    label_len: u16,
    state: ItemState,
    submenu: ?w32.HMENU,
    unchecked_bitmap: ?w32.HBITMAP,

    pub fn get_label(self: *const ItemInfo) []const u8 {
        std.debug.assert(self.label_len <= label_max);

        const result = self.label[0..self.label_len];

        return result;
    }
};

pub const Error = error{
    CreationFailed,
    GetInfoFailed,
    InsertFailed,
    InvalidLabel,
    InvalidPosition,
    ModifyFailed,
    NotFound,
    RemoveFailed,
};

fn apply_item_attributes(info: *w32.MENUITEMINFOW, options: ItemOptions) void {
    if (options.sub) |sub| {
        info.fMask.SUBMENU = 1;
        info.hSubMenu = sub.handle;
    }

    if (options.checked_bitmap) |bitmap| {
        info.fMask.CHECKMARKS = 1;
        info.hbmpChecked = bitmap;
    }

    if (options.unchecked_bitmap) |bitmap| {
        info.fMask.CHECKMARKS = 1;
        info.hbmpUnchecked = bitmap;
    }

    if (options.bitmap) |bitmap| {
        info.fMask.BITMAP = 1;
        info.hbmpItem = bitmap;
    }

    if (options.data != 0) {
        info.fMask.DATA = 1;
        info.dwItemData = options.data;
    }
}

pub const Menu = struct {
    handle: w32.HMENU,
    owned: bool = true,

    pub fn create(options: CreateOptions) Error!Menu {
        const handle = if (options.popup)
            w32.CreatePopupMenu()
        else
            w32.CreateMenu();

        if (handle == null) {
            return Error.CreationFailed;
        }

        std.debug.assert(handle != null);

        const result = Menu{
            .handle = handle.?,
            .owned = true,
        };

        return result;
    }

    pub fn from_handle(handle: w32.HMENU) Menu {
        const result = Menu{
            .handle = handle,
            .owned = false,
        };

        return result;
    }

    pub fn append(self: *const Menu, options: ItemOptions) Error!void {
        std.debug.assert(self.is_valid());

        const position = self.count();

        return self.insert(position, options);
    }

    pub fn check_radio(self: *const Menu, first: u32, last: u32, selected: u32) Error!void {
        std.debug.assert(self.is_valid());
        std.debug.assert(first <= last);
        std.debug.assert(selected >= first);
        std.debug.assert(selected <= last);

        const status = w32.CheckMenuRadioItem(self.handle, first, last, selected, .{ .BYPOSITION = 1 });

        if (status == 0) {
            return Error.ModifyFailed;
        }
    }

    pub fn clear(self: *const Menu) u32 {
        std.debug.assert(self.is_valid());

        var removed: u32 = 0;
        var iteration: u32 = 0;

        while (self.count() > 0) {
            std.debug.assert(iteration < iteration_max);

            if (iteration >= iteration_max) {
                break;
            }

            if (w32.DeleteMenu(self.handle, 0, .{ .BYPOSITION = 1 }) != 0) {
                removed += 1;
            } else {
                break;
            }

            iteration += 1;
        }

        return removed;
    }

    pub fn count(self: *const Menu) u32 {
        std.debug.assert(self.is_valid());

        const raw_result = w32.GetMenuItemCount(self.handle);

        if (raw_result < 0) {
            return 0;
        }

        const result: u32 = @intCast(raw_result);

        return result;
    }

    pub fn destroy(self: *const Menu) bool {
        if (self.owned and self.is_valid()) {
            const result = w32.DestroyMenu(self.handle) != 0;

            return result;
        }

        return true;
    }

    pub fn end_menu() bool {
        const result = w32.EndMenu() != 0;

        return result;
    }

    pub fn get_id(self: *const Menu, position: u32) ?u32 {
        std.debug.assert(self.is_valid());

        const id = w32.GetMenuItemID(self.handle, @intCast(position));

        if (id == invalid_menu_id) {
            return null;
        }

        return id;
    }

    pub fn get_item(self: *const Menu, position: u32) Error!ItemInfo {
        std.debug.assert(self.is_valid());

        var info = std.mem.zeroes(w32.MENUITEMINFOW);
        var label_wide: [label_max]u16 = undefined;

        info.cbSize = @sizeOf(w32.MENUITEMINFOW);
        info.fMask = .{
            .BITMAP = 1,
            .CHECKMARKS = 1,
            .DATA = 1,
            .ID = 1,
            .STATE = 1,
            .STRING = 1,
            .SUBMENU = 1,
            .TYPE = 1,
        };
        info.dwTypeData = @ptrCast(&label_wide);
        info.cch = label_max;

        const status = w32.GetMenuItemInfoW(self.handle, position, w32.TRUE, &info);

        if (status == 0) {
            return Error.GetInfoFailed;
        }

        var result = ItemInfo{
            .checked_bitmap = info.hbmpChecked,
            .data = info.dwItemData,
            .id = info.wID,
            .item_type = .string,
            .label = [_]u8{0} ** label_max,
            .label_len = 0,
            .state = ItemState.from_uint(@bitCast(info.fState)),
            .submenu = info.hSubMenu,
            .unchecked_bitmap = info.hbmpUnchecked,
        };

        const ftype: u32 = @bitCast(info.fType);

        if ((ftype & type_separator) != 0) {
            result.item_type = .separator;
        } else if ((ftype & type_bitmap) != 0) {
            result.item_type = .bitmap;
        } else if ((ftype & type_owner_draw) != 0) {
            result.item_type = .owner_draw;
        }

        if (info.cch > 0) {
            std.debug.assert(info.cch <= label_max);

            const length = std.unicode.utf16LeToUtf8(&result.label, label_wide[0..info.cch]) catch 0;

            result.label_len = @intCast(length);
        }

        return result;
    }

    pub fn get_submenu(self: *const Menu, position: u32) ?Menu {
        std.debug.assert(self.is_valid());

        const handle = w32.GetSubMenu(self.handle, @intCast(position));

        if (handle == null) {
            return null;
        }

        const result = Menu{
            .handle = handle.?,
            .owned = false,
        };

        return result;
    }

    pub fn hilite(self: *const Menu, hwnd: w32.HWND, position: u32, highlight: bool) bool {
        std.debug.assert(self.is_valid());

        var flags = w32.MENU_ITEM_FLAGS{ .BYPOSITION = 1 };

        if (highlight) {
            flags.HILITE = 1;
        }

        const result = w32.HiliteMenuItem(hwnd, self.handle, position, flags) != 0;

        return result;
    }

    pub fn insert(self: *const Menu, position: u32, options: ItemOptions) Error!void {
        std.debug.assert(self.is_valid());

        var info = std.mem.zeroes(w32.MENUITEMINFOW);
        var label_wide: [label_max]u16 = undefined;

        info.cbSize = @sizeOf(w32.MENUITEMINFOW);

        if (options.item_type == .separator) {
            info.fMask = .{ .FTYPE = 1 };
            info.fType = .{ .SEPARATOR = 1 };
        } else {
            info.fMask = .{
                .FTYPE = 1,
                .ID = 1,
                .STATE = 1,
                .STRING = 1,
            };

            info.fType = switch (options.item_type) {
                .bitmap => .{ .BITMAP = 1 },
                .owner_draw => .{ .OWNERDRAW = 1 },
                .separator => .{ .SEPARATOR = 1 },
                .string => .{},
            };

            info.fState = @bitCast(options.state.to_uint());
            info.wID = options.id;

            if (options.label.len > 0) {
                std.debug.assert(options.label.len < label_max);

                const length = std.unicode.utf8ToUtf16Le(&label_wide, options.label) catch {
                    return Error.InvalidLabel;
                };

                if (length >= label_max) {
                    return Error.InvalidLabel;
                }

                label_wide[length] = 0;
                info.dwTypeData = @ptrCast(&label_wide);
                info.cch = @intCast(length);
            }
        }

        apply_item_attributes(&info, options);

        const status = w32.InsertMenuItemW(self.handle, position, w32.TRUE, &info);

        if (status == 0) {
            return Error.InsertFailed;
        }
    }

    pub fn is_checked(self: *const Menu, id: u32) bool {
        std.debug.assert(self.is_valid());

        const state = w32.GetMenuState(self.handle, id, .{});

        if (state == invalid_menu_state) {
            return false;
        }

        const result = (state & state_checked) != 0;

        return result;
    }

    pub fn is_enabled(self: *const Menu, id: u32) bool {
        std.debug.assert(self.is_valid());

        const state = w32.GetMenuState(self.handle, id, .{});

        if (state == invalid_menu_state) {
            return true;
        }

        const result = (state & state_enabled_mask) == 0;

        return result;
    }

    pub fn is_menu(handle: w32.HMENU) bool {
        const result = w32.IsMenu(handle) != 0;

        return result;
    }

    pub fn is_valid(self: *const Menu) bool {
        const result = @intFromPtr(self.handle) != 0;

        return result;
    }

    pub fn remove(self: *const Menu, position: u32) Error!void {
        std.debug.assert(self.is_valid());

        const status = w32.DeleteMenu(self.handle, position, .{ .BYPOSITION = 1 });

        if (status == 0) {
            return Error.RemoveFailed;
        }
    }

    pub fn remove_by_id(self: *const Menu, id: u32) Error!void {
        std.debug.assert(self.is_valid());

        const status = w32.DeleteMenu(self.handle, id, .{});

        if (status == 0) {
            return Error.RemoveFailed;
        }
    }

    pub fn set_bitmaps(self: *const Menu, position: u32, unchecked: ?w32.HBITMAP, checked: ?w32.HBITMAP) Error!void {
        std.debug.assert(self.is_valid());

        const status = w32.SetMenuItemBitmaps(self.handle, position, .{ .BYPOSITION = 1 }, unchecked, checked);

        if (status == 0) {
            return Error.ModifyFailed;
        }
    }

    pub fn set_checked(self: *const Menu, id: u32, checked: bool) Error!void {
        std.debug.assert(self.is_valid());

        const flag: u32 = if (checked) state_checked else 0;
        const result = w32.CheckMenuItem(self.handle, id, flag);

        if (result == invalid_menu_state) {
            return Error.ModifyFailed;
        }
    }

    pub fn set_default(self: *const Menu, position: u32) Error!void {
        std.debug.assert(self.is_valid());

        const status = w32.SetMenuDefaultItem(self.handle, position, w32.TRUE);

        if (status == 0) {
            return Error.ModifyFailed;
        }
    }

    pub fn set_enabled(self: *const Menu, id: u32, enabled: bool) Error!void {
        std.debug.assert(self.is_valid());

        const flag: u32 = if (enabled) 0 else state_enabled_mask;
        const result = w32.EnableMenuItem(self.handle, id, flag);

        if (result == invalid_menu_state) {
            return Error.ModifyFailed;
        }
    }

    pub fn set_item(self: *const Menu, position: u32, options: ItemOptions) Error!void {
        std.debug.assert(self.is_valid());

        var info = std.mem.zeroes(w32.MENUITEMINFOW);
        var label_wide: [label_max]u16 = undefined;

        info.cbSize = @sizeOf(w32.MENUITEMINFOW);

        if (options.label.len > 0) {
            std.debug.assert(options.label.len < label_max);

            info.fMask.STRING = 1;

            const length = std.unicode.utf8ToUtf16Le(&label_wide, options.label) catch {
                return Error.InvalidLabel;
            };

            label_wide[length] = 0;
            info.dwTypeData = @ptrCast(&label_wide);
            info.cch = @intCast(length);
        }

        info.fMask.STATE = 1;
        info.fState = @bitCast(options.state.to_uint());

        if (options.sub) |sub| {
            info.fMask.SUBMENU = 1;
            info.hSubMenu = sub.handle;
        }

        if (options.bitmap) |bitmap| {
            info.fMask.BITMAP = 1;
            info.hbmpItem = bitmap;
        }

        const status = w32.SetMenuItemInfoW(self.handle, position, w32.TRUE, &info);

        if (status == 0) {
            return Error.ModifyFailed;
        }
    }

    pub fn set_state(self: *const Menu, position: u32, state: ItemState) Error!void {
        std.debug.assert(self.is_valid());

        var info = std.mem.zeroes(w32.MENUITEMINFOW);

        info.cbSize = @sizeOf(w32.MENUITEMINFOW);
        info.fMask = .{ .STATE = 1 };
        info.fState = @bitCast(state.to_uint());

        const status = w32.SetMenuItemInfoW(self.handle, position, w32.TRUE, &info);

        if (status == 0) {
            return Error.ModifyFailed;
        }
    }

    pub fn show(self: *const Menu, hwnd: w32.HWND, options: ShowOptions) u32 {
        std.debug.assert(self.is_valid());

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

        const command = w32.TrackPopupMenuEx(self.handle, flags, x, y, hwnd, null);

        _ = w32.PostMessageW(hwnd, 0, 0, 0);

        const result: u32 = @intCast(command);

        return result;
    }
};
