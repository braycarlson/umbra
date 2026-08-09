const std = @import("std");

const sys = @import("sys.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

pub const Error = sys.Error;

pub const queue_capacity: u32 = 64;
pub const queue_mask: u32 = queue_capacity - 1;
pub const claim_retry_max: u32 = 64;
pub const counter_bytes: u32 = 8;

const Slot = struct {
    code: u32,
    sequence: std.atomic.Value(u32),
};

comptime {
    assert(queue_capacity > 0);
    assert(queue_capacity & queue_mask == 0);
    assert(claim_retry_max > 0);
    assert(counter_bytes == @sizeOf(u64));
}

var slots: [queue_capacity]Slot = undefined;
var enqueue_position: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
var dequeue_position: std.atomic.Value(u32) = std.atomic.Value(u32).init(0);
var doorbell: std.atomic.Value(sys.Fd) = std.atomic.Value(sys.Fd).init(-1);

pub fn open() Error!sys.Fd {
    assert(doorbell.load(.seq_cst) < 0);

    const raw = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);

    if (!sys.ok(raw)) {
        return Error.Failed;
    }

    const fd: sys.Fd = @intCast(raw);

    assert(fd >= 0);

    clear();

    doorbell.store(fd, .seq_cst);

    assert(doorbell.load(.seq_cst) == fd);

    return fd;
}

pub fn close() void {
    const fd = doorbell.swap(-1, .seq_cst);

    if (fd < 0) {
        return;
    }

    sys.close(fd);

    assert(doorbell.load(.seq_cst) < 0);
}

pub fn descriptor() ?sys.Fd {
    const fd = doorbell.load(.seq_cst);

    if (fd < 0) {
        return null;
    }

    return fd;
}

pub fn post(code: u32) bool {
    if (descriptor() == null) {
        return false;
    }

    if (!enqueue(code)) {
        return false;
    }

    ring();

    return true;
}

pub fn drain() void {
    const fd = descriptor() orelse return;

    var counter: [counter_bytes]u8 = undefined;

    _ = sys.read(fd, &counter) catch return;
}

pub fn take() ?u32 {
    var position = dequeue_position.load(.seq_cst);
    var attempt: u32 = 0;

    while (attempt < claim_retry_max) : (attempt += 1) {
        assert(attempt < claim_retry_max);

        const slot = &slots[position & queue_mask];
        const sequence = slot.sequence.load(.seq_cst);
        const claimed = position +% 1;
        const difference: i32 = @bitCast(sequence -% claimed);

        if (difference == 0) {
            const raced = dequeue_position.cmpxchgWeak(position, claimed, .seq_cst, .seq_cst);

            if (raced) |actual| {
                position = actual;

                continue;
            }

            const code = slot.code;

            slot.sequence.store(position +% queue_capacity, .seq_cst);

            return code;
        }

        if (difference < 0) {
            return null;
        }

        position = dequeue_position.load(.seq_cst);
    }

    return null;
}

fn enqueue(code: u32) bool {
    var position = enqueue_position.load(.seq_cst);
    var attempt: u32 = 0;

    while (attempt < claim_retry_max) : (attempt += 1) {
        assert(attempt < claim_retry_max);

        const slot = &slots[position & queue_mask];
        const sequence = slot.sequence.load(.seq_cst);
        const difference: i32 = @bitCast(sequence -% position);

        if (difference == 0) {
            const claimed = position +% 1;
            const raced = enqueue_position.cmpxchgWeak(position, claimed, .seq_cst, .seq_cst);

            if (raced) |actual| {
                position = actual;

                continue;
            }

            slot.code = code;
            slot.sequence.store(claimed, .seq_cst);

            return true;
        }

        if (difference < 0) {
            return false;
        }

        position = enqueue_position.load(.seq_cst);
    }

    return false;
}

fn ring() void {
    const fd = descriptor() orelse return;

    const counter = std.mem.toBytes(@as(u64, 1));

    sys.write_all(fd, &counter) catch return;
}

fn clear() void {
    var index: u32 = 0;

    while (index < queue_capacity) : (index += 1) {
        assert(index < queue_capacity);

        slots[index] = Slot{
            .code = 0,
            .sequence = std.atomic.Value(u32).init(index),
        };
    }

    assert(index == queue_capacity);

    enqueue_position.store(0, .seq_cst);
    dequeue_position.store(0, .seq_cst);

    assert(enqueue_position.load(.seq_cst) == 0);
    assert(dequeue_position.load(.seq_cst) == 0);
}

fn reset() void {
    close();
    clear();

    assert(doorbell.load(.seq_cst) < 0);
}

const testing = std.testing;

test "post is refused while the doorbell is closed" {
    reset();

    try testing.expect(descriptor() == null);
    try testing.expect(!post(7));
    try testing.expect(take() == null);
}

test "a posted code comes back out in order" {
    reset();

    _ = try open();
    defer reset();

    try testing.expect(post(11));
    try testing.expect(post(22));

    drain();

    try testing.expectEqual(@as(?u32, 11), take());
    try testing.expectEqual(@as(?u32, 22), take());
    try testing.expect(take() == null);
}

test "a full queue refuses the next post" {
    reset();

    _ = try open();
    defer reset();

    var index: u32 = 0;

    while (index < queue_capacity) : (index += 1) {
        try testing.expect(post(index));
    }

    try testing.expect(!post(queue_capacity));

    drain();

    var taken: u32 = 0;

    while (taken < queue_capacity) : (taken += 1) {
        try testing.expectEqual(@as(?u32, taken), take());
    }

    try testing.expect(take() == null);
}

test "the queue keeps serving after it wraps" {
    reset();

    _ = try open();
    defer reset();

    var round: u32 = 0;

    while (round < queue_capacity * 4) : (round += 1) {
        try testing.expect(post(round));
        try testing.expectEqual(@as(?u32, round), take());
    }

    try testing.expect(take() == null);
}

test "a closed doorbell drops the queue" {
    reset();

    _ = try open();

    try testing.expect(post(5));

    close();

    try testing.expect(descriptor() == null);
    try testing.expect(!post(6));

    reset();
}

test "posting from another thread reaches the consumer" {
    reset();

    _ = try open();
    defer reset();

    const Producer = struct {
        fn run(base: u32) void {
            var index: u32 = 0;

            while (index < 8) : (index += 1) {
                _ = post(base + index);
            }
        }
    };

    const first = try std.Thread.spawn(.{}, Producer.run, .{100});
    const second = try std.Thread.spawn(.{}, Producer.run, .{200});

    first.join();
    second.join();

    drain();

    var seen: u32 = 0;

    while (take()) |_| {
        seen += 1;
    }

    try testing.expectEqual(@as(u32, 16), seen);
}
