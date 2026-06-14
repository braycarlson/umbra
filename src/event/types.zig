const std = @import("std");

const w32 = @import("win32").everything;

pub const handler_max: u8 = 32;
pub const kind_max: u8 = 12;

pub const Kind = enum(u8) {
    app_init = 0,
    app_shutdown = 1,
    custom = 2,
    icon_change = 3,
    menu_select = 4,
    menu_show = 5,
    state_change = 6,
    taskbar_restart = 7,
    timer_tick = 8,
    tray_double_click = 9,
    tray_left_click = 10,
    tray_right_click = 11,
    window_message = 12,

    pub fn is_valid(self: Kind) bool {
        const value = @intFromEnum(self);

        std.debug.assert(value <= 255);

        const result = value <= kind_max;

        return result;
    }
};

pub const Response = enum(u8) {
    pass = 0,
    handled = 1,
    quit = 2,

    pub fn should_quit(self: Response) bool {
        const value = @intFromEnum(self);

        std.debug.assert(value <= 2);

        const result = self == .quit;

        return result;
    }

    pub fn should_stop(self: Response) bool {
        const value = @intFromEnum(self);

        std.debug.assert(value <= 2);

        const result = self == .handled or self == .quit;

        return result;
    }
};

pub const CustomPayload = struct {
    code: u32,
    data: ?*anyopaque,
};

pub const IconPayload = struct {
    name: []const u8,
};

pub const MenuPayload = struct {
    checked: bool,
    id: u32,
};

pub const MessagePayload = struct {
    lparam: i64,
    message: u32,
    wparam: u64,
};

pub const StatePayload = struct {
    from: []const u8,
    to: []const u8,
};

pub const TimerPayload = struct {
    id: u32,
    tick_count: u64,
};

pub const Payload = union(Kind) {
    app_init: void,
    app_shutdown: void,
    custom: CustomPayload,
    icon_change: IconPayload,
    menu_select: MenuPayload,
    menu_show: void,
    state_change: StatePayload,
    taskbar_restart: void,
    timer_tick: TimerPayload,
    tray_double_click: void,
    tray_left_click: void,
    tray_right_click: void,
    window_message: MessagePayload,
};

pub const Event = struct {
    kind: Kind,
    payload: Payload,
    timestamp_ms: i64,

    pub fn create(kind: Kind, payload: Payload) Event {
        std.debug.assert(kind.is_valid());
        std.debug.assert(@intFromEnum(kind) == @as(u8, @intFromEnum(payload)));

        const result = Event{
            .kind = kind,
            .payload = payload,
            .timestamp_ms = @intCast(w32.GetTickCount64()),
        };

        std.debug.assert(result.kind == kind);
        std.debug.assert(result.timestamp_ms != 0);

        return result;
    }

    pub fn app_init() Event {
        const result = Event.create(.app_init, .{ .app_init = {} });

        std.debug.assert(result.kind == .app_init);

        return result;
    }

    pub fn app_shutdown() Event {
        const result = Event.create(.app_shutdown, .{ .app_shutdown = {} });

        std.debug.assert(result.kind == .app_shutdown);

        return result;
    }

    pub fn custom(code: u32, data: ?*anyopaque) Event {
        std.debug.assert(code <= 0xFFFFFFFF);

        const result = Event.create(.custom, .{
            .custom = CustomPayload{
                .code = code,
                .data = data,
            },
        });

        std.debug.assert(result.kind == .custom);

        return result;
    }

    pub fn icon_change(name: []const u8) Event {
        std.debug.assert(name.len > 0);
        std.debug.assert(name.len < 256);

        const result = Event.create(.icon_change, .{
            .icon_change = IconPayload{
                .name = name,
            },
        });

        std.debug.assert(result.kind == .icon_change);

        return result;
    }

    pub fn menu_select(id: u32, checked: bool) Event {
        std.debug.assert(id <= 0xFFFFFFFF);

        const result = Event.create(.menu_select, .{
            .menu_select = MenuPayload{
                .checked = checked,
                .id = id,
            },
        });

        std.debug.assert(result.kind == .menu_select);

        return result;
    }

    pub fn menu_show() Event {
        const result = Event.create(.menu_show, .{ .menu_show = {} });

        std.debug.assert(result.kind == .menu_show);

        return result;
    }

    pub fn state_change(from: []const u8, to: []const u8) Event {
        std.debug.assert(from.len < 256);
        std.debug.assert(to.len < 256);

        const result = Event.create(.state_change, .{
            .state_change = StatePayload{
                .from = from,
                .to = to,
            },
        });

        std.debug.assert(result.kind == .state_change);

        return result;
    }

    pub fn taskbar_restart() Event {
        const result = Event.create(.taskbar_restart, .{ .taskbar_restart = {} });

        std.debug.assert(result.kind == .taskbar_restart);

        return result;
    }

    pub fn timer_tick(id: u32, tick_count: u64) Event {
        std.debug.assert(id <= 0xFFFFFFFF);

        const result = Event.create(.timer_tick, .{
            .timer_tick = TimerPayload{
                .id = id,
                .tick_count = tick_count,
            },
        });

        std.debug.assert(result.kind == .timer_tick);

        return result;
    }

    pub fn tray_double_click() Event {
        const result = Event.create(.tray_double_click, .{ .tray_double_click = {} });

        std.debug.assert(result.kind == .tray_double_click);

        return result;
    }

    pub fn tray_left_click() Event {
        const result = Event.create(.tray_left_click, .{ .tray_left_click = {} });

        std.debug.assert(result.kind == .tray_left_click);

        return result;
    }

    pub fn tray_right_click() Event {
        const result = Event.create(.tray_right_click, .{ .tray_right_click = {} });

        std.debug.assert(result.kind == .tray_right_click);

        return result;
    }

    pub fn window_message(message: u32, wparam: u64, lparam: i64) Event {
        std.debug.assert(message <= 0xFFFFFFFF);

        const result = Event.create(.window_message, .{
            .window_message = MessagePayload{
                .lparam = lparam,
                .message = message,
                .wparam = wparam,
            },
        });

        std.debug.assert(result.kind == .window_message);

        return result;
    }
};
