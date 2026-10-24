const std = @import("std");

const event_module = @import("../event.zig");

const assert = std.debug.assert;

const Event = event_module.Event;

pub const CapacityError = error{
    BodyTooLong,
    IconsExhausted,
    IntervalTooLong,
    ItemsExhausted,
    LabelTooLong,
    ListenersExhausted,
    NameTooLong,
    PathTooLong,
    PixelsExhausted,
    TimersExhausted,
    TitleTooLong,
    TooltipTooLong,
    WatchesExhausted,
};

pub const PlatformError = error{
    DirectoryMissing,
    IconLoadFailed,
    LaunchFailed,
    LoopFailed,
    MenuBuildFailed,
    NotificationFailed,
    RuntimeOpenFailed,
    TimerStartFailed,
    TrayCreateFailed,
    TrayUpdateFailed,
    WatchAddFailed,
};

pub const RequestError = error{
    BodyEmpty,
    BodyInvalid,
    IconDuplicate,
    IconUnknown,
    IconsEmpty,
    IntervalInvalid,
    ItemUnknown,
    LabelEmpty,
    LabelInvalid,
    NameEmpty,
    NameInvalid,
    PathEmpty,
    PathInvalid,
    SourceInvalid,
    TimerDuplicate,
    TimerUnknown,
    TitleEmpty,
    TitleInvalid,
    TooltipEmpty,
    TooltipInvalid,
    TrayMissing,
};

pub fn is_valid_text(text: []const u8) bool {
    if (std.mem.findScalar(u8, text, 0) != null) {
        return false;
    }

    return std.unicode.utf8ValidateSlice(text);
}

pub const Icon = enum(u32) {
    _,

    pub const Pixmap = struct {
        argb: []const u8,
        height: u32,
        width: u32,

        pub fn init(argb: []const u8, width: u32, height: u32) Pixmap {
            assert(width > 0);
            assert(height > 0);

            const result = Pixmap{
                .argb = argb,
                .height = height,
                .width = width,
            };

            assert(result.is_valid());

            return result;
        }

        pub fn byte_count(pixmap: *const Pixmap) u64 {
            const width: u64 = pixmap.width;
            const height: u64 = pixmap.height;

            return width * height * channel_count;
        }

        pub fn from_rgba(comptime rgba: []const u8, comptime width: u32) Pixmap {
            const row_bytes = width * channel_count;

            comptime assert(width > 0);
            comptime assert(rgba.len >= row_bytes);

            const height: u32 = @divExact(rgba.len, row_bytes);
            const argb = comptime to_argb(rgba);

            return Pixmap.init(&argb, width, height);
        }

        pub fn is_valid(pixmap: *const Pixmap) bool {
            if (pixmap.width == 0) return false;
            if (pixmap.width > pixmap_dimension_max) return false;
            if (pixmap.height == 0) return false;
            if (pixmap.height > pixmap_dimension_max) return false;
            return pixmap.argb.len == pixmap.byte_count();
        }
    };

    pub const Source = union(enum) {
        file_path: []const u8,
        pixels: Pixmap,
        stock: Stock,

        pub fn is_valid(source: *const Source) bool {
            const result = switch (source.*) {
                .file_path => |path| path.len > 0 and
                    path.len < path_bytes_max and
                    is_valid_text(path),
                .pixels => |pixmap| pixmap.is_valid(),
                .stock => |stock| stock.is_valid(),
            };

            return result;
        }
    };

    pub const Stock = enum(u8) {
        application = 0,
        err = 1,
        information = 2,
        question = 3,
        shield = 4,
        warning = 5,

        pub fn is_valid(stock: Stock) bool {
            return @backingInt(stock) <= @backingInt(Stock.warning);
        }
    };
};

fn to_argb(comptime rgba: []const u8) [rgba.len]u8 {
    @setEvalBranchQuota(rgba.len * 8);

    comptime assert(rgba.len % channel_count == 0);

    var result: [rgba.len]u8 = undefined;
    var index: usize = 0;

    while (index + channel_count <= rgba.len) : (index += channel_count) {
        result[index + 0] = rgba[index + 3];
        result[index + 1] = rgba[index + 0];
        result[index + 2] = rgba[index + 1];
        result[index + 3] = rgba[index + 2];
    }

    return result;
}

