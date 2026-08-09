const std = @import("std");

const contract = @import("../contract.zig");

const assert = std.debug.assert;

pub const text_bytes_max: u32 = contract.path_bytes_max;

comptime {
    assert(text_bytes_max > 0);
    assert(text_bytes_max <= 4096);
}

pub const Text = struct {
    bytes: [text_bytes_max]u8,
    length: u32,

    pub fn empty() Text {
        const result = Text{
            .bytes = [_]u8{0} ** text_bytes_max,
            .length = 0,
        };

        assert(result.length == 0);

        return result;
    }

    pub fn set(text: *Text, source: []const u8) void {
        assert(source.len <= text_bytes_max);

        const limit: u32 = @intCast(@min(source.len, text_bytes_max));

        var index: u32 = 0;

        while (index < limit) : (index += 1) {
            assert(index < text_bytes_max);

            text.bytes[index] = source[index];
        }

        text.length = limit;

        assert(text.length <= text_bytes_max);
    }

    pub fn get(text: *const Text) []const u8 {
        assert(text.length <= text_bytes_max);

        return text.bytes[0..text.length];
    }

    pub fn equals(text: *const Text, other: []const u8) bool {
        assert(text.length <= text_bytes_max);

        return std.mem.eql(u8, text.get(), other);
    }
};

const testing = std.testing;

test "a fresh recorded text starts blank" {
    const text = Text.empty();

    try testing.expectEqual(@as(u32, 0), text.length);
    try testing.expectEqualStrings("", text.get());
}

test "recorded text stores and reads back" {
    var text = Text.empty();

    text.set("wisp");

    try testing.expectEqualStrings("wisp", text.get());
    try testing.expect(text.equals("wisp"));
    try testing.expect(!text.equals("other"));
}

test "recorded text truncates at its maximum" {
    var text = Text.empty();
    const source = [_]u8{'a'} ** text_bytes_max;

    text.set(&source);

    try testing.expectEqual(text_bytes_max, text.length);
}
