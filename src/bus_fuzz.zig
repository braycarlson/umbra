const std = @import("std");

const bus_mod = @import("bus.zig");
const event_module = @import("event.zig");
const fuzz = @import("testing/fuzz.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Bus = bus_mod.Bus;
const Event = event_module.Event;
const Kind = Event.Kind;

const pool_max: u8 = 4;
const kind_count = event_module.kind_count;

const Operation = enum {
    attach_clicker,
    attach_starter,
    emit,
};

const Counter = [kind_count]u32;

const Clicker = struct {
    bus: *Bus,
    seen: Counter = @splat(0),

    pub fn on_menu_show(clicker: *Clicker) void {
        clicker.seen[@backingInt(Kind.menu_show)] += 1;
    }

    pub fn on_tray_left_click(clicker: *Clicker) void {
        clicker.seen[@backingInt(Kind.tray_left_click)] += 1;

        clicker.bus.emit(&Event.create(.{ .menu_show = {} }));
    }
};

const Starter = struct {
    seen: Counter = @splat(0),

    pub fn on_app_init(starter: *Starter) void {
        starter.seen[@backingInt(Kind.app_init)] += 1;
    }

    pub fn on_custom(starter: *Starter, _: Event.Custom) void {
        starter.seen[@backingInt(Kind.custom)] += 1;
    }

    pub fn on_timer_tick(starter: *Starter, _: Event.Tick) void {
        starter.seen[@backingInt(Kind.timer_tick)] += 1;
    }
};

const Model = struct {
    clickers: [pool_max]u32 = @splat(0),
    expected_clickers: [pool_max]Counter = @splat(@splat(0)),
    expected_starters: [pool_max]Counter = @splat(@splat(0)),
    listeners: u32 = 0,
    starters: [pool_max]u32 = @splat(0),

    fn clicker_total(model: *const Model) u32 {
        var total: u32 = 0;

        for (model.clickers) |count| total += count;

        return total;
    }

    fn deliver(model: *Model, kind: Kind) void {
        const index = @backingInt(kind);
        const nested = if (kind == .tray_left_click) model.clicker_total() else 0;

        for (model.starters, &model.expected_starters) |count, *expected| {
            if (starter_hears(kind)) {
                expected[index] += count;
            }
        }

        for (model.clickers, &model.expected_clickers) |count, *expected| {
            if (clicker_hears(kind)) {
                expected[index] += count;
            }

            expected[@backingInt(Kind.menu_show)] += count * nested;
        }
    }

    fn clicker_hears(kind: Kind) bool {
        const result = switch (kind) {
            .menu_show, .tray_left_click => true,
            .app_init,
            .app_shutdown,
            .custom,
            .menu_select,
            .taskbar_restart,
            .timer_tick,
            .tray_double_click,
            .tray_right_click,
            => false,
        };

        return result;
    }

    fn starter_hears(kind: Kind) bool {
        const result = switch (kind) {
            .app_init, .custom, .timer_tick => true,
            .app_shutdown,
            .menu_select,
            .menu_show,
            .taskbar_restart,
            .tray_double_click,
            .tray_left_click,
            .tray_right_click,
            => false,
        };

        return result;
    }
};

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();

    var bus = Bus.init();
    defer bus.deinit();

    var clickers: [pool_max]Clicker = @splat(.{ .bus = &bus });
    var starters: [pool_max]Starter = @splat(.{});
    var model = Model{};
    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        const slot = random.uintLessThan(u8, pool_max);

        switch (fuzz.random_enum_uniform(random, Operation)) {
            .attach_clicker => attach_clicker(&bus, &model, &clickers[slot], slot),
            .attach_starter => attach_starter(&bus, &model, &starters[slot], slot),
            .emit => emit(&bus, &model, random),
        }

        assert(bus.listener_count() == model.listeners);
    }

    for (clickers, model.expected_clickers) |clicker, expected| {
        assert(std.mem.eql(u32, &clicker.seen, &expected));
    }

    for (starters, model.expected_starters) |starter, expected| {
        assert(std.mem.eql(u32, &starter.seen, &expected));
    }
}

fn attach_clicker(bus: *Bus, model: *Model, clicker: *Clicker, slot: u8) void {
    const full = model.listeners + 2 > bus_mod.listener_count_max;
    const queue_full = model.clicker_total() == bus_mod.pending_count_max;
    if (queue_full) return;

    bus.attach(Clicker, clicker) catch |err| switch (err) {
        error.ListenersExhausted => {
            assert(full);

            return;
        },
        else => unreachable,
    };

    assert(!full);

    model.clickers[slot] += 1;
    model.listeners += 2;
}

fn attach_starter(bus: *Bus, model: *Model, starter: *Starter, slot: u8) void {
    const full = model.listeners + 3 > bus_mod.listener_count_max;

    bus.attach(Starter, starter) catch |err| switch (err) {
        error.ListenersExhausted => {
            assert(full);

            return;
        },
        else => unreachable,
    };

    assert(!full);

    model.starters[slot] += 1;
    model.listeners += 3;
}

fn emit(bus: *Bus, model: *Model, random: std.Random) void {
    const kind = fuzz.random_enum_uniform(random, Kind);

    bus.emit(&Event.create(payload_for(kind)));

    model.deliver(kind);
}

fn payload_for(kind: Kind) Event.Payload {
    const result: Event.Payload = switch (kind) {
        .app_init => .{ .app_init = {} },
        .app_shutdown => .{ .app_shutdown = {} },
        .custom => .{ .custom = .{ .code = 1 } },
        .menu_select => .{ .menu_select = .{ .checked = false, .id = 1 } },
        .menu_show => .{ .menu_show = {} },
        .taskbar_restart => .{ .taskbar_restart = {} },
        .timer_tick => .{ .timer_tick = .{ .id = 1, .tick_count = 1 } },
        .tray_double_click => .{ .tray_double_click = {} },
        .tray_left_click => .{ .tray_left_click = {} },
        .tray_right_click => .{ .tray_right_click = {} },
    };

    return result;
}

const testing = std.testing;

test "bus fuzzer survives a fixed seed" {
    try main(testing.allocator, .{ .events_max = fuzz.events_max_smoke, .seed = 123 });
}

test "payload_for covers every kind" {
    for (std.enums.values(Kind)) |kind| {
        try testing.expectEqual(kind, std.meta.activeTag(payload_for(kind)));
    }
}