pub const MenuItem = struct {
    checked: bool = false,
    enabled: bool = true,
    id: u32 = 0,
    kind: MenuItemKind = .action,
    label: []const u8 = "",

    pub fn is_valid(item: *const MenuItem) bool {
        if (!item.kind.is_valid()) {
            return false;
        }

        if (item.id > menu_item_id_max) {
            return false;
        }

        if (item.kind == .separator) {
            return true;
        }

        if (item.label.len == 0) return false;
        if (item.label.len > menu_label_bytes_max) return false;
        return is_valid_text(item.label);
    }
};

pub const MenuItemKind = enum(u8) {
    action = 0,
    radio = 1,
    separator = 2,
    toggle = 3,

    pub fn is_valid(kind: MenuItemKind) bool {
        return @backingInt(kind) <= @backingInt(MenuItemKind.toggle);
    }
};

pub const Notification = struct {
    body: []const u8,
    kind: Kind = .info,
    silent: bool = false,
    title: []const u8,

    pub const Kind = enum(u8) {
        err = 0,
        info = 1,
        none = 2,
        warning = 3,

        pub fn is_valid(kind: Kind) bool {
            return @backingInt(kind) <= @backingInt(Kind.warning);
        }
    };

    pub fn validate(notification: *const Notification) (CapacityError || RequestError)!void {
        assert(notification.kind.is_valid());

        if (notification.title.len == 0) return error.TitleEmpty;
        if (notification.title.len > notification_title_bytes_max) return error.TitleTooLong;
        if (!is_valid_text(notification.title)) return error.TitleInvalid;
        if (notification.body.len == 0) return error.BodyEmpty;
        if (notification.body.len > notification_body_bytes_max) return error.BodyTooLong;
        if (!is_valid_text(notification.body)) return error.BodyInvalid;
    }

    pub fn is_valid(notification: *const Notification) bool {
        notification.validate() catch return false;

        return true;
    }
};

pub const RuntimeOptions = struct {
    name: []const u8,

    pub fn is_valid(options: *const RuntimeOptions) bool {
        if (options.name.len == 0) return false;
        if (options.name.len > app_name_bytes_max) return false;
        return is_valid_text(options.name);
    }
};

pub const Timer = struct {
    id: u32,
    interval_ms: u32,
};

pub const TrayCreateOptions = struct {
    icon: ?Icon = null,
    tooltip: []const u8 = "",
};

pub const Watch = enum(u32) { _ };
pub const Listener = *const fn (*anyopaque) void;
pub const app_name_bytes_max: u32 = 63;
pub const channel_count: u32 = 4;
pub const icon_count_max: u8 = 16;
pub const icon_name_bytes_max: u32 = 31;
pub const menu_group_bytes_max: u32 = 31;
pub const menu_item_count_max: u8 = 64;
pub const menu_item_id_max: u32 = (1 << 30) - 1;
pub const menu_label_bytes_max: u32 = 127;
pub const notification_body_bytes_max: u32 = 255;
pub const notification_title_bytes_max: u32 = 63;
pub const path_bytes_max: u32 = 512;
pub const pixmap_dimension_max: u32 = 256;
pub const pixmap_bytes_max: u32 = pixmap_dimension_max * pixmap_dimension_max * channel_count;
pub const timer_count_max: u8 = 16;
pub const timer_interval_ms_max: u32 = 0x7FFF_FFFF;
pub const tooltip_bytes_max: u32 = 127;
pub const watch_count_max: u8 = 4;

comptime {
    assert(app_name_bytes_max > 0);
    assert(channel_count == 4);
    assert(icon_count_max > 0);
    assert(icon_name_bytes_max > 0);
    assert(menu_group_bytes_max > 0);
    assert(menu_item_count_max > 0);
    assert(menu_item_id_max < std.math.maxInt(i32));
    assert(menu_label_bytes_max > 0);
    assert(notification_title_bytes_max < notification_body_bytes_max);
    assert(path_bytes_max >= 260);
    assert(pixmap_dimension_max > 0);
    assert(timer_count_max > 0);
    assert(timer_interval_ms_max == std.math.maxInt(i32));
    assert(tooltip_bytes_max > 0);
    assert(watch_count_max > 0);
    assert(@typeInfo(Icon.Stock).@"enum".field_names.len == 6);
    assert(@typeInfo(MenuItemKind).@"enum".field_names.len == 4);
    assert(@typeInfo(Notification.Kind).@"enum".field_names.len == 4);
}

pub fn assert_backend(comptime backend: type) void {
    comptime {
        assert_time(backend);
        assert_runtime(backend);
        assert_icon(backend);
        assert_tray(backend);
        assert_menu(backend);
        assert_notification(backend);
        assert_paths(backend);
        assert_shell(backend);
        assert_timer(backend);
        assert_watcher(backend);
        assert_loop(backend);
    }
}

