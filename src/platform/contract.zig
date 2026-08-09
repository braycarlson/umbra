const std = @import("std");

const types = @import("../event/types.zig");

const assert = std.debug.assert;

const Event = types.Event;
const Response = types.Response;

pub const Capabilities = struct {
    balloon: bool,
    icon_resource: bool,
    taskbar_restart: bool,
    window_message: bool,
};

pub const capability_count: u8 = @typeInfo(Capabilities).@"struct".fields.len;

pub const pixmap_dimension_max: u32 = 256;
pub const pixmap_bytes_max: u32 = pixmap_dimension_max * pixmap_dimension_max * 4;
pub const channel_count: u32 = 4;
pub const path_bytes_max: u32 = 512;

pub const Stock = enum(u8) {
    application = 0,
    err = 1,
    information = 2,
    question = 3,
    shield = 4,
    warning = 5,

    pub fn is_valid(stock: Stock) bool {
        return @intFromEnum(stock) <= @intFromEnum(Stock.warning);
    }
};

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

    pub fn is_valid(pixmap: *const Pixmap) bool {
        if (pixmap.width == 0 or pixmap.width > pixmap_dimension_max) {
            return false;
        }

        if (pixmap.height == 0 or pixmap.height > pixmap_dimension_max) {
            return false;
        }

        return pixmap.argb.len == pixmap.byte_count();
    }
};

pub const IconSource = union(enum) {
    file_path: []const u8,
    pixels: Pixmap,
    resource: u32,
    stock: Stock,

    pub fn is_valid(source: *const IconSource) bool {
        const result = switch (source.*) {
            .file_path => |path| path.len > 0,
            .pixels => |pixmap| pixmap.is_valid(),
            .resource => |id| id > 0,
            .stock => |stock| stock.is_valid(),
        };

        return result;
    }
};

pub const MenuItemKind = enum(u8) {
    action = 0,
    radio = 1,
    separator = 2,
    toggle = 3,

    pub fn is_valid(kind: MenuItemKind) bool {
        return @intFromEnum(kind) <= @intFromEnum(MenuItemKind.toggle);
    }
};

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

        if (item.kind == .separator) {
            return true;
        }

        return item.label.len > 0;
    }
};

pub const NotificationKind = enum(u8) {
    err = 0,
    info = 1,
    none = 2,
    warning = 3,

    pub fn is_valid(kind: NotificationKind) bool {
        return @intFromEnum(kind) <= @intFromEnum(NotificationKind.warning);
    }
};

pub const NotificationOptions = struct {
    body: []const u8,
    kind: NotificationKind = .info,
    silent: bool = false,
    title: []const u8,

    pub fn is_valid(options: *const NotificationOptions) bool {
        return options.title.len > 0 and options.body.len > 0 and options.kind.is_valid();
    }
};

pub const RuntimeOptions = struct {
    name: []const u8,

    pub fn is_valid(options: *const RuntimeOptions) bool {
        return options.name.len > 0;
    }
};

pub const IconHandle = u32;

pub const TrayCreateOptions = struct {
    icon: ?IconHandle = null,
    id: u32 = 1,
    tooltip: []const u8 = "",
};

pub const WatchCallback = *const fn (?*anyopaque) void;

pub const BalloonError = error{
    HideFailed,
    InvalidBalloon,
    NotCreated,
    ShowFailed,
};

pub const IconError = error{
    CapacityExceeded,
    DuplicateName,
    InvalidName,
    InvalidSource,
    LoadFailed,
    NoSlotAvailable,
    NotFound,
    Unsupported,
};

pub const LoopError = error{
    AlreadyRunning,
    Failed,
    NotConnected,
};

pub const MenuError = error{
    BuildFailed,
    CapacityExceeded,
    InvalidItem,
    InvalidLabel,
    NotFound,
};

pub const NotificationError = error{
    InvalidNotification,
    SendFailed,
};

pub const PathError = error{
    NotFound,
    TooLong,
};

pub const RuntimeError = error{
    AlreadyOpen,
    InvalidOptions,
    OpenFailed,
};

pub const ShellError = error{
    InvalidPath,
    LaunchFailed,
};

pub const TimerError = error{
    CapacityExceeded,
    DuplicateId,
    InvalidInterval,
    NoSlotAvailable,
    NotFound,
    StartFailed,
};

