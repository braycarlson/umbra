const std = @import("std");

const w32 = @import("win32").everything;

const runtime = @import("../runtime/root.zig");
const win32 = @import("../win32/root.zig");

const Icon = win32.Icon;
const Service = runtime.Service;
const Tray = win32.Tray;
const TrayEvent = win32.TrayEvent;

pub const tooltip_max: u8 = 128;

pub const Error = error{
    BalloonFailed,
    CreationFailed,
    InvalidTooltip,
    NotBound,
    UpdateFailed,
};

pub const BalloonIcon = enum(u8) {
    err = 0,
    info = 1,
    none = 2,
    warning = 3,

    pub fn to_interface(self: BalloonIcon) win32.TrayBalloonIcon {
        const result = switch (self) {
            .err => win32.TrayBalloonIcon.err,
            .info => win32.TrayBalloonIcon.info,
            .none => win32.TrayBalloonIcon.none,
            .warning => win32.TrayBalloonIcon.warning,
        };

        return result;
    }
};

pub const Config = struct {
    id: u32 = 1,
    tooltip: []const u8,
};

pub const TrayManager = struct {
    hwnd: ?w32.HWND,
    id: u32,
    service: ?*Service,
    tooltip: [tooltip_max]u8,
    tooltip_len: u8,
    tray: ?Tray,

    pub fn init(config: Config) TrayManager {
        std.debug.assert(config.tooltip.len < tooltip_max);

        var result = TrayManager{
            .hwnd = null,
            .id = config.id,
            .service = null,
            .tooltip = [_]u8{0} ** tooltip_max,
            .tooltip_len = 0,
            .tray = null,
        };

        if (config.tooltip.len > 0 and config.tooltip.len < tooltip_max) {
            var index: u8 = 0;

            while (index < config.tooltip.len) : (index += 1) {
                std.debug.assert(index < tooltip_max);

                result.tooltip[index] = config.tooltip[index];
            }

            result.tooltip_len = @intCast(config.tooltip.len);
        }

        std.debug.assert(result.tray == null);

        return result;
    }

    pub fn deinit(self: *TrayManager) void {
        self.destroy();
        self.service = null;
        self.hwnd = null;

        std.debug.assert(self.tray == null);
    }

    pub fn bind(self: *TrayManager, service: *Service) void {
        self.service = service;

        std.debug.assert(self.service != null);
    }

    pub fn create(self: *TrayManager, hwnd: w32.HWND, icon: *const Icon) Error!void {
        self.hwnd = hwnd;

        self.tray = Tray.create(.{
            .hwnd = hwnd,
            .icon = icon.*,
            .id = self.id,
            .tooltip = self.tooltip[0..self.tooltip_len],
        }) catch {
            return Error.CreationFailed;
        };

        std.debug.assert(self.tray != null);
    }

    pub fn destroy(self: *TrayManager) void {
        if (self.tray) |tray| {
            tray.destroy() catch {};
            self.tray = null;
        }

        std.debug.assert(self.tray == null);
    }

    pub fn get_id(self: *const TrayManager) u32 {
        return self.id;
    }

    pub fn get_tooltip(self: *const TrayManager) []const u8 {
        std.debug.assert(self.tooltip_len <= tooltip_max);

        const result = self.tooltip[0..self.tooltip_len];

        return result;
    }

    pub fn handle_message(lparam: w32.LPARAM) ?TrayEvent {
        const result = TrayEvent.parse(lparam);

        return result;
    }

    pub fn hide_balloon(self: *TrayManager) Error!void {
        if (self.tray == null) {
            return Error.NotBound;
        }

        self.tray.?.hide_balloon() catch {
            return Error.BalloonFailed;
        };
    }

    pub fn is_created(self: *const TrayManager) bool {
        const result = self.tray != null;

        return result;
    }

    pub fn recreate(self: *TrayManager, icon: *const Icon) Error!void {
        if (self.hwnd == null) {
            return Error.NotBound;
        }

        self.destroy();

        try self.create(self.hwnd.?, icon);

        std.debug.assert(self.tray != null);
    }

    pub fn set_icon(self: *TrayManager, icon: *const Icon) Error!void {
        if (self.tray == null) {
            return Error.NotBound;
        }

        self.tray.?.set_icon(icon) catch {
            return Error.UpdateFailed;
        };
    }

    pub fn set_tooltip(self: *TrayManager, tooltip: []const u8) Error!void {
        std.debug.assert(tooltip.len < tooltip_max);

        if (tooltip.len == 0 or tooltip.len >= tooltip_max) {
            return Error.InvalidTooltip;
        }

        var index: u8 = 0;

        while (index < tooltip.len) : (index += 1) {
            std.debug.assert(index < tooltip_max);

            self.tooltip[index] = tooltip[index];
        }

        self.tooltip_len = @intCast(tooltip.len);

        if (self.tray) |tray| {
            tray.set_tooltip(self.tooltip[0..self.tooltip_len]) catch {
                return Error.UpdateFailed;
            };
        }
    }

    pub fn show_balloon(self: *TrayManager, title: []const u8, body: []const u8, icon: BalloonIcon) Error!void {
        std.debug.assert(title.len > 0);
        std.debug.assert(body.len > 0);

        if (self.tray == null) {
            return Error.NotBound;
        }

        self.tray.?.show_balloon(.{
            .body = body,
            .icon = icon.to_interface(),
            .title = title,
        }) catch {
            return Error.BalloonFailed;
        };
    }

    pub fn show_balloon_error(self: *TrayManager, title: []const u8, body: []const u8) Error!void {
        try self.show_balloon(title, body, .err);
    }

    pub fn show_balloon_info(self: *TrayManager, title: []const u8, body: []const u8) Error!void {
        try self.show_balloon(title, body, .info);
    }

    pub fn show_balloon_warning(self: *TrayManager, title: []const u8, body: []const u8) Error!void {
        try self.show_balloon(title, body, .warning);
    }

    pub fn show_balloon_with_icon(self: *TrayManager, title: []const u8, body: []const u8, custom_icon: *const Icon) Error!void {
        if (self.tray == null) {
            return Error.NotBound;
        }

        self.tray.?.show_balloon(.{
            .body = body,
            .custom_icon = custom_icon,
            .title = title,
        }) catch {
            return Error.BalloonFailed;
        };
    }
};
