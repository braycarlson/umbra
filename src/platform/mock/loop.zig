const std = @import("std");

const contract = @import("../contract.zig");
const types = @import("../../event/types.zig");

const assert = std.debug.assert;

const Event = types.Event;

pub const Error = contract.LoopError;

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
var quit_requested: bool = false;
var running: bool = false;
var dispatched: u32 = 0;
var run_count: u32 = 0;
var post_count: u32 = 0;

pub fn push(event: Event) TapeError!void {
    if (tape_count >= tape_max) {
        return TapeError.TapeOverflow;
    }

    assert(tape_count < tape_max);

    tape[tape_count] = event;
    tape_count += 1;

    assert(tape_count <= tape_max);
}

pub fn quit() void {
    quit_requested = true;
    running = false;

    assert(quit_requested);
}

pub fn post(code: u32) bool {
    push(Event.custom(code, null)) catch {
        return false;
    };

    post_count += 1;

    assert(post_count > 0);

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
    quit_requested = false;
    running = false;
    dispatched = 0;
    run_count = 0;
    post_count = 0;

    assert(tape_count == 0);
    assert(!quit_requested);
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

        pub fn run(instance: *Instance, owner: *Owner) Error!void {
            assert(!instance.started);

            if (running) {
                return Error.AlreadyRunning;
            }

            instance.started = true;
            quit_requested = false;
            running = true;
            run_count += 1;
            errdefer running = false;

            while (running and tape_index < tape_count) {
                assert(tape_index < tape_max);

                const event = tape[tape_index];

                tape_index += 1;
                dispatched += 1;

                const response = owner.dispatch(&event);

                if (response.should_quit()) {
                    quit();
                }
            }

            running = false;

            assert(tape_index <= tape_count);
        }
    };
}

const testing = std.testing;

const Collector = struct {
    kinds: [tape_max]types.Kind,
    count: u32,

    fn init() Collector {
        return .{ .kinds = undefined, .count = 0 };
    }

    pub fn dispatch(collector: *Collector, event: *const Event) types.Response {
        if (collector.count < tape_max) {
            collector.kinds[collector.count] = event.kind();
            collector.count += 1;
        }

        if (event.kind() == .menu_select) {
            return .quit;
        }

        return .pass;
    }
};

test "run drains the tape into the owner" {
    reset();

    try push(Event.app_init());
    try push(Event.tray_left_click());

    var collector = Collector.init();
    var instance = LoopType(Collector).init();

    try instance.run(&collector);

    try testing.expectEqual(@as(u32, 2), collector.count);
    try testing.expectEqual(types.Kind.app_init, collector.kinds[0]);
    try testing.expectEqual(types.Kind.tray_left_click, collector.kinds[1]);
    try testing.expectEqual(@as(u32, 2), dispatch_count());
    try testing.expectEqual(@as(u32, 0), pending_count());
}

test "a quit response stops the tape early" {
    reset();

    try push(Event.app_init());
    try push(Event.menu_select(1, false));
    try push(Event.tray_left_click());

    var collector = Collector.init();
    var instance = LoopType(Collector).init();

    try instance.run(&collector);

    try testing.expectEqual(@as(u32, 2), collector.count);
    try testing.expectEqual(@as(u32, 1), pending_count());
}

test "run clears a stale quit request" {
    reset();

    try push(Event.app_init());

    quit();

    var collector = Collector.init();
    var instance = LoopType(Collector).init();

    try instance.run(&collector);

    try testing.expectEqual(@as(u32, 1), collector.count);
    try testing.expectEqual(@as(u32, 0), pending_count());
}

test "a second run drains what the first left behind" {
    reset();

    try push(Event.menu_select(1, false));
    try push(Event.tray_left_click());

    var first_collector = Collector.init();
    var first = LoopType(Collector).init();

    try first.run(&first_collector);

    try testing.expectEqual(@as(u32, 1), pending_count());

    var second_collector = Collector.init();
    var second = LoopType(Collector).init();

    try second.run(&second_collector);

    try testing.expectEqual(@as(u32, 1), second_collector.count);
    try testing.expectEqual(@as(u32, 0), pending_count());
    try testing.expectEqual(@as(u32, 2), runs());
}

test "post appends a custom event the loop delivers" {
    reset();

    try testing.expect(post(42));
    try testing.expectEqual(@as(u32, 1), posts());

    var collector = Collector.init();
    var instance = LoopType(Collector).init();

    try instance.run(&collector);

    try testing.expectEqual(@as(u32, 1), collector.count);
    try testing.expectEqual(types.Kind.custom, collector.kinds[0]);
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

test "push reports tape overflow" {
    reset();

    var index: u32 = 0;

    while (index < tape_max) : (index += 1) {
        try push(Event.app_init());
    }

    try testing.expectError(TapeError.TapeOverflow, push(Event.app_init()));
}
