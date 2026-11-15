const std = @import("std");

const platform_module = @import("../platform.zig");

const assert = std.debug.assert;

const CapacityError = platform_module.CapacityError;
const Icon = platform_module.Icon;
const PlatformError = platform_module.PlatformError;
const RequestError = platform_module.RequestError;

const tooltip_bytes_max = platform_module.tooltip_bytes_max;

pub fn TrayType(comptime Platform: type) type {
    return struct {
        created: bool,
        platform: *Platform,
        tooltip: [tooltip_bytes_max]u8,
        tooltip_len: u8,

        const Tray = @This();

        pub fn init(platform: *Platform, tooltip: []const u8) Tray {
            assert(tooltip.len <= tooltip_bytes_max);
            assert(platform_module.is_valid_text(tooltip));

            var result = Tray{
                .created = false,
                .platform = platform,
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

        pub fn get_activation_token(tray: *const Tray) []const u8 {
            assert(tray.tooltip_len <= tooltip_bytes_max);

            const result = tray.platform.tray_activation_token();

            assert(result.len <= platform_module.activation_token_bytes_max);
            assert(platform_module.is_valid_text(result));

            return result;
        }

        pub fn create(tray: *Tray, icon: ?Icon) PlatformError!void {
            if (icon) |value| assert(@backingInt(value) < platform_module.icon_count_max);
            assert(!tray.created);

            try tray.platform.tray_create(.{ .icon = icon, .tooltip = tray.get_tooltip() });

            tray.created = true;
        }

        pub fn destroy(tray: *Tray) void {
            if (!tray.created) {
                return;
            }

            tray.platform.tray_destroy();

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
            if (icon) |value| assert(@backingInt(value) < platform_module.icon_count_max);

            tray.destroy();

            try tray.create(icon);

            assert(tray.created);
        }

        pub fn set_icon(tray: *Tray, icon: Icon) (PlatformError || RequestError)!void {
            assert(@backingInt(icon) < platform_module.icon_count_max);

            if (!tray.created) return error.TrayMissing;

            try tray.platform.tray_set_icon(icon);
        }

        pub fn set_tooltip(
            tray: *Tray,
            tooltip: []const u8,
        ) (CapacityError || PlatformError || RequestError)!void {
            if (tooltip.len == 0) return error.TooltipEmpty;
            if (tooltip.len > tooltip_bytes_max) return error.TooltipTooLong;
            if (!platform_module.is_valid_text(tooltip)) return error.TooltipInvalid;

            @memcpy(tray.tooltip[0..tooltip.len], tooltip);

            tray.tooltip_len = @intCast(tooltip.len);

            if (!tray.created) {
                return;
            }

            try tray.platform.tray_set_tooltip(tray.get_tooltip());
        }
    };
}

const testing = std.testing;

const Fake = platform_module.Fake;
const FakeTray = TrayType(Fake);

test TrayType {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "tray" });
    defer fake.deinit();

    var tray = FakeTray.init(&fake, "Test Tooltip");
    defer tray.deinit();

    try testing.expectEqualStrings("Test Tooltip", tray.get_tooltip());
    try testing.expect(!tray.is_created());

    try tray.set_tooltip("New Tooltip");

    try testing.expectEqualStrings("New Tooltip", tray.get_tooltip());
    try testing.expectEqualStrings("", tray.get_activation_token());
}

test "a tray names the fault in each refused tooltip" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "tray" });
    defer fake.deinit();

    var tray = FakeTray.init(&fake, "Test");
    defer tray.deinit();

    const long: [tooltip_bytes_max + 1]u8 = @splat('a');

    try testing.expectError(error.TooltipEmpty, tray.set_tooltip(""));
    try testing.expectError(error.TooltipTooLong, tray.set_tooltip(&long));
    try testing.expectError(error.TooltipInvalid, tray.set_tooltip("\xC3\x28"));
    try testing.expectEqualStrings("Test", tray.get_tooltip());
}

test "setting an icon requires a created tray" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "tray" });
    defer fake.deinit();

    var tray = FakeTray.init(&fake, "Test");
    defer tray.deinit();

    const icon: Icon = @fromBackingInt(0);

    try testing.expectError(error.TrayMissing, tray.set_icon(icon));
}

test "destroying a tray twice is inert" {
    var fake: Fake = undefined;

    try fake.init(.{ .name = "tray" });
    defer fake.deinit();

    var tray = FakeTray.init(&fake, "Test");

    tray.destroy();
    tray.destroy();

    try testing.expect(!tray.is_created());
}
