const std = @import("std");

const w32 = @import("win32").everything;

const event = @import("event/root.zig");
const runtime = @import("runtime/root.zig");
const ui = @import("ui/root.zig");
const win32 = @import("win32/root.zig");

const Bus = event.Bus;
const Event = event.Event;
const Lifecycle = runtime.Lifecycle;
const Response = event.Response;
const Service = runtime.Service;

const IconManager = ui.IconManager;
const MenuManager = ui.MenuManager;
const NotificationManager = ui.NotificationManager;
const StateManager = ui.StateManager;
const TimerManager = ui.TimerManager;
const TrayManager = ui.TrayManager;

const Icon = win32.Icon;
const Tray = win32.Tray;
const TrayEvent = win32.TrayEvent;
const Window = win32.Window;

pub const name_max: u8 = 64;

pub const Error = error{
    AlreadyRunning,
    IconLoadFailed,
    InvalidState,
    TrayCreationFailed,
    WindowCreationFailed,
};

pub const Config = struct {
    initial_state: []const u8 = "",
    name: []const u8,
    tooltip: []const u8 = "",
};

pub const App = struct {
    bus: Bus,
    config: Config,
    icon: IconManager,
    lifecycle: Lifecycle,
    menu: MenuManager,
    name_wide: [name_max]u16,
    notification: NotificationManager,
    service: Service,
    state: StateManager,
    timer: TimerManager,
    tray: TrayManager,
    window: ?Window,

    pub fn init(self: *App, config: Config) void {
        std.debug.assert(config.name.len > 0);
        std.debug.assert(config.name.len < name_max);

        const tooltip = if (config.tooltip.len > 0) config.tooltip else config.name;

        self.* = App{
            .bus = Bus.init(),
            .config = config,
            .icon = IconManager.init(),
            .lifecycle = Lifecycle.init(),
            .menu = MenuManager.init(),
            .name_wide = undefined,
            .notification = NotificationManager.init(),
            .service = undefined,
            .state = StateManager.init(),
            .timer = TimerManager.init(),
            .tray = TrayManager.init(.{ .tooltip = tooltip }),
            .window = null,
        };

        self.service = Service.init(&self.bus);

        const length = std.unicode.utf8ToUtf16Le(&self.name_wide, config.name) catch 0;

        if (length < name_max) {
            self.name_wide[length] = 0;
        }

        if (config.initial_state.len > 0) {
            std.debug.assert(config.initial_state.len < ui.state.state_max);

            self.state.set(config.initial_state) catch unreachable;
        }

        std.debug.assert(self.lifecycle.stage == .created);
    }

    pub fn deinit(self: *App) void {
        self.timer.deinit();
        self.menu.deinit();
        self.tray.deinit();
        self.icon.deinit();

        if (self.window) |window| {
            _ = window.destroy();
            self.window = null;
        }

        self.bus.deinit();
        self.state.deinit();
        self.notification.deinit();

        self.lifecycle.force_stop();

        std.debug.assert(self.window == null);
        std.debug.assert(self.lifecycle.stage == .stopped);
    }

    pub fn configure(self: *App) *App {
        _ = self.lifecycle.transition(.configured);

        std.debug.assert(self.lifecycle.stage == .configured);

        return self;
    }

    pub fn event_bus(self: *App) *Bus {
        return &self.bus;
    }

    pub fn get_hwnd(self: *const App) ?w32.HWND {
        if (self.window) |window| {
            return window.handle;
        }

        return null;
    }

    pub fn get_icon(self: *App) *IconManager {
        return &self.icon;
    }

    pub fn get_instance(self: *const App) w32.HINSTANCE {
        return self.service.instance;
    }

    pub fn get_menu(self: *App) *MenuManager {
        return &self.menu;
    }

    pub fn get_notification(self: *App) *NotificationManager {
        return &self.notification;
    }

    pub fn get_state(self: *App) *StateManager {
        return &self.state;
    }

    pub fn get_timer(self: *App) *TimerManager {
        return &self.timer;
    }

    pub fn get_tray(self: *App) *TrayManager {
        return &self.tray;
    }

    pub fn is_running(self: *const App) bool {
        const result = self.lifecycle.is_running();

        return result;
    }

    pub fn post_message(self: *const App, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) bool {
        if (self.window) |window| {
            const result = window.post(message, wparam, lparam);

            return result;
        }

        return false;
    }

    pub fn quit(self: *App) void {
        win32.Loop.quit();

        _ = self.lifecycle.transition(.stopping);
    }

    pub fn run(self: *App) Error!void {
        if (self.lifecycle.stage != .configured) {
            return Error.InvalidState;
        }

        bind_services(self);

        const name_pointer: [*:0]const u16 = @ptrCast(&self.name_wide);
        const name_slice_len = std.mem.indexOfScalar(u16, &self.name_wide, 0) orelse 0;

        std.debug.assert(name_slice_len > 0);

        const window_config = win32.WindowConfig{
            .callback = @ptrCast(&window_callback),
            .context = self,
            .instance = self.service.instance,
            .name = name_pointer[0..name_slice_len :0],
        };

        self.window = Window.create(&window_config) catch {
            return Error.WindowCreationFailed;
        };

        std.debug.assert(self.window != null);

        const hwnd = self.window.?.handle;

        self.service.bind_window(hwnd, self.service.instance);

        if (!self.icon.load(self.service.instance)) {
            return Error.IconLoadFailed;
        }

        const current_icon = self.icon.get_current() orelse {
            return Error.IconLoadFailed;
        };

        self.tray.create(hwnd, current_icon) catch {
            return Error.TrayCreationFailed;
        };

        self.timer.bind(hwnd);
        self.notification.bind(hwnd, self.tray.get_id());

        _ = self.lifecycle.transition(.running);

        std.debug.assert(self.lifecycle.is_running());

        const init_event = Event.app_init();

        _ = self.bus.emit(&init_event);

        win32.Loop.run();

        _ = self.lifecycle.transition(.stopping);

        const shutdown_event = Event.app_shutdown();

        _ = self.bus.emit(&shutdown_event);
    }
};

