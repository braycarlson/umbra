const std = @import("std");

const w32 = @import("../win32.zig");

const change_processor = @import("processor.zig");
const path_module = @import("path.zig");

const assert = std.debug.assert;

const Path = path_module.Path;
const path_max = path_module.path_max;

const Monitor = @This();

callback: ?Callback = null,
context: ?*anyopaque = null,
directory: ?Directory = null,
failed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
path: Path = .{},
running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
stop_event: ?ResetEvent = null,
thread: ?std.Thread = null,

pub const Callback = change_processor.Callback;

pub const Error = path_module.Error || error{
    AlreadyWatching,
    DirectoryOpenFailed,
    EventCreationFailed,
    ThreadSpawnFailed,
};

const iteration_loop_max: u32 = 0xFFFFFFFF;
const delay_error_ms: u64 = 100;
const notify_filter: u32 = w32.FILE_NOTIFY_CHANGE_FILE_NAME | w32.FILE_NOTIFY_CHANGE_LAST_WRITE;

pub fn init() Monitor {
    const result = Monitor{};

    assert(!result.running.load(.acquire));
    assert(result.thread == null);

    return result;
}

pub fn deinit(monitor: *Monitor) void {
    monitor.stop();

    assert(!monitor.running.load(.acquire));
}

pub fn has_failed(monitor: *const Monitor) bool {
    return monitor.failed.load(.acquire);
}

pub fn is_running(monitor: *const Monitor) bool {
    return monitor.running.load(.acquire);
}

pub fn stop(monitor: *Monitor) void {
    monitor.running.store(false, .release);

    if (monitor.stop_event) |event| {
        _ = event.set();
    }

    if (monitor.thread) |thread| {
        thread.join();
        monitor.thread = null;
    }

    monitor.deinit_directory();
    monitor.destroy_event();

    assert(!monitor.running.load(.acquire));
    assert(monitor.thread == null);
    assert(monitor.directory == null);
}

pub fn watch(
    monitor: *Monitor,
    input: []const u8,
    callback: Callback,
    context: *anyopaque,
) Error!void {
    assert(input.len < path_max);

    if (monitor.running.load(.acquire)) {
        return Error.AlreadyWatching;
    }

    monitor.failed.store(false, .release);

    monitor.path = try Path.parse(input);
    monitor.callback = callback;
    monitor.context = context;
    monitor.stop_event = try ResetEvent.create();
    errdefer monitor.destroy_event();

    monitor.directory = try Directory.open(monitor.path.get_directory());
    errdefer monitor.deinit_directory();

    monitor.running.store(true, .release);
    errdefer monitor.running.store(false, .release);

    monitor.thread = std.Thread.spawn(.{}, loop, .{monitor}) catch {
        return Error.ThreadSpawnFailed;
    };

    assert(monitor.running.load(.acquire));
    assert(monitor.thread != null);
}

fn deinit_directory(monitor: *Monitor) void {
    if (monitor.directory) |dir| {
        _ = dir.close();
        monitor.directory = null;
    }

    assert(monitor.directory == null);
}

fn destroy_event(monitor: *Monitor) void {
    if (monitor.stop_event) |event| {
        _ = event.destroy();
        monitor.stop_event = null;
    }

    assert(monitor.stop_event == null);
}

fn loop(monitor: *Monitor) void {
    const io_event = ResetEvent.create() catch {
        monitor.failed.store(true, .release);
        monitor.running.store(false, .release);

        return;
    };

    defer _ = io_event.destroy();

    const buffer_align = @alignOf(w32.FILE_NOTIFY_INFORMATION);

    var buffer: [change_processor.size_buffer]u8 align(buffer_align) = undefined;
    var overlapped: w32.OVERLAPPED = std.mem.zeroes(w32.OVERLAPPED);

    overlapped.hEvent = io_event.handle;

    var iteration: u32 = 0;

    while (iteration < iteration_loop_max) : (iteration += 1) {
        if (!monitor.running.load(.acquire)) {
            break;
        }

        const directory = monitor.directory orelse break;
        const stop_event = monitor.stop_event orelse break;

        const result = wait(
            &directory,
            &stop_event,
            &io_event,
            &buffer,
            &overlapped,
            &monitor.running,
        );

        switch (result) {
            .stopped => break,
            .failed => {
                w32.Sleep(@intCast(delay_error_ms));

                continue;
            },
            .complete => {},
        }

        var count: u32 = 0;

        const status = w32.GetOverlappedResult(directory.handle, &overlapped, &count, w32.FALSE);
        if (status == 0) continue;
        if (count == 0) continue;

        assert(count > 0);

        const callback = monitor.callback orelse continue;
        const context = monitor.context orelse continue;
        const target = monitor.path.get_filename();

        change_processor.process(&buffer, count, target, callback, context);
    }

    assert(iteration <= iteration_loop_max);
}

