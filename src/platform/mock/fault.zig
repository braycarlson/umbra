const std = @import("std");

const assert = std.debug.assert;

pub const Point = enum(u8) {
    icon_load = 0,
    menu_build = 1,
    notification_send = 2,
    runtime_open = 3,
    shell_open = 4,
    timer_start = 5,
    tray_create = 6,
    watcher_watch = 7,
};

var armed: std.EnumSet(Point) = .empty;

pub fn arm(point: Point) void {
    armed.insert(point);

    assert(armed.contains(point));
}

pub fn disarm(point: Point) void {
    armed.remove(point);

    assert(!armed.contains(point));
}

pub fn is_armed(point: Point) bool {
    return armed.contains(point);
}

pub fn reset() void {
    armed = .empty;

    assert(armed.count() == 0);
}

const testing = std.testing;

test "an armed point stays armed until it is disarmed" {
    reset();

    arm(.tray_create);

    try testing.expect(is_armed(.tray_create));
    try testing.expect(!is_armed(.icon_load));

    disarm(.tray_create);

    try testing.expect(!is_armed(.tray_create));
}

test "reset disarms every point" {
    arm(.icon_load);
    arm(.watcher_watch);

    reset();

    for (std.enums.values(Point)) |point| {
        try testing.expect(!is_armed(point));
    }
}
