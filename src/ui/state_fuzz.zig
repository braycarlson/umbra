const std = @import("std");

const fuzz = @import("../testing/fuzz.zig");
const state_mod = @import("state.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const StateManager = state_mod.StateManager;

pub const label_bytes_max: u32 = 8;

comptime {
    assert(label_bytes_max > 0);
    assert(label_bytes_max < state_mod.state_max);
}

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();

    var manager = StateManager.init();
    defer manager.deinit();

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        var buffer: [label_bytes_max]u8 = undefined;
        const label = build_label(random, &buffer);
        const previous = manager.get();
        const was_empty = manager.is_empty();

        manager.set(label) catch {
            assert(label.len == 0 or label.len >= state_mod.state_max);

            continue;
        };

        assert(manager.equals(label));
        assert(!manager.is_empty());
        assert(manager.history_len() <= state_mod.history_max);

        check_history(&manager);

        if (!was_empty and !std.mem.eql(u8, previous, label)) {
            assert(manager.get_previous().len > 0);
        }

        if (random.uintLessThan(u8, 16) == 0) {
            manager.clear_history();

            assert(manager.history_len() == 0);
        }
    }

    assert(event == args.events_max);
}

fn check_history(manager: *const StateManager) void {
    const count = manager.history_len();

    assert(count <= state_mod.history_max);

    var index: u8 = 0;

    while (index < count) : (index += 1) {
        assert(index < state_mod.history_max);

        const entry = manager.history_at(index).?;

        assert(entry.to.len > 0);
        assert(entry.to.len < state_mod.state_max);
        assert(entry.from.len < state_mod.state_max);
    }

    assert(manager.history_at(count) == null);
}

fn build_label(random: std.Random, buffer: []u8) []const u8 {
    assert(buffer.len > 0);

    const length = random.uintLessThan(usize, buffer.len + 1);

    var index: usize = 0;

    while (index < length) : (index += 1) {
        assert(index < buffer.len);

        buffer[index] = 'a' + random.uintLessThan(u8, 4);
    }

    assert(length <= buffer.len);

    return buffer[0..length];
}

const testing = std.testing;

test "state fuzzer survives a fixed seed" {
    try main(testing.allocator, .{ .events_max = fuzz.events_max_smoke, .seed = 123 });
}

test "build_label stays inside the buffer" {
    var prng = std.Random.DefaultPrng.init(7);
    const random = prng.random();

    var buffer: [label_bytes_max]u8 = undefined;
    var event: u32 = 0;

    while (event < 100) : (event += 1) {
        const label = build_label(random, &buffer);

        try testing.expect(label.len <= buffer.len);
    }
}
