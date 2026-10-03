const std = @import("std");

const event = @import("../event/root.zig");
const platform = @import("../platform.zig");

const assert = std.debug.assert;

const Bus = event.Bus;
const Event = event.Event;

pub const history_max: u8 = 8;
pub const state_max: u32 = 32;

pub const Error = error{
    InvalidState,
};

pub const Transition = struct {
    from: []const u8,
    timestamp_ms: u64,
    to: []const u8,
};

const Record = struct {
    from: [state_max]u8,
    from_len: u8,
    timestamp_ms: u64,
    to: [state_max]u8,
    to_len: u8,
};

pub const StateManager = struct {
    current: [state_max]u8,
    current_len: u8,
    history: [history_max]Record,
    history_count: u8,
    history_index: u8,
    previous: [state_max]u8,
    previous_len: u8,
    bus: ?*Bus,

    pub fn init() StateManager {
        const result = StateManager{
            .current = @splat(0),
            .current_len = 0,
            .history = undefined,
            .history_count = 0,
            .history_index = 0,
            .previous = @splat(0),
            .previous_len = 0,
            .bus = null,
        };

        assert(result.current_len == 0);
        assert(result.history_count == 0);

        return result;
    }

    pub fn deinit(manager: *StateManager) void {
        manager.bus = null;
        manager.current_len = 0;
        manager.previous_len = 0;
        manager.history_count = 0;
        manager.history_index = 0;
    }

    pub fn bind(manager: *StateManager, bus: *Bus) void {
        manager.bus = bus;

        assert(manager.bus != null);
    }

    pub fn clear_history(manager: *StateManager) void {
        manager.history_count = 0;
        manager.history_index = 0;

        assert(manager.history_count == 0);
        assert(manager.history_index == 0);
    }

    pub fn equals(manager: *const StateManager, target: []const u8) bool {
        if (target.len != manager.current_len) {
            return false;
        }

        return std.mem.eql(u8, manager.current[0..manager.current_len], target);
    }

    pub fn get(manager: *const StateManager) []const u8 {
        assert(manager.current_len <= state_max);

        return manager.current[0..manager.current_len];
    }

    pub fn history_len(manager: *const StateManager) u8 {
        assert(manager.history_count <= history_max);

        return manager.history_count;
    }

    pub fn history_at(manager: *const StateManager, index: u8) ?Transition {
        assert(manager.history_count <= history_max);

        if (index >= manager.history_count) {
            return null;
        }

        const oldest: u8 = if (manager.history_count < history_max) 0 else manager.history_index;
        const slot: u8 = (oldest + index) % history_max;

        assert(slot < history_max);

        const record = &manager.history[slot];

        assert(record.from_len <= state_max);
        assert(record.to_len <= state_max);

        const result = Transition{
            .from = record.from[0..record.from_len],
            .timestamp_ms = record.timestamp_ms,
            .to = record.to[0..record.to_len],
        };

        return result;
    }

    pub fn get_previous(manager: *const StateManager) []const u8 {
        assert(manager.previous_len <= state_max);

        return manager.previous[0..manager.previous_len];
    }

    pub fn is_empty(manager: *const StateManager) bool {
        return manager.current_len == 0;
    }

    pub fn is_one_of(manager: *const StateManager, states: []const []const u8) bool {
        assert(states.len > 0);

        for (states) |state| {
            if (manager.equals(state)) {
                return true;
            }
        }

        return false;
    }

    pub fn set(manager: *StateManager, new_state: []const u8) Error!void {
        if (new_state.len == 0 or new_state.len >= state_max) {
            return Error.InvalidState;
        }

        if (manager.equals(new_state)) {
            return;
        }

        assert(manager.current_len <= state_max);

        @memcpy(manager.previous[0..manager.current_len], manager.current[0..manager.current_len]);

        manager.previous_len = manager.current_len;

        @memcpy(manager.current[0..new_state.len], new_state);

        manager.current_len = @intCast(new_state.len);

        assert(manager.current_len == new_state.len);

        record_history(manager);

        if (manager.bus) |bus| {
            const changed = Event.state_change(
                manager.previous[0..manager.previous_len],
                manager.current[0..manager.current_len],
            );

            _ = bus.emit(&changed);
        }
    }
};

fn record_history(manager: *StateManager) void {
    assert(manager.history_index < history_max);
    assert(manager.previous_len <= state_max);
    assert(manager.current_len <= state_max);

    const record = &manager.history[manager.history_index];

    @memcpy(record.from[0..manager.previous_len], manager.previous[0..manager.previous_len]);
    @memcpy(record.to[0..manager.current_len], manager.current[0..manager.current_len]);

    record.from_len = manager.previous_len;
    record.timestamp_ms = platform.backend.time.now_ms();
    record.to_len = manager.current_len;

    manager.history_index = (manager.history_index + 1) % history_max;

    if (manager.history_count < history_max) {
        manager.history_count += 1;
    }

    assert(manager.history_count <= history_max);
}

const testing = std.testing;

