const std = @import("std");

const w32 = @import("win32").everything;

const runtime = @import("../runtime/root.zig");

const Service = runtime.Service;

pub const body_max: u16 = 256;
pub const title_max: u16 = 64;

pub const Error = error{
    InvalidNotification,
    NotBound,
    SendFailed,
};

pub const Icon = enum(u8) {
    err = 0,
    info = 1,
    none = 2,
    warning = 3,

    pub fn to_flag(self: Icon) u32 {
        return switch (self) {
            .err => 0x00000003,
            .info => 0x00000001,
            .none => 0x00000000,
            .warning => 0x00000002,
        };
    }
};

pub const Notification = struct {
    body: [body_max]u8,
    body_len: u16,
    icon: Icon,
    silent: bool,
    title: [title_max]u8,
    title_len: u16,

    pub fn init(title: []const u8, body: []const u8) Notification {
        std.debug.assert(title.len > 0);
        std.debug.assert(title.len < title_max);
        std.debug.assert(body.len > 0);
        std.debug.assert(body.len < body_max);

        var result = Notification{
            .body = [_]u8{0} ** body_max,
            .body_len = 0,
            .icon = .info,
            .silent = false,
            .title = [_]u8{0} ** title_max,
            .title_len = 0,
        };

        result.set_title(title);
        result.set_body(body);

        std.debug.assert(result.title_len > 0);
        std.debug.assert(result.body_len > 0);

        return result;
    }

    pub fn err(title: []const u8, body: []const u8) Notification {
        var result = Notification.init(title, body);

        result.icon = .err;

        std.debug.assert(result.icon == .err);

        return result;
    }

    pub fn info(title: []const u8, body: []const u8) Notification {
        var result = Notification.init(title, body);

        result.icon = .info;

        std.debug.assert(result.icon == .info);

        return result;
    }

    pub fn warning(title: []const u8, body: []const u8) Notification {
        var result = Notification.init(title, body);

        result.icon = .warning;

        std.debug.assert(result.icon == .warning);

        return result;
    }

    pub fn get_body(self: *const Notification) []const u8 {
        std.debug.assert(self.body_len <= body_max);

        const result = self.body[0..self.body_len];

        return result;
    }

    pub fn get_title(self: *const Notification) []const u8 {
        std.debug.assert(self.title_len <= title_max);

        const result = self.title[0..self.title_len];

        return result;
    }

    pub fn is_valid(self: *const Notification) bool {
        const result = self.title_len > 0 and self.body_len > 0;

        return result;
    }

    pub fn set_body(self: *Notification, body: []const u8) void {
        if (body.len == 0 or body.len >= body_max) {
            return;
        }

        var index: u16 = 0;

        while (index < body.len) : (index += 1) {
            std.debug.assert(index < body_max);

            self.body[index] = body[index];
        }

        self.body_len = @intCast(body.len);

        std.debug.assert(self.body_len == body.len);
    }

    pub fn set_title(self: *Notification, title: []const u8) void {
        if (title.len == 0 or title.len >= title_max) {
            return;
        }

        var index: u16 = 0;

        while (index < title.len) : (index += 1) {
            std.debug.assert(index < title_max);

            self.title[index] = title[index];
        }

        self.title_len = @intCast(title.len);

        std.debug.assert(self.title_len == title.len);
    }

    pub fn with_icon(self: Notification, icon_type: Icon) Notification {
        var result = self;

        result.icon = icon_type;

        return result;
    }

    pub fn with_silent(self: Notification, silent: bool) Notification {
        var result = self;

        result.silent = silent;

        return result;
    }
};

pub const NotificationManager = struct {
    hwnd: ?w32.HWND,
    service: ?*Service,
    tray_id: u32,

    pub fn init() NotificationManager {
        const result = NotificationManager{
            .hwnd = null,
            .service = null,
            .tray_id = 1,
        };

        std.debug.assert(result.hwnd == null);

        return result;
    }

    pub fn deinit(self: *NotificationManager) void {
        self.hwnd = null;
        self.service = null;
    }

    pub fn bind(self: *NotificationManager, hwnd: w32.HWND, tray_id: u32) void {
        self.hwnd = hwnd;
        self.tray_id = tray_id;

        std.debug.assert(self.hwnd != null);
    }

    pub fn bind_service(self: *NotificationManager, service: *Service) void {
        self.service = service;

        std.debug.assert(self.service != null);
    }

    pub fn is_bound(self: *const NotificationManager) bool {
        const result = self.hwnd != null;

        return result;
    }

    pub fn send(self: *const NotificationManager, notification: *const Notification) Error!void {
        if (self.hwnd == null) {
            return Error.NotBound;
        }

        if (!notification.is_valid()) {
            return Error.InvalidNotification;
        }

        var data = std.mem.zeroes(w32.NOTIFYICONDATAW);

        data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
        data.hWnd = self.hwnd.?;
        data.uID = self.tray_id;
        data.uFlags = .{ .INFO = 1 };
        data.dwInfoFlags = notification.icon.to_flag();

        if (notification.silent) {
            data.dwInfoFlags |= 0x00000010;
        }

        copy_utf8_to_wide(&data.szInfoTitle, notification.get_title());
        copy_utf8_to_wide(&data.szInfo, notification.get_body());

        const status = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);

        if (status == 0) {
            return Error.SendFailed;
        }
    }

    pub fn send_error(self: *const NotificationManager, title: []const u8, body: []const u8) Error!void {
        std.debug.assert(title.len > 0);
        std.debug.assert(body.len > 0);

        const notification = Notification.err(title, body);

        try self.send(&notification);
    }

    pub fn send_simple(self: *const NotificationManager, title: []const u8, body: []const u8) Error!void {
        std.debug.assert(title.len > 0);
        std.debug.assert(body.len > 0);

        const notification = Notification.info(title, body);

        try self.send(&notification);
    }

    pub fn send_warning(self: *const NotificationManager, title: []const u8, body: []const u8) Error!void {
        std.debug.assert(title.len > 0);
        std.debug.assert(body.len > 0);

        const notification = Notification.warning(title, body);

        try self.send(&notification);
    }
};

fn copy_utf8_to_wide(buffer: anytype, source: []const u8) void {
    std.debug.assert(buffer.len > 0);

    if (source.len == 0) {
        buffer[0] = 0;

        return;
    }

    const buffer_len: u64 = buffer.len;
    const limit = @min(source.len, buffer_len - 1);

    var index: u64 = 0;

    while (index < limit) : (index += 1) {
        std.debug.assert(index < buffer_len);

        buffer[index] = @as(u16, source[index]);
    }

    buffer[index] = 0;
}
