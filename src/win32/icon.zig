const std = @import("std");

const w32 = @import("win32").everything;

pub const path_max: u16 = 260;

const draw_flag_mask: u32 = 0x0001;
const draw_flag_image: u32 = 0x0002;
const draw_flag_rop_mask: u32 = 0x0004;
const draw_flag_default_size: u32 = 0x0008;
const draw_flag_no_mirror: u32 = 0x0010;
const draw_flag_overlay_mask: u32 = 0x0020;
const draw_flag_selected: u32 = 0x0040;
const draw_flag_focus: u32 = 0x0080;
const draw_flag_disabled: u32 = 0x0100;
const draw_flag_transparent: u32 = 0x0200;

pub const System = enum(u8) {
    application = 0,
    shield = 1,

    pub fn to_resource(self: System) [*:0]align(1) const u16 {
        const result = switch (self) {
            .application => w32.IDI_APPLICATION,
            .shield => w32.IDI_SHIELD,
        };

        return result;
    }
};

pub const Source = union(enum) {
    data: DataSource,
    file: FileSource,
    handle: w32.HICON,
    resource: ResourceSource,
    system: System,

    pub const DataSource = struct {
        info: *const w32.ICONINFO,
    };

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
    source: Source,
    width: u32 = 0,
};

pub const DrawOptions = struct {
    background: ?w32.HBRUSH = null,
    flags: DrawFlags = .{},
    foreground: ?u32 = null,
    frame_index: u32 = 0,
    hdc: w32.HDC,
    height: u32 = 0,
    width: u32 = 0,
    x: i32 = 0,
    y: i32 = 0,

    pub const DrawFlags = struct {
        default_size: bool = false,
        disabled: bool = false,
        focus: bool = false,
        image: bool = false,
        mask: bool = false,
        no_mirror: bool = false,
        overlay_mask: bool = false,
        rop_mask: bool = false,
        selected: bool = false,
        transparent: bool = false,

        pub fn to_uint(self: DrawFlags) u32 {
            var result: u32 = 0;

            if (self.mask) result |= draw_flag_mask;
            if (self.image) result |= draw_flag_image;
            if (self.rop_mask) result |= draw_flag_rop_mask;
            if (self.default_size) result |= draw_flag_default_size;
            if (self.no_mirror) result |= draw_flag_no_mirror;
            if (self.overlay_mask) result |= draw_flag_overlay_mask;
            if (self.selected) result |= draw_flag_selected;
            if (self.focus) result |= draw_flag_focus;
            if (self.disabled) result |= draw_flag_disabled;
            if (self.transparent) result |= draw_flag_transparent;

            return result;
        }
    };
};

pub const IconInfo = struct {
    color_bitmap: ?w32.HBITMAP,
    hotspot_x: u32,
    hotspot_y: u32,
    is_icon: bool,
    mask_bitmap: ?w32.HBITMAP,

    pub fn deinit(self: *IconInfo) void {
        if (self.mask_bitmap) |bitmap| {
            _ = w32.DeleteObject(bitmap);
            self.mask_bitmap = null;
        }

        if (self.color_bitmap) |bitmap| {
            _ = w32.DeleteObject(bitmap);
            self.color_bitmap = null;
        }

        std.debug.assert(self.mask_bitmap == null);
        std.debug.assert(self.color_bitmap == null);
    }
};

pub const Error = error{
    CopyFailed,
    CreateFailed,
    DrawFailed,
    GetInfoFailed,
    InvalidSource,
    LoadFailed,
    PathConversionFailed,
    PathTooLong,
};

