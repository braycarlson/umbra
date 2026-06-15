const std = @import("std");

const w32 = @import("win32").everything;

const icon_mod = @import("icon.zig");
const text = @import("text.zig");

pub const info_max: u32 = 256;
pub const message: u32 = w32.WM_APP + 1;
pub const title_max: u32 = 64;
pub const tooltip_max: u32 = 128;

const event_select: u32 = 0x0400;
const event_key_select: u32 = 0x0401;
const event_balloon_show: u32 = 0x0402;
const event_balloon_hide: u32 = 0x0403;
const event_balloon_timeout: u32 = 0x0404;
const event_balloon_click: u32 = 0x0405;
const event_popup_open: u32 = 0x0406;
const event_popup_close: u32 = 0x0407;

const balloon_icon_error: u32 = 0x00000003;
const balloon_icon_info: u32 = 0x00000001;
const balloon_icon_none: u32 = 0x00000000;
const balloon_icon_user: u32 = 0x00000004;
const balloon_icon_warning: u32 = 0x00000002;
const balloon_flag_silent: u32 = 0x00000010;
const balloon_flag_large_icon: u32 = 0x00000020;
const balloon_flag_realtime: u32 = 0x00000040;
const balloon_flag_respect_quiet: u32 = 0x00000080;

const icon_state_hidden: u32 = 0x00000001;
const icon_state_shared: u32 = 0x00000002;
const icon_state_mask: u32 = 0x00000003;

const lparam_low_mask: w32.LPARAM = 0xFFFF;

pub const Event = enum(u8) {
    balloon_click = 0,
    balloon_hide = 1,
    balloon_show = 2,
    balloon_timeout = 3,
    context_menu = 4,
    key_select = 5,
    left_button_down = 6,
    left_click = 7,
    left_double_click = 8,
    middle_button_down = 9,
    middle_button_up = 10,
    middle_double_click = 11,
    mouse_move = 12,
    popup_close = 13,
    popup_open = 14,
    right_button_down = 15,
    right_click = 16,
    right_double_click = 17,
    select = 18,

    pub fn is_click(self: Event) bool {
        const result = switch (self) {
            .left_click, .middle_button_up, .right_click => true,
            else => false,
        };

        return result;
    }

    pub fn is_double_click(self: Event) bool {
        const result = switch (self) {
            .left_double_click, .middle_double_click, .right_double_click => true,
            else => false,
        };

        return result;
    }

    pub fn parse(lparam: w32.LPARAM) ?Event {
        const low = @as(u32, @intCast(lparam & lparam_low_mask));

        const result: ?Event = switch (low) {
            w32.WM_LBUTTONDOWN => .left_button_down,
            w32.WM_LBUTTONUP => .left_click,
            w32.WM_LBUTTONDBLCLK => .left_double_click,
            w32.WM_RBUTTONDOWN => .right_button_down,
            w32.WM_RBUTTONUP => .right_click,
            w32.WM_RBUTTONDBLCLK => .right_double_click,
            w32.WM_MBUTTONDOWN => .middle_button_down,
            w32.WM_MBUTTONUP => .middle_button_up,
            w32.WM_MBUTTONDBLCLK => .middle_double_click,
            w32.WM_MOUSEMOVE => .mouse_move,
            w32.WM_CONTEXTMENU => .context_menu,
            event_select => .select,
            event_key_select => .key_select,
            event_balloon_show => .balloon_show,
            event_balloon_hide => .balloon_hide,
            event_balloon_timeout => .balloon_timeout,
            event_balloon_click => .balloon_click,
            event_popup_open => .popup_open,
            event_popup_close => .popup_close,
            else => null,
        };

        return result;
    }
};

pub const BalloonIcon = enum(u8) {
    err = 0,
    info = 1,
    none = 2,
    user = 3,
    warning = 4,

    pub fn to_flag(self: BalloonIcon) u32 {
        const result = switch (self) {
            .err => balloon_icon_error,
            .info => balloon_icon_info,
            .none => balloon_icon_none,
            .user => balloon_icon_user,
            .warning => balloon_icon_warning,
        };

        return result;
    }
};

