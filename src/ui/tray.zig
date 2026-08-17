const std = @import("std");

const icon = @import("icon.zig");
const platform = @import("../platform.zig");

const assert = std.debug.assert;

const backend = platform.backend.tray;

pub const tooltip_max: u32 = 128;

pub const IconHandle = icon.Handle;

pub const Error = platform.TrayError;

pub const BalloonIcon = platform.NotificationKind;

pub const Config = struct {
    id: u32 = 1,
    tooltip: []const u8,
};

comptime {
    assert(tooltip_max > 1);
}

pub const TrayManager = struct {
    created: bool,
    id: u32,
    tooltip: [tooltip_max]u8,
    tooltip_len: u8,

    pub fn init(config: Config) TrayManager {
        assert(config.tooltip.len < tooltip_max);

        var result = TrayManager{
            .created = false,
            .id = config.id,
            .tooltip = [_]u8{0} ** tooltip_max,
            .tooltip_len = 0,
        };

        if (config.tooltip.len > 0 and config.tooltip.len < tooltip_max) {
            copy_tooltip(&result, config.tooltip);
        }

        assert(!result.created);

        return result;
    }

    pub fn deinit(manager: *TrayManager) void {
        manager.destroy();

        assert(!manager.created);
    }

    pub fn create(manager: *TrayManager, handle: ?IconHandle) Error!void {
        backend.create(.{
            .icon = handle,
            .id = manager.id,
            .tooltip = manager.tooltip[0..manager.tooltip_len],
        }) catch {
            return Error.CreationFailed;
        };

        manager.created = true;

        assert(manager.created);
    }

    pub fn destroy(manager: *TrayManager) void {
        if (!manager.created) {
            return;
        }

        backend.destroy();

        manager.created = false;

        assert(!manager.created);
    }

    pub fn get_tooltip(manager: *const TrayManager) []const u8 {
        assert(manager.tooltip_len <= tooltip_max);

        return manager.tooltip[0..manager.tooltip_len];
    }

    pub fn hide_balloon(manager: *TrayManager) Error!void {
        if (comptime !platform.capabilities.balloon) {
            @compileError("umbra: hide_balloon requires the balloon capability");
        }

        if (!manager.created) {
            return Error.NotCreated;
        }

        platform.backend.balloon.hide() catch {
            return Error.BalloonFailed;
        };
    }

    pub fn is_created(manager: *const TrayManager) bool {
        return manager.created;
    }

    pub fn recreate(manager: *TrayManager, handle: ?IconHandle) Error!void {
        manager.destroy();

        try manager.create(handle);

        assert(manager.created);
    }

    pub fn set_icon(manager: *TrayManager, handle: IconHandle) Error!void {
        if (!manager.created) {
            return Error.NotCreated;
        }

        backend.set_icon(handle) catch {
            return Error.UpdateFailed;
        };
    }

    pub fn set_tooltip(manager: *TrayManager, tooltip: []const u8) Error!void {
        if (tooltip.len == 0 or tooltip.len >= tooltip_max) {
            return Error.InvalidTooltip;
        }

        copy_tooltip(manager, tooltip);

        if (!manager.created) {
            return;
        }

        backend.set_tooltip(manager.tooltip[0..manager.tooltip_len]) catch {
            return Error.UpdateFailed;
        };
    }

    pub fn show_balloon(
        manager: *TrayManager,
        title: []const u8,
        body: []const u8,
        kind: BalloonIcon,
    ) Error!void {
        if (comptime !platform.capabilities.balloon) {
            @compileError("umbra: show_balloon requires the balloon capability");
        }

        assert(title.len > 0);
        assert(body.len > 0);

        if (!manager.created) {
            return Error.NotCreated;
        }

        platform.backend.balloon.show(.{
            .body = body,
            .kind = kind,
            .title = title,
        }) catch {
            return Error.BalloonFailed;
        };
    }

    pub fn show_balloon_error(
        manager: *TrayManager,
        title: []const u8,
        body: []const u8,
    ) Error!void {
        try manager.show_balloon(title, body, .err);
    }

    pub fn show_balloon_info(
        manager: *TrayManager,
        title: []const u8,
        body: []const u8,
    ) Error!void {
        try manager.show_balloon(title, body, .info);
    }

    pub fn show_balloon_warning(
        manager: *TrayManager,
        title: []const u8,
        body: []const u8,
    ) Error!void {
        try manager.show_balloon(title, body, .warning);
    }
};

fn copy_tooltip(manager: *TrayManager, tooltip: []const u8) void {
    assert(tooltip.len < tooltip_max);

    @memcpy(manager.tooltip[0..tooltip.len], tooltip);

    manager.tooltip_len = @intCast(tooltip.len);

    assert(manager.tooltip_len == tooltip.len);
}

const testing = std.testing;

test "BalloonIcon is the neutral notification kind" {
    try testing.expectEqual(platform.NotificationKind, BalloonIcon);
    try testing.expect(BalloonIcon.err.is_valid());
    try testing.expect(BalloonIcon.warning.is_valid());
}

test "a tray carries the tooltip and id it was built from" {
    const manager = TrayManager.init(.{ .id = 42, .tooltip = "Test Tooltip" });

    try testing.expectEqualStrings("Test Tooltip", manager.get_tooltip());
    try testing.expectEqual(@as(u32, 42), manager.id);
    try testing.expect(!manager.is_created());
}

test "a tray falls back to a default id" {
    const manager = TrayManager.init(.{ .tooltip = "Test" });

    try testing.expectEqual(@as(u32, 1), manager.id);
}

test "a tray rejects an empty tooltip" {
    var manager = TrayManager.init(.{ .tooltip = "Test" });
    defer manager.deinit();

    try testing.expectError(Error.InvalidTooltip, manager.set_tooltip(""));
}

test "a tray rejects an oversized tooltip" {
    var manager = TrayManager.init(.{ .tooltip = "Test" });
    defer manager.deinit();

    const long = [_]u8{'a'} ** tooltip_max;

    try testing.expectError(Error.InvalidTooltip, manager.set_tooltip(&long));
}

test "a tooltip set before creation updates local state" {
    var manager = TrayManager.init(.{ .tooltip = "Old" });
    defer manager.deinit();

    try manager.set_tooltip("New Tooltip");

    try testing.expectEqualStrings("New Tooltip", manager.get_tooltip());
}

test "setting an icon requires a created tray" {
    var manager = TrayManager.init(.{ .tooltip = "Test" });
    defer manager.deinit();

    const handle = std.mem.zeroes(IconHandle);

    try testing.expectError(Error.NotCreated, manager.set_icon(handle));
}

test "destroying a tray twice is inert" {
    var manager = TrayManager.init(.{ .tooltip = "Test" });

    manager.destroy();
    manager.destroy();

    try testing.expect(!manager.is_created());
}
