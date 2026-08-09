const std = @import("std");

const event = @import("../event/root.zig");
const platform = @import("../platform.zig");

const assert = std.debug.assert;

const Bus = event.Bus;
const Event = event.Event;

const backend = platform.backend.icon;

pub const icon_max: u8 = 16;
pub const name_max: u32 = 32;

pub const Handle = backend.Handle;
pub const Source = platform.IconSource;
pub const Pixmap = platform.Pixmap;
pub const Stock = platform.Stock;

pub const Error = platform.IconError;

comptime {
    assert(icon_max > 0);
    assert(name_max > 1);
}

pub const Entry = struct {
    handle: ?Handle,
    name: [name_max]u8,
    name_len: u8,
    source: Source,

    pub fn init(name: []const u8, source: Source) Entry {
        assert(name.len > 0);
        assert(name.len < name_max);

        var result = Entry{
            .handle = null,
            .name = [_]u8{0} ** name_max,
            .name_len = 0,
            .source = source,
        };

        @memcpy(result.name[0..name.len], name);

        result.name_len = @intCast(name.len);

        assert(result.name_len == name.len);

        return result;
    }

    pub fn deinit(entry: *Entry) void {
        if (entry.handle) |handle| {
            backend.destroy(handle);
            entry.handle = null;
        }

        assert(entry.handle == null);
    }

    pub fn get_name(entry: *const Entry) []const u8 {
        assert(entry.name_len <= name_max);

        return entry.name[0..entry.name_len];
    }

    pub fn matches(entry: *const Entry, target: []const u8) bool {
        if (target.len != entry.name_len) {
            return false;
        }

        return std.mem.eql(u8, entry.name[0..entry.name_len], target);
    }
};

pub const IconManager = struct {
    bus: ?*Bus,
    count: u8,
    current: u8,
    entries: [icon_max]?Entry,
    loaded: bool,

    pub fn init() IconManager {
        const result = IconManager{
            .bus = null,
            .count = 0,
            .current = 0,
            .entries = [_]?Entry{null} ** icon_max,
            .loaded = false,
        };

        assert(result.count == 0);
        assert(!result.loaded);

        return result;
    }

    pub fn deinit(manager: *IconManager) void {
        var index: u8 = 0;

        while (index < icon_max) : (index += 1) {
            assert(index < icon_max);

            if (manager.entries[index]) |*entry| {
                entry.deinit();
                manager.entries[index] = null;
            }
        }

        manager.count = 0;
        manager.current = 0;
        manager.loaded = false;
        manager.bus = null;

        assert(manager.count == 0);
    }

    pub fn bind(manager: *IconManager, bus: *Bus) void {
        manager.bus = bus;

        assert(manager.bus != null);
    }

    pub fn add(manager: *IconManager, name: []const u8, source: Source) Error!void {
        if (manager.count >= icon_max) {
            return Error.CapacityExceeded;
        }

        if (name.len == 0 or name.len >= name_max) {
            return Error.InvalidName;
        }

        if (!source.is_valid()) {
            return Error.InvalidSource;
        }

        if (find_index(manager, name) != null) {
            return Error.DuplicateName;
        }

        const slot = find_empty_slot(manager) orelse return Error.NoSlotAvailable;

        assert(slot < icon_max);

        manager.entries[slot] = Entry.init(name, source);
        manager.count += 1;

        assert(manager.count <= icon_max);
    }

    pub fn add_file(manager: *IconManager, name: []const u8, file_path: []const u8) Error!void {
        assert(file_path.len > 0);

        try manager.add(name, .{ .file_path = file_path });
    }

    pub fn add_pixels(manager: *IconManager, name: []const u8, pixmap: Pixmap) Error!void {
        assert(pixmap.is_valid());

        try manager.add(name, .{ .pixels = pixmap });
    }

    pub fn add_resource(manager: *IconManager, name: []const u8, id: u32) Error!void {
        if (comptime !platform.capabilities.icon_resource) {
            return Error.Unsupported;
        }

        assert(id > 0);

        try manager.add(name, .{ .resource = id });
    }

    pub fn add_stock(manager: *IconManager, name: []const u8, stock: Stock) Error!void {
        try manager.add(name, .{ .stock = stock });
    }

    pub fn get(manager: *const IconManager, name: []const u8) ?Handle {
        assert(name.len > 0);

        const index = find_index(manager, name) orelse return null;

        assert(index < icon_max);

        if (manager.entries[index]) |*entry| {
            return entry.handle;
        }

        return null;
    }

    pub fn get_current(manager: *const IconManager) ?Handle {
        assert(manager.current < icon_max);

        if (manager.entries[manager.current]) |*entry| {
            return entry.handle;
        }

        return null;
    }

    pub fn get_current_name(manager: *const IconManager) ?[]const u8 {
        assert(manager.current < icon_max);

        if (manager.entries[manager.current]) |*entry| {
            return entry.get_name();
        }

        return null;
    }

    pub fn get_source(manager: *const IconManager, name: []const u8) ?Source {
        assert(name.len > 0);

        const index = find_index(manager, name) orelse return null;

        assert(index < icon_max);

        if (manager.entries[index]) |*entry| {
            return entry.source;
        }

        return null;
    }

    pub fn is_empty(manager: *const IconManager) bool {
        return manager.count == 0;
    }

    pub fn is_loaded(manager: *const IconManager) bool {
        return manager.loaded;
    }

    pub fn load(manager: *IconManager) Error!void {
        if (manager.count == 0) {
            return Error.NotFound;
        }

        var success: u8 = 0;
        var index: u8 = 0;

        while (index < icon_max) : (index += 1) {
            assert(index < icon_max);

            if (manager.entries[index]) |*entry| {
                if (entry.handle == null) {
                    entry.handle = backend.load(entry.source) catch {
                        return Error.LoadFailed;
                    };
                }

                assert(entry.handle != null);

                success += 1;
            }
        }

        assert(success == manager.count);

        manager.loaded = true;
    }

    pub fn set_current(manager: *IconManager, name: []const u8) Error!void {
        assert(name.len > 0);

        const index = find_index(manager, name) orelse return Error.NotFound;

        assert(index < icon_max);

        if (index == manager.current) {
            return;
        }

        manager.current = index;

        if (manager.bus) |bus| {
            const changed = Event.icon_change(name);

            _ = bus.emit(&changed);
        }
    }
};

