const std = @import("std");

const event_module = @import("event.zig");
const platform = @import("platform.zig");

const assert = std.debug.assert;

const CapacityError = platform.CapacityError;
const Event = event_module.Event;
const Kind = Event.Kind;

pub const listener_count_max: u8 = 32;
pub const pending_count_max: u8 = 8;

comptime {
    assert(listener_count_max > 0);
    assert(pending_count_max > 0);
    assert(pending_count_max <= listener_count_max);
}

const Listener = struct {
    invoke: *const fn (*anyopaque, *const Event) void,
    kind: Kind,
    owner: *anyopaque,
};

pub const Bus = struct {
    count: u8,
    dispatching: bool,
    listeners: [listener_count_max]Listener,
    pending: [pending_count_max]Event,
    pending_count: u8,

    pub fn init() Bus {
        const result = Bus{
            .count = 0,
            .dispatching = false,
            .listeners = undefined,
            .pending = undefined,
            .pending_count = 0,
        };

        assert(result.count == 0);
        assert(result.pending_count == 0);

        return result;
    }

    pub fn deinit(bus: *Bus) void {
        assert(!bus.dispatching);

        bus.count = 0;
        bus.pending_count = 0;

        assert(bus.listener_count() == 0);
    }

    pub fn attach(bus: *Bus, comptime Owner: type, owner: *Owner) CapacityError!void {
        const listened = comptime listened_count(Owner);

        comptime assert(listened > 0);
        comptime assert(listened <= event_module.kind_count);

        assert(bus.count <= listener_count_max);

        if (listened > listener_count_max - bus.count) return error.ListenersExhausted;

        inline for (comptime std.enums.values(Kind)) |kind| {
            if (comptime @hasDecl(Owner, listener_name(kind))) {
                bus.listeners[bus.count] = .{
                    .invoke = ListenerType(Owner, kind).invoke,
                    .kind = kind,
                    .owner = owner,
                };

                bus.count += 1;
            }
        }

        assert(bus.count <= listener_count_max);
    }

    pub fn emit(bus: *Bus, event: *const Event) void {
        assert(event.kind().is_valid());

        if (bus.dispatching) {
            assert(bus.pending_count < pending_count_max);

            bus.pending[bus.pending_count] = event.*;
            bus.pending_count += 1;

            return;
        }

        assert(bus.pending_count == 0);

        bus.dispatching = true;
        defer {
            bus.dispatching = false;
            bus.pending_count = 0;
        }

        bus.dispatch(event);

        var index: u8 = 0;

        while (index < bus.pending_count) : (index += 1) {
            assert(index < pending_count_max);

            const next = bus.pending[index];

            bus.dispatch(&next);
        }
    }

    pub fn listener_count(bus: *const Bus) u8 {
        assert(bus.count <= listener_count_max);

        return bus.count;
    }

    fn dispatch(bus: *Bus, event: *const Event) void {
        assert(bus.dispatching);

        const live = bus.count;
        const kind = event.kind();

        for (bus.listeners[0..live]) |*listener| {
            if (listener.kind == kind) {
                listener.invoke(listener.owner, event);
            }
        }
    }
};

fn ListenerType(comptime Owner: type, comptime kind: Kind) type {
    const name = listener_name(kind);
    const Payload = @FieldType(Event.Payload, @tagName(kind));
    const method = @field(Owner, name);
    const Expected = if (Payload == void) fn (*Owner) void else fn (*Owner, Payload) void;

    if (@TypeOf(method) != Expected) {
        @compileError("umbra: " ++ @typeName(Owner) ++ "." ++ name ++ " must be " ++
            @typeName(Expected));
    }

    return struct {
        fn invoke(context: *anyopaque, event: *const Event) void {
            assert(event.kind() == kind);

            const owner: *Owner = @ptrCast(@alignCast(context));

            if (Payload == void) {
                method(owner);
            } else {
                method(owner, @field(event.payload, @tagName(kind)));
            }
        }
    };
}

