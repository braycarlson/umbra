const std = @import("std");

const contract = @import("../contract.zig");
const event_module = @import("../../event.zig");

const assert = std.debug.assert;

const Event = event_module.Event;
const PlatformError = contract.PlatformError;

pub const TapeError = error{
    TapeOverflow,
};

pub const tape_max: u32 = 64;

comptime {
    assert(tape_max > 0);
}

var tape: [tape_max]Event = undefined;
var tape_count: u32 = 0;
var tape_index: u32 = 0;
var running: bool = false;
var dispatched: u32 = 0;
var run_count: u32 = 0;
var post_count: u32 = 0;

pub fn push(event: Event) TapeError!void {
    if (tape_count == tape_max) {
        return TapeError.TapeOverflow;
    }

    tape[tape_count] = event;
    tape_count += 1;

    assert(tape_count <= tape_max);
}

pub fn quit() void {
    running = false;

    assert(!running);
}

pub fn post(code: u32) bool {
    push(Event.create(.{ .custom = .{ .code = code } })) catch {
        return false;
    };

    post_count += 1;

    return true;
}

pub fn posts() u32 {
    return post_count;
}

pub fn is_running() bool {
    return running;
}

pub fn dispatch_count() u32 {
    return dispatched;
}

pub fn pending_count() u32 {
    assert(tape_index <= tape_count);

    return tape_count - tape_index;
}

pub fn runs() u32 {
    return run_count;
}

pub fn reset() void {
    tape_count = 0;
    tape_index = 0;
    running = false;
    dispatched = 0;
    run_count = 0;
    post_count = 0;

    assert(tape_count == 0);
    assert(post_count == 0);
}

pub fn LoopType(comptime Owner: type) type {
    return struct {
        started: bool,

        const Instance = @This();

        pub fn init() Instance {
            assert(!running);

            const result = Instance{ .started = false };

            assert(!result.started);

            return result;
        }

        pub fn run(instance: *Instance, owner: *Owner) PlatformError!void {
            assert(!instance.started);
            assert(!running);

            instance.started = true;
            running = true;
            run_count += 1;

            while (tape_index < tape_count) {
                assert(tape_index < tape_max);

                if (!running) break;

                const event = tape[tape_index];

                tape_index += 1;
                dispatched += 1;

                owner.dispatch(&event);
            }

            running = false;

            assert(tape_index <= tape_count);
        }
    };
}

const testing = std.testing;

const Collector = struct {
    kinds: [tape_max]Event.Kind = undefined,
    count: u32 = 0,

    pub fn dispatch(collector: *Collector, event: *const Event) void {
        if (collector.count < tape_max) {
            collector.kinds[collector.count] = event.kind();
            collector.count += 1;
        }

        if (event.kind() == .menu_select) {
            quit();
        }
    }
};

test "run drains the tape into the owner" {
    reset();

    try push(Event.create(.{ .app_init = {} }));
    try push(Event.create(.{ .tray_left_click = {} }));

    var collector = Collector{};
    var instance = LoopType(Collector).init();

    try instance.run(&collector);

    try testing.expectEqual(@as(u32, 2), collector.count);
    try testing.expectEqual(Event.Kind.app_init, collector.kinds[0]);
    try testing.expectEqual(Event.Kind.tray_left_click, collector.kinds[1]);
    try testing.expectEqual(@as(u32, 0), pending_count());
}

test "a quit stops the tape early and a second run drains the rest" {
    reset();

    try push(Event.create(.{ .app_init = {} }));
    try push(Event.create(.{ .menu_select = .{ .checked = false, .id = 1 } }));
    try push(Event.create(.{ .tray_left_click = {} }));

    var collector_first = Collector{};
    var first = LoopType(Collector).init();

    try first.run(&collector_first);

    try testing.expectEqual(@as(u32, 2), collector_first.count);
    try testing.expectEqual(@as(u32, 1), pending_count());

    var collector_second = Collector{};
    var second = LoopType(Collector).init();

    try second.run(&collector_second);

    try testing.expectEqual(@as(u32, 1), collector_second.count);
    try testing.expectEqual(@as(u32, 2), runs());
}

test "post appends a custom event the loop delivers" {
    reset();

    try testing.expect(post(42));
    try testing.expectEqual(@as(u32, 1), posts());

    var collector = Collector{};
    var instance = LoopType(Collector).init();

    try instance.run(&collector);

    try testing.expectEqual(@as(u32, 1), collector.count);
    try testing.expectEqual(Event.Kind.custom, collector.kinds[0]);
}

test "post reports a full tape" {
    reset();

    var index: u32 = 0;

    while (index < tape_max) : (index += 1) {
        try testing.expect(post(index));
    }

    try testing.expect(!post(tape_max));
    try testing.expectEqual(tape_max, posts());
}
