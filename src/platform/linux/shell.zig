const std = @import("std");

const contract = @import("../contract.zig");
const sys = @import("sys.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

pub const Error = contract.ShellError;

pub const opener_name = "xdg-open";
pub const candidate_bytes_max: u32 = 512;
pub const candidate_count_max: u32 = 16;
pub const path_fallback = "/usr/bin/xdg-open";
pub const path_separator: u8 = ':';

comptime {
    assert(opener_name.len > 0);
    assert(candidate_bytes_max > opener_name.len + 1);
    assert(candidate_count_max > 0);
    assert(path_fallback.len < candidate_bytes_max);
    assert(path_separator == ':');
}

var target_storage: [contract.path_bytes_max:0]u8 = undefined;
var argv_storage: [3]?[*:0]const u8 = undefined;
var environ_storage: [sys.environ_entries_max + 1]?[*:0]const u8 = undefined;
var candidate_storage: [candidate_count_max][candidate_bytes_max:0]u8 = undefined;
var candidate_count: u32 = 0;

pub fn open(path: []const u8) Error!void {
    if (path.len == 0 or path.len >= contract.path_bytes_max) {
        return Error.InvalidPath;
    }

    @memcpy(target_storage[0..path.len], path);

    target_storage[path.len] = 0;

    argv_storage[0] = opener_name;
    argv_storage[1] = target_storage[0..path.len :0].ptr;
    argv_storage[2] = null;

    _ = sys.environ_list(&environ_storage);

    build_candidates(sys.getenv("PATH") orelse "");

    assert(candidate_count > 0);
    assert(candidate_count <= candidate_count_max);

    try spawn();
}

fn spawn() Error!void {
    const forked = linux.fork();

    if (!sys.ok(forked)) {
        return Error.LaunchFailed;
    }

    const child: linux.pid_t = @intCast(forked);

    if (child == 0) {
        const grandchild = linux.fork();

        if (sys.ok(grandchild) and grandchild == 0) {
            execute_opener();
        }

        linux.exit_group(0);
    }

    reap(child);
}

fn execute_opener() noreturn {
    var index: u32 = 0;

    while (index < candidate_count) : (index += 1) {
        assert(index < candidate_count_max);

        const candidate: [*:0]const u8 = &candidate_storage[index];

        _ = linux.execve(
            candidate,
            @ptrCast(&argv_storage),
            @ptrCast(&environ_storage),
        );
    }

    linux.exit_group(127);
}

fn reap(child: linux.pid_t) void {
    var status: i32 = 0;
    var attempt: u32 = 0;

    while (attempt < sys.interrupt_retry_max) : (attempt += 1) {
        const raw = linux.waitpid(child, &status, 0);

        if (sys.ok(raw)) {
            return;
        }

        if (std.posix.errno(raw) != .INTR) {
            return;
        }
    }

    assert(attempt <= sys.interrupt_retry_max);
}

fn build_candidates(path_value: []const u8) void {
    candidate_count = 0;

    var start: usize = 0;

    while (start <= path_value.len and candidate_count < candidate_count_max - 1) {
        const end = std.mem.findScalarPos(u8, path_value, start, path_separator) orelse
            path_value.len;

        const entry = path_value[start..end];

        start = end + 1;

        if (entry.len == 0) {
            continue;
        }

        if (entry.len + 1 + opener_name.len >= candidate_bytes_max) {
            continue;
        }

        const slot = &candidate_storage[candidate_count];

        @memcpy(slot[0..entry.len], entry);

        slot[entry.len] = '/';

        @memcpy(slot[entry.len + 1 ..][0..opener_name.len], opener_name);

        slot[entry.len + 1 + opener_name.len] = 0;

        candidate_count += 1;
    }

    assert(candidate_count < candidate_count_max);

    const slot = &candidate_storage[candidate_count];

    @memcpy(slot[0..path_fallback.len], path_fallback);

    slot[path_fallback.len] = 0;

    candidate_count += 1;

    assert(candidate_count <= candidate_count_max);
}

const testing = std.testing;

test "open rejects an empty path" {
    try testing.expectError(Error.InvalidPath, open(""));
}

test "open rejects an oversized path" {
    const long: [contract.path_bytes_max]u8 = @splat('a');

    try testing.expectError(Error.InvalidPath, open(&long));
}

test "build_candidates appends the opener to every searchable entry" {
    build_candidates("/usr/bin:/bin");

    try testing.expectEqual(@as(u32, 3), candidate_count);

    try testing.expectEqualStrings(
        "/usr/bin/xdg-open",
        std.mem.sliceTo(&candidate_storage[0], 0),
    );

    try testing.expectEqualStrings("/bin/xdg-open", std.mem.sliceTo(&candidate_storage[1], 0));
    try testing.expectEqualStrings(path_fallback, std.mem.sliceTo(&candidate_storage[2], 0));
}

test "build_candidates skips empty and oversized entries" {
    const oversized: [candidate_bytes_max]u8 = @splat('d');

    var path_buffer: [candidate_bytes_max + 16]u8 = undefined;

    const path_value = try std.mem.print(
        &path_buffer,
        "::{s}:/opt",
        .{oversized},
    );

    build_candidates(path_value);

    try testing.expectEqual(@as(u32, 2), candidate_count);
    try testing.expectEqualStrings("/opt/xdg-open", std.mem.sliceTo(&candidate_storage[0], 0));
    try testing.expectEqualStrings(path_fallback, std.mem.sliceTo(&candidate_storage[1], 0));
}

test "the fallback is always the final candidate" {
    build_candidates("");

    try testing.expectEqual(@as(u32, 1), candidate_count);
    try testing.expectEqualStrings(path_fallback, std.mem.sliceTo(&candidate_storage[0], 0));
}