fn assert_time(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "time", "backend");

    require_fn(scope, "now_ms", fn () u64, "time");
}

fn assert_runtime(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "runtime", "backend");

    require_fn(scope, "open", fn (RuntimeOptions) PlatformError!void, "runtime");
    require_fn(scope, "close", fn () void, "runtime");
    require_fn(scope, "is_open", fn () bool, "runtime");
}

fn assert_icon(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "icon", "backend");

    require_fn(scope, "load", fn (Icon.Source) (CapacityError || PlatformError)!Icon, "icon");
    require_fn(scope, "destroy", fn (Icon) void, "icon");
}

fn assert_tray(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "tray", "backend");

    require_fn(scope, "create", fn (TrayCreateOptions) PlatformError!void, "tray");
    require_fn(scope, "destroy", fn () void, "tray");
    require_fn(scope, "is_created", fn () bool, "tray");
    require_fn(scope, "set_icon", fn (Icon) PlatformError!void, "tray");
    require_fn(scope, "set_tooltip", fn ([]const u8) PlatformError!void, "tray");
}

fn assert_menu(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "menu", "backend");

    require_fn(scope, "build", fn ([]const MenuItem) PlatformError!void, "menu");
    require_fn(scope, "destroy", fn () void, "menu");
}

fn assert_notification(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "notification", "backend");

    require_fn(scope, "send", fn (Notification) PlatformError!void, "notification");
}

fn assert_paths(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "paths", "backend");
    const Located = (CapacityError || PlatformError)![]const u8;

    require_fn(scope, "config_dir", fn ([]u8, []const u8) Located, "paths");
    require_fn(scope, "state_dir", fn ([]u8, []const u8) Located, "paths");
}

fn assert_shell(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "shell", "backend");

    require_fn(scope, "open", fn ([]const u8) PlatformError!void, "shell");
}

fn assert_timer(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "timer", "backend");

    require_fn(scope, "start", fn (Timer) PlatformError!void, "timer");
    require_fn(scope, "stop", fn (u32) bool, "timer");
    require_fn(scope, "stop_all", fn () void, "timer");
}

fn assert_watcher(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "watcher", "backend");
    const Watched = (CapacityError || PlatformError)!Watch;

    require_fn(scope, "watch", fn ([]const u8, Listener, *anyopaque) Watched, "watcher");
    require_fn(scope, "unwatch", fn (Watch) void, "watcher");
    require_fn(scope, "stop_all", fn () void, "watcher");
}

fn assert_loop(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "loop", "backend");

    require_decl(scope, "LoopType", "loop");

    const Owner = struct {
        pub fn dispatch(_: *@This(), _: *const Event) void {}
    };

    const Instance = scope.LoopType(Owner);

    require_fn(Instance, "init", fn () Instance, "loop.LoopType");
    require_fn(Instance, "run", fn (*Instance, *Owner) PlatformError!void, "loop.LoopType");
    require_fn(scope, "quit", fn () void, "loop");
    require_fn(scope, "post", fn (u32) bool, "loop");
}

fn RequiredNamespaceType(
    comptime scope: type,
    comptime name: []const u8,
    comptime label: []const u8,
) type {
    require_decl(scope, name, label);

    const Namespace = @field(scope, name);

    if (@TypeOf(Namespace) != type) {
        @compileError(
            "umbra backend " ++ label ++ "." ++ name ++ " must be a namespace, found " ++
                @typeName(@TypeOf(Namespace)),
        );
    }

    return Namespace;
}

fn require_decl(comptime scope: type, comptime name: []const u8, comptime label: []const u8) void {
    if (!@hasDecl(scope, name)) {
        @compileError("umbra backend " ++ label ++ " is missing declaration '" ++ name ++ "'");
    }
}

fn require_fn(
    comptime scope: type,
    comptime name: []const u8,
    comptime Signature: type,
    comptime label: []const u8,
) void {
    require_decl(scope, name, label);

    const Actual = @TypeOf(@field(scope, name));

    if (Actual != Signature) {
        @compileError(
            "umbra backend " ++ label ++ "." ++ name ++ " has type " ++ @typeName(Actual) ++
                ", expected " ++ @typeName(Signature),
        );
    }
}

const testing = std.testing;