pub const TrayError = error{
    AlreadyCreated,
    BalloonFailed,
    CreationFailed,
    InvalidTooltip,
    NotCreated,
    RuntimeClosed,
    UpdateFailed,
};

pub const WatcherError = error{
    CapacityExceeded,
    InvalidPath,
    WatchFailed,
};

comptime {
    assert(capability_count == 4);
    assert(pixmap_dimension_max > 0);
    assert(pixmap_bytes_max == pixmap_dimension_max * pixmap_dimension_max * channel_count);
    assert(channel_count == 4);
    assert(path_bytes_max >= 260);
    assert(@typeInfo(Stock).@"enum".fields.len == 6);
    assert(@typeInfo(MenuItemKind).@"enum".fields.len == 4);
    assert(@typeInfo(NotificationKind).@"enum".fields.len == 4);
    assert(@typeInfo(BalloonError).error_set.?.len == 4);
    assert(@typeInfo(IconError).error_set.?.len == 8);
    assert(@typeInfo(LoopError).error_set.?.len == 3);
    assert(@typeInfo(MenuError).error_set.?.len == 5);
    assert(@typeInfo(NotificationError).error_set.?.len == 2);
    assert(@typeInfo(PathError).error_set.?.len == 2);
    assert(@typeInfo(RuntimeError).error_set.?.len == 3);
    assert(@typeInfo(ShellError).error_set.?.len == 2);
    assert(@typeInfo(TimerError).error_set.?.len == 6);
    assert(@typeInfo(TrayError).error_set.?.len == 7);
    assert(@typeInfo(WatcherError).error_set.?.len == 3);
}

pub fn assert_backend(comptime backend: type) void {
    comptime {
        require_decl(backend, "capabilities", "backend");

        const capabilities: Capabilities = backend.capabilities;

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
        assert_balloon(backend, capabilities);
        assert_icon_resource(backend, capabilities);
        assert_taskbar(backend, capabilities);
        assert_window(backend, capabilities);
    }
}

fn assert_time(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "time", "backend");

    require_fn(scope, "now_ms", fn () u64, "time");
    require_fn(scope, "sleep_ms", fn (u32) void, "time");
}

fn assert_runtime(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "runtime", "backend");

    require_error_set(scope, "Error", RuntimeError, "runtime");
    require_type(scope, "Options", RuntimeOptions, "runtime");

    require_fn(scope, "open", fn (RuntimeOptions) RuntimeError!void, "runtime");
    require_fn(scope, "close", fn () void, "runtime");
    require_fn(scope, "is_open", fn () bool, "runtime");
}

fn assert_icon(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "icon", "backend");

    require_error_set(scope, "Error", IconError, "icon");
    require_type(scope, "Handle", IconHandle, "icon");
    require_type(scope, "Source", IconSource, "icon");

    require_fn(scope, "load", fn (IconSource) IconError!IconHandle, "icon");
    require_fn(scope, "destroy", fn (IconHandle) void, "icon");
}

fn assert_tray(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "tray", "backend");

    require_error_set(scope, "Error", TrayError, "tray");
    require_type(scope, "CreateOptions", TrayCreateOptions, "tray");

    require_fn(scope, "create", fn (TrayCreateOptions) TrayError!void, "tray");
    require_fn(scope, "destroy", fn () void, "tray");
    require_fn(scope, "is_created", fn () bool, "tray");
    require_fn(scope, "set_icon", fn (IconHandle) TrayError!void, "tray");
    require_fn(scope, "set_tooltip", fn ([]const u8) TrayError!void, "tray");
}

fn assert_menu(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "menu", "backend");

    require_error_set(scope, "Error", MenuError, "menu");
    require_type(scope, "Item", MenuItem, "menu");

    require_fn(scope, "build", fn ([]const MenuItem) MenuError!void, "menu");
    require_fn(scope, "destroy", fn () void, "menu");
}

fn assert_notification(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "notification", "backend");

    require_error_set(scope, "Error", NotificationError, "notification");
    require_type(scope, "Options", NotificationOptions, "notification");

    require_fn(scope, "send", fn (NotificationOptions) NotificationError!void, "notification");
}

