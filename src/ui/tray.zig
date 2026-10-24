const std = @import("std");

const platform = @import("../platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.tray;

const CapacityError = platform.CapacityError;
const Icon = platform.Icon;
const PlatformError = platform.PlatformError;
const RequestError = platform.RequestError;

const tooltip_bytes_max = platform.tooltip_bytes_max;

pub const Tray = struct {
    created: bool,
    tooltip: [tooltip_bytes_max]u8,
    tooltip_len: u8,

    pub fn init(tooltip: []const u8) Tray {
        assert(tooltip.len <= tooltip_bytes_max);
        assert(platform.is_valid_text(tooltip));

        var result = Tray{
            .created = false,
            .tooltip = @splat(0),
            .tooltip_len = @intCast(tooltip.len),
        };

        @memcpy(result.tooltip[0..tooltip.len], tooltip);

        assert(!result.created);

        return result;
    }

    pub fn deinit(tray: *Tray) void {
        tray.destroy();

        assert(!tray.created);
    }

    pub fn create(tray: *Tray, icon: ?Icon) PlatformError!void {
        assert(!tray.created);

        try backend.create(.{
            .icon = icon,
            .tooltip = tray.get_tooltip(),
        });

        tray.created = true;
    }

    pub fn destroy(tray: *Tray) void {
        if (!tray.created) {
            return;
        }

        backend.destroy();

        tray.created = false;

        assert(!tray.created);
    }

    pub fn get_tooltip(tray: *const Tray) []const u8 {
        assert(tray.tooltip_len <= tooltip_bytes_max);

        return tray.tooltip[0..tray.tooltip_len];
    }

    pub fn is_created(tray: *const Tray) bool {
        return tray.created;
    }

    pub fn recreate(tray: *Tray, icon: ?Icon) PlatformError!void {
        tray.destroy();

        try tray.create(icon);

        assert(tray.created);
    }

    pub fn set_icon(tray: *Tray, icon: Icon) (PlatformError || RequestError)!void {
        if (!tray.created) return error.TrayMissing;

        try backend.set_icon(icon);
    }

    pub fn set_tooltip(
        tray: *Tray,
        tooltip: []const u8,
    ) (CapacityError || PlatformError || RequestError)!void {
        if (tooltip.len == 0) return error.TooltipEmpty;
        if (tooltip.len > tooltip_bytes_max) return error.TooltipTooLong;
        if (!platform.is_valid_text(tooltip)) return error.TooltipInvalid;

        @memcpy(tray.tooltip[0..tooltip.len], tooltip);

        tray.tooltip_len = @intCast(tooltip.len);

        if (!tray.created) {
            return;
        }

        try backend.set_tooltip(tray.get_tooltip());
    }
};

const testing = std.testing;

test Tray {
    var tray = Tray.init("Test Tooltip");
    defer tray.deinit();

    try testing.expectEqualStrings("Test Tooltip", tray.get_tooltip());
    try testing.expect(!tray.is_created());

    try tray.set_tooltip("New Tooltip");

    try testing.expectEqualStrings("New Tooltip", tray.get_tooltip());
}

test "a tray names the fault in each refused tooltip" {
    var tray = Tray.init("Test");
    defer tray.deinit();

    const long: [tooltip_bytes_max + 1]u8 = @splat('a');

    try testing.expectError(error.TooltipEmpty, tray.set_tooltip(""));
    try testing.expectError(error.TooltipTooLong, tray.set_tooltip(&long));
    try testing.expectError(error.TooltipInvalid, tray.set_tooltip("\xC3\x28"));
    try testing.expectEqualStrings("Test", tray.get_tooltip());
}

test "setting an icon requires a created tray" {
    var tray = Tray.init("Test");
    defer tray.deinit();

    const icon: Icon = @fromBackingInt(0);

    try testing.expectError(error.TrayMissing, tray.set_icon(icon));
}

test "destroying a tray twice is inert" {
    var tray = Tray.init("Test");

    tray.destroy();
    tray.destroy();

    try testing.expect(!tray.is_created());
}
