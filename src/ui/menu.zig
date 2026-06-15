const std = @import("std");

const w32 = @import("win32").everything;

const runtime = @import("../runtime/root.zig");
const win32 = @import("../win32/root.zig");

const Menu = win32.Menu;
const Service = runtime.Service;

pub const group_max: u8 = 32;
pub const id_offset: u32 = 1000;
pub const item_max: u8 = 64;
pub const label_max: u16 = 128;

pub const Error = error{
    BuildFailed,
    CapacityExceeded,
    InvalidLabel,
    NotFound,
};

pub const ItemKind = enum(u8) {
    action = 0,
    radio = 1,
    separator = 2,
    toggle = 3,
};

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
        std.debug.assert(label.len > 0);
        std.debug.assert(label.len < label_max);

        var result = empty();

        result.id = id;
        result.kind = .action;
        result.set_label(label);

        std.debug.assert(result.kind == .action);

        return result;
    }

    pub fn radio(id: u32, label: []const u8, group_name: []const u8, initial: bool) Item {
        std.debug.assert(label.len > 0);
        std.debug.assert(label.len < label_max);
        std.debug.assert(group_name.len > 0);
        std.debug.assert(group_name.len < group_max);

        var result = empty();

        result.checked = initial;
        result.id = id;
        result.kind = .radio;
        result.set_group(group_name);
        result.set_label(label);

        std.debug.assert(result.kind == .radio);

        return result;
    }

    pub fn separator() Item {
        var result = empty();

        result.kind = .separator;

        std.debug.assert(result.kind == .separator);

        return result;
    }

    pub fn toggle(id: u32, label: []const u8, initial: bool) Item {
        std.debug.assert(label.len > 0);
        std.debug.assert(label.len < label_max);

        var result = empty();

        result.checked = initial;
        result.id = id;
        result.kind = .toggle;
        result.set_label(label);

        std.debug.assert(result.kind == .toggle);

        return result;
    }

    fn empty() Item {
        const result = Item{
            .checked = false,
            .enabled = true,
            .group = [_]u8{0} ** group_max,
            .group_len = 0,
            .id = 0,
            .kind = .action,
            .label = [_]u8{0} ** label_max,
            .label_len = 0,
            .visible = true,
        };

        return result;
    }

    pub fn get_group(self: *const Item) ?[]const u8 {
        if (self.group_len == 0) {
            return null;
        }

        std.debug.assert(self.group_len <= group_max);

        const result = self.group[0..self.group_len];

        return result;
    }

    pub fn get_label(self: *const Item) []const u8 {
        std.debug.assert(self.label_len <= label_max);

        const result = self.label[0..self.label_len];

        return result;
    }

    pub fn is_in_group(self: *const Item, group_name: []const u8) bool {
        if (self.group_len == 0 or group_name.len != self.group_len) {
            return false;
        }

        const result = std.mem.eql(u8, self.group[0..self.group_len], group_name);

        return result;
    }

    pub fn set_group(self: *Item, group_name: []const u8) void {
        if (group_name.len == 0 or group_name.len >= group_max) {
            return;
        }

        var index: u8 = 0;

        while (index < group_name.len) : (index += 1) {
            std.debug.assert(index < group_max);

            self.group[index] = group_name[index];
        }

        self.group_len = @intCast(group_name.len);

        std.debug.assert(self.group_len == group_name.len);
    }

    pub fn set_label(self: *Item, label: []const u8) void {
        if (label.len == 0 or label.len >= label_max) {
            return;
        }

        var index: u16 = 0;

        while (index < label.len) : (index += 1) {
            std.debug.assert(index < label_max);

            self.label[index] = label[index];
        }

        self.label_len = @intCast(label.len);

        std.debug.assert(self.label_len == label.len);
    }
};

