const std = @import("std");

const event_module = @import("../../event.zig");
const sys = @import("sys.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

const Event = event_module.Event;

const PostQueue = @This();

dequeue_position: std.atomic.Value(u32),
doorbell: std.atomic.Value(sys.Fd),
enqueue_position: std.atomic.Value(u32),
posts_in_flight: std.atomic.Value(u32),
slots: [capacity]Slot,

pub const Error = sys.Error;

pub const capacity: u32 = 64;
pub const mask: u32 = capacity - 1;
pub const claim_retry_max: u32 = 64;
pub const counter_bytes: u32 = 8;
pub const close_yield_max: u32 = 1 << 22;

const Slot = struct {
    code: Event.Code,
    sequence: std.atomic.Value(u32),
};

comptime {
    assert(capacity > 0);
    assert(capacity & mask == 0);
    assert(claim_retry_max > 0);
    assert(counter_bytes == @sizeOf(u64));
    assert(close_yield_max > 0);
}

pub fn init(queue: *PostQueue) void {
    queue.doorbell = .init(-1);
    queue.posts_in_flight = .init(0);

    queue.clear();

    assert(queue.descriptor() == null);
    assert(queue.posts_in_flight.load(.seq_cst) == 0);
}

pub fn open(queue: *PostQueue) Error!sys.Fd {
    assert(queue.doorbell.load(.seq_cst) < 0);

    const raw = linux.eventfd(0, linux.EFD.CLOEXEC | linux.EFD.NONBLOCK);

    if (!sys.ok(raw)) {
        return Error.Failed;
    }

    const fd: sys.Fd = @intCast(raw);

    assert(fd >= 0);

    queue.clear();

    queue.doorbell.store(fd, .seq_cst);

    assert(queue.doorbell.load(.seq_cst) == fd);

    return fd;
}

pub fn close(queue: *PostQueue) void {
    const fd = queue.doorbell.swap(-1, .seq_cst);

    if (fd < 0) {
        return;
    }

    queue.wait_posts();

    sys.close(fd);

    assert(queue.doorbell.load(.seq_cst) < 0);
}

pub fn descriptor(queue: *const PostQueue) ?sys.Fd {
    const fd = queue.doorbell.load(.seq_cst);

    if (fd < 0) {
        return null;
    }

    return fd;
}

pub fn post(queue: *PostQueue, code: Event.Code) bool {
    _ = queue.posts_in_flight.fetchAdd(1, .seq_cst);
    defer _ = queue.posts_in_flight.fetchSub(1, .seq_cst);

    if (queue.descriptor() == null) {
        return false;
    }

    if (!queue.enqueue(code)) {
        return false;
    }

    queue.ring();

    return true;
}

pub fn drain(queue: *const PostQueue) void {
    const fd = queue.descriptor() orelse return;

    var counter: [counter_bytes]u8 = undefined;

    _ = sys.read(fd, &counter) catch return;
}

pub fn take(queue: *PostQueue) ?Event.Code {
    var position = queue.dequeue_position.load(.seq_cst);
    var attempt: u32 = 0;

    while (attempt < claim_retry_max) : (attempt += 1) {
        assert(attempt < claim_retry_max);

        const slot = &queue.slots[position & mask];
        const sequence = slot.sequence.load(.seq_cst);
        const claimed = position +% 1;
        const difference: i32 = @bitCast(sequence -% claimed);

        if (difference == 0) {
            const raced = queue.dequeue_position.cmpxchgWeak(position, claimed, .seq_cst, .seq_cst);

            if (raced) |actual| {
                position = actual;

                continue;
            }

            const code = slot.code;

            slot.sequence.store(position +% capacity, .seq_cst);

            return code;
        }

        if (difference < 0) {
            return null;
        }

        position = queue.dequeue_position.load(.seq_cst);
    }

    return null;
}

fn enqueue(queue: *PostQueue, code: Event.Code) bool {
    var position = queue.enqueue_position.load(.seq_cst);
    var attempt: u32 = 0;

    while (attempt < claim_retry_max) : (attempt += 1) {
        assert(attempt < claim_retry_max);

        const slot = &queue.slots[position & mask];
        const sequence = slot.sequence.load(.seq_cst);
        const difference: i32 = @bitCast(sequence -% position);

        if (difference == 0) {
            const claimed = position +% 1;
            const raced = queue.enqueue_position.cmpxchgWeak(position, claimed, .seq_cst, .seq_cst);

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

        position = queue.enqueue_position.load(.seq_cst);
    }

    return false;
}

fn ring(queue: *const PostQueue) void {
    const fd = queue.descriptor() orelse return;
    const counter = std.mem.toBytes(@as(u64, 1));

    sys.write_all(fd, &counter) catch return;
}

fn wait_posts(queue: *const PostQueue) void {
    assert(queue.doorbell.load(.seq_cst) < 0);

    var attempts: u32 = 0;

    while (queue.posts_in_flight.load(.seq_cst) != 0) : (attempts += 1) {
        assert(attempts < close_yield_max);

        std.Thread.yield() catch continue;
    }

    assert(queue.posts_in_flight.load(.seq_cst) == 0);
}

fn clear(queue: *PostQueue) void {
    var index: u32 = 0;

    while (index < capacity) : (index += 1) {
        assert(index < capacity);

        queue.slots[index] = Slot{
            .code = @fromBackingInt(0),
            .sequence = std.atomic.Value(u32).init(index),
        };
    }

    assert(index == capacity);

    queue.enqueue_position.store(0, .seq_cst);
    queue.dequeue_position.store(0, .seq_cst);

    assert(queue.enqueue_position.load(.seq_cst) == 0);
    assert(queue.dequeue_position.load(.seq_cst) == 0);
}

const testing = std.testing;

fn create_queue() !*PostQueue {
    const queue = try testing.allocator.create(PostQueue);

    queue.init();

    assert(queue.descriptor() == null);

    return queue;
}

fn destroy_queue(queue: *PostQueue) void {
    queue.close();

    assert(queue.descriptor() == null);

    testing.allocator.destroy(queue);
}

test "post is refused while the doorbell is closed" {
    const queue = try create_queue();
    defer destroy_queue(queue);

    try testing.expect(queue.descriptor() == null);
    try testing.expect(!queue.post(@fromBackingInt(7)));
    try testing.expect(queue.take() == null);
}

test "a posted code comes back out in order" {
    const queue = try create_queue();
    defer destroy_queue(queue);

    _ = try queue.open();

    try testing.expect(queue.post(@fromBackingInt(11)));
    try testing.expect(queue.post(@fromBackingInt(22)));

    queue.drain();

    try testing.expectEqual(@as(?Event.Code, @fromBackingInt(11)), queue.take());
    try testing.expectEqual(@as(?Event.Code, @fromBackingInt(22)), queue.take());
    try testing.expect(queue.take() == null);
}

test "a full queue refuses the next post" {
    const queue = try create_queue();
    defer destroy_queue(queue);

    _ = try queue.open();

    var index: u32 = 0;

    while (index < capacity) : (index += 1) {
        try testing.expect(queue.post(@fromBackingInt(index)));
    }

    try testing.expect(!queue.post(@fromBackingInt(capacity)));

    queue.drain();

    var taken: u32 = 0;

    while (taken < capacity) : (taken += 1) {
        try testing.expectEqual(@as(?Event.Code, @fromBackingInt(taken)), queue.take());
    }

    try testing.expect(queue.take() == null);
}

test "the queue keeps serving after it wraps" {
    const queue = try create_queue();
    defer destroy_queue(queue);

    _ = try queue.open();

    var round: u32 = 0;

    while (round < capacity * 4) : (round += 1) {
        try testing.expect(queue.post(@fromBackingInt(round)));
        try testing.expectEqual(@as(?Event.Code, @fromBackingInt(round)), queue.take());
    }

    try testing.expect(queue.take() == null);
}

test "a closed doorbell drops the queue" {
    const queue = try create_queue();
    defer destroy_queue(queue);

    _ = try queue.open();

    try testing.expect(queue.post(@fromBackingInt(5)));

    queue.close();

    try testing.expect(queue.descriptor() == null);
    try testing.expect(!queue.post(@fromBackingInt(6)));
}

test "close waits for a post in flight before closing the doorbell" {
    const queue = try create_queue();
    defer destroy_queue(queue);

    const fd = try queue.open();

    _ = queue.posts_in_flight.fetchAdd(1, .seq_cst);

    const closer = try std.Thread.spawn(.{}, PostQueue.close, .{queue});

    try std.Io.sleep(testing.io, .fromMilliseconds(20), .awake);

    try testing.expect(linux.errno(linux.fcntl(fd, linux.F.GETFD, 0)) == .SUCCESS);

    _ = queue.posts_in_flight.fetchSub(1, .seq_cst);

    closer.join();

    try testing.expect(linux.errno(linux.fcntl(fd, linux.F.GETFD, 0)) == .BADF);
    try testing.expect(queue.descriptor() == null);
    try testing.expect(!queue.post(@fromBackingInt(9)));
}

test "posting from another thread reaches the consumer" {
    const queue = try create_queue();
    defer destroy_queue(queue);

    _ = try queue.open();

    const Producer = struct {
        fn run(target: *PostQueue, base: u32) void {
            assert(base <= std.math.maxInt(u32) - 8);

            var index: u32 = 0;

            while (index < 8) : (index += 1) {
                _ = target.post(@fromBackingInt(base + index));
            }
        }
    };

    const first = try std.Thread.spawn(.{}, Producer.run, .{ queue, 100 });
    const second = try std.Thread.spawn(.{}, Producer.run, .{ queue, 200 });

    first.join();
    second.join();

    queue.drain();

    var seen: u32 = 0;

    while (queue.take()) |_| {
        seen += 1;

        assert(seen <= capacity);
    }

    try testing.expectEqual(@as(u32, 16), seen);
}
