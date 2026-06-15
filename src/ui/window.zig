const std = @import("std");

const w32 = @import("win32").everything;

const runtime = @import("../runtime/root.zig");
const win32 = @import("../win32/root.zig");

const Service = runtime.Service;
const Window = win32.Window;

pub const name_max: u8 = 64;

pub const Error = error{
    CreationFailed,
    InvalidName,
};

pub const Config = struct {
    name: []const u8,
};

pub const MessageCallback = *const fn (hwnd: w32.HWND, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM, context: ?*anyopaque) ?w32.LRESULT;

pub const WindowManager = struct {
    instance: w32.HINSTANCE,
    message_context: ?*anyopaque,
    name: [name_max]u8,
    name_len: u8,
    name_wide: [name_max]u16,
    on_message: ?MessageCallback,
    service: ?*Service,
    window: ?Window,

    pub fn init(config: Config) WindowManager {
        std.debug.assert(config.name.len > 0);
        std.debug.assert(config.name.len < name_max);

        var result = WindowManager{
            .instance = @ptrCast(w32.GetModuleHandleW(null)),
            .message_context = null,
            .name = [_]u8{0} ** name_max,
            .name_len = 0,
            .name_wide = undefined,
            .on_message = null,
            .service = null,
            .window = null,
        };

        if (config.name.len > 0 and config.name.len < name_max) {
            var index: u8 = 0;

            while (index < config.name.len) : (index += 1) {
                std.debug.assert(index < name_max);

                result.name[index] = config.name[index];
            }

            result.name_len = @intCast(config.name.len);

            const length = std.unicode.utf8ToUtf16Le(&result.name_wide, config.name) catch 0;

            if (length < name_max) {
                result.name_wide[length] = 0;
            }
        }

        std.debug.assert(@intFromPtr(result.instance) != 0);
        std.debug.assert(result.window == null);

        return result;
    }

    pub fn deinit(self: *WindowManager) void {
        self.destroy();

        std.debug.assert(self.window == null);
    }

    pub fn bind(self: *WindowManager, service: *Service) void {
        self.service = service;

        std.debug.assert(self.service != null);
    }

    pub fn create(self: *WindowManager) Error!void {
        if (self.name_len == 0) {
            return Error.InvalidName;
        }

        const name_pointer: [*:0]const u16 = @ptrCast(&self.name_wide);
        const name_slice_len = std.mem.indexOfScalar(u16, &self.name_wide, 0) orelse 0;

        std.debug.assert(name_slice_len > 0);

        const config = win32.WindowConfig{
            .callback = window_callback,
            .context = self,
            .instance = self.instance,
            .name = name_pointer[0..name_slice_len :0],
        };

        self.window = Window.create(&config) catch {
            return Error.CreationFailed;
        };

        std.debug.assert(self.window != null);
    }

    pub fn destroy(self: *WindowManager) void {
        if (self.window) |window| {
            _ = window.destroy();
            self.window = null;
        }

        std.debug.assert(self.window == null);
    }

    pub fn get_handle(self: *const WindowManager) ?w32.HWND {
        if (self.window) |window| {
            return window.handle;
        }

        return null;
    }

    pub fn get_instance(self: *const WindowManager) w32.HINSTANCE {
        return self.instance;
    }

    pub fn get_taskbar_message(self: *const WindowManager) ?u32 {
        if (self.window) |window| {
            return window.msg_taskbar;
        }

        return null;
    }

    pub fn handle_message(self: *WindowManager, hwnd: w32.HWND, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) w32.LRESULT {
        if (self.on_message) |callback| {
            const result = callback(hwnd, message, wparam, lparam, self.message_context);

            if (result) |r| {
                return r;
            }
        }

        const result = w32.DefWindowProcW(hwnd, message, wparam, lparam);

        return result;
    }

    pub fn is_created(self: *const WindowManager) bool {
        const result = self.window != null;

        return result;
    }

    pub fn set_message_callback(self: *WindowManager, callback: MessageCallback, context: ?*anyopaque) void {
        self.on_message = callback;
        self.message_context = context;

        std.debug.assert(self.on_message != null);
    }
};

fn window_callback(hwnd: w32.HWND, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) callconv(.c) w32.LRESULT {
    const manager = Window.context(WindowManager, hwnd);

    if (manager) |m| {
        return m.handle_message(hwnd, message, wparam, lparam);
    }

    const result = w32.DefWindowProcW(hwnd, message, wparam, lparam);

    return result;
}
