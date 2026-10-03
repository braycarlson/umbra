const std = @import("std");

const w32 = @import("../win32.zig");

const change_processor = @import("processor.zig");
const path_mod = @import("path.zig");

const assert = std.debug.assert;

const Path = path_mod.Path;
const path_max = path_mod.path_max;

pub const Callback = change_processor.Callback;

pub const Error = path_mod.Error || error{
    AlreadyWatching,
    DirectoryOpenFailed,
    EventCreationFailed,
    ThreadSpawnFailed,
};

const iteration_loop_max: u32 = 0xFFFFFFFF;
const delay_error_ms: u64 = 100;

pub const Watcher = struct {
    callback: ?Callback = null,
    directory: ?Directory = null,
    failed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    path: Path = .{},
    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    stop_signal: ?Signal = null,
    thread: ?std.Thread = null,

    pub fn init() Watcher {
        const result = Watcher{};

        assert(!result.running.load(.acquire));
        assert(result.thread == null);

        return result;
    }

    pub fn deinit(watcher: *Watcher) void {
        watcher.stop();

        assert(!watcher.running.load(.acquire));
    }

    pub fn has_failed(watcher: *const Watcher) bool {
        return watcher.failed.load(.acquire);
    }

    pub fn is_running(watcher: *const Watcher) bool {
        return watcher.running.load(.acquire);
    }

    pub fn stop(watcher: *Watcher) void {
        watcher.running.store(false, .release);

        if (watcher.stop_signal) |signal| {
            _ = signal.set();
        }

        if (watcher.thread) |thread| {
            thread.join();
            watcher.thread = null;
        }

        deinit_directory(watcher);
        destroy_signal(watcher);

        assert(!watcher.running.load(.acquire));
        assert(watcher.thread == null);
        assert(watcher.directory == null);
    }

    pub fn watch(watcher: *Watcher, input: []const u8, callback: Callback) Error!void {
        if (watcher.running.load(.acquire)) {
            return Error.AlreadyWatching;
        }

        watcher.failed.store(false, .release);

        watcher.path = try Path.parse(input);
        watcher.callback = callback;
        watcher.stop_signal = try Signal.create();
        errdefer destroy_signal(watcher);

        watcher.directory = try Directory.open(watcher.path.get_directory());
        errdefer deinit_directory(watcher);

        watcher.running.store(true, .release);
        errdefer watcher.running.store(false, .release);

        watcher.thread = std.Thread.spawn(.{}, loop, .{watcher}) catch {
            return Error.ThreadSpawnFailed;
        };

        assert(watcher.running.load(.acquire));
        assert(watcher.thread != null);
    }
};

fn deinit_directory(watcher: *Watcher) void {
    if (watcher.directory) |dir| {
        _ = dir.close();
        watcher.directory = null;
    }

    assert(watcher.directory == null);
}

fn destroy_signal(watcher: *Watcher) void {
    if (watcher.stop_signal) |signal| {
        _ = signal.destroy();
        watcher.stop_signal = null;
    }

    assert(watcher.stop_signal == null);
}

