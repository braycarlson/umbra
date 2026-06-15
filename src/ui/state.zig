const std = @import("std");

const w32 = @import("win32").everything;

const event = @import("../event/root.zig");
const runtime = @import("../runtime/root.zig");

const Event = event.Event;
const Service = runtime.Service;

pub const history_max: u8 = 8;
pub const state_max: u8 = 32;

pub const Error = error{
    InvalidState,
};

pub const Transition = struct {
    from: []const u8,
    timestamp_ms: i64,
    to: []const u8,
};

pub const StateManager = struct {
    current: [state_max]u8,
    current_len: u8,
    history: [history_max]Transition,
    history_count: u8,
    history_index: u8,
    previous: [state_max]u8,
    previous_len: u8,
    service: ?*Service,

    pub fn init() StateManager {
        const result = StateManager{
            .current = [_]u8{0} ** state_max,
            .current_len = 0,
            .history = undefined,
            .history_count = 0,
            .history_index = 0,
            .previous = [_]u8{0} ** state_max,
            .previous_len = 0,
            .service = null,
        };

        std.debug.assert(result.current_len == 0);
        std.debug.assert(result.history_count == 0);

        return result;
    }

    pub fn deinit(self: *StateManager) void {
        self.service = null;
        self.current_len = 0;
        self.previous_len = 0;
        self.history_count = 0;
        self.history_index = 0;
    }

    pub fn bind(self: *StateManager, service: *Service) void {
        self.service = service;

        std.debug.assert(self.service != null);
    }

    pub fn clear_history(self: *StateManager) void {
        self.history_count = 0;
        self.history_index = 0;

        std.debug.assert(self.history_count == 0);
        std.debug.assert(self.history_index == 0);
    }

    pub fn equals(self: *const StateManager, target: []const u8) bool {
        if (target.len != self.current_len) {
            return false;
        }

        const result = std.mem.eql(u8, self.current[0..self.current_len], target);

        return result;
    }

    pub fn get(self: *const StateManager) []const u8 {
        std.debug.assert(self.current_len <= state_max);

        const result = self.current[0..self.current_len];

        return result;
    }

    pub fn get_history(self: *const StateManager) []const Transition {
        std.debug.assert(self.history_count <= history_max);

        const result = self.history[0..self.history_count];

        return result;
    }

    pub fn get_previous(self: *const StateManager) []const u8 {
        std.debug.assert(self.previous_len <= state_max);

        const result = self.previous[0..self.previous_len];

        return result;
    }

    pub fn is_empty(self: *const StateManager) bool {
        const result = self.current_len == 0;

        return result;
    }

    pub fn is_one_of(self: *const StateManager, states: []const []const u8) bool {
        std.debug.assert(states.len > 0);

        for (states) |state| {
            if (self.equals(state)) {
                return true;
            }
        }

        return false;
    }

    pub fn set(self: *StateManager, new_state: []const u8) Error!void {
        if (new_state.len == 0 or new_state.len >= state_max) {
            return Error.InvalidState;
        }

        if (self.equals(new_state)) {
            return;
        }

        var index: u8 = 0;

        while (index < self.current_len) : (index += 1) {
            std.debug.assert(index < state_max);

            self.previous[index] = self.current[index];
        }

        self.previous_len = self.current_len;

        var new_index: u8 = 0;

        while (new_index < new_state.len) : (new_index += 1) {
            std.debug.assert(new_index < state_max);

            self.current[new_index] = new_state[new_index];
        }

        self.current_len = @intCast(new_state.len);

        std.debug.assert(self.current_len == new_state.len);

        const transition = Transition{
            .from = self.previous[0..self.previous_len],
            .timestamp_ms = @intCast(w32.GetTickCount64()),
            .to = self.current[0..self.current_len],
        };

        record_history(self, &transition);

        if (self.service) |service| {
            const e = Event.state_change(transition.from, transition.to);
            _ = service.bus.emit(&e);
        }
    }
};

fn record_history(manager: *StateManager, transition: *const Transition) void {
    std.debug.assert(manager.history_index < history_max);

    manager.history[manager.history_index] = transition.*;

    manager.history_index = (manager.history_index + 1) % history_max;

    if (manager.history_count < history_max) {
        manager.history_count += 1;
    }

    std.debug.assert(manager.history_count <= history_max);
}
