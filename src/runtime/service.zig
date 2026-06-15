const std = @import("std");

const w32 = @import("win32").everything;

const event = @import("../event/root.zig");

const Bus = event.Bus;

pub const Service = struct {
    bus: *Bus,
    hwnd: ?w32.HWND,
    instance: w32.HINSTANCE,

    pub fn init(event_bus: *Bus) Service {
        const result = Service{
            .bus = event_bus,
            .hwnd = null,
            .instance = @ptrCast(w32.GetModuleHandleW(null)),
        };

        std.debug.assert(@intFromPtr(result.instance) != 0);
        std.debug.assert(result.hwnd == null);

        return result;
    }

    pub fn bind_window(self: *Service, hwnd: w32.HWND, instance: w32.HINSTANCE) void {
        self.hwnd = hwnd;
        self.instance = instance;

        std.debug.assert(self.hwnd != null);
    }

    pub fn is_bound(self: *const Service) bool {
        const result = self.hwnd != null;

        return result;
    }
};