fn loop(watcher: *Watcher) void {
    const signal_io = Signal.create() catch {
        watcher.failed.store(true, .release);
        watcher.running.store(false, .release);

        return;
    };

    defer _ = signal_io.destroy();

    const buffer_align = @alignOf(w32.FILE_NOTIFY_INFORMATION);

    var buffer: [change_processor.size_buffer]u8 align(buffer_align) = undefined;
    var overlapped: w32.OVERLAPPED = std.mem.zeroes(w32.OVERLAPPED);

    overlapped.hEvent = signal_io.handle;

    var iteration: u32 = 0;

    while (iteration < iteration_loop_max) : (iteration += 1) {
        if (!watcher.running.load(.acquire)) {
            break;
        }

        const directory = watcher.directory orelse break;
        const stop_signal = watcher.stop_signal orelse break;

        const result = wait(
            &directory,
            &stop_signal,
            &signal_io,
            &buffer,
            &overlapped,
            &watcher.running,
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

        if (status == 0 or count == 0) {
            continue;
        }

        assert(count > 0);

        if (watcher.callback) |callback| {
            change_processor.process(&buffer, count, watcher.path.get_filename(), callback);
        }
    }

    assert(iteration <= iteration_loop_max);
}

const flag_backup_semantics: u32 = 0x02000000;
const flag_overlapped: u32 = 0x40000000;
const access_list_directory: u32 = 0x0001;

pub const Directory = struct {
    handle: w32.HANDLE,

    pub fn open(path: []const u8) Error!Directory {
        if (path.len == 0 or path.len >= path_max) {
            return Error.InvalidPath;
        }

        var wide: [path_max]u16 = undefined;

        const length = std.unicode.utf8ToUtf16Le(&wide, path) catch {
            return Error.InvalidPath;
        };

        assert(length > 0);
        assert(length < path_max);

        if (length == 0 or length >= path_max) {
            return Error.InvalidPath;
        }

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

        const result = Directory{
            .handle = handle,
        };

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

pub const Signal = struct {
    handle: w32.HANDLE,

    pub fn create() Error!Signal {
        const handle = w32.CreateEventW(null, w32.TRUE, w32.FALSE, null);

        if (handle == null) {
            return Error.EventCreationFailed;
        }

        assert(handle != null);

        const result = Signal{
            .handle = handle.?,
        };

        return result;
    }

    pub fn destroy(signal: *const Signal) bool {
        assert(signal.is_valid());

        const status = w32.CloseHandle(signal.handle);

        return status != 0;
    }

    pub fn is_valid(signal: *const Signal) bool {
        const address = @intFromPtr(signal.handle);

        return address != 0;
    }

    pub fn reset(signal: *const Signal) bool {
        assert(signal.is_valid());

        const status = w32.ResetEvent(signal.handle);

        return status != 0;
    }

    pub fn set(signal: *const Signal) bool {
        assert(signal.is_valid());

        const status = w32.SetEvent(signal.handle);

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
    stop_signal: *const Signal,
    io_signal: *const Signal,
    buffer: *align(@alignOf(w32.FILE_NOTIFY_INFORMATION)) [change_processor.size_buffer]u8,
    overlapped: *w32.OVERLAPPED,
    running: *const std.atomic.Value(bool),
) WaitResult {
    assert(directory.is_valid());
    assert(stop_signal.is_valid());
    assert(io_signal.is_valid());
    assert(buffer.len == change_processor.size_buffer);

    _ = io_signal.reset();

    const read_status = w32.ReadDirectoryChangesW(
        directory.handle,
        buffer,
        buffer.len,
        w32.FALSE,
        w32.FILE_NOTIFY_CHANGE_LAST_WRITE,
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

    const handles = [wait_handle_count]w32.HANDLE{ io_signal.handle, stop_signal.handle };

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

test "a fresh watcher starts stopped" {
    const watcher = Watcher.init();

    try testing.expect(!watcher.is_running());
    try testing.expect(!watcher.has_failed());
    try testing.expect(watcher.thread == null);
    try testing.expect(watcher.directory == null);
    try testing.expect(watcher.stop_signal == null);
    try testing.expect(watcher.callback == null);
}

test "a fresh watcher is not running" {
    const watcher = Watcher.init();

    try testing.expect(!watcher.is_running());
}

test "stopping a stopped watcher is inert" {
    var watcher = Watcher.init();

    watcher.stop();

    try testing.expect(!watcher.is_running());
    try testing.expect(watcher.thread == null);
}

test "tearing down a watcher clears its state" {
    var watcher = Watcher.init();

    watcher.deinit();

    try testing.expect(!watcher.is_running());
}

test "a watcher rejects an empty path" {
    var watcher = Watcher.init();
    defer watcher.deinit();

    const callback = struct {
        fn cb() void {}
    }.cb;

    const result = watcher.watch("", callback);

    try testing.expectError(Error.InvalidPath, result);
}

test "a watcher rejects a path with no directory" {
    var watcher = Watcher.init();
    defer watcher.deinit();

    const callback = struct {
        fn cb() void {}
    }.cb;

    const result = watcher.watch("filename_only", callback);

    try testing.expectError(Error.InvalidPath, result);
}

test "Watcher callback type is valid" {
    const callback_info = @typeInfo(Callback);

    try testing.expect(callback_info == .pointer);
}

test "an invalid directory handle reports as invalid" {
    const directory = Directory{
        .handle = w32.INVALID_HANDLE_VALUE,
    };

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

test "a valid signal handle reports as valid" {
    const signal = Signal{
        .handle = @ptrFromInt(0x12345678),
    };

    try testing.expect(signal.is_valid());
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
