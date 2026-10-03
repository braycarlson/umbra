const std = @import("std");

const w32 = @import("win32.zig");

const contract = @import("../contract.zig");
const runtime = @import("runtime.zig");

const assert = std.debug.assert;

pub const Error = contract.IconError;

pub const Source = contract.IconSource;
pub const Handle = contract.IconHandle;

pub const supports_resource: bool = true;

pub const handle_max: u32 = 32;
pub const path_bytes_max: u32 = contract.path_bytes_max;

const NativeError = error{
    CreateFailed,
    InvalidSource,
    LoadFailed,
    PathConversionFailed,
    PathTooLong,
};

const resource_application: u32 = 32512;
const resource_error: u32 = 32513;
const resource_question: u32 = 32514;
const resource_warning: u32 = 32515;
const resource_information: u32 = 32516;
const resource_shield: u32 = 32518;

comptime {
    assert(handle_max > 0);
    assert(path_bytes_max > 0);
}

pub const System = enum(u8) {
    application = 0,
    err = 1,
    information = 2,
    question = 3,
    shield = 4,
    warning = 5,

    pub fn from_stock(stock: contract.Stock) System {
        const result = switch (stock) {
            .application => System.application,
            .err => System.err,
            .information => System.information,
            .question => System.question,
            .shield => System.shield,
            .warning => System.warning,
        };

        return result;
    }

    pub fn to_resource(system: System) [*:0]align(1) const u16 {
        const id: u32 = switch (system) {
            .application => resource_application,
            .err => resource_error,
            .information => resource_information,
            .question => resource_question,
            .shield => resource_shield,
            .warning => resource_warning,
        };

        const result: [*:0]align(1) const u16 = @ptrFromInt(id);

        return result;
    }
};

pub const NativeSource = union(enum) {
    file: FileSource,
    resource: ResourceSource,
    system: System,

    pub const FileSource = struct {
        path: []const u8,
    };

    pub const ResourceSource = struct {
        id: u32,
        instance: ?w32.HINSTANCE = null,
    };
};

pub const LoadOptions = struct {
    default_size: bool = true,
    height: u32 = 0,
    shared: bool = false,
    source: NativeSource,
    width: u32 = 0,
};

pub const Icon = struct {
    handle: w32.HICON,
    owned: bool = true,

    pub fn load(options: LoadOptions) NativeError!Icon {
        const result = switch (options.source) {
            .file => |source| load_from_file(source, options),
            .resource => |source| load_from_resource(source, options),
            .system => |system| load_from_system(system),
        };

        return result;
    }

    pub fn deinit(icon: *const Icon) bool {
        if (icon.owned and icon.is_valid()) {
            return w32.DestroyIcon(icon.handle) != 0;
        }

        return true;
    }

    pub fn is_valid(icon: *const Icon) bool {
        return @intFromPtr(icon.handle) != 0;
    }
};

var entries: [handle_max]?Icon = @splat(null);

pub fn load(source: Source) Error!Handle {
    if (!source.is_valid()) {
        return Error.InvalidSource;
    }

    const slot = find_empty_slot() orelse return Error.CapacityExceeded;

    assert(slot < handle_max);

    const icon = load_native(source) catch |err| {
        return translate(err);
    };

    entries[slot] = icon;

    assert(entries[slot] != null);

    return slot;
}

pub fn destroy(handle: Handle) void {
    if (handle >= handle_max) {
        return;
    }

    const icon = entries[handle] orelse return;

    _ = icon.deinit();

    entries[handle] = null;

    assert(entries[handle] == null);
}

pub fn get(handle: Handle) ?Icon {
    if (handle >= handle_max) {
        return null;
    }

    return entries[handle];
}

pub fn live_count() u32 {
    var total: u32 = 0;
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

        if (entries[index] != null) total += 1;
    }

    assert(total <= handle_max);

    return total;
}

fn translate(err: NativeError) Error {
    const result = switch (err) {
        NativeError.InvalidSource, NativeError.PathTooLong => Error.InvalidSource,
        NativeError.CreateFailed,
        NativeError.LoadFailed,
        NativeError.PathConversionFailed,
        => Error.LoadFailed,
    };

    return result;
}

