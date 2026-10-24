const std = @import("std");

const contract = @import("../contract.zig");
const sys = @import("sys.zig");

const assert = std.debug.assert;

const linux = std.os.linux;

const PlatformError = contract.PlatformError;

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

const Argv = [3]?[*:0]const u8;
const EnvironPointers = [sys.environ_entries_max + 1]?[*:0]const u8;

const Candidates = struct {
    count: u32,
    storage: [candidate_count_max][candidate_bytes_max:0]u8,

    fn build(candidates: *Candidates, path_value: []const u8) void {
        candidates.count = 0;

        var start: usize = 0;

        while (candidates.count < candidate_count_max - 1) {
            if (start > path_value.len) break;

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

            const slot = &candidates.storage[candidates.count];

            @memcpy(slot[0..entry.len], entry);

            slot[entry.len] = '/';

            @memcpy(slot[entry.len + 1 ..][0..opener_name.len], opener_name);

            slot[entry.len + 1 + opener_name.len] = 0;

            candidates.count += 1;
        }

        assert(candidates.count < candidate_count_max);

        const slot = &candidates.storage[candidates.count];

        @memcpy(slot[0..path_fallback.len], path_fallback);

        slot[path_fallback.len] = 0;

        candidates.count += 1;

        assert(candidates.count <= candidate_count_max);
    }
};

pub fn open(path: []const u8) PlatformError!void {
    assert(path.len > 0);
    assert(path.len < contract.path_bytes_max);

    var target: [contract.path_bytes_max:0]u8 = undefined;

    @memcpy(target[0..path.len], path);

    target[path.len] = 0;

    const argv: Argv = .{ opener_name, target[0..path.len :0].ptr, null };

    var environ: sys.Environ = undefined;
    var pointers: EnvironPointers = undefined;
    var candidates: Candidates = undefined;

    environ.load();

    _ = environ.list(&pointers);

    candidates.build(environ.get("PATH") orelse "");

    assert(candidates.count > 0);
    assert(candidates.count <= candidate_count_max);

    try spawn(&argv, &pointers, &candidates);
}

fn spawn(
    argv: *const Argv,
    pointers: *const EnvironPointers,
    candidates: *const Candidates,
) PlatformError!void {
    const forked = linux.fork();

    if (!sys.ok(forked)) {
        return error.LaunchFailed;
    }

    const child: linux.pid_t = @intCast(forked);

    if (child == 0) {
        const grandchild = linux.fork();

        if (sys.ok(grandchild)) {
            if (grandchild == 0) {
                execute_opener(argv, pointers, candidates);
            }
        }

        linux.exit_group(0);
    }

    reap(child);
}

fn execute_opener(
    argv: *const Argv,
    pointers: *const EnvironPointers,
    candidates: *const Candidates,
) noreturn {
    var index: u32 = 0;

    while (index < candidates.count) : (index += 1) {
        assert(index < candidate_count_max);

        const candidate: [*:0]const u8 = &candidates.storage[index];

        _ = linux.execve(
            candidate,
            @ptrCast(argv),
            @ptrCast(pointers),
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

const testing = std.testing;

test "build_candidates appends the opener to every searchable entry" {
    var candidates: Candidates = undefined;

    candidates.build("/usr/bin:/bin");

    try testing.expectEqual(@as(u32, 3), candidates.count);

    try testing.expectEqualStrings(
        "/usr/bin/xdg-open",
        std.mem.sliceTo(&candidates.storage[0], 0),
    );

    try testing.expectEqualStrings("/bin/xdg-open", std.mem.sliceTo(&candidates.storage[1], 0));
    try testing.expectEqualStrings(path_fallback, std.mem.sliceTo(&candidates.storage[2], 0));
}

test "build_candidates skips empty and oversized entries" {
    const oversized: [candidate_bytes_max]u8 = @splat('d');

    var path_buffer: [candidate_bytes_max + 16]u8 = undefined;

    const path_value = try std.mem.print(
        &path_buffer,
        "::{s}:/opt",
        .{oversized},
    );

    var candidates: Candidates = undefined;

    candidates.build(path_value);

    try testing.expectEqual(@as(u32, 2), candidates.count);
    try testing.expectEqualStrings("/opt/xdg-open", std.mem.sliceTo(&candidates.storage[0], 0));
    try testing.expectEqualStrings(path_fallback, std.mem.sliceTo(&candidates.storage[1], 0));
}

test "the fallback is always the final candidate" {
    var candidates: Candidates = undefined;

    candidates.build("");

    try testing.expectEqual(@as(u32, 1), candidates.count);
    try testing.expectEqualStrings(path_fallback, std.mem.sliceTo(&candidates.storage[0], 0));
}