pub const IconState = struct {
    hidden: bool = false,
    shared_icon: bool = false,

    pub fn to_uint(self: IconState) u32 {
        var result: u32 = 0;

        if (self.hidden) result |= icon_state_hidden;
        if (self.shared_icon) result |= icon_state_shared;

        return result;
    }
};

pub const Error = error{
    CreationFailed,
    DeleteFailed,
    GetRectFailed,
    InvalidBody,
    InvalidTitle,
    InvalidTooltip,
    ModifyFailed,
    SetFocusFailed,
    SetVersionFailed,
};

pub const CreateOptions = struct {
    callback_message: u32 = message,
    hwnd: w32.HWND,
    icon: ?icon_mod.Icon = null,
    id: u32 = 1,
    state: IconState = .{},
    tooltip: []const u8 = "",
    version: u32 = 4,
};

pub const ModifyOptions = struct {
    callback_message: ?u32 = null,
    icon: ?*const icon_mod.Icon = null,
    state: ?IconState = null,
    tooltip: ?[]const u8 = null,
};

pub const BalloonOptions = struct {
    body: []const u8 = "",
    custom_icon: ?*const icon_mod.Icon = null,
    icon: BalloonIcon = .info,
    large_icon: bool = false,
    realtime: bool = false,
    respect_quiet: bool = true,
    silent: bool = false,
    timeout_ms: u32 = 0,
    title: []const u8 = "",
    tray_icon: ?*const icon_mod.Icon = null,
};

