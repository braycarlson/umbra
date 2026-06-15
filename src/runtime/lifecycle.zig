const std = @import("std");

pub const Stage = enum(u8) {
    created = 0,
    configured = 1,
    running = 2,
    stopped = 3,
    stopping = 4,

    pub fn can_transition_to(self: Stage, target: Stage) bool {
        const result = switch (self) {
            .created => target == .configured,
            .configured => target == .running,
            .running => target == .stopping,
            .stopped => false,
            .stopping => target == .stopped,
        };

        return result;
    }
};

pub const Lifecycle = struct {
    stage: Stage,

    pub fn init() Lifecycle {
        const result = Lifecycle{
            .stage = .created,
        };

        std.debug.assert(result.stage == .created);

        return result;
    }

    pub fn is_configured(self: *const Lifecycle) bool {
        const result = self.stage == .configured;

        return result;
    }

    pub fn is_running(self: *const Lifecycle) bool {
        const result = self.stage == .running;

        return result;
    }

    pub fn is_stopped(self: *const Lifecycle) bool {
        const result = self.stage == .stopped;

        return result;
    }

    pub fn transition(self: *Lifecycle, target: Stage) bool {
        if (!self.stage.can_transition_to(target)) {
            return false;
        }

        self.stage = target;

        std.debug.assert(self.stage == target);

        return true;
    }

    pub fn force_stop(self: *Lifecycle) void {
        self.stage = .stopped;

        std.debug.assert(self.stage == .stopped);
    }
};