pub const Icon = struct {
    handle: w32.HICON,
    owned: bool = true,

    pub fn load(options: LoadOptions) Error!Icon {
        const result = switch (options.source) {
            .data => |source| load_from_data(source),
            .file => |source| load_from_file(source, options),
            .handle => |handle| Icon{ .handle = handle, .owned = false },
            .resource => |source| load_from_resource(source, options),
            .system => |system| load_from_system(system),
        };

        return result;
    }

    pub fn copy(self: *const Icon) Error!Icon {
        if (!self.is_valid()) {
            return Error.InvalidSource;
        }

        const new_handle = w32.CopyIcon(self.handle);

        if (new_handle == null) {
            return Error.CopyFailed;
        }

        std.debug.assert(new_handle != null);

        const result = Icon{
            .handle = new_handle.?,
            .owned = true,
        };

        return result;
    }

    pub fn deinit(self: *const Icon) bool {
        if (self.owned and self.is_valid()) {
            const result = w32.DestroyIcon(self.handle) != 0;

            return result;
        }

        return true;
    }

    pub fn draw(self: *const Icon, options: DrawOptions) Error!void {
        if (!self.is_valid()) {
            return Error.InvalidSource;
        }

        const flags = options.flags.to_uint();

        if (options.width == 0 and options.height == 0) {
            if (w32.DrawIcon(options.hdc, options.x, options.y, self.handle) == 0) {
                return Error.DrawFailed;
            }
        } else {
            if (w32.DrawIconEx(
                options.hdc,
                options.x,
                options.y,
                self.handle,
                @intCast(options.width),
                @intCast(options.height),
                options.frame_index,
                options.background,
                flags,
            ) == 0) {
                return Error.DrawFailed;
            }
        }
    }

    pub fn get_info(self: *const Icon) Error!IconInfo {
        if (!self.is_valid()) {
            return Error.InvalidSource;
        }

        var info: w32.ICONINFO = undefined;

        if (w32.GetIconInfo(self.handle, &info) == 0) {
            return Error.GetInfoFailed;
        }

        const result = IconInfo{
            .color_bitmap = info.hbmColor,
            .hotspot_x = info.xHotspot,
            .hotspot_y = info.yHotspot,
            .is_icon = info.fIcon != 0,
            .mask_bitmap = info.hbmMask,
        };

        return result;
    }

    pub fn get_size(self: *const Icon) ?struct { height: i32, width: i32 } {
        var info = self.get_info() catch return null;

        defer info.deinit();

        var bitmap: w32.BITMAP = undefined;

        if (info.color_bitmap) |color| {
            if (w32.GetObjectW(color, @sizeOf(w32.BITMAP), &bitmap) != 0) {
                return .{
                    .height = bitmap.bmHeight,
                    .width = bitmap.bmWidth,
                };
            }
        }

        if (info.mask_bitmap) |mask| {
            if (w32.GetObjectW(mask, @sizeOf(w32.BITMAP), &bitmap) != 0) {
                return .{
                    .height = @divFloor(bitmap.bmHeight, 2),
                    .width = bitmap.bmWidth,
                };
            }
        }

        return null;
    }

    pub fn is_valid(self: *const Icon) bool {
        const result = @intFromPtr(self.handle) != 0;

        return result;
    }
};

fn load_from_data(source: Source.DataSource) Error!Icon {
    const handle = w32.CreateIconIndirect(@constCast(source.info));

    if (handle == null) {
        return Error.CreateFailed;
    }

    std.debug.assert(handle != null);

    const result = Icon{
        .handle = handle.?,
        .owned = true,
    };

    return result;
}

fn load_from_file(source: Source.FileSource, options: LoadOptions) Error!Icon {
    std.debug.assert(source.path.len > 0);

    if (source.path.len == 0 or source.path.len >= path_max) {
        return Error.PathTooLong;
    }

    var wide: [path_max]u16 = undefined;

    const length = std.unicode.utf8ToUtf16Le(&wide, source.path) catch {
        return Error.PathConversionFailed;
    };

    std.debug.assert(length > 0);
    std.debug.assert(length < path_max);

    if (length >= path_max) {
        return Error.PathTooLong;
    }

    wide[length] = 0;

    var flags: w32.IMAGE_FLAGS = .{ .LOADFROMFILE = 1 };

    if (options.default_size) flags.DEFAULTSIZE = 1;
    if (options.shared) flags.SHARED = 1;

    const handle: ?w32.HICON = @ptrCast(w32.LoadImageW(
        null,
        @ptrCast(&wide),
        w32.IMAGE_ICON,
        @intCast(options.width),
        @intCast(options.height),
        flags,
    ));

    if (handle == null) {
        return Error.LoadFailed;
    }

    std.debug.assert(handle != null);

    const result = Icon{
        .handle = handle.?,
        .owned = !options.shared,
    };

    return result;
}

fn load_from_resource(source: Source.ResourceSource, options: LoadOptions) Error!Icon {
    std.debug.assert(source.id > 0);

    if (source.id == 0) {
        return Error.InvalidSource;
    }

    const instance = source.instance orelse @as(w32.HINSTANCE, @ptrCast(w32.GetModuleHandleW(null)));

    std.debug.assert(@intFromPtr(instance) != 0);

    var flags: w32.IMAGE_FLAGS = .{};

    if (options.default_size) flags.DEFAULTSIZE = 1;
    if (options.shared) flags.SHARED = 1;

    const handle: ?w32.HICON = @ptrCast(w32.LoadImageW(
        instance,
        @ptrFromInt(@as(u64, source.id)),
        w32.IMAGE_ICON,
        @intCast(options.width),
        @intCast(options.height),
        flags,
    ));

    if (handle == null) {
        return Error.LoadFailed;
    }

    std.debug.assert(handle != null);

    const result = Icon{
        .handle = handle.?,
        .owned = !options.shared,
    };

    return result;
}

fn load_from_system(system: System) Error!Icon {
    const handle = w32.LoadIconW(null, system.to_resource());

    if (handle == null) {
        return Error.LoadFailed;
    }

    std.debug.assert(handle != null);

    const result = Icon{
        .handle = handle.?,
        .owned = false,
    };

    return result;
}
