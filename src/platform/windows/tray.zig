const std = @import("std");

const w32 = @import("win32.zig");

const contract = @import("../contract.zig");
const icon_mod = @import("icon.zig");
const window = @import("window.zig");

const assert = std.debug.assert;

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

pub const Notification = enum(u8) {
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

    pub fn is_click(notification: Notification) bool {
        const result = switch (notification) {
            .left_click, .middle_button_up, .right_click => true,
            else => false,
        };

        return result;
    }

    pub fn is_double_click(notification: Notification) bool {
        const result = switch (notification) {
            .left_double_click, .middle_double_click, .right_double_click => true,
            else => false,
        };

        return result;
    }

    pub fn parse(lparam: w32.LPARAM) ?Notification {
        const low = @as(u32, @intCast(lparam & lparam_low_mask));

        const result: ?Notification = switch (low) {
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

    pub fn to_flag(icon: BalloonIcon) u32 {
        const result = switch (icon) {
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

    pub fn to_uint(state: IconState) u32 {
        var result: u32 = 0;

        if (state.hidden) result |= icon_state_hidden;
        if (state.shared_icon) result |= icon_state_shared;

        return result;
    }
};

pub const Error = contract.TrayError;

pub const NativeError = error{
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

pub const NotifyOptions = struct {
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

    pub fn open(options: NotifyOptions) NativeError!Tray {
        assert(options.tooltip.len < tooltip_max);

        if (options.tooltip.len >= tooltip_max) {
            return NativeError.InvalidTooltip;
        }

        var data = base_data(options.hwnd, options.id);

        data.uFlags = w32.NIF_MESSAGE | w32.NIF_SHOWTIP | w32.NIF_TIP;
        data.uCallbackMessage = options.callback_message;

        if (options.icon) |icon| {
            data.uFlags |= w32.NIF_ICON;
            data.hIcon = icon.handle;
        }

        if (options.tooltip.len > 0 and !copy_wide(&data.szTip, options.tooltip)) {
            return NativeError.InvalidTooltip;
        }

        if (options.state.hidden or options.state.shared_icon) {
            data.uFlags |= w32.NIF_STATE;
            data.dwState = options.state.to_uint();
            data.dwStateMask = icon_state_mask;
        }

        const status = w32.Shell_NotifyIconW(w32.NIM_ADD, &data);

        if (status == 0) {
            return NativeError.CreationFailed;
        }

        var version_data = base_data(options.hwnd, options.id);

        version_data.uVersionOrTimeout = options.version;

        const version_status = w32.Shell_NotifyIconW(w32.NIM_SETVERSION, &version_data);

        if (version_status == 0) {
            _ = w32.Shell_NotifyIconW(w32.NIM_DELETE, &data);

            return NativeError.SetVersionFailed;
        }

        const result = Tray{
            .hwnd = options.hwnd,
            .id = options.id,
        };

        assert(result.hwnd == options.hwnd);
        assert(result.id == options.id);

        return result;
    }

    pub fn destroy(tray: *const Tray) NativeError!void {
        var data = base_data(tray.hwnd, tray.id);

        const status = w32.Shell_NotifyIconW(w32.NIM_DELETE, &data);

        if (status == 0) {
            return NativeError.DeleteFailed;
        }
    }

    pub fn get_rect(tray: *const Tray) NativeError!w32.RECT {
        var identifier: w32.NOTIFYICONIDENTIFIER = undefined;

        identifier.cbSize = @sizeOf(w32.NOTIFYICONIDENTIFIER);
        identifier.hWnd = tray.hwnd;
        identifier.uID = tray.id;
        identifier.guidItem = std.mem.zeroes(@TypeOf(identifier.guidItem));

        var rect: w32.RECT = undefined;

        const hr = w32.Shell_NotifyIconGetRect(&identifier, &rect);

        if (hr != w32.S_OK) {
            return NativeError.GetRectFailed;
        }

        return rect;
    }

    pub fn hide_balloon(tray: *const Tray) NativeError!void {
        var data = base_data(tray.hwnd, tray.id);

        data.uFlags |= w32.NIF_INFO;
        data.szInfo[0] = 0;
        data.szInfoTitle[0] = 0;

        const status = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);

        if (status == 0) {
            return NativeError.ModifyFailed;
        }
    }

    pub fn is_visible(tray: *const Tray) bool {
        const rect = tray.get_rect() catch return false;

        return rect.right > rect.left and rect.bottom > rect.top;
    }

    pub fn modify(tray: *const Tray, options: ModifyOptions) NativeError!void {
        var data = base_data(tray.hwnd, tray.id);

        if (options.icon) |icon| {
            data.uFlags |= w32.NIF_ICON;
            data.hIcon = icon.handle;
        }

        if (options.tooltip) |tooltip| {
            assert(tooltip.len < tooltip_max);

            if (tooltip.len >= tooltip_max) {
                return NativeError.InvalidTooltip;
            }

            data.uFlags |= w32.NIF_TIP;

            if (!copy_wide(&data.szTip, tooltip)) {
                return NativeError.InvalidTooltip;
            }
        }

        if (options.state) |state| {
            data.uFlags |= w32.NIF_STATE;
            data.dwState = state.to_uint();
            data.dwStateMask = icon_state_mask;
        }

        if (options.callback_message) |callback_message| {
            data.uFlags |= w32.NIF_MESSAGE;
            data.uCallbackMessage = callback_message;
        }

        const status = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);

        if (status == 0) {
            return NativeError.ModifyFailed;
        }
    }

    pub fn set_focus(tray: *const Tray) NativeError!void {
        var data = base_data(tray.hwnd, tray.id);

        const status = w32.Shell_NotifyIconW(w32.NIM_SETFOCUS, &data);

        if (status == 0) {
            return NativeError.SetFocusFailed;
        }
    }

    pub fn set_hidden(tray: *const Tray, hidden: bool) NativeError!void {
        return tray.set_state(IconState{ .hidden = hidden });
    }

    pub fn set_icon(tray: *const Tray, icon: *const icon_mod.Icon) NativeError!void {
        return tray.modify(ModifyOptions{ .icon = icon });
    }

    pub fn set_state(tray: *const Tray, state: IconState) NativeError!void {
        return tray.modify(ModifyOptions{ .state = state });
    }

    pub fn set_tooltip(tray: *const Tray, tooltip: []const u8) NativeError!void {
        assert(tooltip.len < tooltip_max);

        return tray.modify(ModifyOptions{ .tooltip = tooltip });
    }

    pub fn show_balloon(tray: *const Tray, options: BalloonOptions) NativeError!void {
        assert(options.title.len < title_max);
        assert(options.body.len < info_max);

        if (options.title.len >= title_max) {
            return NativeError.InvalidTitle;
        }

        if (options.body.len >= info_max) {
            return NativeError.InvalidBody;
        }

        var data = base_data(tray.hwnd, tray.id);

        data.uFlags |= w32.NIF_INFO;
        data.dwInfoFlags = options.icon.to_flag();

        if (options.tray_icon) |tray_icon| {
            data.uFlags |= w32.NIF_ICON;
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
            data.uVersionOrTimeout = options.timeout_ms;
        }

        if (!copy_wide(&data.szInfoTitle, options.title)) {
            return NativeError.InvalidTitle;
        }

        if (!copy_wide(&data.szInfo, options.body)) {
            return NativeError.InvalidBody;
        }

        const status = w32.Shell_NotifyIconW(w32.NIM_MODIFY, &data);

        if (status == 0) {
            return NativeError.ModifyFailed;
        }
    }
};

fn copy_wide(destination: []u16, source: []const u8) bool {
    assert(destination.len > 0);
    assert(source.len < destination.len);

    if (source.len >= destination.len) {
        return false;
    }

    const length = std.unicode.utf8ToUtf16Le(destination[0..source.len], source) catch {
        return false;
    };

    assert(length <= source.len);

    destination[length] = 0;

    return true;
}

pub const CreateOptions = contract.TrayCreateOptions;

var current: ?Tray = null;

pub fn create(options: CreateOptions) Error!void {
    if (options.tooltip.len >= tooltip_max) {
        return Error.InvalidTooltip;
    }

    if (current != null) {
        return Error.AlreadyCreated;
    }

    const target = window.handle() orelse return Error.RuntimeClosed;
    const icon = if (options.icon) |handle| icon_mod.get(handle) else null;

    current = Tray.open(.{
        .hwnd = target,
        .icon = icon,
        .id = options.id,
        .tooltip = options.tooltip,
    }) catch |err| {
        return translate(err);
    };

    assert(current != null);
}

pub fn destroy() void {
    const handle = current orelse return;

    current = null;

    handle.destroy() catch {
        return;
    };
}

pub fn is_created() bool {
    return current != null;
}

pub fn set_icon(handle: icon_mod.Handle) Error!void {
    const live = current orelse return Error.NotCreated;
    const icon = icon_mod.get(handle) orelse return Error.UpdateFailed;

    live.set_icon(&icon) catch |err| {
        return translate(err);
    };
}

pub fn set_tooltip(tooltip: []const u8) Error!void {
    const live = current orelse return Error.NotCreated;

    if (tooltip.len >= tooltip_max) {
        return Error.InvalidTooltip;
    }

    live.set_tooltip(tooltip) catch |err| {
        return translate(err);
    };
}

pub fn active() ?Tray {
    return current;
}

fn translate(err: NativeError) Error {
    const result = switch (err) {
        NativeError.InvalidTooltip => Error.InvalidTooltip,
        NativeError.CreationFailed, NativeError.SetVersionFailed => Error.CreationFailed,
        NativeError.DeleteFailed,
        NativeError.GetRectFailed,
        NativeError.InvalidBody,
        NativeError.InvalidTitle,
        NativeError.ModifyFailed,
        NativeError.SetFocusFailed,
        => Error.UpdateFailed,
    };

    return result;
}

fn base_data(hwnd: w32.HWND, id: u32) w32.NOTIFYICONDATAW {
    var data = std.mem.zeroes(w32.NOTIFYICONDATAW);

    data.cbSize = @sizeOf(w32.NOTIFYICONDATAW);
    data.hWnd = hwnd;
    data.uID = id;

    return data;
}

const testing = std.testing;

test "a click notification reports as a click" {
    try testing.expect(Notification.left_click.is_click());
    try testing.expect(Notification.middle_button_up.is_click());
    try testing.expect(Notification.right_click.is_click());
}

test "a notification that is not a click reports so" {
    try testing.expect(!Notification.mouse_move.is_click());
    try testing.expect(!Notification.left_button_down.is_click());
    try testing.expect(!Notification.balloon_click.is_click());
}

test "a double click notification reports as one" {
    try testing.expect(Notification.left_double_click.is_double_click());
    try testing.expect(Notification.middle_double_click.is_double_click());
    try testing.expect(Notification.right_double_click.is_double_click());
}

test "a single click is not a double click" {
    try testing.expect(!Notification.left_click.is_double_click());
    try testing.expect(!Notification.right_click.is_double_click());
}

test "a left button release parses as a left click" {
    const result = Notification.parse(0x0202);

    try testing.expect(result != null);
    try testing.expectEqual(Notification.left_click, result.?);
}

test "a right button release parses as a right click" {
    const result = Notification.parse(0x0205);

    try testing.expect(result != null);
    try testing.expectEqual(Notification.right_click, result.?);
}

test "a left button double click parses as one" {
    const result = Notification.parse(0x0203);

    try testing.expect(result != null);
    try testing.expectEqual(Notification.left_double_click, result.?);
}

test "a mouse move message parses as a move" {
    const result = Notification.parse(0x0200);

    try testing.expect(result != null);
    try testing.expectEqual(Notification.mouse_move, result.?);
}

test "a context menu message parses as a context menu" {
    const result = Notification.parse(0x007B);

    try testing.expect(result != null);
    try testing.expectEqual(Notification.context_menu, result.?);
}

test "an unknown message parses to nothing" {
    const result = Notification.parse(0xFFFF);

    try testing.expect(result == null);
}

test "a balloon icon maps to its flag" {
    try testing.expectEqual(@as(u32, 0x00000003), BalloonIcon.err.to_flag());
    try testing.expectEqual(@as(u32, 0x00000001), BalloonIcon.info.to_flag());
    try testing.expectEqual(@as(u32, 0x00000000), BalloonIcon.none.to_flag());
    try testing.expectEqual(@as(u32, 0x00000004), BalloonIcon.user.to_flag());
    try testing.expectEqual(@as(u32, 0x00000002), BalloonIcon.warning.to_flag());
}

test "a default icon state converts to no bits" {
    const state = IconState{};

    try testing.expectEqual(@as(u32, 0), state.to_uint());
}

test "an icon state carries its hidden flag" {
    const state = IconState{ .hidden = true };

    try testing.expectEqual(@as(u32, 0x00000001), state.to_uint());
}

test "an icon state carries its shared icon flag" {
    const state = IconState{ .shared_icon = true };

    try testing.expectEqual(@as(u32, 0x00000002), state.to_uint());
}

test "an icon state combines several flags" {
    const state = IconState{ .hidden = true, .shared_icon = true };

    try testing.expectEqual(@as(u32, 0x00000003), state.to_uint());
}

test "BalloonOptions defaults" {
    const options = BalloonOptions{};

    try testing.expectEqualStrings("", options.body);
    try testing.expectEqualStrings("", options.title);
    try testing.expectEqual(BalloonIcon.info, options.icon);
    try testing.expect(!options.large_icon);
    try testing.expect(!options.realtime);
    try testing.expect(options.respect_quiet);
    try testing.expect(!options.silent);
    try testing.expectEqual(@as(u32, 0), options.timeout_ms);
}

test "BalloonOptions custom values" {
    const options = BalloonOptions{
        .body = "Test body",
        .title = "Test title",
        .icon = .warning,
        .silent = true,
        .timeout_ms = 5000,
    };

    try testing.expectEqualStrings("Test body", options.body);
    try testing.expectEqualStrings("Test title", options.title);
    try testing.expectEqual(BalloonIcon.warning, options.icon);
    try testing.expect(options.silent);
    try testing.expectEqual(@as(u32, 5000), options.timeout_ms);
}

test "ModifyOptions defaults to null" {
    const options = ModifyOptions{};

    try testing.expect(options.callback_message == null);
    try testing.expect(options.icon == null);
    try testing.expect(options.state == null);
    try testing.expect(options.tooltip == null);
}

test "ModifyOptions with tooltip" {
    const options = ModifyOptions{
        .tooltip = "New tooltip",
    };

    try testing.expect(options.tooltip != null);
    try testing.expectEqualStrings("New tooltip", options.tooltip.?);
}

test "NotifyOptions defaults" {
    const options = NotifyOptions{
        .hwnd = @ptrFromInt(0x12345678),
    };

    try testing.expectEqual(@as(u32, message), options.callback_message);
    try testing.expectEqual(@as(u32, 1), options.id);
    try testing.expectEqual(@as(u32, 4), options.version);
    try testing.expectEqualStrings("", options.tooltip);
}

test "message constant is WM_APP + 1" {
    try testing.expectEqual(@as(u32, 0x8001), message);
}

test "create requires an open window" {
    if (is_created()) {
        return;
    }

    try testing.expectError(Error.RuntimeClosed, create(.{}));
}

test "set_icon and set_tooltip require a created tray" {
    if (is_created()) {
        return;
    }

    try testing.expectError(Error.NotCreated, set_icon(0));
    try testing.expectError(Error.NotCreated, set_tooltip("x"));
}

test "translate maps every native failure" {
    try testing.expectEqual(Error.InvalidTooltip, translate(NativeError.InvalidTooltip));
    try testing.expectEqual(Error.CreationFailed, translate(NativeError.CreationFailed));
    try testing.expectEqual(Error.CreationFailed, translate(NativeError.SetVersionFailed));
    try testing.expectEqual(Error.UpdateFailed, translate(NativeError.ModifyFailed));
    try testing.expectEqual(Error.UpdateFailed, translate(NativeError.DeleteFailed));

    assert(@typeInfo(NativeError).error_set.error_names.?.len == 9);
}
