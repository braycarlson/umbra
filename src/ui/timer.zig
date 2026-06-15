const std = @import("std");

const w32 = @import("win32").everything;

const runtime = @import("../runtime/root.zig");
const win32 = @import("../win32/root.zig");

const Service = runtime.Service;
const Timer = win32.Timer;

pub const timer_max: u8 = 16;

pub const Error = error{
    CapacityExceeded,
    DuplicateId,
    NoSlotAvailable,
    NotBound,
    NotFound,
    StartFailed,
};

pub const Handle = struct {
    id: u32,
    manager: *TimerManager,

    pub fn get_tick_count(self: *const Handle) u64 {
        const result = self.manager.get_tick_count(self.id);

        return result;
    }

    pub fn reset_tick_count(self: *const Handle) void {
        self.manager.reset_tick_count(self.id);
    }

    pub fn stop(self: *const Handle) Error!void {
        try self.manager.stop(self.id);
    }
};

pub const Entry = struct {
    tick_count: u64,
    timer: Timer,

    pub fn init(options: win32.TimerOptions) Entry {
        const result = Entry{
            .tick_count = 0,
            .timer = Timer.init(options),
        };

        std.debug.assert(result.tick_count == 0);

        return result;
    }
};

pub const TimerManager = struct {
    count: u8,
    entries: [timer_max]?Entry,
    hwnd: ?w32.HWND,
    service: ?*Service,

    pub fn init() TimerManager {
        const result = TimerManager{
            .count = 0,
            .entries = [_]?Entry{null} ** timer_max,
            .hwnd = null,
            .service = null,
        };

        std.debug.assert(result.count == 0);
        std.debug.assert(result.hwnd == null);

        return result;
    }

    pub fn deinit(self: *TimerManager) void {
        self.stop_all();

        std.debug.assert(self.count == 0);
    }

    pub fn bind(self: *TimerManager, hwnd: w32.HWND) void {
        self.hwnd = hwnd;

        std.debug.assert(self.hwnd != null);
    }

    pub fn bind_service(self: *TimerManager, service: *Service) void {
        self.service = service;

        std.debug.assert(self.service != null);
    }

    pub fn get_tick_count(self: *const TimerManager, id: u32) u64 {
        const index = find_index(self, id) orelse return 0;

        std.debug.assert(index < timer_max);

        if (self.entries[index]) |*entry| {
            return entry.tick_count;
        }

        return 0;
    }

    pub fn handle_tick(self: *TimerManager, timer_id: u32) void {
        const index = find_index(self, timer_id) orelse return;

        std.debug.assert(index < timer_max);

        if (self.entries[index]) |*entry| {
            entry.tick_count += 1;
        }
    }

    pub fn is_bound(self: *const TimerManager) bool {
        const result = self.hwnd != null;

        return result;
    }

    pub fn is_running(self: *const TimerManager, id: u32) bool {
        const index = find_index(self, id) orelse return false;

        std.debug.assert(index < timer_max);

        if (self.entries[index]) |*entry| {
            return entry.timer.is_running();
        }

        return false;
    }

    pub fn reset_tick_count(self: *TimerManager, id: u32) void {
        const index = find_index(self, id) orelse return;

        std.debug.assert(index < timer_max);

        if (self.entries[index]) |*entry| {
            entry.tick_count = 0;
        }
    }

    pub fn start(self: *TimerManager, id: u32, interval_ms: u32) Error!Handle {
        std.debug.assert(interval_ms > 0);

        if (self.hwnd == null) {
            return Error.NotBound;
        }

        if (self.count >= timer_max) {
            return Error.CapacityExceeded;
        }

        if (find_index(self, id) != null) {
            return Error.DuplicateId;
        }

        const slot_index = find_empty_slot(self);

        if (slot_index == null) {
            return Error.NoSlotAvailable;
        }

        std.debug.assert(slot_index.? < timer_max);

        var entry = Entry.init(.{
            .hwnd = self.hwnd,
            .id = id,
            .interval_ms = interval_ms,
        });

        entry.timer.start() catch {
            return Error.StartFailed;
        };

        self.entries[slot_index.?] = entry;
        self.count += 1;

        std.debug.assert(self.count <= timer_max);

        const result = Handle{
            .id = id,
            .manager = self,
        };

        return result;
    }

    pub fn stop(self: *TimerManager, id: u32) Error!void {
        const index = find_index(self, id) orelse return Error.NotFound;

        std.debug.assert(index < timer_max);

        if (self.entries[index]) |*entry| {
            entry.timer.stop() catch {};

            self.entries[index] = null;

            std.debug.assert(self.count > 0);

            self.count -= 1;
        }
    }

    pub fn stop_all(self: *TimerManager) void {
        var index: u8 = 0;

        while (index < timer_max) : (index += 1) {
            if (self.entries[index]) |*entry| {
                entry.timer.stop() catch {};

                self.entries[index] = null;
            }
        }

        self.count = 0;

        std.debug.assert(self.count == 0);
    }
};

fn find_empty_slot(manager: *const TimerManager) ?u8 {
    var index: u8 = 0;

    while (index < timer_max) : (index += 1) {
        if (manager.entries[index] == null) {
            return index;
        }
    }

    return null;
}

fn find_index(manager: *const TimerManager, id: u32) ?u8 {
    var index: u8 = 0;

    while (index < timer_max) : (index += 1) {
        if (manager.entries[index]) |*entry| {
            if (entry.timer.id == id) {
                return index;
            }
        }
    }

    return null;
}
