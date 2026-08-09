const std = @import("std");

const types = @import("types.zig");

const assert = std.debug.assert;

const Event = types.Event;
const Kind = types.Kind;
const Response = types.Response;

pub const HandlerFn = *const fn (event: *const Event, context: ?*anyopaque) Response;

pub const Handler = struct {
    callback: HandlerFn,
    context: ?*anyopaque,
    enabled: bool,
    filter: ?Kind,
    priority: u8,

    pub fn init(callback: HandlerFn) Handler {
        const result = Handler{
            .callback = callback,
            .context = null,
            .enabled = true,
            .filter = null,
            .priority = 100,
        };

        return result;
    }

    pub fn with_context(handler: Handler, context: ?*anyopaque) Handler {
        var result = handler;

        result.context = context;

        return result;
    }

    pub fn with_filter(handler: Handler, filter: Kind) Handler {
        assert(filter.is_valid());

        var result = handler;

        result.filter = filter;

        return result;
    }

    pub fn with_priority(handler: Handler, priority: u8) Handler {
        var result = handler;

        result.priority = priority;

        return result;
    }

    pub fn invoke(handler: *const Handler, event: *const Event) Response {
        if (!handler.enabled) {
            return .pass;
        }

        if (handler.filter) |filter| {
            assert(filter.is_valid());

            if (event.kind() != filter) {
                return .pass;
            }
        }

        return handler.callback(event, handler.context);
    }
};

pub const Subscription = struct {
    bus: *Bus,
    generation: u32,
    index: u8,

    pub fn set_enabled(subscription: *const Subscription, enabled: bool) bool {
        assert(subscription.index < types.handler_max);

        return subscription.bus.set_enabled(subscription.index, subscription.generation, enabled);
    }

    pub fn unsubscribe(subscription: *const Subscription) bool {
        assert(subscription.index < types.handler_max);

        return subscription.bus.remove(subscription.index, subscription.generation);
    }
};

pub const Bus = struct {
    count: u8,
    dispatching: bool,
    generations: [types.handler_max]u32,
    handlers: [types.handler_max]?Handler,
    order: [types.handler_max]u8,
    pending: [types.pending_max]Event,
    pending_count: u8,

    pub fn init() Bus {
        const result = Bus{
            .count = 0,
            .dispatching = false,
            .generations = [_]u32{0} ** types.handler_max,
            .handlers = [_]?Handler{null} ** types.handler_max,
            .order = [_]u8{0} ** types.handler_max,
            .pending = undefined,
            .pending_count = 0,
        };

        assert(result.count == 0);
        assert(result.pending_count == 0);

        return result;
    }

    pub fn deinit(bus: *Bus) void {
        bus.clear();

        assert(bus.count == 0);
    }

    pub fn clear(bus: *Bus) void {
        var index: u8 = 0;

        while (index < types.handler_max) : (index += 1) {
            bus.handlers[index] = null;
        }

        bus.count = 0;

        assert(bus.count == 0);
    }

    pub fn emit(bus: *Bus, event: *const Event) Response {
        assert(event.kind().is_valid());

        if (bus.dispatching) {
            assert(bus.pending_count < types.pending_max);

            bus.pending[bus.pending_count] = event.*;
            bus.pending_count += 1;

            assert(bus.pending_count <= types.pending_max);

            return .pass;
        }

        assert(bus.pending_count == 0);

        bus.dispatching = true;
        defer {
            bus.dispatching = false;
            bus.pending_count = 0;
        }

        const result = dispatch(bus, event);

        drain_pending(bus);

        return result;
    }

    pub fn emit_kind(bus: *Bus, kind: Kind) Response {
        assert(kind.is_valid());

        const event = Event.create(@unionInit(types.Payload, @tagName(kind), {}));

        assert(event.kind() == kind);

        return bus.emit(&event);
    }

    pub fn handler_count(bus: *const Bus) u8 {
        assert(bus.count <= types.handler_max);

        return bus.count;
    }

    pub fn on(bus: *Bus, kind: Kind, callback: HandlerFn, context: ?*anyopaque) ?Subscription {
        assert(kind.is_valid());

        const handler = Handler.init(callback).with_filter(kind).with_context(context);

        return bus.subscribe(handler);
    }

    pub fn on_any(bus: *Bus, callback: HandlerFn, context: ?*anyopaque) ?Subscription {
        const handler = Handler.init(callback).with_context(context);

        return bus.subscribe(handler);
    }

    pub fn remove(bus: *Bus, index: u8, generation: u32) bool {
        assert(index < types.handler_max);

        if (bus.handlers[index] == null or bus.generations[index] != generation) {
            return false;
        }

        bus.handlers[index] = null;

        assert(bus.count > 0);

        bus.count -= 1;

        drop_from_order(bus, index);

        assert(bus.count <= types.handler_max);

        return true;
    }

    pub fn set_enabled(bus: *Bus, index: u8, generation: u32, enabled: bool) bool {
        assert(index < types.handler_max);

        if (bus.handlers[index] == null or bus.generations[index] != generation) {
            return false;
        }

        bus.handlers[index].?.enabled = enabled;

        return true;
    }

    pub fn subscribe(bus: *Bus, handler: Handler) ?Subscription {
        if (bus.count >= types.handler_max) {
            return null;
        }

        const slot = find_empty_slot(bus) orelse return null;

        assert(slot < types.handler_max);

        bus.handlers[slot] = handler;
        bus.generations[slot] +%= 1;
        bus.count += 1;

        assert(bus.count <= types.handler_max);

        insert_into_order(bus, slot, handler.priority);

        const result = Subscription{
            .bus = bus,
            .generation = bus.generations[slot],
            .index = slot,
        };

        return result;
    }
};