fn load_native(source: Source) NativeError!Icon {
    const result = switch (source) {
        .file_path => |path| try Icon.load(.{
            .source = .{ .file = .{ .path = path } },
        }),
        .pixels => |pixmap| try load_from_pixels(pixmap),
        .resource => |id| try Icon.load(.{
            .source = .{ .resource = .{ .id = id, .instance = runtime.module_instance() } },
        }),
        .stock => |stock| try Icon.load(.{
            .source = .{ .system = System.from_stock(stock) },
        }),
    };

    return result;
}

fn find_empty_slot() ?Handle {
    var index: u32 = 0;

    while (index < handle_max) : (index += 1) {
        assert(index < handle_max);

        if (entries[index] == null) return index;
    }

    return null;
}

fn load_from_file(source: NativeSource.FileSource, options: LoadOptions) NativeError!Icon {
    assert(source.path.len > 0);

    if (source.path.len == 0 or source.path.len >= path_bytes_max) {
        return NativeError.PathTooLong;
    }

    var wide: [path_bytes_max]u16 = undefined;

    const length = std.unicode.utf8ToUtf16Le(wide[0..source.path.len], source.path) catch {
        return NativeError.PathConversionFailed;
    };

    assert(length > 0);
    assert(length < path_bytes_max);

    wide[length] = 0;

    var flags: u32 = w32.LR_LOADFROMFILE;

    if (options.default_size) flags |= w32.LR_DEFAULTSIZE;
    if (options.shared) flags |= w32.LR_SHARED;

    const handle: ?w32.HICON = @ptrCast(w32.LoadImageW(
        null,
        @ptrCast(&wide),
        w32.IMAGE_ICON,
        @intCast(options.width),
        @intCast(options.height),
        flags,
    ));

    if (handle == null) {
        return NativeError.LoadFailed;
    }

    assert(handle != null);

    const result = Icon{
        .handle = handle.?,
        .owned = !options.shared,
    };

    return result;
}

fn load_from_resource(source: NativeSource.ResourceSource, options: LoadOptions) NativeError!Icon {
    assert(source.id > 0);

    if (source.id == 0) {
        return NativeError.InvalidSource;
    }

    const module: w32.HINSTANCE = @ptrCast(w32.GetModuleHandleW(null));
    const instance = source.instance orelse module;

    assert(@intFromPtr(instance) != 0);

    var flags: u32 = 0;

    if (options.default_size) flags |= w32.LR_DEFAULTSIZE;
    if (options.shared) flags |= w32.LR_SHARED;

    const handle: ?w32.HICON = @ptrCast(w32.LoadImageW(
        instance,
        @ptrFromInt(@as(u64, source.id)),
        w32.IMAGE_ICON,
        @intCast(options.width),
        @intCast(options.height),
        flags,
    ));

    if (handle == null) {
        return NativeError.LoadFailed;
    }

    assert(handle != null);

    const result = Icon{
        .handle = handle.?,
        .owned = !options.shared,
    };

    return result;
}

fn load_from_pixels(pixmap: contract.Pixmap) NativeError!Icon {
    assert(pixmap.is_valid());

    const width: i32 = @intCast(pixmap.width);
    const height: i32 = @intCast(pixmap.height);

    var header = std.mem.zeroes(w32.BITMAPINFO);

    header.bmiHeader.biSize = @sizeOf(w32.BITMAPINFOHEADER);
    header.bmiHeader.biWidth = width;
    header.bmiHeader.biHeight = -height;
    header.bmiHeader.biPlanes = 1;
    header.bmiHeader.biBitCount = 32;
    header.bmiHeader.biCompression = w32.BI_RGB;

    var bits: ?*anyopaque = null;

    const color = w32.CreateDIBSection(null, &header, w32.DIB_RGB_COLORS, &bits, null, 0);

    if (color == null or bits == null) {
        return NativeError.CreateFailed;
    }
    defer _ = w32.DeleteObject(color.?);

    copy_argb_to_bgra(@ptrCast(bits.?), pixmap);

    const mask = w32.CreateBitmap(width, height, 1, 1, null);

    if (mask == null) {
        return NativeError.CreateFailed;
    }
    defer _ = w32.DeleteObject(mask.?);

    var info = std.mem.zeroes(w32.ICONINFO);

    info.fIcon = 1;
    info.hbmColor = color.?;
    info.hbmMask = mask.?;

    const handle = w32.CreateIconIndirect(&info);

    if (handle == null) {
        return NativeError.CreateFailed;
    }

    const result = Icon{
        .handle = handle.?,
        .owned = true,
    };

    return result;
}

