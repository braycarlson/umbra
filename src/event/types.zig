const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

pub const handler_max: u8 = 32;
pub const pending_max: u8 = 8;

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

    pub fn is_valid(kind: Kind) bool {
        const value = @backingInt(kind);

        return value < kind_count;
    }
};

pub const kind_count: u8 = @typeInfo(Kind).@"enum".field_names.len;

comptime {
    assert(kind_count == 13);
    assert(handler_max > 0);
    assert(pending_max > 0);
    assert(pending_max <= handler_max);
}

pub const Response = enum(u8) {
    pass = 0,
    handled = 1,
    quit = 2,

    pub fn should_quit(response: Response) bool {
        return response == .quit;
    }

    pub fn should_stop(response: Response) bool {
        return response == .handled or response == .quit;
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

pub const name_bytes_max: u32 = 256;

pub const Event = struct {
    payload: Payload,
    timestamp_ms: u64,

    pub fn create(payload: Payload) Event {
        const result = Event{
            .payload = payload,
            .timestamp_ms = platform.backend.time.now_ms(),
        };

        assert(result.kind().is_valid());

        return result;
    }

    pub fn kind(event: *const Event) Kind {
        const result = std.meta.activeTag(event.payload);

        assert(result.is_valid());

        return result;
    }

    pub fn app_init() Event {
        return Event.create(.{ .app_init = {} });
    }

    pub fn app_shutdown() Event {
        return Event.create(.{ .app_shutdown = {} });
    }

    pub fn custom(code: u32, data: ?*anyopaque) Event {
        const result = Event.create(.{
            .custom = CustomPayload{
                .code = code,
                .data = data,
            },
        });

        return result;
    }

    pub fn icon_change(name: []const u8) Event {
        assert(name.len > 0);
        assert(name.len < name_bytes_max);

        const result = Event.create(.{
            .icon_change = IconPayload{
                .name = name,
            },
        });

        return result;
    }

    pub fn menu_select(id: u32, checked: bool) Event {
        const result = Event.create(.{
            .menu_select = MenuPayload{
                .checked = checked,
                .id = id,
            },
        });

        return result;
    }

    pub fn menu_show() Event {
        return Event.create(.{ .menu_show = {} });
    }

    pub fn state_change(from: []const u8, to: []const u8) Event {
        assert(from.len < name_bytes_max);
        assert(to.len < name_bytes_max);

        const result = Event.create(.{
            .state_change = StatePayload{
                .from = from,
                .to = to,
            },
        });

        return result;
    }

    pub fn taskbar_restart() Event {
        return Event.create(.{ .taskbar_restart = {} });
    }

    pub fn timer_tick(id: u32, tick_count: u64) Event {
        const result = Event.create(.{
            .timer_tick = TimerPayload{
                .id = id,
                .tick_count = tick_count,
            },
        });

        return result;
    }

    pub fn tray_double_click() Event {
        return Event.create(.{ .tray_double_click = {} });
    }

    pub fn tray_left_click() Event {
        return Event.create(.{ .tray_left_click = {} });
    }

    pub fn tray_right_click() Event {
        return Event.create(.{ .tray_right_click = {} });
    }

    pub fn window_message(message: u32, wparam: u64, lparam: i64) Event {
        const result = Event.create(.{
            .window_message = MessagePayload{
                .lparam = lparam,
                .message = message,
                .wparam = wparam,
            },
        });

        return result;
    }
};

const testing = std.testing;

test "every defined event kind is valid" {
    const kinds = [_]Kind{
        .app_init,
        .app_shutdown,
        .custom,
        .icon_change,
        .menu_select,
        .menu_show,
        .state_change,
        .taskbar_restart,
        .timer_tick,
        .tray_double_click,
        .tray_left_click,
        .tray_right_click,
        .window_message,
    };

    try testing.expectEqual(@as(usize, kind_count), kinds.len);

    var index: u8 = 0;

    while (index < kinds.len) : (index += 1) {
        assert(index < kinds.len);

        const kind = kinds[index];
        const result = kind.is_valid();

        try testing.expect(result);
    }
}

test "only a quit response ends the loop" {
    try testing.expect(!Response.pass.should_quit());
    try testing.expect(!Response.handled.should_quit());
    try testing.expect(Response.quit.should_quit());
}

test "a handled or quit response stops further dispatch" {
    try testing.expect(!Response.pass.should_stop());
    try testing.expect(Response.handled.should_stop());
    try testing.expect(Response.quit.should_stop());
}

test "the app init constructor builds its event" {
    const event = Event.app_init();

    try testing.expectEqual(Kind.app_init, event.kind());
}

test "the app shutdown constructor builds its event" {
    const event = Event.app_shutdown();

    try testing.expectEqual(Kind.app_shutdown, event.kind());
}

test "a custom event carries its code and data" {
    const code: u32 = 42;
    const event = Event.custom(code, null);

    try testing.expectEqual(Kind.custom, event.kind());
    try testing.expectEqual(code, event.payload.custom.code);
    try testing.expectEqual(@as(?*anyopaque, null), event.payload.custom.data);
}

test "an icon change event carries the icon name" {
    const name = "test_icon";
    const event = Event.icon_change(name);

    try testing.expectEqual(Kind.icon_change, event.kind());
    try testing.expectEqualStrings(name, event.payload.icon_change.name);
}

test "a menu select event carries the id and the checked flag" {
    const id: u32 = 100;
    const checked = true;
    const event = Event.menu_select(id, checked);

    try testing.expectEqual(Kind.menu_select, event.kind());
    try testing.expectEqual(id, event.payload.menu_select.id);
    try testing.expectEqual(checked, event.payload.menu_select.checked);
}

test "the menu show constructor builds its event" {
    const event = Event.menu_show();

    try testing.expectEqual(Kind.menu_show, event.kind());
}

test "a state change event carries the old and new state" {
    const from = "idle";
    const to = "active";
    const event = Event.state_change(from, to);

    try testing.expectEqual(Kind.state_change, event.kind());
    try testing.expectEqualStrings(from, event.payload.state_change.from);
    try testing.expectEqualStrings(to, event.payload.state_change.to);
}

test "the taskbar restart constructor builds its event" {
    const event = Event.taskbar_restart();

    try testing.expectEqual(Kind.taskbar_restart, event.kind());
}

test "a timer tick event carries the id and the tick count" {
    const id: u32 = 1;
    const tick_count: u64 = 100;
    const event = Event.timer_tick(id, tick_count);

    try testing.expectEqual(Kind.timer_tick, event.kind());
    try testing.expectEqual(id, event.payload.timer_tick.id);
    try testing.expectEqual(tick_count, event.payload.timer_tick.tick_count);
}

test "the tray double click constructor builds its event" {
    const event = Event.tray_double_click();

    try testing.expectEqual(Kind.tray_double_click, event.kind());
}

test "the tray left click constructor builds its event" {
    const event = Event.tray_left_click();

    try testing.expectEqual(Kind.tray_left_click, event.kind());
}

test "the tray right click constructor builds its event" {
    const event = Event.tray_right_click();

    try testing.expectEqual(Kind.tray_right_click, event.kind());
}

test "a window message event carries its message parameters" {
    const message: u32 = 0x0010;
    const wparam: u64 = 1;
    const lparam: i64 = -1;
    const event = Event.window_message(message, wparam, lparam);

    try testing.expectEqual(Kind.window_message, event.kind());
    try testing.expectEqual(message, event.payload.window_message.message);
    try testing.expectEqual(wparam, event.payload.window_message.wparam);
    try testing.expectEqual(lparam, event.payload.window_message.lparam);
}

test "an event derives its kind from the payload" {
    const payload = Payload{ .app_init = {} };
    const event = Event.create(payload);

    try testing.expectEqual(Kind.app_init, event.kind());
}

test "Event timestamps never move backwards" {
    const first = Event.app_init();
    const second = Event.app_init();

    try testing.expect(second.timestamp_ms >= first.timestamp_ms);
}
