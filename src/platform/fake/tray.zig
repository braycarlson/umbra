const std = @import("std");

const interface = @import("../interface.zig");
const record = @import("record.zig");

const assert = std.debug.assert;

const CreateOptions = interface.TrayCreateOptions;
const Icon = interface.Icon;

const Tray = @This();

activation: record.Text,
create_count: u32,
created: bool,
destroy_count: u32,
icon_count: u32,
icon_current: ?Icon,
tooltip: record.Text,
tooltip_count: u32,

comptime {
    assert(interface.activation_token_bytes_max <= record.text_bytes_max);
    assert(interface.tooltip_bytes_max <= record.text_bytes_max);
}

pub fn init(tray: *Tray) void {
    tray.activation = record.Text.empty();
    tray.create_count = 0;
    tray.created = false;
    tray.destroy_count = 0;
    tray.icon_count = 0;
    tray.icon_current = null;
    tray.tooltip = record.Text.empty();
    tray.tooltip_count = 0;

    assert(!tray.is_created());
    assert(tray.activation_token().len == 0);
}

pub fn activation_clear(tray: *Tray) void {
    tray.activation = record.Text.empty();

    assert(tray.activation_token().len == 0);
}

pub fn activation_provide(tray: *Tray, token: []const u8) void {
    assert(token.len <= interface.activation_token_bytes_max);
    assert(interface.is_valid_text(token));

    tray.activation.set(token);

    assert(std.mem.eql(u8, tray.activation_token(), token));
}

pub fn activation_token(tray: *const Tray) []const u8 {
    return tray.activation.get();
}

pub fn create(tray: *Tray, options: CreateOptions) void {
    assert(!tray.created);
    assert(options.tooltip.len <= interface.tooltip_bytes_max);

    tray.created = true;
    tray.icon_current = options.icon;
    tray.create_count += 1;

    tray.tooltip.set(options.tooltip);

    assert(tray.created);
}

pub fn destroy(tray: *Tray) void {
    if (!tray.created) {
        return;
    }

    tray.created = false;
    tray.icon_current = null;
    tray.destroy_count += 1;

    assert(!tray.created);
}

pub fn is_created(tray: *const Tray) bool {
    return tray.created;
}

pub fn set_icon(tray: *Tray, icon: Icon) void {
    assert(tray.created);

    tray.icon_current = icon;
    tray.icon_count += 1;
}

pub fn set_tooltip(tray: *Tray, text: []const u8) void {
    assert(tray.created);
    assert(text.len <= interface.tooltip_bytes_max);

    tray.tooltip.set(text);
    tray.tooltip_count += 1;
}

pub fn tooltip_current(tray: *const Tray) []const u8 {
    return tray.tooltip.get();
}

pub fn icon_handle(tray: *const Tray) ?Icon {
    return tray.icon_current;
}

pub fn counts(tray: *const Tray) struct {
    created: u32,
    destroyed: u32,
    icons: u32,
    tooltips: u32,
} {
    return .{
        .created = tray.create_count,
        .destroyed = tray.destroy_count,
        .icons = tray.icon_count,
        .tooltips = tray.tooltip_count,
    };
}

const testing = std.testing;

test "create records the tray configuration" {
    var tray: Tray = undefined;

    tray.init();

    const icon: Icon = @fromBackingInt(3);

    tray.create(.{ .icon = icon, .tooltip = "umbra" });

    try testing.expect(tray.is_created());
    try testing.expectEqual(@as(?Icon, icon), tray.icon_handle());
    try testing.expectEqualStrings("umbra", tray.tooltip_current());
}

test "set_icon and set_tooltip update the live tray" {
    var tray: Tray = undefined;

    tray.init();

    const icon: Icon = @fromBackingInt(9);

    tray.create(.{});
    tray.set_icon(icon);
    tray.set_tooltip("updated");

    try testing.expectEqual(@as(?Icon, icon), tray.icon_handle());
    try testing.expectEqualStrings("updated", tray.tooltip_current());
    try testing.expectEqual(@as(u32, 1), tray.counts().icons);
    try testing.expectEqual(@as(u32, 1), tray.counts().tooltips);
}

test "destroy is idempotent" {
    var tray: Tray = undefined;

    tray.init();
    tray.create(.{});

    tray.destroy();
    tray.destroy();

    try testing.expect(!tray.is_created());
    try testing.expectEqual(@as(u32, 1), tray.counts().destroyed);
}
