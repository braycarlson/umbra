const std = @import("std");

const platform = @import("platform.zig");

const assert = std.debug.assert;

pub const Event = struct {
    payload: Payload,
    timestamp_ms: u64,

    pub const Kind = enum(u8) {
        app_init = 0,
        app_shutdown = 1,
        custom = 2,
        menu_select = 3,
        menu_show = 4,
        taskbar_restart = 5,
        timer_tick = 6,
        tray_double_click = 7,
        tray_left_click = 8,
        tray_right_click = 9,

        pub fn is_valid(tag: Kind) bool {
            return @backingInt(tag) < kind_count;
        }
    };

    pub const Payload = union(Kind) {
        app_init: void,
        app_shutdown: void,
        custom: Custom,
        menu_select: Selection,
        menu_show: void,
        taskbar_restart: void,
        timer_tick: Tick,
        tray_double_click: void,
        tray_left_click: void,
        tray_right_click: void,
    };

    pub const Custom = struct {
        code: u32,
    };

    pub const Selection = struct {
        checked: bool,
        id: u32,
    };

    pub const Tick = struct {
        id: u32,
        tick_count: u64,
    };

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
};

pub const kind_count: u8 = @typeInfo(Event.Kind).@"enum".field_names.len;

comptime {
    assert(kind_count == 10);
}

const testing = std.testing;

test Event {
    const selected = Event.create(.{ .menu_select = .{ .checked = true, .id = 7 } });

    try testing.expectEqual(Event.Kind.menu_select, selected.kind());
    try testing.expectEqual(@as(u32, 7), selected.payload.menu_select.id);
    try testing.expect(selected.payload.menu_select.checked);

    const posted = Event.create(.{ .custom = .{ .code = 42 } });

    try testing.expectEqual(@as(u32, 42), posted.payload.custom.code);
}

test "every defined event kind is valid" {
    for (std.enums.values(Event.Kind)) |value| {
        try testing.expect(value.is_valid());
    }

    try testing.expectEqual(@as(usize, kind_count), std.enums.values(Event.Kind).len);
}

test "an event derives its kind from the payload" {
    const ticked = Event.create(.{ .timer_tick = .{ .id = 1, .tick_count = 100 } });

    try testing.expectEqual(Event.Kind.timer_tick, ticked.kind());
    try testing.expectEqual(@as(u64, 100), ticked.payload.timer_tick.tick_count);
}

test "event timestamps never move backwards" {
    const first = Event.create(.{ .app_init = {} });
    const second = Event.create(.{ .app_init = {} });

    try testing.expect(second.timestamp_ms >= first.timestamp_ms);
}
