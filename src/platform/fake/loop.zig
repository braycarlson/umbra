const std = @import("std");

const event_module = @import("../../event.zig");
const interface = @import("../interface.zig");
const Tray = @import("tray.zig");

const assert = std.debug.assert;

const Event = event_module.Event;

const Loop = @This();

dispatched: u32,
post_count: u32,
queue: [queue_max]Event,
queue_count: u32,
queue_index: u32,
run_count: u32,
running: bool,

pub const QueueError = error{
    QueueFull,
};

pub const queue_max: u32 = 64;

comptime {
    assert(queue_max > 0);
}

pub fn init(loop: *Loop) void {
    loop.dispatched = 0;
    loop.post_count = 0;
    loop.queue = undefined;
    loop.queue_count = 0;
    loop.queue_index = 0;
    loop.run_count = 0;
    loop.running = false;

    assert(loop.pending_count() == 0);
    assert(!loop.is_running());
}

pub fn push(loop: *Loop, event: Event) QueueError!void {
    assert(event.kind().is_valid());

    if (loop.queue_count == queue_max) {
        return QueueError.QueueFull;
    }

    loop.queue[loop.queue_count] = event;
    loop.queue_count += 1;

    assert(loop.queue_count <= queue_max);
}

pub fn quit(loop: *Loop) void {
    loop.running = false;

    assert(!loop.running);
}

pub fn post(loop: *Loop, code: Event.Code, timestamp_ms: u64) bool {
    loop.push(Event.create(.{ .custom = .{ .code = code } }, timestamp_ms)) catch {
        return false;
    };

    loop.post_count += 1;

    return true;
}

pub fn run(loop: *Loop, comptime Owner: type, owner: *Owner, tray: *Tray) void {
    assert(!loop.running);
    assert(loop.queue_index <= loop.queue_count);

    loop.running = true;
    loop.run_count += 1;

    while (loop.queue_index < loop.queue_count) {
        assert(loop.queue_index < queue_max);

        if (!loop.running) break;

        const event = loop.queue[loop.queue_index];

        loop.queue_index += 1;
        loop.dispatched += 1;

        owner.dispatch(&event);

        if (interface.is_activation(event.kind())) tray.activation_clear();
    }

    loop.running = false;

    assert(loop.queue_index <= loop.queue_count);
}

pub fn posts(loop: *const Loop) u32 {
    return loop.post_count;
}

pub fn is_running(loop: *const Loop) bool {
    return loop.running;
}

pub fn dispatch_count(loop: *const Loop) u32 {
    return loop.dispatched;
}

pub fn pending_count(loop: *const Loop) u32 {
    assert(loop.queue_index <= loop.queue_count);

    return loop.queue_count - loop.queue_index;
}

pub fn runs(loop: *const Loop) u32 {
    return loop.run_count;
}

const testing = std.testing;

const Collector = struct {
    kinds: [queue_max]Event.Kind = undefined,
    count: u32 = 0,
    loop: *Loop,

    pub fn dispatch(collector: *Collector, event: *const Event) void {
        if (collector.count < queue_max) {
            collector.kinds[collector.count] = event.kind();
            collector.count += 1;
        }

        if (event.kind() == .menu_select) {
            collector.loop.quit();
        }
    }
};

const Fixture = struct {
    loop: Loop,
    tray: Tray,

    fn init(fixture: *Fixture) void {
        fixture.loop.init();
        fixture.tray.init();

        assert(fixture.loop.pending_count() == 0);
        assert(!fixture.tray.is_created());
    }
};

test "run drains the queue into the owner" {
    var fixture: Fixture = undefined;

    fixture.init();

    try fixture.loop.push(Event.create(.{ .app_init = {} }, 0));
    try fixture.loop.push(Event.create(.{ .tray_left_click = {} }, 0));

    var collector = Collector{ .loop = &fixture.loop };

    fixture.loop.run(Collector, &collector, &fixture.tray);

    try testing.expectEqual(@as(u32, 2), collector.count);
    try testing.expectEqual(Event.Kind.app_init, collector.kinds[0]);
    try testing.expectEqual(Event.Kind.tray_left_click, collector.kinds[1]);
    try testing.expectEqual(@as(u32, 0), fixture.loop.pending_count());
}

test "a quit stops the queue early and a second run drains the rest" {
    var fixture: Fixture = undefined;

    fixture.init();

    try fixture.loop.push(Event.create(.{ .app_init = {} }, 0));
    try fixture.loop.push(Event.create(.{ .menu_select = .{ .checked = false, .id = 1 } }, 0));
    try fixture.loop.push(Event.create(.{ .tray_left_click = {} }, 0));

    var collector_first = Collector{ .loop = &fixture.loop };

    fixture.loop.run(Collector, &collector_first, &fixture.tray);

    try testing.expectEqual(@as(u32, 2), collector_first.count);
    try testing.expectEqual(@as(u32, 1), fixture.loop.pending_count());

    var collector_second = Collector{ .loop = &fixture.loop };

    fixture.loop.run(Collector, &collector_second, &fixture.tray);

    try testing.expectEqual(@as(u32, 1), collector_second.count);
    try testing.expectEqual(@as(u32, 2), fixture.loop.runs());
}

test "post appends a custom event the loop delivers" {
    var fixture: Fixture = undefined;

    fixture.init();

    try testing.expect(fixture.loop.post(@fromBackingInt(42), 0));
    try testing.expectEqual(@as(u32, 1), fixture.loop.posts());

    var collector = Collector{ .loop = &fixture.loop };

    fixture.loop.run(Collector, &collector, &fixture.tray);

    try testing.expectEqual(@as(u32, 1), collector.count);
    try testing.expectEqual(Event.Kind.custom, collector.kinds[0]);
}

test "post reports a full queue" {
    var fixture: Fixture = undefined;

    fixture.init();

    var index: u32 = 0;

    while (index < queue_max) : (index += 1) {
        try testing.expect(fixture.loop.post(@fromBackingInt(index), 0));
    }

    try testing.expect(!fixture.loop.post(@fromBackingInt(queue_max), 0));
    try testing.expectEqual(queue_max, fixture.loop.posts());
}
