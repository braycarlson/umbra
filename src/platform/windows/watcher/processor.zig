const std = @import("std");

const w32 = @import("../win32.zig");

const path_mod = @import("path.zig");

const assert = std.debug.assert;

const path_max = path_mod.path_max;

pub const iteration_max: u32 = 64;
pub const size_buffer: u32 = 4096;

const debounce_ms: u64 = 50;
const filename_length_divisor: u32 = 2;
const utf8_bytes_per_unit_max: u32 = 3;
const name_bytes_max: u32 = path_max * utf8_bytes_per_unit_max;
const entry_align: u32 = @alignOf(w32.FILE_NOTIFY_INFORMATION);
const entry_header_bytes: u32 = @offsetOf(w32.FILE_NOTIFY_INFORMATION, "FileName");

pub const Callback = *const fn () void;

comptime {
    assert(iteration_max > 0);
    assert(size_buffer > entry_header_bytes);
    assert(entry_align > 0);
    assert(entry_header_bytes > 0);
    assert(name_bytes_max > path_max);
}

pub fn process(
    buffer: *align(@alignOf(w32.FILE_NOTIFY_INFORMATION)) [size_buffer]u8,
    count: u32,
    target: []const u8,
    callback: Callback,
) void {
    assert(count > 0);
    assert(count <= size_buffer);
    assert(target.len > 0);

    var offset: u32 = 0;
    var iteration: u32 = 0;
    var found: bool = false;

    while (iteration < iteration_max) : (iteration += 1) {
        if (offset % entry_align != 0) {
            break;
        }

        if (offset + entry_header_bytes > count) {
            break;
        }

        assert(offset < size_buffer);

        const info: *const w32.FILE_NOTIFY_INFORMATION = @ptrCast(@alignCast(&buffer[offset]));
        const name_bytes = info.FileNameLength;

        if (name_bytes > count - offset - entry_header_bytes) {
            break;
        }

        if (is_match(info, target)) {
            found = true;
        }

        const next = info.NextEntryOffset;

        if (next == 0) {
            break;
        }

        if (next < entry_header_bytes or next > count - offset) {
            break;
        }

        offset += next;
    }

    assert(iteration <= iteration_max);

    if (found) {
        w32.Sleep(@intCast(debounce_ms));
        callback();
    }
}

fn is_match(info: *const w32.FILE_NOTIFY_INFORMATION, target: []const u8) bool {
    assert(target.len > 0);

    const length = info.FileNameLength / filename_length_divisor;

    if (length == 0 or length > path_max) {
        return false;
    }

    assert(length > 0);
    assert(length * utf8_bytes_per_unit_max <= name_bytes_max);

    const slice = @as([*]const u16, &info.FileName)[0..length];

    var name: [name_bytes_max]u8 = undefined;

    const size = std.unicode.utf16LeToUtf8(&name, slice) catch {
        return false;
    };

    if (size == 0) {
        return false;
    }

    assert(size > 0);

    return std.mem.eql(u8, name[0..size], target);
}

const testing = std.testing;

test "iteration_max constant value" {
    try testing.expectEqual(@as(u32, 64), iteration_max);
}

test "size_buffer constant value" {
    try testing.expectEqual(@as(u32, 4096), size_buffer);
}

test "Callback type is function pointer" {
    const callback_info = @typeInfo(Callback);

    try testing.expect(callback_info == .pointer);
}
