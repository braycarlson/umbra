const std = @import("std");

const w32 = @import("win32").everything;

const path_mod = @import("path.zig");

const path_max = path_mod.path_max;

pub const iteration_max: u32 = 64;
pub const size_buffer: u32 = 4096;

const debounce_ms: u64 = 50;
const ns_debounce: u64 = debounce_ms * std.time.ns_per_ms;
const filename_length_divisor: u32 = 2;

pub const Callback = *const fn () void;

pub fn process(
    buffer: *align(@alignOf(w32.FILE_NOTIFY_INFORMATION)) [size_buffer]u8,
    count: u32,
    target: []const u8,
    callback: Callback,
) void {
    std.debug.assert(count > 0);
    std.debug.assert(count <= size_buffer);
    std.debug.assert(target.len > 0);

    var offset: u32 = 0;
    var iteration: u32 = 0;
    var found: bool = false;

    while (iteration < iteration_max) : (iteration += 1) {
        if (offset >= size_buffer) {
            break;
        }

        std.debug.assert(offset < size_buffer);

        const info: *const w32.FILE_NOTIFY_INFORMATION = @ptrCast(@alignCast(&buffer[offset]));

        if (is_match(info, target)) {
            found = true;
        }

        if (info.NextEntryOffset == 0) {
            break;
        }

        offset += info.NextEntryOffset;
    }

    std.debug.assert(iteration <= iteration_max);

    if (found) {
        w32.Sleep(@intCast(debounce_ms));
        callback();
    }
}

fn is_match(info: *const w32.FILE_NOTIFY_INFORMATION, target: []const u8) bool {
    std.debug.assert(target.len > 0);

    const length = info.FileNameLength / filename_length_divisor;

    if (length == 0) {
        return false;
    }

    std.debug.assert(length > 0);

    const slice = @as([*]const u16, &info.FileName)[0..length];

    var name: [path_max]u8 = undefined;

    const size = std.unicode.utf16LeToUtf8(&name, slice) catch {
        return false;
    };

    if (size == 0) {
        return false;
    }

    std.debug.assert(size > 0);

    const result = std.mem.eql(u8, name[0..size], target);

    return result;
}
