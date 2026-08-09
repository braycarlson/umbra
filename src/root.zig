const platform = @import("platform.zig");

pub const app = @import("app.zig");
pub const builder = @import("builder.zig");
pub const event = @import("event/root.zig");
pub const runtime = @import("runtime/root.zig");
pub const ui = @import("ui/root.zig");

pub const App = app.App;
pub const AppConfig = app.Config;
pub const AppError = app.Error;

pub const IconBuilder = builder.IconBuilder;
pub const MenuBuilder = builder.MenuBuilder;

pub const Bus = event.Bus;
pub const Event = event.Event;
pub const Kind = event.Kind;
pub const Response = event.Response;
pub const Handler = event.Handler;
pub const HandlerFn = event.HandlerFn;
pub const Subscription = event.Subscription;
pub const Payload = event.Payload;
pub const MessagePayload = event.MessagePayload;

pub const Lifecycle = runtime.Lifecycle;
pub const Stage = runtime.Stage;

pub const IconManager = ui.IconManager;
pub const IconHandle = ui.IconHandle;
pub const IconPixmap = ui.IconPixmap;
pub const IconSource = ui.IconSource;
pub const IconStock = ui.IconStock;
pub const IconError = ui.IconError;

pub const MenuManager = ui.MenuManager;
pub const MenuItem = ui.MenuItem;
pub const MenuItemKind = ui.MenuItemKind;
pub const MenuError = ui.MenuError;

pub const NotificationManager = ui.NotificationManager;
pub const Notification = ui.Notification;
pub const NotificationIcon = ui.NotificationIcon;
pub const NotificationError = ui.NotificationError;

pub const StateManager = ui.StateManager;
pub const StateTransition = ui.StateTransition;
pub const StateError = ui.StateError;

pub const TimerManager = ui.TimerManager;
pub const TimerHandle = ui.TimerHandle;
pub const TimerError = ui.TimerError;

pub const TrayManager = ui.TrayManager;
pub const TrayConfig = ui.TrayConfig;
pub const TrayError = ui.TrayError;
pub const TrayBalloonIcon = ui.TrayBalloonIcon;

pub const Capabilities = platform.Capabilities;
pub const capabilities = platform.capabilities;

pub const mock = platform.mock;

pub const loop = struct {
    pub fn quit() void {
        platform.backend.loop.quit();
    }

    pub fn post(code: u32) bool {
        return platform.backend.loop.post(code);
    }
};

pub const paths = struct {
    pub const Error = platform.backend.paths.Error;

    pub fn config_dir(buffer: []u8, name: []const u8) Error![]const u8 {
        return try platform.backend.paths.config_dir(buffer, name);
    }

    pub fn state_dir(buffer: []u8, name: []const u8) Error![]const u8 {
        return try platform.backend.paths.state_dir(buffer, name);
    }
};

pub const shell = struct {
    pub const Error = platform.backend.shell.Error;

    pub fn open(path: []const u8) Error!void {
        try platform.backend.shell.open(path);
    }
};

pub const time = struct {
    pub fn now_ms() u64 {
        return platform.backend.time.now_ms();
    }

    pub fn sleep_ms(duration_ms: u32) void {
        platform.backend.time.sleep_ms(duration_ms);
    }
};

pub const watcher = struct {
    pub const Callback = platform.WatchCallback;
    pub const Error = platform.backend.watcher.Error;
    pub const Handle = platform.backend.watcher.Handle;

    pub fn watch(target: []const u8, callback: Callback, context: ?*anyopaque) Error!Handle {
        return try platform.backend.watcher.watch(target, callback, context);
    }

    pub fn unwatch(handle: Handle) void {
        platform.backend.watcher.unwatch(handle);
    }
};

pub const balloon = if (platform.capabilities.balloon) struct {
    pub const Error = platform.backend.balloon.Error;
    pub const Options = platform.backend.balloon.Options;

    pub fn show(options: Options) Error!void {
        try platform.backend.balloon.show(options);
    }

    pub fn hide() Error!void {
        try platform.backend.balloon.hide();
    }
} else unavailable("balloon", "balloon");

pub const icon_resource = if (platform.capabilities.icon_resource)
    make_icon_resource
else
    unavailable("icon_resource", "icon_resource");

pub const taskbar = if (platform.capabilities.taskbar_restart) struct {
    pub fn restart_message() u32 {
        return platform.backend.taskbar.restart_message();
    }

    pub fn is_restart(message: u32) bool {
        return platform.backend.taskbar.is_restart(message);
    }
} else unavailable("taskbar", "taskbar_restart");

pub const window = if (platform.capabilities.window_message) struct {
    pub const Handle = platform.backend.window.Handle;

    pub fn handle() ?Handle {
        return platform.backend.window.handle();
    }

    pub fn post(message: u32, wparam: u64, lparam: i64) bool {
        return platform.backend.window.post(message, wparam, lparam);
    }
} else unavailable("window", "window_message");

fn make_icon_resource(id: u32) IconSource {
    return IconSource{ .resource = id };
}

fn unavailable(comptime feature: []const u8, comptime capability: []const u8) noreturn {
    @compileError("wisp: " ++ feature ++ " requires the " ++ capability ++
        " capability, which this backend does not provide");
}
