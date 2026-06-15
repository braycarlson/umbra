const std = @import("std");

const w32 = @import("win32").everything;

const timer_all_access: u32 = 0x001F0003;
const interval_max: u32 = 0x7FFFFFFF;
const ns_per_100ns: i64 = 10000;
const ns_per_second: f64 = 1_000_000_000.0;
const ns_to_ms: u64 = 1_000_000;
const ns_to_us: u64 = 1000;
const frequency_to_ns: i64 = 1_000_000_000;

pub const State = enum(u8) {
    running = 0,
    stopped = 1,
};

pub const Options = struct {
    coalesce_tolerance_ms: u32 = 0,
    hwnd: ?w32.HWND = null,
    id: u32,
    interval_ms: u32 = 1000,
};

pub const Error = error{
    CreateFailed,
    StopFailed,
};

pub const Timer = struct {
    hwnd: ?w32.HWND,
    id: u32,
    interval_ms: u32,
    state: State,

    pub fn init(options: Options) Timer {
        std.debug.assert(options.interval_ms > 0);
        std.debug.assert(options.interval_ms <= interval_max);

        const result = Timer{
            .hwnd = options.hwnd,
            .id = options.id,
            .interval_ms = options.interval_ms,
            .state = .stopped,
        };

        std.debug.assert(result.state == .stopped);

        return result;
    }

    pub fn is_running(self: *const Timer) bool {
        const result = self.state == .running;

        return result;
    }

    pub fn restart(self: *Timer) Error!void {
        std.debug.assert(self.interval_ms > 0);

        if (self.state == .running) {
            try self.stop();
        }

        try self.start();

        std.debug.assert(self.state == .running);
    }

    pub fn set_interval(self: *Timer, interval_ms: u32) Error!void {
        std.debug.assert(interval_ms > 0);
        std.debug.assert(interval_ms <= interval_max);

        self.interval_ms = interval_ms;

        if (self.state == .running) {
            const status = w32.SetTimer(self.hwnd, self.id, interval_ms, null);

            if (status == 0) {
                return Error.CreateFailed;
            }
        }

        std.debug.assert(self.interval_ms == interval_ms);
    }

    pub fn start(self: *Timer) Error!void {
        std.debug.assert(self.interval_ms > 0);

        if (self.state == .running) {
            return;
        }

        const status = w32.SetTimer(self.hwnd, self.id, self.interval_ms, null);

        if (status == 0) {
            return Error.CreateFailed;
        }

        self.state = .running;

        std.debug.assert(self.state == .running);
    }

    pub fn stop(self: *Timer) Error!void {
        if (self.state != .running) {
            return;
        }

        const status = w32.KillTimer(self.hwnd, self.id);

        self.state = .stopped;

        std.debug.assert(self.state == .stopped);

        if (status == 0) {
            return Error.StopFailed;
        }
    }
};

pub const WaitableTimerOptions = struct {
    high_resolution: bool = false,
    manual_reset: bool = true,
    name: ?[]const u8 = null,
};

pub const WaitableTimerSetOptions = struct {
    due_time_100ns: i64 = 0,
    period_ms: i32 = 0,
    resume_from_suspend: bool = false,
    tolerance_ms: u32 = 0,
};

pub const WaitResult = enum(u8) {
    abandoned = 0,
    failed = 1,
    signaled = 2,
    timeout = 3,
};

