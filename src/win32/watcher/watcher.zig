const std = @import("std");

const w32 = @import("win32").everything;

const change_processor = @import("processor.zig");
const directory_mod = @import("directory.zig");
const io_waiter = @import("waiter.zig");
const path_mod = @import("path.zig");
const signal_mod = @import("signal.zig");

const Directory = directory_mod.Directory;
const Path = path_mod.Path;
const Signal = signal_mod.Signal;

pub const Callback = change_processor.Callback;

pub const Error = path_mod.Error || directory_mod.Error || signal_mod.Error || error{
    ThreadSpawnFailed,
};

const iteration_loop_max: u32 = 0xFFFFFFFF;
const error_delay_ms: u64 = 100;
const ns_delay_error: u64 = error_delay_ms * std.time.ns_per_ms;

pub const Watcher = struct {
    callback: ?Callback = null,
    directory: ?Directory = null,
    path: Path = .{},
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    signal_stop: ?Signal = null,
    thread: ?std.Thread = null,

    pub fn init() Watcher {
        const result = Watcher{};

        std.debug.assert(!result.running.load(.acquire));
        std.debug.assert(result.thread == null);

        return result;
    }

    pub fn deinit(self: *Watcher) void {
        std.debug.assert(@intFromPtr(self) != 0);

        self.stop();

        std.debug.assert(!self.running.load(.acquire));
    }

    pub fn is_running(self: *const Watcher) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const result = self.running.load(.acquire);

        return result;
    }

    pub fn stop(self: *Watcher) void {
        std.debug.assert(@intFromPtr(self) != 0);

        if (!self.running.load(.acquire)) {
            return;
        }

        self.running.store(false, .release);

        if (self.signal_stop) |signal| {
            _ = signal.set();
        }

        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }

        deinit_directory(self);
        destroy_signal(self);

        std.debug.assert(!self.running.load(.acquire));
        std.debug.assert(self.thread == null);
    }

    pub fn watch(self: *Watcher, input: []const u8, callback: Callback) Error!void {
        std.debug.assert(@intFromPtr(self) != 0);
        std.debug.assert(@intFromPtr(callback) != 0);

        if (self.running.load(.acquire)) {
            return;
        }

        self.path = try Path.parse(input);
        self.callback = callback;
        self.signal_stop = try Signal.create();

        errdefer destroy_signal(self);

        self.directory = try Directory.open(self.path.get_directory());

        errdefer deinit_directory(self);

        self.running.store(true, .release);

        self.thread = std.Thread.spawn(.{}, loop, .{self}) catch {
            deinit_directory(self);
            destroy_signal(self);
            self.running.store(false, .release);

            return Error.ThreadSpawnFailed;
        };

        std.debug.assert(self.running.load(.acquire));
        std.debug.assert(self.thread != null);
    }
};

fn deinit_directory(watcher: *Watcher) void {
    std.debug.assert(@intFromPtr(watcher) != 0);

    if (watcher.directory) |dir| {
        _ = dir.close();
        watcher.directory = null;
    }

    std.debug.assert(watcher.directory == null);
}

fn destroy_signal(watcher: *Watcher) void {
    std.debug.assert(@intFromPtr(watcher) != 0);

    if (watcher.signal_stop) |signal| {
        _ = signal.destroy();
        watcher.signal_stop = null;
    }

    std.debug.assert(watcher.signal_stop == null);
}

fn loop(watcher: *Watcher) void {
    std.debug.assert(@intFromPtr(watcher) != 0);

    const signal_io = Signal.create() catch return;

    defer _ = signal_io.destroy();

    var buffer: [change_processor.size_buffer]u8 align(@alignOf(w32.FILE_NOTIFY_INFORMATION)) = undefined;
    var overlapped: w32.OVERLAPPED = std.mem.zeroes(w32.OVERLAPPED);

    overlapped.hEvent = signal_io.handle;

    var iteration: u32 = 0;

    while (iteration < iteration_loop_max) : (iteration += 1) {
        std.debug.assert(iteration < iteration_loop_max);

        if (!watcher.running.load(.acquire)) {
            break;
        }

        const directory = watcher.directory orelse break;
        const signal_stop = watcher.signal_stop orelse break;

        const result = io_waiter.wait(
            &directory,
            &signal_stop,
            &signal_io,
            &buffer,
            &overlapped,
            &watcher.running,
        );

        switch (result) {
            .stopped => break,
            .failed => {
                w32.Sleep(@intCast(error_delay_ms));

                continue;
            },
            .complete => {},
        }

        var count: u32 = 0;

        const status = w32.GetOverlappedResult(directory.handle, &overlapped, &count, w32.FALSE);

        if (status == 0 or count == 0) {
            continue;
        }

        std.debug.assert(count > 0);

        if (watcher.callback) |callback| {
            change_processor.process(&buffer, count, watcher.path.get_filename(), callback);
        }
    }

    std.debug.assert(iteration <= iteration_loop_max);
}
