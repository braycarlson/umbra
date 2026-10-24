const std = @import("std");

const platform = @import("../platform.zig");
const tray_module = @import("tray.zig");

const assert = std.debug.assert;

const backend = platform.backend.icon;

const CapacityError = platform.CapacityError;
const Icon = platform.Icon;
const PlatformError = platform.PlatformError;
const RequestError = platform.RequestError;
const Tray = tray_module.Tray;

const icon_count_max = platform.icon_count_max;
const icon_name_bytes_max = platform.icon_name_bytes_max;
const pixmap_bytes_max = platform.pixmap_bytes_max;

const Entry = struct {
    icon: ?Icon,
    name: [icon_name_bytes_max]u8,
    name_len: u8,
    source: Icon.Source,

    fn init(name: []const u8, source: Icon.Source) Entry {
        assert(name.len > 0);
        assert(name.len <= icon_name_bytes_max);

        var result = Entry{
            .icon = null,
            .name = @splat(0),
            .name_len = @intCast(name.len),
            .source = source,
        };

        @memcpy(result.name[0..name.len], name);

        return result;
    }

    fn release(entry: *Entry) void {
        if (entry.icon) |icon| {
            backend.destroy(icon);

            entry.icon = null;
        }

        assert(entry.icon == null);
    }

    fn get_name(entry: *const Entry) []const u8 {
        assert(entry.name_len <= icon_name_bytes_max);

        return entry.name[0..entry.name_len];
    }

    fn matches(entry: *const Entry, target: []const u8) bool {
        return std.mem.eql(u8, entry.get_name(), target);
    }
};

pub const IconSet = struct {
    count: u8,
    current: u8,
    entries: [icon_count_max]?Entry,
    loaded: bool,
    pixel_bytes: u32,
    tray: ?*Tray,

    pub fn init() IconSet {
        const result = IconSet{
            .count = 0,
            .current = 0,
            .entries = @splat(null),
            .loaded = false,
            .pixel_bytes = 0,
            .tray = null,
        };

        assert(result.is_empty());
        assert(!result.is_loaded());

        return result;
    }

    pub fn deinit(icons: *IconSet) void {
        for (&icons.entries) |*slot| {
            if (slot.*) |*entry| {
                entry.release();
            }

            slot.* = null;
        }

        icons.count = 0;
        icons.current = 0;
        icons.loaded = false;
        icons.pixel_bytes = 0;
        icons.tray = null;

        assert(icons.is_empty());
    }

    pub fn bind(icons: *IconSet, tray: *Tray) void {
        icons.tray = tray;

        assert(icons.tray != null);
    }

    pub fn add(
        icons: *IconSet,
        name: []const u8,
        source: Icon.Source,
    ) (CapacityError || RequestError)!void {
        if (name.len == 0) return error.NameEmpty;
        if (name.len > icon_name_bytes_max) return error.NameTooLong;
        if (!source.is_valid()) return error.SourceInvalid;
        if (icons.find(name) != null) return error.IconDuplicate;

        const pixel_bytes = pixel_bytes_of(source);
        const slot = icons.find_empty() orelse return error.IconsExhausted;

        if (pixel_bytes > pixmap_bytes_max - icons.pixel_bytes) return error.PixelsExhausted;

        assert(slot < icon_count_max);

        icons.entries[slot] = Entry.init(name, source);
        icons.count += 1;
        icons.pixel_bytes += pixel_bytes;

        assert(icons.count <= icon_count_max);
        assert(icons.pixel_bytes <= pixmap_bytes_max);
    }

    pub fn get_current(icons: *const IconSet) ?Icon {
        assert(icons.current < icon_count_max);

        const entry = icons.entries[icons.current] orelse return null;
        return entry.icon;
    }

    pub fn get_current_name(icons: *const IconSet) ?[]const u8 {
        assert(icons.current < icon_count_max);

        if (icons.entries[icons.current]) |*entry| {
            return entry.get_name();
        }

        return null;
    }

    pub fn get_source(icons: *const IconSet, name: []const u8) ?Icon.Source {
        const index = icons.find(name) orelse return null;
        const entry = icons.entries[index] orelse return null;

        return entry.source;
    }

    pub fn is_empty(icons: *const IconSet) bool {
        return icons.count == 0;
    }

    pub fn is_loaded(icons: *const IconSet) bool {
        return icons.loaded;
    }

    pub fn load(icons: *IconSet) (CapacityError || PlatformError || RequestError)!void {
        if (icons.count == 0) return error.IconsEmpty;

        var loaded: u8 = 0;

        for (&icons.entries) |*slot| {
            const entry = if (slot.*) |*live| live else continue;

            if (entry.icon == null) {
                entry.icon = try backend.load(entry.source);
            }

            loaded += 1;
        }

        assert(loaded == icons.count);

        icons.loaded = true;
    }

    pub fn set_current(icons: *IconSet, name: []const u8) (PlatformError || RequestError)!void {
        const index = icons.find(name) orelse return error.IconUnknown;

        assert(index < icon_count_max);

        if (index == icons.current) {
            return;
        }

        icons.current = index;

        const tray = icons.tray orelse return;
        const icon = icons.get_current() orelse return;

        if (!tray.is_created()) {
            return;
        }

        try tray.set_icon(icon);
    }

    fn find(icons: *const IconSet, name: []const u8) ?u8 {
        for (icons.entries, 0..) |slot, index| {
            const entry = slot orelse continue;
            if (entry.matches(name)) return @intCast(index);
        }

        return null;
    }

    fn find_empty(icons: *const IconSet) ?u8 {
        for (icons.entries, 0..) |slot, index| {
            if (slot == null) return @intCast(index);
        }

        return null;
    }
};

