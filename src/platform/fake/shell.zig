const std = @import("std");

const interface = @import("../interface.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

const Shell = @This();

count: u32,
entries: [opened_max]record.Text,
open_count: u32,

pub const opened_max: u32 = 16;

comptime {
    assert(opened_max > 0);
}

pub fn init(shell: *Shell) void {
    shell.count = 0;
    shell.entries = undefined;
    shell.open_count = 0;

    assert(shell.recorded_count() == 0);
    assert(shell.opened_count() == 0);
}

pub fn open(shell: *Shell, path: []const u8) void {
    assert(path.len > 0);
    assert(path.len < interface.path_bytes_max);

    shell.open_count += 1;

    if (shell.count == opened_max) {
        return;
    }

    shell.entries[shell.count] = record.Text.empty();

    shell.entries[shell.count].set(path);
    shell.count += 1;

    assert(shell.count <= opened_max);
}

pub fn opened_count(shell: *const Shell) u32 {
    return shell.open_count;
}

pub fn recorded_count(shell: *const Shell) u32 {
    assert(shell.count <= opened_max);

    return shell.count;
}

pub fn path_at(shell: *const Shell, index: u32) []const u8 {
    assert(index < shell.count);

    return shell.entries[index].get();
}

const testing = std.testing;

test "open records the requested path" {
    var shell: Shell = undefined;

    shell.init();
    shell.open("/tmp/config.zon");

    try testing.expectEqual(@as(u32, 1), shell.opened_count());
    try testing.expectEqual(@as(u32, 1), shell.recorded_count());
    try testing.expectEqualStrings("/tmp/config.zon", shell.path_at(0));
}
