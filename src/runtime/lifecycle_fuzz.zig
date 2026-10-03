const std = @import("std");

const fuzz = @import("../testing/fuzz.zig");
const lifecycle_mod = @import("lifecycle.zig");

const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Lifecycle = lifecycle_mod.Lifecycle;
const Stage = lifecycle_mod.Stage;

pub fn main(gpa: Allocator, args: fuzz.FuzzArgs) !void {
    _ = gpa;

    assert(args.events_max >= 1);

    var prng = std.Random.DefaultPrng.init(args.seed);
    const random = prng.random();

    var lifecycle = Lifecycle.init();

    assert(lifecycle.stage == .created);

    var event: u32 = 0;

    while (event < args.events_max) : (event += 1) {
        const before = lifecycle.stage;
        const target = fuzz.random_enum_uniform(random, Stage);
        const allowed = before.can_transition_to(target);
        const moved = lifecycle.transition(target);

        assert(moved == allowed);

        if (moved) {
            assert(lifecycle.stage == target);
        } else {
            assert(lifecycle.stage == before);
        }

        assert(!lifecycle.stage.can_transition_to(lifecycle.stage));

        if (lifecycle.stage == .stopped) {
            lifecycle = Lifecycle.init();

            assert(lifecycle.stage == .created);
        }
    }

    assert(event == args.events_max);
}

const testing = std.testing;

test "lifecycle fuzzer survives a fixed seed" {
    try main(testing.allocator, .{ .events_max = fuzz.events_max_smoke, .seed = 123 });
}

test "a stopped lifecycle refuses every transition" {
    var lifecycle = Lifecycle.init();

    lifecycle.force_stop();

    for (std.enums.values(Stage)) |target| {
        try testing.expect(!lifecycle.transition(target));
    }
}