pub const WaitableTimer = struct {
    handle: w32.HANDLE,

    pub fn create(options: WaitableTimerOptions) Error!WaitableTimer {
        var name_wide: [256]u16 = undefined;
        var name_pointer: ?[*:0]const u16 = null;

        if (options.name) |name| {
            std.debug.assert(name.len > 0);
            std.debug.assert(name.len < 256);

            const length = std.unicode.utf8ToUtf16Le(&name_wide, name) catch 0;

            name_wide[length] = 0;
            name_pointer = @ptrCast(&name_wide);
        }

        var flags: w32.CREATE_WAITABLE_TIMER_FLAGS = .{};

        if (options.manual_reset) {
            flags.MANUAL_RESET = 1;
        }

        if (options.high_resolution) {
            flags.HIGH_RESOLUTION = 1;
        }

        const handle = w32.CreateWaitableTimerExW(null, name_pointer, flags, timer_all_access);

        if (handle == null) {
            return Error.CreateFailed;
        }

        std.debug.assert(handle != null);

        const result = WaitableTimer{
            .handle = handle.?,
        };

        return result;
    }

    pub fn cancel(self: *const WaitableTimer) bool {
        const result = w32.CancelWaitableTimer(self.handle) != 0;

        return result;
    }

    pub fn close(self: *const WaitableTimer) void {
        _ = w32.CloseHandle(self.handle);
    }

    pub fn set(self: *const WaitableTimer, options: WaitableTimerSetOptions) bool {
        var due_time: w32.LARGE_INTEGER = undefined;

        due_time.QuadPart = options.due_time_100ns;

        if (options.tolerance_ms > 0) {
            const result = w32.SetWaitableTimerEx(
                self.handle,
                &due_time,
                options.period_ms,
                null,
                null,
                null,
                options.tolerance_ms,
            ) != 0;

            return result;
        }

        const result = w32.SetWaitableTimer(
            self.handle,
            &due_time,
            options.period_ms,
            null,
            null,
            if (options.resume_from_suspend) w32.TRUE else w32.FALSE,
        ) != 0;

        return result;
    }

    pub fn set_periodic_ms(self: *const WaitableTimer, initial_ms: u32, period_ms: i32) bool {
        std.debug.assert(initial_ms > 0);

        const result = self.set(WaitableTimerSetOptions{
            .due_time_100ns = -@as(i64, @intCast(initial_ms)) * ns_per_100ns,
            .period_ms = period_ms,
        });

        return result;
    }

    pub fn set_relative_ms(self: *const WaitableTimer, milliseconds: u32) bool {
        std.debug.assert(milliseconds > 0);

        const result = self.set(WaitableTimerSetOptions{
            .due_time_100ns = -@as(i64, @intCast(milliseconds)) * ns_per_100ns,
        });

        return result;
    }

    pub fn wait(self: *const WaitableTimer, timeout_ms: ?u32) WaitResult {
        const timeout = timeout_ms orelse w32.INFINITE;

        const result = switch (w32.WaitForSingleObject(self.handle, timeout)) {
            w32.WAIT_OBJECT_0 => WaitResult.signaled,
            @intFromEnum(w32.WAIT_TIMEOUT) => WaitResult.timeout,
            @intFromEnum(w32.WAIT_ABANDONED) => WaitResult.abandoned,
            else => WaitResult.failed,
        };

        return result;
    }
};

pub const PerformanceCounter = struct {
    frequency: i64,
    start: i64,

    pub fn init() ?PerformanceCounter {
        var frequency: w32.LARGE_INTEGER = undefined;

        if (w32.QueryPerformanceFrequency(&frequency) == 0) {
            return null;
        }

        std.debug.assert(frequency.QuadPart > 0);

        var start: w32.LARGE_INTEGER = undefined;

        if (w32.QueryPerformanceCounter(&start) == 0) {
            return null;
        }

        std.debug.assert(start.QuadPart >= 0);

        const result = PerformanceCounter{
            .frequency = frequency.QuadPart,
            .start = start.QuadPart,
        };

        return result;
    }

    pub fn elapsed_ms(self: *const PerformanceCounter) u64 {
        std.debug.assert(self.frequency > 0);

        const result = self.elapsed_ns() / ns_to_ms;

        return result;
    }

    pub fn elapsed_ns(self: *const PerformanceCounter) u64 {
        std.debug.assert(self.frequency > 0);

        var counter: w32.LARGE_INTEGER = undefined;

        if (w32.QueryPerformanceCounter(&counter) == 0) {
            return 0;
        }

        const elapsed = counter.QuadPart - self.start;

        std.debug.assert(elapsed >= 0);

        const result: u64 = @intCast(@divFloor(elapsed * frequency_to_ns, self.frequency));

        return result;
    }

    pub fn elapsed_sec(self: *const PerformanceCounter) f64 {
        std.debug.assert(self.frequency > 0);

        const result = @as(f64, @floatFromInt(self.elapsed_ns())) / ns_per_second;

        return result;
    }

    pub fn elapsed_us(self: *const PerformanceCounter) u64 {
        std.debug.assert(self.frequency > 0);

        const result = self.elapsed_ns() / ns_to_us;

        return result;
    }

    pub fn reset(self: *PerformanceCounter) void {
        var counter: w32.LARGE_INTEGER = undefined;

        if (w32.QueryPerformanceCounter(&counter) != 0) {
            self.start = counter.QuadPart;
        }
    }
};

pub fn get_tick_count() u32 {
    const result = w32.GetTickCount();

    return result;
}

pub fn get_tick_count_64() u64 {
    const result = w32.GetTickCount64();

    return result;
}

pub fn sleep(milliseconds: u32) void {
    std.debug.assert(milliseconds <= interval_max);

    w32.Sleep(milliseconds);
}
