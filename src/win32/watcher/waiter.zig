const std = @import("std");

const w32 = @import("win32").everything;

const change_processor = @import("processor.zig");
const directory_mod = @import("directory.zig");
const signal_mod = @import("signal.zig");

const Directory = directory_mod.Directory;
const Signal = signal_mod.Signal;

pub const wait_max: u8 = 2;

pub const WaitResult = enum(u8) {
    complete = 0,
    failed = 1,
    stopped = 2,

    pub fn is_valid(self: WaitResult) bool {
        const value = @intFromEnum(self);
        const result = value <= wait_max;

        return result;
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
    _ = io_signal.reset();

    const read_status = w32.ReadDirectoryChangesW(
        directory.handle,
        buffer,
        buffer.len,
        w32.FALSE,
        .{ .LAST_WRITE = 1 },
        null,
        overlapped,
        null,
    );

    if (read_status == 0) {
        const err = w32.GetLastError();

        if (err != w32.WIN32_ERROR.ERROR_IO_PENDING) {
            if (!running.load(.acquire)) {
                return .stopped;
            }

            return .failed;
        }
    }

    const handles = [2]w32.HANDLE{ io_signal.handle, stop_signal.handle };
    const wait_status = @intFromEnum(w32.WaitForMultipleObjects(2, &handles, w32.FALSE, w32.INFINITE));
    const object_0 = @intFromEnum(w32.WAIT_OBJECT_0);

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

    return .complete;
}