fn insert_into_order(bus: *Bus, slot: u8, priority: u8) void {
    assert(bus.count > 0);
    assert(bus.count <= types.handler_max);

    var position: u8 = 0;

    while (position + 1 < bus.count) : (position += 1) {
        assert(position < types.handler_max);

        const other = bus.order[position];

        if (bus.handlers[other].?.priority > priority) {
            break;
        }
    }

    var index: u8 = bus.count - 1;

    while (index > position) : (index -= 1) {
        assert(index < types.handler_max);

        bus.order[index] = bus.order[index - 1];
    }

    bus.order[position] = slot;

    assert(is_ordered(bus));
}

fn drop_from_order(bus: *Bus, slot: u8) void {
    assert(bus.count < types.handler_max);

    const live = bus.count + 1;

    var index: u8 = 0;

    while (index < live) : (index += 1) {
        assert(index < types.handler_max);

        if (bus.order[index] == slot) {
            break;
        }
    }

    assert(index < live);

    while (index < bus.count) : (index += 1) {
        assert(index + 1 < types.handler_max);

        bus.order[index] = bus.order[index + 1];
    }

    assert(is_ordered(bus));
}

fn is_ordered(bus: *const Bus) bool {
    var index: u8 = 1;

    while (index < bus.count) : (index += 1) {
        assert(index < types.handler_max);

        const previous = bus.handlers[bus.order[index - 1]].?.priority;
        const current = bus.handlers[bus.order[index]].?.priority;

        if (previous > current) {
            return false;
        }
    }

    return true;
}

fn dispatch(bus: *Bus, event: *const Event) Response {
    assert(bus.dispatching);
    assert(bus.count <= types.handler_max);
    assert(is_ordered(bus));

    const snapshot = bus.order;
    const snapshot_count = bus.count;

    var index: u8 = 0;

    while (index < snapshot_count) : (index += 1) {
        assert(index < types.handler_max);

        const slot = snapshot[index];

        assert(slot < types.handler_max);

        const handler = &(bus.handlers[slot] orelse continue);
        const response = handler.invoke(event);

        if (response.should_stop()) {
            return response;
        }
    }

    return .pass;
}

fn drain_pending(bus: *Bus) void {
    assert(bus.dispatching);

    var index: u8 = 0;

    while (index < bus.pending_count) : (index += 1) {
        assert(index < types.pending_max);

        const next = bus.pending[index];

        _ = dispatch(bus, &next);
    }

    assert(bus.pending_count <= types.pending_max);
}

fn find_empty_slot(bus: *Bus) ?u8 {
    var index: u8 = 0;

    while (index < types.handler_max) : (index += 1) {
        if (bus.handlers[index] == null) {
            return index;
        }
    }

    return null;
}

const testing = std.testing;

const Nested = struct {
    var bus_pointer: ?*Bus = null;
    var clicks: u32 = 0;
    var changes: u32 = 0;
    var last_to: []const u8 = "";

    fn reset(bus: *Bus) void {
        bus_pointer = bus;
        clicks = 0;
        changes = 0;
        last_to = "";
    }

    fn on_click(_: *const Event, _: ?*anyopaque) Response {
        clicks += 1;

        const bus = bus_pointer orelse return .pass;
        const changed = Event.state_change("idle", "active");

        _ = bus.emit(&changed);

        return .pass;
    }

    fn on_change(event: *const Event, _: ?*anyopaque) Response {
        changes += 1;
        last_to = event.payload.state_change.to;

        return .pass;
    }
};

const Priority = struct {
    var seen: [types.handler_max]u8 = undefined;
    var count: u8 = 0;

    fn note(tag: u8) void {
        if (count < types.handler_max) {
            seen[count] = tag;
            count += 1;
        }
    }

    fn first(_: *const Event, _: ?*anyopaque) Response {
        note(1);

        return .pass;
    }

    fn second(_: *const Event, _: ?*anyopaque) Response {
        note(2);

        return .pass;
    }

    fn third(_: *const Event, _: ?*anyopaque) Response {
        note(3);

        return .pass;
    }
};