pub const MenuManager = struct {
    count: u8,
    dirty: bool,
    items: [item_max]?Item,
    menu: ?Menu,
    service: ?*Service,

    pub fn init() MenuManager {
        const result = MenuManager{
            .count = 0,
            .dirty = true,
            .items = [_]?Item{null} ** item_max,
            .menu = null,
            .service = null,
        };

        std.debug.assert(result.count == 0);
        std.debug.assert(result.dirty == true);

        return result;
    }

    pub fn deinit(self: *MenuManager) void {
        if (self.menu) |menu| {
            _ = menu.destroy();
            self.menu = null;
        }

        self.clear();

        std.debug.assert(self.menu == null);
    }

    pub fn add(self: *MenuManager, item: Item) Error!void {
        if (self.count >= item_max) {
            return Error.CapacityExceeded;
        }

        self.items[self.count] = item;
        self.count += 1;
        self.dirty = true;

        std.debug.assert(self.count <= item_max);
    }

    pub fn add_action(self: *MenuManager, id: u32, label: []const u8) Error!void {
        try self.add(Item.action(id, label));
    }

    pub fn add_radio(self: *MenuManager, id: u32, label: []const u8, group_name: []const u8, initial: bool) Error!void {
        try self.add(Item.radio(id, label, group_name, initial));

        if (initial) {
            select_radio(self, group_name, id);
        }
    }

    pub fn add_separator(self: *MenuManager) Error!void {
        try self.add(Item.separator());
    }

    pub fn add_toggle(self: *MenuManager, id: u32, label: []const u8, initial: bool) Error!void {
        try self.add(Item.toggle(id, label, initial));
    }

    pub fn bind(self: *MenuManager, service: *Service) void {
        self.service = service;

        std.debug.assert(self.service != null);
    }

    pub fn build(self: *MenuManager) Error!void {
        if (!self.dirty and self.menu != null) {
            return;
        }

        if (self.menu == null) {
            self.menu = Menu.create(.{}) catch return Error.BuildFailed;
        }

        std.debug.assert(self.menu != null);

        _ = self.menu.?.clear();

        var position: u32 = 0;
        var index: u8 = 0;

        while (index < self.count) : (index += 1) {
            std.debug.assert(index < item_max);

            if (self.items[index]) |*item| {
                if (!item.visible) {
                    continue;
                }

                if (item.kind == .separator) {
                    self.menu.?.insert(position, .{ .item_type = .separator }) catch continue;
                    position += 1;

                    continue;
                }

                const label = item.get_label();

                if (label.len == 0) {
                    continue;
                }

                var state = win32.MenuItemState{};

                if (item.checked) {
                    state.checked = true;
                }

                if (!item.enabled) {
                    state.disabled = true;
                }

                self.menu.?.insert(position, .{
                    .id = item.id + id_offset,
                    .label = label,
                    .state = state,
                }) catch continue;

                position += 1;
            }
        }

        self.dirty = false;

        std.debug.assert(self.dirty == false);
    }

    pub fn clear(self: *MenuManager) void {
        var index: u8 = 0;

        while (index < self.count) : (index += 1) {
            std.debug.assert(index < item_max);

            self.items[index] = null;
        }

        self.count = 0;
        self.dirty = true;

        std.debug.assert(self.count == 0);
    }

    pub fn get_item(self: *const MenuManager, id: u32) ?*const Item {
        var index: u8 = 0;

        while (index < self.count) : (index += 1) {
            std.debug.assert(index < item_max);

            if (self.items[index]) |*item| {
                if (item.id == id) {
                    return item;
                }
            }
        }

        return null;
    }

    pub fn get_radio_selection(self: *const MenuManager, group_name: []const u8) ?u32 {
        var index: u8 = 0;

        while (index < self.count) : (index += 1) {
            std.debug.assert(index < item_max);

            if (self.items[index]) |*item| {
                if (item.kind == .radio and item.is_in_group(group_name) and item.checked) {
                    return item.id;
                }
            }
        }

        return null;
    }

    pub fn handle_command(_: *MenuManager, raw_id: u32) ?u32 {
        if (raw_id < id_offset) {
            return null;
        }

        const result = raw_id - id_offset;

        return result;
    }

    pub fn is_checked(self: *const MenuManager, id: u32) bool {
        const item = self.get_item(id) orelse return false;

        return item.checked;
    }

    pub fn is_empty(self: *const MenuManager) bool {
        const result = self.count == 0;

        return result;
    }

    pub fn mark_dirty(self: *MenuManager) void {
        self.dirty = true;
    }

    pub fn set_checked(self: *MenuManager, id: u32, checked: bool) Error!void {
        const item = get_item_mut(self, id) orelse return Error.NotFound;

        if (item.kind == .radio and checked) {
            if (item.get_group()) |group_name| {
                select_radio(self, group_name, id);
            }
        } else {
            item.checked = checked;
        }

        self.dirty = true;
    }

    pub fn set_enabled(self: *MenuManager, id: u32, enabled: bool) Error!void {
        const item = get_item_mut(self, id) orelse return Error.NotFound;

        item.enabled = enabled;
        self.dirty = true;
    }

    pub fn set_label(self: *MenuManager, id: u32, label: []const u8) Error!void {
        std.debug.assert(label.len > 0);

        const item = get_item_mut(self, id) orelse return Error.NotFound;

        item.set_label(label);
        self.dirty = true;
    }

    pub fn set_visible(self: *MenuManager, id: u32, visible: bool) Error!void {
        const item = get_item_mut(self, id) orelse return Error.NotFound;

        item.visible = visible;
        self.dirty = true;
    }

    pub fn show(self: *MenuManager, hwnd: w32.HWND) ?u32 {
        self.build() catch return null;

        if (self.menu == null) {
            return null;
        }

        const command = self.menu.?.show(hwnd, .{});

        if (command == 0) {
            return null;
        }

        if (command >= id_offset) {
            return command - id_offset;
        }

        return null;
    }

    pub fn toggle_item(self: *MenuManager, id: u32) Error!bool {
        const item = get_item_mut(self, id) orelse return Error.NotFound;

        if (item.kind == .toggle) {
            item.checked = !item.checked;
            self.dirty = true;

            return item.checked;
        }

        if (item.kind == .radio and !item.checked) {
            if (item.get_group()) |group_name| {
                select_radio(self, group_name, id);
                self.dirty = true;

                return true;
            }
        }

        return item.checked;
    }
};

fn get_item_mut(manager: *MenuManager, id: u32) ?*Item {
    var index: u8 = 0;

    while (index < manager.count) : (index += 1) {
        std.debug.assert(index < item_max);

        if (manager.items[index]) |*item| {
            if (item.id == id) {
                return item;
            }
        }
    }

    return null;
}

fn select_radio(manager: *MenuManager, group_name: []const u8, selected_id: u32) void {
    std.debug.assert(group_name.len > 0);

    var index: u8 = 0;

    while (index < manager.count) : (index += 1) {
        std.debug.assert(index < item_max);

        if (manager.items[index]) |*item| {
            if (item.kind == .radio and item.is_in_group(group_name)) {
                item.checked = item.id == selected_id;
            }
        }
    }
}