const flag_backup_semantics: u32 = 0x02000000;
const flag_overlapped: u32 = 0x40000000;
const access_list_directory: u32 = 0x0001;

pub const Directory = struct {
    handle: w32.HANDLE,

    pub fn open(path: []const u8) Error!Directory {
        if (path.len == 0) return Error.InvalidPath;
        if (path.len >= path_max) return Error.InvalidPath;

        var wide: [path_max]u16 = undefined;

        const length = std.unicode.utf8ToUtf16Le(&wide, path) catch {
            return Error.InvalidPath;
        };

        assert(length > 0);
        assert(length < path_max);

        if (length == 0) return Error.InvalidPath;
        if (length >= path_max) return Error.InvalidPath;

        wide[length] = 0;

        const handle = w32.CreateFileW(
            @ptrCast(&wide),
            access_list_directory,
            w32.FILE_SHARE_DELETE | w32.FILE_SHARE_READ | w32.FILE_SHARE_WRITE,
            null,
            w32.OPEN_EXISTING,
            flag_backup_semantics | flag_overlapped,
            null,
        );

        if (handle == w32.INVALID_HANDLE_VALUE) {
            return Error.DirectoryOpenFailed;
        }

        assert(handle != w32.INVALID_HANDLE_VALUE);

        const result = Directory{ .handle = handle };

        return result;
    }

    pub fn close(directory: *const Directory) bool {
        assert(directory.is_valid());

        const status = w32.CloseHandle(directory.handle);
        return status != 0;
    }

    pub fn is_valid(directory: *const Directory) bool {
        return directory.handle != w32.INVALID_HANDLE_VALUE;
    }
};

pub const ResetEvent = struct {
    handle: w32.HANDLE,

    pub fn create() Error!ResetEvent {
        const handle = w32.CreateEventW(null, w32.TRUE, w32.FALSE, null);

        if (handle == null) {
            return Error.EventCreationFailed;
        }

        assert(handle != null);

        const result = ResetEvent{ .handle = handle.? };

        return result;
    }

    pub fn destroy(event: *const ResetEvent) bool {
        assert(event.is_valid());

        const status = w32.CloseHandle(event.handle);
        return status != 0;
    }

    pub fn is_valid(event: *const ResetEvent) bool {
        const address = @intFromPtr(event.handle);
        return address != 0;
    }

    pub fn reset(event: *const ResetEvent) bool {
        assert(event.is_valid());

        const status = w32.ResetEvent(event.handle);
        return status != 0;
    }

    pub fn set(event: *const ResetEvent) bool {
        assert(event.is_valid());

        const status = w32.SetEvent(event.handle);
        return status != 0;
    }
};

pub const wait_max: u8 = 2;
pub const wait_handle_count: u32 = 2;

comptime {
    assert(wait_handle_count == 2);
}

pub const WaitResult = enum(u8) {
    complete = 0,
    failed = 1,
    stopped = 2,

    pub fn is_valid(result: WaitResult) bool {
        const value = @backingInt(result);
        return value <= wait_max;
    }
};

pub fn wait(
    directory: *const Directory,
    stop_event: *const ResetEvent,
    io_event: *const ResetEvent,
    buffer: *align(@alignOf(w32.FILE_NOTIFY_INFORMATION)) [change_processor.size_buffer]u8,
    overlapped: *w32.OVERLAPPED,
    running: *const std.atomic.Value(bool),
) WaitResult {
    assert(directory.is_valid());
    assert(stop_event.is_valid());
    assert(io_event.is_valid());
    assert(buffer.len == change_processor.size_buffer);

    _ = io_event.reset();

    const read_status = w32.ReadDirectoryChangesW(
        directory.handle,
        buffer,
        buffer.len,
        w32.FALSE,
        notify_filter,
        null,
        overlapped,
        null,
    );

    if (read_status == 0) {
        const err = w32.GetLastError();

        if (err != w32.ERROR_IO_PENDING) {
            if (!running.load(.acquire)) {
                return .stopped;
            }

            return .failed;
        }
    }

    const handles = [wait_handle_count]w32.HANDLE{ io_event.handle, stop_event.handle };

    const wait_status = w32.WaitForMultipleObjects(
        wait_handle_count,
        &handles,
        w32.FALSE,
        w32.INFINITE,
    );

    const object_0 = w32.WAIT_OBJECT_0;

    if (wait_status == object_0 + 1) {
        _ = w32.CancelIo(directory.handle);

        return .stopped;
    }

    if (wait_status != object_0) {
        if (!running.load(.acquire)) {
            return .stopped;
        }

        return .failed;
    }

    assert(wait_status == object_0);

    return .complete;
}

const testing = std.testing;

test "a fresh monitor starts stopped" {
    const monitor = Monitor.init();

    try testing.expect(!monitor.is_running());
    try testing.expect(!monitor.has_failed());
    try testing.expect(monitor.thread == null);
    try testing.expect(monitor.directory == null);
    try testing.expect(monitor.stop_event == null);
    try testing.expect(monitor.callback == null);
}