fn pixel_bytes_of(source: Icon.Source) u32 {
    const result: u32 = switch (source) {
        .file_path, .stock => 0,
        .pixels => |pixmap| @intCast(pixmap.byte_count()),
    };

    assert(result <= pixmap_bytes_max);

    return result;
}

const testing = std.testing;

const full_argb: [pixmap_bytes_max]u8 = @splat(0);

test IconSet {
    var icons = IconSet.init();
    defer icons.deinit();

    try icons.add("idle", .{ .stock = .application });
    try icons.add("active", .{ .stock = .shield });
    try icons.set_current("active");

    try testing.expectEqualStrings("active", icons.get_current_name().?);
    try testing.expectEqual(Icon.Stock.shield, icons.get_source("active").?.stock);
    try testing.expect(icons.get_current() == null);
}

test "an icon set names the fault in each refused icon" {
    var icons = IconSet.init();
    defer icons.deinit();

    const long: [icon_name_bytes_max + 1]u8 = @splat('a');

    try icons.add("icon", .{ .stock = .application });

    try testing.expectError(error.IconDuplicate, icons.add("icon", .{ .stock = .shield }));
    try testing.expectError(error.NameEmpty, icons.add("", .{ .stock = .application }));
    try testing.expectError(error.NameTooLong, icons.add(&long, .{ .stock = .application }));
    try testing.expectError(error.SourceInvalid, icons.add("file", .{ .file_path = "" }));
    try testing.expectError(error.IconUnknown, icons.set_current("unknown"));
}

test "a full icon set refuses another icon" {
    var icons = IconSet.init();
    defer icons.deinit();

    var index: u8 = 0;

    while (index < icon_count_max) : (index += 1) {
        var name: [8]u8 = undefined;
        const formatted = try std.mem.print(&name, "{d}", .{index});

        try icons.add(formatted, .{ .stock = .application });
    }

    const overflow = icons.add("overflow", .{ .stock = .application });

    try testing.expectError(error.IconsExhausted, overflow);
}

test "the pixmaps of an icon set share one pixel budget" {
    var icons = IconSet.init();
    defer icons.deinit();

    const dimension = platform.pixmap_dimension_max;
    const full = Icon.Pixmap.init(&full_argb, dimension, dimension);
    const pixel = Icon.Pixmap.init(full_argb[0..platform.channel_count], 1, 1);

    try icons.add("full", .{ .pixels = full });

    try testing.expectEqual(@as(u32, @intCast(full.byte_count())), icons.pixel_bytes);
    try testing.expectError(error.PixelsExhausted, icons.add("pixel", .{ .pixels = pixel }));

    try icons.add("stock", .{ .stock = .shield });

    try testing.expectEqual(pixmap_bytes_max, icons.pixel_bytes);
    try testing.expectEqual(@as(u8, 2), icons.count);
}

test "an empty icon set has nothing to load and names no current icon" {
    var icons = IconSet.init();
    defer icons.deinit();

    try testing.expect(icons.get_current_name() == null);
    try testing.expectError(error.IconsEmpty, icons.load());
}

test "tearing down an icon set clears every entry" {
    var icons = IconSet.init();

    try icons.add("icon1", .{ .stock = .application });
    try icons.add("icon2", .{ .stock = .shield });

    icons.deinit();

    try testing.expect(icons.is_empty());
    try testing.expect(!icons.is_loaded());
}