test "handlers dispatch in priority order regardless of subscribe order" {
    var bus = Bus.init();
    defer bus.deinit();

    Priority.count = 0;

    _ = bus.subscribe(Handler.init(Priority.second).with_priority(50));
    _ = bus.subscribe(Handler.init(Priority.third).with_priority(200));
    _ = bus.subscribe(Handler.init(Priority.first).with_priority(10));

    const started = Event.app_init();

    _ = bus.emit(&started);

    try testing.expectEqual(@as(u8, 3), Priority.count);
    try testing.expectEqual(@as(u8, 1), Priority.seen[0]);
    try testing.expectEqual(@as(u8, 2), Priority.seen[1]);
    try testing.expectEqual(@as(u8, 3), Priority.seen[2]);
}

test "a stale subscription cannot remove a reused slot" {
    var bus = Bus.init();
    defer bus.deinit();

    Priority.count = 0;

    const first = bus.subscribe(Handler.init(Priority.first)).?;

    try testing.expect(first.unsubscribe());
    try testing.expect(!first.unsubscribe());

    const second = bus.subscribe(Handler.init(Priority.second)).?;

    try testing.expectEqual(first.index, second.index);
    try testing.expect(first.generation != second.generation);
    try testing.expect(!first.unsubscribe());
    try testing.expect(!first.set_enabled(false));
    try testing.expectEqual(@as(u8, 1), bus.handler_count());

    const started = Event.app_init();

    _ = bus.emit(&started);

    try testing.expectEqual(@as(u8, 1), Priority.count);
    try testing.expectEqual(@as(u8, 2), Priority.seen[0]);
}

test "an event emitted from a handler still reaches its own handler" {
    var bus = Bus.init();
    defer bus.deinit();

    Nested.reset(&bus);

    _ = bus.on(.tray_left_click, Nested.on_click, null);
    _ = bus.on(.state_change, Nested.on_change, null);

    const clicked = Event.tray_left_click();

    _ = bus.emit(&clicked);

    try testing.expectEqual(@as(u32, 1), Nested.clicks);
    try testing.expectEqual(@as(u32, 1), Nested.changes);
    try testing.expectEqualStrings("active", Nested.last_to);
    try testing.expectEqual(@as(u8, 0), bus.pending_count);
}

test "the pending queue drains in emission order" {
    var bus = Bus.init();
    defer bus.deinit();

    const Recorder = struct {
        var seen: [types.pending_max]Kind = undefined;
        var count: u8 = 0;

        fn handle(event: *const Event, _: ?*anyopaque) Response {
            if (count < types.pending_max) {
                seen[count] = event.kind();
                count += 1;
            }

            return .pass;
        }
    };

    Recorder.count = 0;

    _ = bus.on_any(Recorder.handle, null);

    const Fanout = struct {
        var bus_pointer: ?*Bus = null;

        fn handle(_: *const Event, _: ?*anyopaque) Response {
            const live = bus_pointer orelse return .pass;

            bus_pointer = null;

            const first = Event.menu_show();
            const second = Event.taskbar_restart();

            _ = live.emit(&first);
            _ = live.emit(&second);

            return .pass;
        }
    };

    Fanout.bus_pointer = &bus;

    _ = bus.on(.app_init, Fanout.handle, null);

    const started = Event.app_init();

    _ = bus.emit(&started);

    try testing.expectEqual(@as(u8, 3), Recorder.count);
    try testing.expectEqual(Kind.app_init, Recorder.seen[0]);
    try testing.expectEqual(Kind.menu_show, Recorder.seen[1]);
    try testing.expectEqual(Kind.taskbar_restart, Recorder.seen[2]);
}

test "a handler that stops dispatch still drains the queue" {
    var bus = Bus.init();
    defer bus.deinit();

    const Sink = struct {
        var queued: u32 = 0;
        var bus_pointer: ?*Bus = null;

        fn emit_and_stop(_: *const Event, _: ?*anyopaque) Response {
            const live = bus_pointer orelse return .handled;
            const queued_event = Event.menu_show();

            _ = live.emit(&queued_event);

            return .handled;
        }

        fn count_shows(_: *const Event, _: ?*anyopaque) Response {
            queued += 1;

            return .pass;
        }
    };

    Sink.queued = 0;
    Sink.bus_pointer = &bus;

    _ = bus.on(.app_init, Sink.emit_and_stop, null);
    _ = bus.on(.menu_show, Sink.count_shows, null);

    const started = Event.app_init();

    try testing.expectEqual(Response.handled, bus.emit(&started));
    try testing.expectEqual(@as(u32, 1), Sink.queued);
}