pub const Tray = struct {
    hwnd: w32.HWND,
    id: u32,

    pub fn create(options: CreateOptions) Error!Tray {
        std.debug.assert(options.tooltip.len < tooltip_max);

        if (options.tooltip.len >= tooltip_max) {
            return Error.InvalidTooltip;
        }

        var data = base_data(options.hwnd, options.id);

        data.uFlags = .{ .MESSAGE = 1, .SHOWTIP = 1, .TIP = 1 };
        data.uCallbackMessage = options.callback_message;

        if (options.icon) |icon| {
            data.uFlags.ICON = 1;
            data.hIcon = icon.handle;
        }

        if (options.tooltip.len > 0) {
            text.copy_wide(&data.szTip, options.tooltip);
        }

        if (options.state.hidden or options.state.shared_icon) {
            data.uFlags.STATE = 1;
            data.dwState = options.state.to_uint();
            data.dwStateMask = icon_state_mask;
        }

        const status = w32.Shell_NotifyIconW(w32.NIM_ADD, &data);

        if (status == 0) {
            return Error.CreationFailed;
        }

        var version_data = base_data(options.hwnd, options.id);

        version_data.Anonymous.uVersion = options.version;

        const version_status = w32.Shell_NotifyIconW(w32.NIM_SETVERSION, &version_data);

        if (version_status == 0) {
            _ = w32.Shell_NotifyIconW(w32.NIM_DELETE, &data);

            return Error.SetVersionFailed;
        }

        const result = Tray{
            .hwnd = options.hwnd,
            .id = options.id,
        };

        std.debug.assert(result.hwnd == options.hwnd);
        std.debug.assert(result.id == options.id);

        return result;
    }

    pub fn destroy(self: *const Tray) Error!void {
        var data = base_data(self.hwnd, self.id);

        const status = w32.Shell_NotifyIconW(w32.NIM_DELETE, &data);

        if (status == 0) {
            return Error.DeleteFailed;
        }
    }

    pub fn get_rect(self: *const Tray) Error!w32.RECT {
        var identifier: w32.NOTIFYICONIDENTIFIER = undefined;

        identifier.cbSize = @sizeOf(w32.NOTIFYICONIDENTIFIER);
        identifier.hWnd = self.hwnd;
        identifier.uID = self.id;
        identifier.guidItem = std.mem.zeroes(@TypeOf(identifier.guidItem));

        var rect: w32.RECT = undefined;

        const hr = w32.Shell_NotifyIconGetRect(&identifier, &rect);

        if (hr != w32.S_OK) {
            return Error.GetRectFailed;
        }

        return rect;
    }

    pub fn hide_balloon(self: *const Tray) Error!void {
        var data = base_data(self.hwnd, self.id);

        data.uFlags.INFO = 1;
        data.szInfo[0] = 0;
        data.szInfoTitle[0] = 0;

        const status = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);

        if (status == 0) {
            return Error.ModifyFailed;
        }
    }

    pub fn is_visible(self: *const Tray) bool {
        const rect = self.get_rect() catch return false;
        const result = rect.right > rect.left and rect.bottom > rect.top;

        return result;
    }

    pub fn modify(self: *const Tray, options: ModifyOptions) Error!void {
        var data = base_data(self.hwnd, self.id);

        if (options.icon) |icon| {
            data.uFlags.ICON = 1;
            data.hIcon = icon.handle;
        }

        if (options.tooltip) |tooltip| {
            std.debug.assert(tooltip.len < tooltip_max);

            if (tooltip.len >= tooltip_max) {
                return Error.InvalidTooltip;
            }

            data.uFlags.TIP = 1;
            text.copy_wide(&data.szTip, tooltip);
        }

        if (options.state) |state| {
            data.uFlags.STATE = 1;
            data.dwState = state.to_uint();
            data.dwStateMask = icon_state_mask;
        }

        if (options.callback_message) |callback_message| {
            data.uFlags.MESSAGE = 1;
            data.uCallbackMessage = callback_message;
        }

        const status = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);

        if (status == 0) {
            return Error.ModifyFailed;
        }
    }

    pub fn set_focus(self: *const Tray) Error!void {
        var data = base_data(self.hwnd, self.id);

        const status = w32.Shell_NotifyIconW(w32.NIM_SETFOCUS, &data);

        if (status == 0) {
            return Error.SetFocusFailed;
        }
    }

    pub fn set_hidden(self: *const Tray, hidden: bool) Error!void {
        return self.set_state(IconState{ .hidden = hidden });
    }

    pub fn set_icon(self: *const Tray, icon: *const icon_mod.Icon) Error!void {
        return self.modify(ModifyOptions{ .icon = icon });
    }

    pub fn set_state(self: *const Tray, state: IconState) Error!void {
        return self.modify(ModifyOptions{ .state = state });
    }

    pub fn set_tooltip(self: *const Tray, tooltip: []const u8) Error!void {
        std.debug.assert(tooltip.len < tooltip_max);

        return self.modify(ModifyOptions{ .tooltip = tooltip });
    }

    pub fn show_balloon(self: *const Tray, options: BalloonOptions) Error!void {
        std.debug.assert(options.title.len < title_max);
        std.debug.assert(options.body.len < info_max);

        if (options.title.len >= title_max) {
            return Error.InvalidTitle;
        }

        if (options.body.len >= info_max) {
            return Error.InvalidBody;
        }

        var data = base_data(self.hwnd, self.id);

        data.uFlags.INFO = 1;
        data.dwInfoFlags = options.icon.to_flag();

        if (options.tray_icon) |tray_icon| {
            data.uFlags.ICON = 1;
            data.hIcon = tray_icon.handle;
        }

        if (options.silent) {
            data.dwInfoFlags |= balloon_flag_silent;
        }

        if (options.large_icon) {
            data.dwInfoFlags |= balloon_flag_large_icon;
        }

        if (options.realtime) {
            data.dwInfoFlags |= balloon_flag_realtime;
        }

        if (options.respect_quiet) {
            data.dwInfoFlags |= balloon_flag_respect_quiet;
        }

        if (options.custom_icon) |custom| {
            data.dwInfoFlags = balloon_icon_user | balloon_flag_large_icon;
            data.hBalloonIcon = custom.handle;
        }

        if (options.timeout_ms > 0) {
            data.Anonymous.uTimeout = options.timeout_ms;
        }

        text.copy_wide(&data.szInfoTitle, options.title);
        text.copy_wide(&data.szInfo, options.body);

        const status = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);

        if (status == 0) {
            return Error.ModifyFailed;
        }
    }
};

fn base_data(hwnd: w32.HWND, id: u32) w32.NOTIFYICONDATAW {
    var data = std.mem.zeroes(w32.NOTIFYICONDATAW);

    data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
    data.hWnd = hwnd;
    data.uID = id;

    return data;
}