fn assert_timer(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "timer", "backend");

    require_error_set(scope, "Error", TimerError, "timer");

    require_fn(scope, "start", fn (u32, u32) TimerError!void, "timer");
    require_fn(scope, "stop", fn (u32) bool, "timer");
    require_fn(scope, "stop_all", fn () void, "timer");
}

fn assert_watcher(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "watcher", "backend");

    require_error_set(scope, "Error", WatcherError, "watcher");
    require_decl(scope, "Handle", "watcher");
    require_type(scope, "Callback", WatchCallback, "watcher");

    require_fn(
        scope,
        "watch",
        fn ([]const u8, WatchCallback, ?*anyopaque) WatcherError!scope.Handle,
        "watcher",
    );

    require_fn(scope, "unwatch", fn (scope.Handle) void, "watcher");
    require_fn(scope, "stop_all", fn () void, "watcher");
}

fn assert_loop(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "loop", "backend");

    require_error_set(scope, "Error", LoopError, "loop");
    require_decl(scope, "LoopType", "loop");

    const Owner = struct {
        pub fn dispatch(_: *@This(), _: *const Event) Response {
            return .pass;
        }
    };

    const Instance = scope.LoopType(Owner);

    require_fn(Instance, "init", fn () Instance, "loop.LoopType");
    require_fn(Instance, "run", fn (*Instance, *Owner) LoopError!void, "loop.LoopType");
    require_fn(scope, "quit", fn () void, "loop");
    require_fn(scope, "post", fn (u32) bool, "loop");
}

fn assert_paths(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "paths", "backend");

    require_error_set(scope, "Error", PathError, "paths");

    require_fn(scope, "config_dir", fn ([]u8, []const u8) PathError![]const u8, "paths");
    require_fn(scope, "state_dir", fn ([]u8, []const u8) PathError![]const u8, "paths");
}

fn assert_shell(comptime backend: type) void {
    const scope = RequiredNamespaceType(backend, "shell", "backend");

    require_error_set(scope, "Error", ShellError, "shell");

    require_fn(scope, "open", fn ([]const u8) ShellError!void, "shell");
}

fn assert_balloon(comptime backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.balloon) {
        return;
    }

    const scope = RequiredNamespaceType(backend, "balloon", "backend");

    require_error_set(scope, "Error", BalloonError, "balloon");
    require_decl(scope, "Options", "balloon");

    require_fn(scope, "show", fn (scope.Options) BalloonError!void, "balloon");
    require_fn(scope, "hide", fn () BalloonError!void, "balloon");
}

fn assert_icon_resource(comptime backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.icon_resource) {
        return;
    }

    const scope = RequiredNamespaceType(backend, "icon", "backend");

    require_decl(scope, "supports_resource", "icon");

    const supported: bool = scope.supports_resource;

    if (!supported) {
        @compileError(
            "wisp backend claims the icon_resource capability but icon.supports_resource is false",
        );
    }
}

fn assert_taskbar(comptime backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.taskbar_restart) {
        return;
    }

    const scope = RequiredNamespaceType(backend, "taskbar", "backend");

    require_fn(scope, "restart_message", fn () u32, "taskbar");
    require_fn(scope, "is_restart", fn (u32) bool, "taskbar");
}

fn assert_window(comptime backend: type, comptime capabilities: Capabilities) void {
    if (!capabilities.window_message) {
        return;
    }

    const scope = RequiredNamespaceType(backend, "window", "backend");

    require_decl(scope, "Handle", "window");

    require_fn(scope, "handle", fn () ?scope.Handle, "window");
    require_fn(scope, "post", fn (u32, u64, i64) bool, "window");
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
            "wisp backend " ++ label ++ "." ++ name ++ " must be a namespace, found " ++
                @typeName(@TypeOf(Namespace)),
        );
    }

    return Namespace;
}

fn require_decl(comptime scope: type, comptime name: []const u8, comptime label: []const u8) void {
    if (!@hasDecl(scope, name)) {
        @compileError("wisp backend " ++ label ++ " is missing declaration '" ++ name ++ "'");
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
            "wisp backend " ++ label ++ "." ++ name ++ " has type " ++ @typeName(Actual) ++
                ", expected " ++ @typeName(Signature),
        );
    }
}

