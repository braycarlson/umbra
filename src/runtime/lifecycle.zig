const std = @import("std");

const assert = std.debug.assert;

pub const Stage = enum(u8) {
    created = 0,
    configured = 1,
    running = 2,
    stopping = 3,
    stopped = 4,

    pub fn can_transition_to(stage: Stage, target: Stage) bool {
        const result = switch (stage) {
            .created => target == .configured,
            .configured => target == .running,
            .running => target == .stopping,
            .stopping => target == .stopped,
            .stopped => false,
        };

        return result;
    }
};

pub const stage_count: u8 = @typeInfo(Stage).@"enum".field_names.len;

comptime {
    assert(stage_count == 5);
    assert(@backingInt(Stage.created) < @backingInt(Stage.configured));
    assert(@backingInt(Stage.configured) < @backingInt(Stage.running));
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

    pub fn is_configured(lifecycle: *const Lifecycle) bool {
        return lifecycle.stage == .configured;
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
    }
};

const testing = std.testing;

test "a created stage may become configured" {
    try testing.expect(Stage.created.can_transition_to(.configured));
}

test "a configured stage may start running" {
    try testing.expect(Stage.configured.can_transition_to(.running));
}

test "a running stage may begin stopping" {
    try testing.expect(Stage.running.can_transition_to(.stopping));
}

test "a stopping stage may reach stopped" {
    try testing.expect(Stage.stopping.can_transition_to(.stopped));
}

test "a created stage refuses every other transition" {
    try testing.expect(!Stage.created.can_transition_to(.created));
    try testing.expect(!Stage.created.can_transition_to(.running));
    try testing.expect(!Stage.created.can_transition_to(.stopped));
    try testing.expect(!Stage.created.can_transition_to(.stopping));
}

test "a configured stage refuses every other transition" {
    try testing.expect(!Stage.configured.can_transition_to(.created));
    try testing.expect(!Stage.configured.can_transition_to(.configured));
    try testing.expect(!Stage.configured.can_transition_to(.stopped));
    try testing.expect(!Stage.configured.can_transition_to(.stopping));
}

test "a running stage refuses every other transition" {
    try testing.expect(!Stage.running.can_transition_to(.created));
    try testing.expect(!Stage.running.can_transition_to(.configured));
    try testing.expect(!Stage.running.can_transition_to(.running));
    try testing.expect(!Stage.running.can_transition_to(.stopped));
}

test "a stopped stage refuses every transition" {
    try testing.expect(!Stage.stopped.can_transition_to(.created));
    try testing.expect(!Stage.stopped.can_transition_to(.configured));
    try testing.expect(!Stage.stopped.can_transition_to(.running));
    try testing.expect(!Stage.stopped.can_transition_to(.stopped));
    try testing.expect(!Stage.stopped.can_transition_to(.stopping));
}

test "a stopping stage refuses every other transition" {
    try testing.expect(!Stage.stopping.can_transition_to(.created));
    try testing.expect(!Stage.stopping.can_transition_to(.configured));
    try testing.expect(!Stage.stopping.can_transition_to(.running));
    try testing.expect(!Stage.stopping.can_transition_to(.stopping));
}

test "a fresh lifecycle starts in the created stage" {
    const lifecycle = Lifecycle.init();

    try testing.expectEqual(Stage.created, lifecycle.stage);
}

test "a lifecycle reports whether it is configured" {
    var lifecycle = Lifecycle.init();

    try testing.expect(!lifecycle.is_configured());

    _ = lifecycle.transition(.configured);

    try testing.expect(lifecycle.is_configured());
}

test "a lifecycle reports whether it is running" {
    var lifecycle = Lifecycle.init();

    try testing.expect(!lifecycle.is_running());

    _ = lifecycle.transition(.configured);
    _ = lifecycle.transition(.running);

    try testing.expect(lifecycle.is_running());
}

test "a lifecycle reports whether it is stopped" {
    var lifecycle = Lifecycle.init();

    try testing.expect(!lifecycle.is_stopped());

    _ = lifecycle.transition(.configured);
    _ = lifecycle.transition(.running);
    _ = lifecycle.transition(.stopping);
    _ = lifecycle.transition(.stopped);

    try testing.expect(lifecycle.is_stopped());
}

test "a lifecycle accepts a legal transition" {
    var lifecycle = Lifecycle.init();

    try testing.expect(lifecycle.transition(.configured));
    try testing.expectEqual(Stage.configured, lifecycle.stage);

    try testing.expect(lifecycle.transition(.running));
    try testing.expectEqual(Stage.running, lifecycle.stage);

    try testing.expect(lifecycle.transition(.stopping));
    try testing.expectEqual(Stage.stopping, lifecycle.stage);

    try testing.expect(lifecycle.transition(.stopped));
    try testing.expectEqual(Stage.stopped, lifecycle.stage);
}

test "a lifecycle refuses an illegal transition" {
    var lifecycle = Lifecycle.init();

    try testing.expect(!lifecycle.transition(.running));
    try testing.expectEqual(Stage.created, lifecycle.stage);

    try testing.expect(!lifecycle.transition(.stopped));
    try testing.expectEqual(Stage.created, lifecycle.stage);
}

test "a refused transition leaves the stage alone" {
    var lifecycle = Lifecycle.init();

    _ = lifecycle.transition(.configured);

    try testing.expect(!lifecycle.transition(.stopped));
    try testing.expectEqual(Stage.configured, lifecycle.stage);
}

test "Lifecycle full valid transition sequence" {
    var lifecycle = Lifecycle.init();

    try testing.expectEqual(Stage.created, lifecycle.stage);
    try testing.expect(!lifecycle.is_configured());
    try testing.expect(!lifecycle.is_running());
    try testing.expect(!lifecycle.is_stopped());

    try testing.expect(lifecycle.transition(.configured));
    try testing.expect(lifecycle.is_configured());

    try testing.expect(lifecycle.transition(.running));
    try testing.expect(lifecycle.is_running());

    try testing.expect(lifecycle.transition(.stopping));
    try testing.expect(!lifecycle.is_running());

    try testing.expect(lifecycle.transition(.stopped));
    try testing.expect(lifecycle.is_stopped());
}
