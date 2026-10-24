const std = @import("std");

const assert = std.debug.assert;

pub const Stage = enum(u8) {
    created = 0,
    running = 1,
    stopping = 2,
    stopped = 3,

    pub fn can_transition_to(stage: Stage, target: Stage) bool {
        const result = switch (stage) {
            .created => target == .running,
            .running => target == .stopping,
            .stopping => target == .stopped,
            .stopped => false,
        };

        return result;
    }
};

pub const stage_count: u8 = @typeInfo(Stage).@"enum".field_names.len;

comptime {
    assert(stage_count == 4);
    assert(@backingInt(Stage.created) < @backingInt(Stage.running));
    assert(@backingInt(Stage.running) < @backingInt(Stage.stopping));
    assert(@backingInt(Stage.stopping) < @backingInt(Stage.stopped));
}

pub const Lifecycle = struct {
    stage: Stage,

    pub fn init() Lifecycle {
        const result = Lifecycle{
            .stage = .created,
        };

        return result;
    }

    pub fn is_running(lifecycle: *const Lifecycle) bool {
        return lifecycle.stage == .running;
    }

    pub fn is_stopped(lifecycle: *const Lifecycle) bool {
        return lifecycle.stage == .stopped;
    }

    pub fn transition(lifecycle: *Lifecycle, target: Stage) bool {
        if (!lifecycle.stage.can_transition_to(target)) {
            return false;
        }

        lifecycle.stage = target;

        return true;
    }

    pub fn force_stop(lifecycle: *Lifecycle) void {
        lifecycle.stage = .stopped;

        assert(lifecycle.is_stopped());
    }
};

const testing = std.testing;

test "each stage may only advance to the next one" {
    try testing.expect(Stage.created.can_transition_to(.running));
    try testing.expect(Stage.running.can_transition_to(.stopping));
    try testing.expect(Stage.stopping.can_transition_to(.stopped));

    for (std.enums.values(Stage)) |stage| {
        for (std.enums.values(Stage)) |target| {
            const next = @backingInt(stage) + 1 == @backingInt(target);

            try testing.expectEqual(next, stage.can_transition_to(target));
        }
    }
}

test "a fresh lifecycle starts in the created stage" {
    const lifecycle = Lifecycle.init();

    try testing.expectEqual(Stage.created, lifecycle.stage);
    try testing.expect(!lifecycle.is_running());
    try testing.expect(!lifecycle.is_stopped());
}

test "a lifecycle walks every stage in order" {
    var lifecycle = Lifecycle.init();

    try testing.expect(lifecycle.transition(.running));
    try testing.expect(lifecycle.is_running());

    try testing.expect(lifecycle.transition(.stopping));
    try testing.expect(!lifecycle.is_running());

    try testing.expect(lifecycle.transition(.stopped));
    try testing.expect(lifecycle.is_stopped());
}

test "a refused transition leaves the stage alone" {
    var lifecycle = Lifecycle.init();

    try testing.expect(!lifecycle.transition(.stopped));
    try testing.expectEqual(Stage.created, lifecycle.stage);

    _ = lifecycle.transition(.running);

    try testing.expect(!lifecycle.transition(.created));
    try testing.expectEqual(Stage.running, lifecycle.stage);
}