fn require_error_set(
    comptime scope: type,
    comptime name: []const u8,
    comptime Expected: type,
    comptime label: []const u8,
) void {
    require_decl(scope, name, label);

    const Actual = @field(scope, name);

    if (Actual != Expected) {
        @compileError(
            "wisp backend " ++ label ++ "." ++ name ++ " is " ++ @typeName(Actual) ++
                ", expected the canonical set " ++ @typeName(Expected),
        );
    }
}

fn require_type(
    comptime scope: type,
    comptime name: []const u8,
    comptime Expected: type,
    comptime label: []const u8,
) void {
    require_decl(scope, name, label);

    const Actual = @field(scope, name);

    if (Actual != Expected) {
        @compileError(
            "wisp backend " ++ label ++ "." ++ name ++ " is " ++ @typeName(Actual) ++
                ", expected " ++ @typeName(Expected),
        );
    }
}

const testing = std.testing;

test "Capabilities field count is fixed" {
    try testing.expectEqual(@as(u8, 4), capability_count);
}

test "Capabilities all false" {
    const capabilities = Capabilities{
        .balloon = false,
        .icon_resource = false,
        .taskbar_restart = false,
        .window_message = false,
    };

    try testing.expect(!capabilities.balloon);
    try testing.expect(!capabilities.icon_resource);
    try testing.expect(!capabilities.taskbar_restart);
    try testing.expect(!capabilities.window_message);
}

test "Capabilities all true" {
    const capabilities = Capabilities{
        .balloon = true,
        .icon_resource = true,
        .taskbar_restart = true,
        .window_message = true,
    };

    try testing.expect(capabilities.balloon);
    try testing.expect(capabilities.icon_resource);
    try testing.expect(capabilities.taskbar_restart);
    try testing.expect(capabilities.window_message);
}

test "Stock covers every documented variant" {
    try testing.expect(Stock.application.is_valid());
    try testing.expect(Stock.err.is_valid());
    try testing.expect(Stock.information.is_valid());
    try testing.expect(Stock.question.is_valid());
    try testing.expect(Stock.shield.is_valid());
    try testing.expect(Stock.warning.is_valid());
}

test "Pixmap accepts a correctly sized buffer" {
    const argb = [_]u8{0} ** (2 * 2 * channel_count);
    const pixmap = Pixmap.init(&argb, 2, 2);

    try testing.expect(pixmap.is_valid());
    try testing.expectEqual(@as(u64, 16), pixmap.byte_count());
}

test "Pixmap rejects a mismatched buffer" {
    const argb = [_]u8{0} ** 8;
    const pixmap = Pixmap{ .argb = &argb, .height = 2, .width = 2 };

    try testing.expect(!pixmap.is_valid());
}

test "Pixmap rejects dimensions beyond the maximum" {
    const argb = [_]u8{0} ** 4;
    const pixmap = Pixmap{ .argb = &argb, .height = 1, .width = pixmap_dimension_max + 1 };

    try testing.expect(!pixmap.is_valid());
}

test "IconSource validates each variant" {
    const argb = [_]u8{0} ** channel_count;

    try testing.expect((IconSource{ .file_path = "icon.png" }).is_valid());
    try testing.expect((IconSource{ .pixels = Pixmap.init(&argb, 1, 1) }).is_valid());
    try testing.expect((IconSource{ .resource = 1 }).is_valid());
    try testing.expect((IconSource{ .stock = .application }).is_valid());

    try testing.expect(!(IconSource{ .file_path = "" }).is_valid());
    try testing.expect(!(IconSource{ .resource = 0 }).is_valid());
}

test "MenuItem requires a label unless it is a separator" {
    try testing.expect((MenuItem{ .kind = .separator }).is_valid());
    try testing.expect((MenuItem{ .kind = .action, .label = "Quit" }).is_valid());
    try testing.expect(!(MenuItem{ .kind = .action, .label = "" }).is_valid());
}

test "NotificationOptions requires a title and a body" {
    try testing.expect((NotificationOptions{ .body = "b", .title = "t" }).is_valid());
    try testing.expect(!(NotificationOptions{ .body = "", .title = "t" }).is_valid());
    try testing.expect(!(NotificationOptions{ .body = "b", .title = "" }).is_valid());
}

test "RuntimeOptions requires a name" {
    try testing.expect((RuntimeOptions{ .name = "wisp" }).is_valid());
    try testing.expect(!(RuntimeOptions{ .name = "" }).is_valid());
}