test "Icon.Pixmap reorders RGBA into ARGB at compile time" {
    const rgba = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    const pixmap = Icon.Pixmap.from_rgba(&rgba, 2);

    try testing.expectEqual(@as(u32, 2), pixmap.width);
    try testing.expectEqual(@as(u32, 2), pixmap.height);
    try testing.expect(pixmap.is_valid());

    try testing.expectEqualSlices(
        u8,
        &.{ 4, 1, 2, 3, 8, 5, 6, 7, 12, 9, 10, 11, 16, 13, 14, 15 },
        pixmap.argb,
    );
}

test "a pixmap rejects a mismatched buffer and oversized dimensions" {
    const short: [8]u8 = @splat(0);
    const mismatched = Icon.Pixmap{ .argb = &short, .height = 2, .width = 2 };
    const pixel: [4]u8 = @splat(0);
    const wide = Icon.Pixmap{ .argb = &pixel, .height = 1, .width = pixmap_dimension_max + 1 };

    try testing.expect(!mismatched.is_valid());
    try testing.expect(!wide.is_valid());
}

test "each icon source validates its own variant" {
    const argb: [channel_count]u8 = @splat(0);

    const sources = [_]Icon.Source{
        .{ .file_path = "icon.png" },
        .{ .pixels = Icon.Pixmap.init(&argb, 1, 1) },
        .{ .stock = .application },
    };

    for (sources) |source| {
        try testing.expect(source.is_valid());
    }

    const empty = Icon.Source{ .file_path = "" };
    const terminated = Icon.Source{ .file_path = "icon\x00.png" };

    try testing.expect(!empty.is_valid());
    try testing.expect(!terminated.is_valid());
}

test "a menu item needs a bounded id, and a bounded label unless it is a separator" {
    const label: [menu_label_bytes_max + 1]u8 = @splat('a');
    const distant = MenuItem{ .id = menu_item_id_max + 1, .kind = .action, .label = "Quit" };
    const garbled = MenuItem{ .id = 1, .kind = .action, .label = "\xFF" };

    try testing.expect((MenuItem{ .kind = .separator }).is_valid());
    try testing.expect((MenuItem{ .kind = .action, .label = "Quit" }).is_valid());
    try testing.expect(!distant.is_valid());
    try testing.expect(!garbled.is_valid());
    try testing.expect(!(MenuItem{ .kind = .action, .label = "" }).is_valid());
    try testing.expect(!(MenuItem{ .kind = .action, .label = &label }).is_valid());
}

test "a notification names the fault in each refused field" {
    const title: [notification_title_bytes_max + 1]u8 = @splat('t');
    const body: [notification_body_bytes_max + 1]u8 = @splat('b');
    const good = Notification{ .body = "b", .title = "t" };
    const untitled = Notification{ .body = "b", .title = "" };
    const blank = Notification{ .body = "", .title = "t" };
    const titled = Notification{ .body = "b", .title = &title };
    const verbose = Notification{ .body = &body, .title = "t" };
    const garbled = Notification{ .body = "b", .title = "\xC3\x28" };
    const terminated = Notification{ .body = "b\x00c", .title = "t" };

    try good.validate();

    try testing.expectError(error.TitleEmpty, untitled.validate());
    try testing.expectError(error.BodyEmpty, blank.validate());
    try testing.expectError(error.TitleTooLong, titled.validate());
    try testing.expectError(error.BodyTooLong, verbose.validate());
    try testing.expectError(error.TitleInvalid, garbled.validate());
    try testing.expectError(error.BodyInvalid, terminated.validate());
}

test is_valid_text {
    const samples = [_][]const u8{
        "",
        "Mute",
        "caf\xC3\xA9",
        "\xC3\x28",
        "\xFF",
        "a\x00b",
        "\xED\xA0\x80",
    };

    for (samples) |sample| {
        const free = std.mem.findScalar(u8, sample, 0) == null;
        const expected = free and std.unicode.utf8ValidateSlice(sample);

        try testing.expectEqual(expected, is_valid_text(sample));
    }

    try testing.expect(is_valid_text("caf\xC3\xA9"));
    try testing.expect(!is_valid_text("a\x00b"));
    try testing.expect(!is_valid_text("\xC3\x28"));
}

test "a runtime name is bounded by the application name" {
    const long: [app_name_bytes_max + 1]u8 = @splat('a');

    try testing.expect((RuntimeOptions{ .name = "umbra" }).is_valid());
    try testing.expect(!(RuntimeOptions{ .name = "" }).is_valid());
    try testing.expect(!(RuntimeOptions{ .name = &long }).is_valid());
    try testing.expect(!(RuntimeOptions{ .name = "\xC3\x28" }).is_valid());
}