fn copy_argb_to_bgra(destination: [*]u8, pixmap: contract.Pixmap) void {
    assert(pixmap.is_valid());
    assert(pixmap.argb.len <= contract.pixmap_bytes_max);

    const count = pixmap.argb.len;

    var index: u64 = 0;

    while (index + contract.channel_count <= count) : (index += contract.channel_count) {
        assert(index + 3 < count);

        destination[index + 0] = pixmap.argb[index + 3];
        destination[index + 1] = pixmap.argb[index + 2];
        destination[index + 2] = pixmap.argb[index + 1];
        destination[index + 3] = pixmap.argb[index + 0];
    }

    assert(index == count);
}

fn load_from_system(system: System) NativeError!Icon {
    const handle = w32.LoadIconW(null, system.to_resource());

    if (handle == null) {
        return NativeError.LoadFailed;
    }

    assert(handle != null);

    const result = Icon{
        .handle = handle.?,
        .owned = false,
    };

    return result;
}

const testing = std.testing;

test "a system icon maps to a valid resource pointer" {
    const app_resource = System.application.to_resource();
    const shield_resource = System.shield.to_resource();

    try testing.expect(@intFromPtr(app_resource) != 0);
    try testing.expect(@intFromPtr(shield_resource) != 0);
    try testing.expect(@intFromPtr(app_resource) != @intFromPtr(shield_resource));
}

test "every stock icon maps to a system icon" {
    try testing.expectEqual(System.application, System.from_stock(.application));
    try testing.expectEqual(System.err, System.from_stock(.err));
    try testing.expectEqual(System.information, System.from_stock(.information));
    try testing.expectEqual(System.question, System.from_stock(.question));
    try testing.expectEqual(System.shield, System.from_stock(.shield));
    try testing.expectEqual(System.warning, System.from_stock(.warning));
}

test "an icon with a handle is valid" {
    const icon = Icon{
        .handle = @ptrFromInt(0x12345678),
        .owned = true,
    };

    try testing.expect(icon.is_valid());
}

test "tearing down an unowned icon leaves the handle alone" {
    const icon = Icon{
        .handle = @ptrFromInt(0x12345678),
        .owned = false,
    };

    const result = icon.deinit();

    try testing.expect(result);
}

test "load rejects an invalid source" {
    try testing.expectError(Error.InvalidSource, load(.{ .file_path = "" }));
    try testing.expectError(Error.InvalidSource, load(.{ .resource = 0 }));
}

test "destroy ignores a handle beyond the table" {
    destroy(handle_max);
    destroy(handle_max + 1);

    try testing.expect(get(handle_max) == null);
}

test "translate maps every native failure" {
    try testing.expectEqual(Error.InvalidSource, translate(NativeError.InvalidSource));
    try testing.expectEqual(Error.InvalidSource, translate(NativeError.PathTooLong));
    try testing.expectEqual(Error.LoadFailed, translate(NativeError.CreateFailed));
    try testing.expectEqual(Error.LoadFailed, translate(NativeError.LoadFailed));
    try testing.expectEqual(Error.LoadFailed, translate(NativeError.PathConversionFailed));

    assert(@typeInfo(NativeError).error_set.error_names.?.len == 5);
}

test "a resource source carries its id" {
    const src = NativeSource{ .resource = .{ .id = 100, .instance = null } };

    switch (src) {
        .resource => |source| {
            try testing.expectEqual(@as(u32, 100), source.id);
            try testing.expect(source.instance == null);
        },
        else => try testing.expect(false),
    }
}

test "a file source carries its path" {
    const src = NativeSource{ .file = .{ .path = "test.ico" } };

    switch (src) {
        .file => |source| {
            try testing.expectEqualStrings("test.ico", source.path);
        },
        else => try testing.expect(false),
    }
}

test "LoadOptions defaults" {
    const options = LoadOptions{
        .source = .{ .system = .application },
    };

    try testing.expect(options.default_size);
    try testing.expect(!options.shared);
    try testing.expectEqual(@as(u32, 0), options.width);
    try testing.expectEqual(@as(u32, 0), options.height);
}