fn listened_count(comptime Owner: type) u8 {
    var result: u8 = 0;

    for (std.enums.values(Kind)) |kind| {
        if (@hasDecl(Owner, listener_name(kind))) {
            result += 1;
        }
    }

    assert(result <= event_module.kind_count);

    return result;
}

fn listener_name(comptime kind: Kind) []const u8 {
    return "on_" ++ @tagName(kind);
}

const testing = std.testing;

const Tally = struct {
    codes: u32 = 0,
    selected: u32 = 0,
    started: u32 = 0,

    pub fn on_app_init(tally: *Tally) void {
        tally.started += 1;
    }

    pub fn on_custom(tally: *Tally, custom: Event.Custom) void {
        tally.codes += custom.code;
    }

    pub fn on_menu_select(tally: *Tally, selection: Event.Selection) void {
        tally.selected = selection.id;
    }
};

test Bus {
    var bus = Bus.init();
    defer bus.deinit();

    var tally = Tally{};

    try bus.attach(Tally, &tally);

    try testing.expectEqual(@as(u8, 3), bus.listener_count());

    bus.emit(&Event.create(.{ .app_init = {} }));
    bus.emit(&Event.create(.{ .custom = .{ .code = 7 } }));
    bus.emit(&Event.create(.{ .menu_select = .{ .checked = false, .id = 4 } }));
    bus.emit(&Event.create(.{ .tray_left_click = {} }));

    try testing.expectEqual(@as(u32, 1), tally.started);
    try testing.expectEqual(@as(u32, 7), tally.codes);
    try testing.expectEqual(@as(u32, 4), tally.selected);
}

const Echo = struct {
    bus: *Bus,
    clicks: u32 = 0,
    shows: u32 = 0,

    pub fn on_tray_left_click(echo: *Echo) void {
        echo.clicks += 1;

        echo.bus.emit(&Event.create(.{ .menu_show = {} }));
    }

    pub fn on_menu_show(echo: *Echo) void {
        echo.shows += 1;
    }
};

test "an event emitted from a listener is queued and still delivered" {
    var bus = Bus.init();
    defer bus.deinit();

    var echo = Echo{ .bus = &bus };

    try bus.attach(Echo, &echo);

    bus.emit(&Event.create(.{ .tray_left_click = {} }));

    try testing.expectEqual(@as(u32, 1), echo.clicks);
    try testing.expectEqual(@as(u32, 1), echo.shows);
    try testing.expectEqual(@as(u8, 0), bus.pending_count);
}

test "listeners run in the order their owners were attached" {
    const Recorder = struct {
        var order: [4]u8 = @splat(0);
        var count: u8 = 0;

        tag: u8,

        pub fn on_app_init(recorder: *@This()) void {
            order[count] = recorder.tag;
            count += 1;
        }
    };

    Recorder.count = 0;

    var bus = Bus.init();
    defer bus.deinit();

    var first = Recorder{ .tag = 1 };
    var second = Recorder{ .tag = 2 };

    try bus.attach(Recorder, &first);
    try bus.attach(Recorder, &second);

    bus.emit(&Event.create(.{ .app_init = {} }));

    try testing.expectEqual(@as(u8, 2), Recorder.count);
    try testing.expectEqual(@as(u8, 1), Recorder.order[0]);
    try testing.expectEqual(@as(u8, 2), Recorder.order[1]);
}

test "a full bus refuses an owner without attaching any of its listeners" {
    var bus = Bus.init();
    defer bus.deinit();

    var tallies: [listener_count_max / 3]Tally = @splat(.{});

    for (&tallies) |*tally| {
        try bus.attach(Tally, tally);
    }

    const before = bus.listener_count();

    var spare = Tally{};

    try testing.expectError(error.ListenersExhausted, bus.attach(Tally, &spare));
    try testing.expectEqual(before, bus.listener_count());
}