fn find_empty_slot(manager: *const IconManager) ?u8 {
    var index: u8 = 0;

    while (index < icon_max) : (index += 1) {
        assert(index < icon_max);

        if (manager.entries[index] == null) return index;
    }

    return null;
}

fn find_index(manager: *const IconManager, name: []const u8) ?u8 {
    var index: u8 = 0;

    while (index < icon_max) : (index += 1) {
        assert(index < icon_max);

        if (manager.entries[index]) |*entry| {
            if (entry.matches(name)) return index;
        }
    }

    return null;
}

const testing = std.testing;

test "an icon entry carries the name and source it was built from" {
    const entry = Entry.init("test_icon", .{ .stock = .application });

    try testing.expectEqualStrings("test_icon", entry.get_name());
    try testing.expect(entry.handle == null);
}

test "an icon entry name matches only in full" {
    const entry = Entry.init("icon", .{ .stock = .application });

    try testing.expect(entry.matches("icon"));
    try testing.expect(!entry.matches("other"));
    try testing.expect(!entry.matches("ico"));
    try testing.expect(!entry.matches("iconx"));
}

test "a fresh icon manager holds no icons" {
    const manager = IconManager.init();

    try testing.expect(manager.is_empty());
    try testing.expectEqual(@as(u8, 0), manager.count);
}

test "an icon manager rejects a duplicate name" {
    var manager = IconManager.init();
    defer manager.deinit();

    try manager.add_stock("icon", .application);

    try testing.expectError(Error.DuplicateName, manager.add_stock("icon", .shield));
}

test "an icon manager rejects an empty name" {
    var manager = IconManager.init();
    defer manager.deinit();

    try testing.expectError(Error.InvalidName, manager.add_stock("", .application));
}

test "an icon manager rejects an invalid source" {
    var manager = IconManager.init();
    defer manager.deinit();

    try testing.expectError(Error.InvalidSource, manager.add("icon", .{ .file_path = "" }));
}

test "a full icon manager refuses another icon" {
    var manager = IconManager.init();
    defer manager.deinit();

    var index: u8 = 0;

    while (index < icon_max) : (index += 1) {
        assert(index < icon_max);

        var name: [8]u8 = undefined;
        const formatted = std.fmt.bufPrint(&name, "{d}", .{index}) catch continue;

        try manager.add_stock(formatted, .application);
    }

    try testing.expectError(Error.CapacityExceeded, manager.add_stock("overflow", .application));
}

test "an empty icon manager names no current icon" {
    const manager = IconManager.init();

    try testing.expect(manager.get_current_name() == null);
}

test "an icon manager has no current icon before loading" {
    var manager = IconManager.init();
    defer manager.deinit();

    try manager.add_stock("icon", .application);

    try testing.expect(manager.get_current() == null);
}

test "selecting an unknown icon is rejected" {
    var manager = IconManager.init();
    defer manager.deinit();

    try manager.add_stock("icon1", .application);

    try testing.expectError(Error.NotFound, manager.set_current("unknown"));
}

test "selecting an icon moves the current selection" {
    var manager = IconManager.init();
    defer manager.deinit();

    try manager.add_stock("icon1", .application);
    try manager.add_stock("icon2", .shield);
    try manager.set_current("icon2");

    try testing.expectEqual(@as(u8, 1), manager.current);
    try testing.expectEqualStrings("icon2", manager.get_current_name().?);
}

test "selecting an icon emits on the bus" {
    var bus = Bus.init();
    defer bus.deinit();

    var manager = IconManager.init();
    defer manager.deinit();

    manager.bind(&bus);

    try manager.add_stock("icon1", .application);
    try manager.add_stock("icon2", .shield);

    const Sink = struct {
        var seen: u32 = 0;

        fn handle(_: *const Event, _: ?*anyopaque) event.Response {
            seen += 1;

            return .pass;
        }
    };

    Sink.seen = 0;

    _ = bus.on(.icon_change, Sink.handle, null);

    try manager.set_current("icon2");

    try testing.expectEqual(@as(u32, 1), Sink.seen);
}

test "tearing down an icon manager clears every entry" {
    var manager = IconManager.init();

    try manager.add_stock("icon1", .application);
    try manager.add_stock("icon2", .shield);

    manager.deinit();

    try testing.expect(manager.is_empty());
    try testing.expect(!manager.is_loaded());
}

test "an icon manager returns the source it stored" {
    var manager = IconManager.init();
    defer manager.deinit();

    try manager.add_stock("icon", .shield);

    const source = manager.get_source("icon");

    try testing.expect(source != null);
    try testing.expectEqual(Stock.shield, source.?.stock);
}