test "a fresh monitor is not running" {
    const monitor = Monitor.init();

    try testing.expect(!monitor.is_running());
}

test "stopping a stopped monitor is inert" {
    var monitor = Monitor.init();

    monitor.stop();

    try testing.expect(!monitor.is_running());
    try testing.expect(monitor.thread == null);
}

test "tearing down a monitor clears its state" {
    var monitor = Monitor.init();

    monitor.deinit();

    try testing.expect(!monitor.is_running());
}

test "a monitor rejects an empty path" {
    var monitor = Monitor.init();
    defer monitor.deinit();

    var context: u32 = 0;

    const callback = struct {
        fn cb(_: *anyopaque) void {}
    }.cb;

    const result = monitor.watch("", callback, &context);

    try testing.expectError(Error.InvalidPath, result);
}

test "a monitor rejects a path with no directory" {
    var monitor = Monitor.init();
    defer monitor.deinit();

    var context: u32 = 0;

    const callback = struct {
        fn cb(_: *anyopaque) void {}
    }.cb;

    const result = monitor.watch("filename_only", callback, &context);

    try testing.expectError(Error.InvalidPath, result);
}

test "Monitor callback type is valid" {
    const callback_info = @typeInfo(Callback);

    try testing.expect(callback_info == .pointer);
}

test "an invalid directory handle reports as invalid" {
    const directory = Directory{ .handle = w32.INVALID_HANDLE_VALUE };

    try testing.expect(!directory.is_valid());
}

test "opening an empty directory path is rejected" {
    const result = Directory.open("");

    try testing.expectError(Error.InvalidPath, result);
}

test "opening an oversized directory path is rejected" {
    var long_path: [path_max + 1]u8 = undefined;
    var index: u32 = 0;

    while (index < path_max + 1) : (index += 1) {
        assert(index < path_max + 1);

        long_path[index] = 'a';
    }

    const result = Directory.open(&long_path);

    try testing.expectError(Error.InvalidPath, result);
}

test "path_max constant value" {
    try testing.expectEqual(@as(u32, 512), path_max);
}

test "a valid event handle reports as valid" {
    const event = ResetEvent{ .handle = @ptrFromInt(0x12345678) };

    try testing.expect(event.is_valid());
}

test "WaitResult enum values" {
    try testing.expectEqual(@as(u8, 0), @backingInt(WaitResult.complete));
    try testing.expectEqual(@as(u8, 1), @backingInt(WaitResult.failed));
    try testing.expectEqual(@as(u8, 2), @backingInt(WaitResult.stopped));
}

test "every wait result variant is valid" {
    try testing.expect(WaitResult.complete.is_valid());
    try testing.expect(WaitResult.failed.is_valid());
    try testing.expect(WaitResult.stopped.is_valid());
}

test "wait_max constant value" {
    try testing.expectEqual(@as(u8, 2), wait_max);
}

fn on_swap(context: *anyopaque) void {
    const fired: *std.atomic.Value(u32) = @ptrCast(@alignCast(context));

    _ = fired.fetchAdd(1, .seq_cst);
}

fn wait_fired(fired: *const std.atomic.Value(u32), attempts: u32) bool {
    assert(attempts > 0);

    var attempt: u32 = 0;

    while (attempt < attempts) : (attempt += 1) {
        if (fired.load(.seq_cst) > 0) return true;

        w32.Sleep(10);
    }

    return fired.load(.seq_cst) > 0;
}

test "a replace through a rename reaches the callback" {
    const io = testing.io;

    var temporary = testing.tmpDir(.{});
    defer temporary.cleanup();

    var real: [path_max]u8 = undefined;
    const length = try temporary.dir.realPath(io, &real);

    var buffer: [path_max]u8 = undefined;
    const target = try std.mem.print(&buffer, "{s}\\config.zon", .{real[0..length]});

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "first" });

    var swap_fired = std.atomic.Value(u32).init(0);
    var monitor = Monitor.init();
    defer monitor.deinit();

    try monitor.watch(target, on_swap, &swap_fired);

    var armed = false;
    var attempt: u32 = 0;

    while (attempt < 100) : (attempt += 1) {
        try temporary.dir.writeFile(io, .{ .sub_path = "config.zon", .data = "armed" });

        armed = wait_fired(&swap_fired, 10);

        if (armed) break;
    }

    try testing.expect(armed);

    w32.Sleep(300);
    swap_fired.store(0, .seq_cst);

    try temporary.dir.writeFile(io, .{ .sub_path = "config.zon.swap", .data = "second" });
    try temporary.dir.rename("config.zon.swap", temporary.dir, "config.zon", io);
    try testing.expect(wait_fired(&swap_fired, 200));
}
