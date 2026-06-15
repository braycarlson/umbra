const std = @import("std");

const w32 = @import("win32").everything;

const event = @import("../event/root.zig");
const runtime = @import("../runtime/root.zig");
const win32 = @import("../win32/root.zig");

const Event = event.Event;
const Icon = win32.Icon;
const Service = runtime.Service;

pub const icon_max: u8 = 16;
pub const name_max: u8 = 32;

pub const Error = error{
    CapacityExceeded,
    DuplicateName,
    InvalidName,
    LoadFailed,
    NoSlotAvailable,
    NotFound,
};

pub const Source = union(enum) {
    resource: u32,
    system: win32.IconSystem,

    pub fn to_load_options(self: Source, instance: w32.HINSTANCE) win32.IconLoadOptions {
        const result = switch (self) {
            .resource => |id| win32.IconLoadOptions{
                .source = .{ .resource = .{ .id = id, .instance = instance } },
            },
            .system => |system| win32.IconLoadOptions{
                .source = .{ .system = system },
            },
        };

        return result;
    }
};

pub const Entry = struct {
    icon: ?Icon,
    name: [name_max]u8,
    name_len: u8,
    source: Source,

    pub fn init(name: []const u8, source: Source) Entry {
        std.debug.assert(name.len > 0);
        std.debug.assert(name.len < name_max);

        var result = Entry{
            .icon = null,
            .name = [_]u8{0} ** name_max,
            .name_len = 0,
            .source = source,
        };

        if (name.len > 0 and name.len < name_max) {
            var index: u8 = 0;

            while (index < name.len) : (index += 1) {
                std.debug.assert(index < name_max);

                result.name[index] = name[index];
            }

            result.name_len = @intCast(name.len);
        }

        std.debug.assert(result.name_len == name.len);

        return result;
    }

    pub fn deinit(self: *Entry) void {
        if (self.icon) |*icon_ptr| {
            _ = icon_ptr.deinit();
            self.icon = null;
        }

        std.debug.assert(self.icon == null);
    }

    pub fn get_name(self: *const Entry) []const u8 {
        std.debug.assert(self.name_len <= name_max);

        const result = self.name[0..self.name_len];

        return result;
    }

    pub fn matches(self: *const Entry, target: []const u8) bool {
        if (target.len != self.name_len) {
            return false;
        }

        const result = std.mem.eql(u8, self.name[0..self.name_len], target);

        return result;
    }
};

pub const IconManager = struct {
    count: u8,
    current: u8,
    entries: [icon_max]?Entry,
    loaded: bool,
    service: ?*Service,

    pub fn init() IconManager {
        const result = IconManager{
            .count = 0,
            .current = 0,
            .entries = [_]?Entry{null} ** icon_max,
            .loaded = false,
            .service = null,
        };

        std.debug.assert(result.count == 0);
        std.debug.assert(result.loaded == false);

        return result;
    }

    pub fn deinit(self: *IconManager) void {
        var index: u8 = 0;

        while (index < icon_max) : (index += 1) {
            if (self.entries[index]) |*entry| {
                entry.deinit();
                self.entries[index] = null;
            }
        }

        self.count = 0;
        self.loaded = false;

        std.debug.assert(self.count == 0);
    }

    pub fn add(self: *IconManager, name: []const u8, source: Source) Error!void {
        if (self.count >= icon_max) {
            return Error.CapacityExceeded;
        }

        if (name.len == 0 or name.len >= name_max) {
            return Error.InvalidName;
        }

        if (find_index(self, name) != null) {
            return Error.DuplicateName;
        }

        const slot_index = find_empty_slot(self);

        if (slot_index == null) {
            return Error.NoSlotAvailable;
        }

        std.debug.assert(slot_index.? < icon_max);

        self.entries[slot_index.?] = Entry.init(name, source);
        self.count += 1;

        std.debug.assert(self.count <= icon_max);
    }

    pub fn add_resource(self: *IconManager, name: []const u8, id: u32) Error!void {
        std.debug.assert(id > 0);

        try self.add(name, .{ .resource = id });
    }

    pub fn add_system(self: *IconManager, name: []const u8, system_icon: win32.IconSystem) Error!void {
        try self.add(name, .{ .system = system_icon });
    }

    pub fn bind(self: *IconManager, service: *Service) void {
        self.service = service;

        std.debug.assert(self.service != null);
    }

    pub fn get(self: *const IconManager, name: []const u8) ?*const Icon {
        std.debug.assert(name.len > 0);

        const index = find_index(self, name) orelse return null;

        std.debug.assert(index < icon_max);

        if (self.entries[index]) |*entry| {
            if (entry.icon) |*icon_ptr| {
                return icon_ptr;
            }
        }

        return null;
    }

    pub fn get_current(self: *const IconManager) ?*const Icon {
        std.debug.assert(self.current < icon_max);

        if (self.entries[self.current]) |*entry| {
            if (entry.icon) |*icon_ptr| {
                return icon_ptr;
            }
        }

        return null;
    }

    pub fn get_current_name(self: *const IconManager) ?[]const u8 {
        std.debug.assert(self.current < icon_max);

        if (self.entries[self.current]) |*entry| {
            return entry.get_name();
        }

        return null;
    }

    pub fn is_empty(self: *const IconManager) bool {
        const result = self.count == 0;

        return result;
    }

    pub fn is_loaded(self: *const IconManager) bool {
        return self.loaded;
    }

    pub fn load(self: *IconManager, instance: w32.HINSTANCE) bool {
        if (self.count == 0) {
            return false;
        }

        var success: u8 = 0;
        var index: u8 = 0;

        while (index < icon_max) : (index += 1) {
            if (self.entries[index]) |*entry| {
                if (entry.icon == null) {
                    const options = entry.source.to_load_options(instance);

                    entry.icon = Icon.load(options) catch null;
                }

                if (entry.icon != null) {
                    success += 1;
                }
            }
        }

        self.loaded = success > 0;

        return self.loaded;
    }

    pub fn set_current(self: *IconManager, name: []const u8) Error!void {
        std.debug.assert(name.len > 0);

        const index = find_index(self, name) orelse return Error.NotFound;

        std.debug.assert(index < icon_max);

        if (index == self.current) {
            return;
        }

        self.current = index;

        if (self.service) |service| {
            const e = Event.icon_change(name);
            _ = service.bus.emit(&e);
        }
    }
};

fn find_empty_slot(manager: *const IconManager) ?u8 {
    var index: u8 = 0;

    while (index < icon_max) : (index += 1) {
        if (manager.entries[index] == null) {
            return index;
        }
    }

    return null;
}

fn find_index(manager: *const IconManager, name: []const u8) ?u8 {
    var index: u8 = 0;

    while (index < icon_max) : (index += 1) {
        if (manager.entries[index]) |*entry| {
            if (entry.matches(name)) {
                return index;
            }
        }
    }

    return null;
}
