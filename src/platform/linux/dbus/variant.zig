const std = @import("std");

const contract = @import("../../contract.zig");
const wire = @import("wire.zig");

const assert = std.debug.assert;

pub const Error = wire.Error;

pub const Writer = wire.Writer;

pub fn put_string_variant(writer: *Writer, value: []const u8) Error!void {
    assert(value.len <= wire.string_bytes_max);

    try writer.put_signature("s");
    try writer.put_string(value);
}

pub fn put_object_variant(writer: *Writer, value: []const u8) Error!void {
    assert(value.len > 0);
    assert(value[0] == '/');

    try writer.put_signature("o");
    try writer.put_string(value);
}

pub fn put_bool_variant(writer: *Writer, value: bool) Error!void {
    try writer.put_signature("b");
    try writer.put_bool(value);
}

pub fn put_u32_variant(writer: *Writer, value: u32) Error!void {
    try writer.put_signature("u");
    try writer.put_u32(value);
}

pub fn put_i32_variant(writer: *Writer, value: i32) Error!void {
    try writer.put_signature("i");
    try writer.put_i32(value);
}

pub fn put_dict_entry_string(writer: *Writer, key: []const u8, value: []const u8) Error!void {
    assert(key.len > 0);

    try writer.pad_to(wire.align_of(wire.code_dict_entry));
    try writer.put_string(key);
    try put_string_variant(writer, value);
}

pub fn put_dict_entry_bool(writer: *Writer, key: []const u8, value: bool) Error!void {
    assert(key.len > 0);

    try writer.pad_to(wire.align_of(wire.code_dict_entry));
    try writer.put_string(key);
    try put_bool_variant(writer, value);
}

pub fn put_dict_entry_i32(writer: *Writer, key: []const u8, value: i32) Error!void {
    assert(key.len > 0);

    try writer.pad_to(wire.align_of(wire.code_dict_entry));
    try writer.put_string(key);
    try put_i32_variant(writer, value);
}

pub fn put_empty_array(writer: *Writer, element_alignment: u32) Error!void {
    assert(element_alignment == 1 or element_alignment == 2 or
        element_alignment == 4 or element_alignment == 8);

    const marker = try writer.open_array(element_alignment);

    try writer.close_array(marker);
}

pub fn put_pixmap_array(
    writer: *Writer,
    argb: []const u8,
    width: u32,
    height: u32,
) Error!void {
    assert(width <= contract.pixmap_dimension_max);
    assert(height <= contract.pixmap_dimension_max);
    assert(argb.len == @as(u64, width) * @as(u64, height) * contract.channel_count);

    const outer = try writer.open_array(wire.align_of(wire.code_struct));

    if (argb.len > 0) {
        try writer.pad_to(wire.align_of(wire.code_struct));
        try writer.put_i32(@intCast(width));
        try writer.put_i32(@intCast(height));

        const inner = try writer.open_array(wire.align_of(wire.code_byte));

        try writer.put_slice(argb);
        try writer.close_array(inner);
    }

    try writer.close_array(outer);
}

const testing = std.testing;

test "put_string_variant writes a signature and a value" {
    var storage: [64]u8 = undefined;
    var writer = Writer.init(&storage);

    try put_string_variant(&writer, "umbra");

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqualStrings("s", try reader.take_signature());
    try testing.expectEqualStrings("umbra", try reader.take_string());
}

test "put_bool_variant writes a four byte boolean" {
    var storage: [64]u8 = undefined;
    var writer = Writer.init(&storage);

    try put_bool_variant(&writer, true);

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqualStrings("b", try reader.take_signature());
    try testing.expectEqual(@as(u32, 1), try reader.take_u32());
}

test "put_empty_array writes a zero length" {
    var storage: [64]u8 = undefined;
    var writer = Writer.init(&storage);

    try put_empty_array(&writer, 8);

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqual(@as(u32, 0), try reader.take_u32());
}

test "put_pixmap_array writes the dimensions and the payload" {
    var storage: [128]u8 = undefined;
    var writer = Writer.init(&storage);

    const argb = [_]u8{ 1, 2, 3, 4 };

    try put_pixmap_array(&writer, &argb, 1, 1);

    var reader = wire.Reader.init(writer.bytes());

    const outer = try reader.take_u32();

    try testing.expect(outer > 0);
    try reader.skip_to(8);
    try testing.expectEqual(@as(i32, 1), try reader.take_i32());
    try testing.expectEqual(@as(i32, 1), try reader.take_i32());
    try testing.expectEqual(@as(u32, 4), try reader.take_u32());
}

test "put_pixmap_array writes an empty outer array without pixels" {
    var storage: [64]u8 = undefined;
    var writer = Writer.init(&storage);

    try put_pixmap_array(&writer, &.{}, 0, 0);

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqual(@as(u32, 0), try reader.take_u32());
}

test "put_dict_entry_string writes a keyed variant" {
    var storage: [128]u8 = undefined;
    var writer = Writer.init(&storage);

    try put_dict_entry_string(&writer, "label", "Quit");

    var reader = wire.Reader.init(writer.bytes());

    try testing.expectEqualStrings("label", try reader.take_string());
    try testing.expectEqualStrings("s", try reader.take_signature());
    try testing.expectEqualStrings("Quit", try reader.take_string());
}