fn bind_services(app: *App) void {
    app.service.bus = &app.bus;

    app.icon.bind(&app.service);
    app.menu.bind(&app.service);
    app.notification.bind_service(&app.service);
    app.state.bind(&app.service);
    app.timer.bind_service(&app.service);
    app.tray.bind(&app.service);
}

fn handle_message(app: *App, hwnd: w32.HWND, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) w32.LRESULT {
    if (app.window) |window| {
        if (message == window.msg_taskbar) {
            handle_taskbar_restart(app);

            return 0;
        }
    }

    if (message == win32.tray.message) {
        handle_tray_message(app, hwnd, lparam);

        return 0;
    }

    switch (message) {
        w32.WM_TIMER => {
            const timer_id: u32 = @intCast(wparam);

            app.timer.handle_tick(timer_id);

            const tick = app.timer.get_tick_count(timer_id);
            const e = Event.timer_tick(timer_id, tick);
            const response = app.bus.emit(&e);

            if (response.should_quit()) {
                app.quit();
            }

            return 0;
        },
        w32.WM_DESTROY => {
            win32.Loop.quit();

            return 0;
        },
        else => {
            const e = Event.window_message(message, wparam, lparam);
            const response = app.bus.emit(&e);

            if (response == .handled) {
                return 0;
            }

            if (response.should_quit()) {
                app.quit();

                return 0;
            }
        },
    }

    const result = w32.DefWindowProcW(hwnd, message, wparam, lparam);

    return result;
}

fn handle_taskbar_restart(app: *App) void {
    const current_icon = app.icon.get_current() orelse return;

    app.tray.recreate(current_icon) catch return;

    const e = Event.taskbar_restart();
    _ = app.bus.emit(&e);
}

fn handle_tray_message(app: *App, hwnd: w32.HWND, lparam: w32.LPARAM) void {
    const tray_event = TrayEvent.parse(lparam) orelse return;

    switch (tray_event) {
        .left_click => {
            const e = Event.tray_left_click();
            const response = app.bus.emit(&e);

            if (response.should_quit()) {
                app.quit();
            }
        },
        .left_double_click => {
            const e = Event.tray_double_click();
            const response = app.bus.emit(&e);

            if (response.should_quit()) {
                app.quit();
            }
        },
        .context_menu => {
            show_context_menu(app, hwnd);
        },
        .right_click => {
            const e = Event.tray_right_click();
            const response = app.bus.emit(&e);

            if (response.should_quit()) {
                app.quit();
            }
        },
        .balloon_click,
        .balloon_hide,
        .balloon_show,
        .balloon_timeout,
        .key_select,
        .left_button_down,
        .middle_button_down,
        .middle_button_up,
        .middle_double_click,
        .mouse_move,
        .popup_close,
        .popup_open,
        .right_button_down,
        .right_double_click,
        .select,
        => {},
    }
}

fn show_context_menu(app: *App, hwnd: w32.HWND) void {
    const show_ev = Event.menu_show();

    _ = app.bus.emit(&show_ev);

    const result = app.menu.show(hwnd);

    if (result) |id| {
        const item = app.menu.get_item(id);
        var checked = false;

        if (item) |it| {
            checked = it.checked;
        }

        const menu_ev = Event.menu_select(id, checked);
        const menu_response = app.bus.emit(&menu_ev);

        if (menu_response.should_quit()) {
            app.quit();
        }
    }
}

fn window_callback(hwnd: w32.HWND, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.c) w32.LRESULT {
    const app_pointer = Window.context(App, hwnd);

    if (app_pointer) |app| {
        return handle_message(app, hwnd, message, wparam, lparam);
    }

    const result = w32.DefWindowProcW(hwnd, message, wparam, lparam);

    return result;
}
