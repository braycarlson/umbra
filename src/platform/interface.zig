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
    MenuTooDeep,
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
    InitFailed,
    LaunchFailed,
    LoopFailed,
    MenuBuildFailed,
    NotificationFailed,
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
    TimerReserved,
    TimerUnknown,
    TitleEmpty,
    TitleInvalid,
    TooltipEmpty,
    TooltipInvalid,
    TrayMissing,
};

pub fn is_activation(kind: Event.Kind) bool {
    assert(kind.is_valid());

    return switch (kind) {
        .menu_select, .tray_double_click, .tray_left_click, .tray_right_click => true,
        .app_init, .app_shutdown, .custom, .menu_show, .taskbar_restart, .timer_tick => false,
    };
}

pub fn is_valid_layout(items: []const MenuItem) bool {
    if (items.len > menu_item_count_max) return false;

    var depth_next_max: u8 = 0;

    for (items) |*item| {
        if (!item.is_valid()) return false;
        if (item.depth > depth_next_max) return false;

        depth_next_max = if (item.kind == .submenu) item.depth + 1 else item.depth;
    }

    return true;
}

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
            assert(argb.len == @as(u64, width) * height * channel_count);

            const result = Pixmap{ .argb = argb, .height = height, .width = width };

            assert(result.is_valid());

            return result;
        }

        pub fn byte_count(pixmap: *const Pixmap) u64 {
            const width: u64 = pixmap.width;
            const height: u64 = pixmap.height;
            const result = width * height * channel_count;
            assert(result <= pixmap_bytes_max);

            return result;
        }

        pub fn from_rgba(comptime rgba: []const u8, comptime width: u32) Pixmap {
            comptime assert(width <= pixmap_dimension_max);

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
    comptime assert(rgba.len > 0);

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
    depth: u8 = 0,
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

        if (item.depth > menu_depth_max) {
            return false;
        }

        if (item.kind == .submenu) {
            if (item.depth == menu_depth_max) return false;
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
    submenu = 4,

    pub fn is_valid(kind: MenuItemKind) bool {
        return @backingInt(kind) <= @backingInt(MenuItemKind.submenu);
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

pub const Options = struct {
    name: []const u8,

    pub fn is_valid(options: *const Options) bool {
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
pub const activation_token_bytes_max: u32 = 255;
pub const app_name_bytes_max: u32 = 63;
pub const channel_count: u32 = 4;
pub const icon_count_max: u8 = 16;
pub const icon_name_bytes_max: u32 = 31;
pub const menu_depth_max: u8 = 4;
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
pub const timer_id_max: u32 = std.math.maxInt(u32) - 1;
pub const timer_interval_ms_max: u32 = 0x7FFF_FFFF;
pub const timer_slot_count: u8 = timer_count_max + 1;
pub const tooltip_bytes_max: u32 = 127;
pub const watch_count_max: u8 = 4;

comptime {
    assert(activation_token_bytes_max > 0);
    assert(app_name_bytes_max > 0);
    assert(channel_count == 4);
    assert(icon_count_max > 0);
    assert(icon_name_bytes_max > 0);
    assert(menu_depth_max > 0);
    assert(menu_depth_max < menu_item_count_max);
    assert(menu_group_bytes_max > 0);
    assert(menu_item_count_max > 0);
    assert(menu_item_id_max < std.math.maxInt(i32));
    assert(menu_label_bytes_max > 0);
    assert(notification_title_bytes_max < notification_body_bytes_max);
    assert(path_bytes_max >= 260);
    assert(pixmap_dimension_max > 0);
    assert(timer_count_max > 0);
    assert(timer_id_max < std.math.maxInt(u32));
    assert(timer_interval_ms_max == std.math.maxInt(i32));
    assert(timer_slot_count == timer_count_max + 1);
    assert(tooltip_bytes_max > 0);
    assert(watch_count_max > 0);
    assert(@typeInfo(Icon.Stock).@"enum".field_names.len == 6);
    assert(@typeInfo(MenuItemKind).@"enum".field_names.len == 5);
    assert(@typeInfo(Notification.Kind).@"enum".field_names.len == 4);
}

pub fn assert_backend(comptime Backend: type) void {
    comptime {
        assert(@typeInfo(Backend) == .@"struct");

        assert_lifecycle(Backend);
        assert_icon(Backend);
        assert_tray(Backend);
        assert_menu(Backend);
        assert_notification(Backend);
        assert_paths(Backend);
        assert_shell(Backend);
        assert_timer(Backend);
        assert_watcher(Backend);
        assert_loop(Backend);
    }
}

fn assert_lifecycle(comptime Backend: type) void {
    require_function(Backend, "init", fn (*Backend, Options) PlatformError!void);
    require_function(Backend, "deinit", fn (*Backend) void);
    require_function(Backend, "now_ms", fn (*const Backend) u64);
}

fn assert_icon(comptime Backend: type) void {
    const Loaded = (CapacityError || PlatformError)!Icon;

    require_function(Backend, "icon_load", fn (*Backend, Icon.Source) Loaded);
    require_function(Backend, "icon_destroy", fn (*Backend, Icon) void);
}

fn assert_tray(comptime Backend: type) void {
    require_function(Backend, "tray_activation_token", fn (*const Backend) []const u8);
    require_function(Backend, "tray_create", fn (*Backend, TrayCreateOptions) PlatformError!void);
    require_function(Backend, "tray_destroy", fn (*Backend) void);
    require_function(Backend, "tray_is_created", fn (*const Backend) bool);
    require_function(Backend, "tray_set_icon", fn (*Backend, Icon) PlatformError!void);
    require_function(Backend, "tray_set_tooltip", fn (*Backend, []const u8) PlatformError!void);
}

fn assert_menu(comptime Backend: type) void {
    require_function(Backend, "menu_build", fn (*Backend, []const MenuItem) PlatformError!void);
    require_function(Backend, "menu_destroy", fn (*Backend) void);
}

fn assert_notification(comptime Backend: type) void {
    require_function(Backend, "notification_send", fn (*Backend, Notification) PlatformError!void);
}

fn assert_paths(comptime Backend: type) void {
    const Located = (CapacityError || PlatformError)![]const u8;

    require_function(Backend, "paths_config_dir", fn (std.Io, []u8, []const u8) Located);
    require_function(Backend, "paths_state_dir", fn (std.Io, []u8, []const u8) Located);
}

fn assert_shell(comptime Backend: type) void {
    require_function(Backend, "shell_open", fn (*Backend, []const u8) PlatformError!void);
}

fn assert_timer(comptime Backend: type) void {
    require_function(Backend, "timer_start", fn (*Backend, Timer) PlatformError!void);
    require_function(Backend, "timer_stop", fn (*Backend, u32) bool);
    require_function(Backend, "timer_stop_all", fn (*Backend) void);
}

fn assert_watcher(comptime Backend: type) void {
    const Watched = (CapacityError || PlatformError)!Watch;
    const Watching = fn (*Backend, []const u8, Listener, *anyopaque) Watched;

    require_function(Backend, "watcher_watch", Watching);
    require_function(Backend, "watcher_unwatch", fn (*Backend, Watch) void);
    require_function(Backend, "watcher_stop_all", fn (*Backend) void);
}

fn assert_loop(comptime Backend: type) void {
    require_function(Backend, "loop_post", fn (*Backend, Event.Code) bool);
    require_function(Backend, "loop_quit", fn (*Backend) void);
    require_declaration(Backend, "loop_run");

    const Probe = struct {
        pub fn dispatch(_: *@This(), _: *const Event) void {}
    };

    const Check = struct {
        fn run(backend: *Backend, probe: *Probe) PlatformError!void {
            const Result = @TypeOf(backend.loop_run(Probe, probe));

            if (Result != (PlatformError!void)) {
                @compileError(
                    "umbra backend function loop_run returns " ++ @typeName(Result) ++
                        ", expected " ++ @typeName(PlatformError!void),
                );
            }

            return backend.loop_run(Probe, probe);
        }
    };

    _ = &Check.run;
}

fn require_declaration(comptime Backend: type, comptime name: []const u8) void {
    assert(name.len > 0);
    assert(@typeInfo(Backend) == .@"struct");

    if (!@hasDecl(Backend, name)) {
        @compileError("umbra backend " ++ @typeName(Backend) ++ " is missing '" ++ name ++ "'");
    }
}

fn require_function(
    comptime Backend: type,
    comptime name: []const u8,
    comptime Signature: type,
) void {
    assert(name.len > 0);
    assert(@typeInfo(Signature) == .@"fn");

    require_declaration(Backend, name);

    const Actual = @TypeOf(@field(Backend, name));

    if (Actual != Signature) {
        @compileError(
            "umbra backend function " ++ name ++ " has type " ++ @typeName(Actual) ++
                ", expected " ++ @typeName(Signature),
        );
    }
}

const testing = std.testing;

const layout_round_count: u32 = 4096;

fn has_parent(before: []const MenuItem, depth: u8) bool {
    assert(before.len < menu_item_count_max);
    assert(depth <= menu_depth_max);

    if (depth == 0) return true;

    var index = before.len;

    while (index > 0) {
        index -= 1;

        const candidate = &before[index];
        if (candidate.depth >= depth) continue;

        return candidate.kind == .submenu and candidate.depth + 1 == depth;
    }

    return false;
}

fn is_parented(items: []const MenuItem) bool {
    assert(items.len <= menu_item_count_max);

    for (items, 0..) |*item, index| {
        if (!item.is_valid()) return false;
        if (!has_parent(items[0..index], item.depth)) return false;
    }

    return true;
}

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

test "a menu item sits within the depth limit and a submenu one level above it" {
    const deepest = MenuItem{ .depth = menu_depth_max, .kind = .action, .label = "Leaf" };
    const beyond = MenuItem{ .depth = menu_depth_max + 1, .kind = .action, .label = "Leaf" };
    const opener = MenuItem{ .depth = menu_depth_max - 1, .kind = .submenu, .label = "More" };
    const bottomless = MenuItem{ .depth = menu_depth_max, .kind = .submenu, .label = "More" };

    try testing.expect(deepest.is_valid());
    try testing.expect(!beyond.is_valid());
    try testing.expect(opener.is_valid());
    try testing.expect(!bottomless.is_valid());
}

test is_valid_layout {
    const nested = [_]MenuItem{
        .{ .id = 1, .kind = .toggle, .label = "Dim" },
        .{ .id = 2, .kind = .submenu, .label = "Level" },
        .{ .depth = 1, .id = 3, .kind = .radio, .label = "10%" },
        .{ .depth = 1, .id = 4, .kind = .submenu, .label = "Finer" },
        .{ .depth = 2, .id = 5, .kind = .radio, .label = "15%" },
        .{ .id = 6, .kind = .action, .label = "Exit" },
    };

    const orphan = [_]MenuItem{
        .{ .id = 1, .kind = .action, .label = "Open" },
        .{ .depth = 1, .id = 2, .kind = .action, .label = "Child" },
    };

    const leap = [_]MenuItem{
        .{ .id = 1, .kind = .submenu, .label = "More" },
        .{ .depth = 2, .id = 2, .kind = .action, .label = "Grandchild" },
    };

    const sunken = [_]MenuItem{.{ .depth = 1, .id = 1, .kind = .action, .label = "Open" }};

    try testing.expect(is_valid_layout(&nested));
    try testing.expect(is_valid_layout(&.{}));
    try testing.expect(!is_valid_layout(&orphan));
    try testing.expect(!is_valid_layout(&leap));
    try testing.expect(!is_valid_layout(&sunken));
}

test "a layout is valid exactly when each nested item has a submenu one level above it" {
    var prng = std.Random.DefaultPrng.init(0x6e6573746564);
    const random = prng.random();
    var valid_count: u32 = 0;
    var round: u32 = 0;

    while (round < layout_round_count) : (round += 1) {
        var items: [8]MenuItem = undefined;
        const length = random.uintAtMost(usize, items.len);
        var depth: u8 = 0;

        for (items[0..length]) |*item| {
            const kind = random.enumValueWithIndex(MenuItemKind, u32);

            depth = random.uintAtMost(u8, @min(depth + 1, menu_depth_max));
            item.* = .{ .depth = depth, .id = 1, .kind = kind, .label = "Item" };
        }

        const expected = is_parented(items[0..length]);

        try testing.expectEqual(expected, is_valid_layout(items[0..length]));

        if (expected) valid_count += 1;
    }

    try testing.expect(valid_count > 0);
    try testing.expect(valid_count < layout_round_count);
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

test is_activation {
    var count: u32 = 0;

    for (std.enums.values(Event.Kind)) |kind| {
        if (is_activation(kind)) count += 1;
    }

    try testing.expectEqual(@as(u32, 4), count);
    try testing.expect(is_activation(.menu_select));
    try testing.expect(is_activation(.tray_left_click));
    try testing.expect(!is_activation(.menu_show));
    try testing.expect(!is_activation(.timer_tick));
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

test "a backend name is bounded by the application name" {
    const long: [app_name_bytes_max + 1]u8 = @splat('a');

    try testing.expect((Options{ .name = "umbra" }).is_valid());
    try testing.expect(!(Options{ .name = "" }).is_valid());
    try testing.expect(!(Options{ .name = &long }).is_valid());
    try testing.expect(!(Options{ .name = "\xC3\x28" }).is_valid());
}