test "a fresh state manager holds no state" {
    const manager = StateManager.init();

    try testing.expect(manager.is_empty());
    try testing.expectEqual(@as(u8, 0), manager.current_len);
    try testing.expectEqual(@as(u8, 0), manager.previous_len);
    try testing.expectEqual(@as(u8, 0), manager.history_count);
}

test "setting a state replaces the current one" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("active");

    try testing.expect(!manager.is_empty());
    try testing.expectEqualStrings("active", manager.get());
}

test "setting a state records the one before it" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("idle");
    try manager.set("active");

    try testing.expectEqualStrings("active", manager.get());
    try testing.expectEqualStrings("idle", manager.get_previous());
}

test "setting the current state again is inert" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("active");
    try manager.set("active");

    try testing.expectEqual(@as(u8, 1), manager.history_count);
}

test "a state manager rejects an empty state" {
    var manager = StateManager.init();
    defer manager.deinit();

    const result = manager.set("");

    try testing.expectError(Error.InvalidState, result);
}

test "a state manager rejects an oversized state" {
    var manager = StateManager.init();
    defer manager.deinit();

    var long_state: [state_max]u8 = undefined;
    var index: u8 = 0;

    while (index < state_max) : (index += 1) {
        assert(index < state_max);

        long_state[index] = 'a';
    }

    const result = manager.set(&long_state);

    try testing.expectError(Error.InvalidState, result);
}

test "a state manager matches its current state" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("active");

    try testing.expect(manager.equals("active"));
}

test "a state manager does not match a different state" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("active");

    try testing.expect(!manager.equals("idle"));
}

test "a state name matches only in full" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("active");

    try testing.expect(!manager.equals("act"));
    try testing.expect(!manager.equals("activex"));
}

test "a state manager matches any of a set of states" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("running");

    const states = [_][]const u8{ "idle", "running", "stopped" };
    const result = manager.is_one_of(&states);

    try testing.expect(result);
}

test "a state manager matches none of an unrelated set" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("paused");

    const states = [_][]const u8{ "idle", "running", "stopped" };
    const result = manager.is_one_of(&states);

    try testing.expect(!result);
}

test "history entries own their bytes" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("idle");
    try manager.set("active");
    try manager.set("stopped");

    try testing.expectEqual(@as(u8, 3), manager.history_len());

    const first = manager.history_at(0).?;

    try testing.expectEqualStrings("", first.from);
    try testing.expectEqualStrings("idle", first.to);

    const second = manager.history_at(1).?;

    try testing.expectEqualStrings("idle", second.from);
    try testing.expectEqualStrings("active", second.to);

    const third = manager.history_at(2).?;

    try testing.expectEqualStrings("active", third.from);
    try testing.expectEqualStrings("stopped", third.to);

    try testing.expect(manager.history_at(3) == null);
}

test "history reads oldest first after the ring wraps" {
    var manager = StateManager.init();
    defer manager.deinit();

    var index: u8 = 0;

    while (index < history_max + 2) : (index += 1) {
        assert(index < history_max + 2);

        var name: [8]u8 = undefined;
        const formatted = try std.mem.print(&name, "s{d}", .{index});

        try manager.set(formatted);
    }

    try testing.expectEqual(history_max, manager.history_len());

    const oldest = manager.history_at(0).?;

    try testing.expectEqualStrings("s1", oldest.from);
    try testing.expectEqualStrings("s2", oldest.to);

    const newest = manager.history_at(history_max - 1).?;

    try testing.expectEqualStrings("s8", newest.from);
    try testing.expectEqualStrings("s9", newest.to);
}

test "clearing the history empties it" {
    var manager = StateManager.init();
    defer manager.deinit();

    try manager.set("idle");
    try manager.set("active");

    try testing.expect(manager.history_count > 0);

    manager.clear_history();

    try testing.expectEqual(@as(u8, 0), manager.history_count);
    try testing.expectEqual(@as(u8, 0), manager.history_index);
}

test "StateManager history wraps at max capacity" {
    var manager = StateManager.init();
    defer manager.deinit();

    var index: u8 = 0;

    while (index < history_max + 2) : (index += 1) {
        assert(index < history_max + 2);

        var name: [8]u8 = undefined;
        const formatted = std.mem.print(&name, "{d}", .{index}) catch continue;

        try manager.set(formatted);
    }

    try testing.expectEqual(history_max, manager.history_count);
}

test "tearing down a state manager resets everything" {
    var manager = StateManager.init();

    try manager.set("active");

    manager.deinit();

    try testing.expectEqual(@as(u8, 0), manager.current_len);
    try testing.expectEqual(@as(u8, 0), manager.previous_len);
    try testing.expectEqual(@as(u8, 0), manager.history_count);
}

test "StateManager transitions preserve data integrity" {
    var manager = StateManager.init();
    defer manager.deinit();

    const states = [_][]const u8{ "init", "loading", "ready", "active", "idle" };

    var index: u8 = 0;

    while (index < states.len) : (index += 1) {
        assert(index < states.len);

        try manager.set(states[index]);
        try testing.expectEqualStrings(states[index], manager.get());
    }
}
