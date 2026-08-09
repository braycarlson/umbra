const std = @import("std");

const bus_mod = @import("bus.zig");
const fuzz = @import("../testing/fuzz.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Bus = bus_mod.Bus;
const Subscription = bus_mod.Subscription;
const Kind = types.Kind;
const Response = types.Response;

const Operation = enum {
    clear,
    emit,
    subscribe,
    toggle,
    unsubscribe,
};

var invocations: u32 = 0;

fn record(_: *const types.Event, _: ?*anyopaque) Response {
    invocations += 1;

    return .pass;
}

fn stop(_: *const types.Event, _: ?*anyopaque) Response {
    invocations += 1;

    return .handled;
}

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();

    var bus = Bus.init();
    defer bus.deinit();

    var live: [types.handler_max]Subscription = undefined;
    var live_count: u8 = 0;

    invocations = 0;

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        assert(bus.handler_count() <= types.handler_max);

        const operation = fuzz.random_enum_uniform(random, Operation);

        switch (operation) {
            .clear => clear(&bus, &live_count),
            .emit => emit(&bus, random),
            .subscribe => subscribe(&bus, random, &live, &live_count),
            .toggle => toggle(random, live[0..live_count]),
            .unsubscribe => unsubscribe(&bus, random, &live, &live_count),
        }

        assert(bus.handler_count() <= types.handler_max);
    }

    assert(event == args.events_max);
}

fn clear(bus: *Bus, live_count: *u8) void {
    bus.clear();

    live_count.* = 0;

    assert(bus.handler_count() == 0);
}

fn emit(bus: *Bus, random: std.Random) void {
    const kind = fuzz.random_enum_uniform(random, Kind);
    const outgoing = types.Event.create(payload_for(kind));
    const response = bus.emit(&outgoing);

    assert(outgoing.kind() == kind);
    assert(response == .pass or response == .handled or response == .quit);
}

fn subscribe(bus: *Bus, random: std.Random, live: []Subscription, live_count: *u8) void {
    const callback = if (random.boolean()) &record else &stop;
    const filtered = random.boolean();

    const subscription = if (filtered)
        bus.on(fuzz.random_enum_uniform(random, Kind), callback, null)
    else
        bus.on_any(callback, null);

    if (subscription) |entry| {
        assert(live_count.* < types.handler_max);

        live[live_count.*] = entry;
        live_count.* += 1;
    }
}

fn toggle(random: std.Random, live: []Subscription) void {
    if (live.len == 0) return;

    const slot = random.uintLessThan(usize, live.len);

    assert(slot < types.handler_max);

    _ = live[slot].set_enabled(random.boolean());
}

fn unsubscribe(bus: *Bus, random: std.Random, live: []Subscription, live_count: *u8) void {
    if (live_count.* == 0) return;

    const slot = random.uintLessThan(u8, live_count.*);

    assert(slot < types.handler_max);

    const removed = live[slot].unsubscribe();

    assert(!live[slot].unsubscribe());
    assert(removed or bus.handler_count() <= types.handler_max);

    live_count.* -= 1;
    live[slot] = live[live_count.*];
}

fn payload_for(kind: Kind) types.Payload {
    const result: types.Payload = switch (kind) {
        .app_init => .{ .app_init = {} },
        .app_shutdown => .{ .app_shutdown = {} },
        .custom => .{ .custom = .{ .code = 1, .data = null } },
        .icon_change => .{ .icon_change = .{ .name = "icon" } },
        .menu_select => .{ .menu_select = .{ .checked = false, .id = 1 } },
        .menu_show => .{ .menu_show = {} },
        .state_change => .{ .state_change = .{ .from = "a", .to = "b" } },
        .taskbar_restart => .{ .taskbar_restart = {} },
        .timer_tick => .{ .timer_tick = .{ .id = 1, .tick_count = 1 } },
        .tray_double_click => .{ .tray_double_click = {} },
        .tray_left_click => .{ .tray_left_click = {} },
        .tray_right_click => .{ .tray_right_click = {} },
        .window_message => .{ .window_message = .{ .lparam = 0, .message = 1, .wparam = 0 } },
    };

    return result;
}

const testing = std.testing;

test "bus fuzzer survives a fixed seed" {
    try main(testing.allocator, .{ .events_max = fuzz.events_max_smoke, .seed = 123 });
}

test "payload_for covers every kind" {
    var index: u8 = 0;

    while (index < types.kind_count) : (index += 1) {
        const kind: Kind = @enumFromInt(index);
        const payload = payload_for(kind);

        try testing.expectEqual(index, @as(u8, @intFromEnum(payload)));
    }
}
