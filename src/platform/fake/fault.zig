const std = @import("std");

const assert = std.debug.assert;

const Fault = @This();

armed: std.EnumSet(Point),

pub const Point = enum(u8) {
    icon_load = 0,
    menu_build = 1,
    notification_send = 2,
    shell_open = 3,
    timer_start = 4,
    tray_create = 5,
    watcher_watch = 6,
};

pub const empty: Fault = .{ .armed = .empty };

pub fn arm(fault: *Fault, point: Point) void {
    fault.armed.insert(point);

    assert(fault.armed.contains(point));
}

pub fn disarm(fault: *Fault, point: Point) void {
    fault.armed.remove(point);

    assert(!fault.armed.contains(point));
}

pub fn is_armed(fault: *const Fault, point: Point) bool {
    return fault.armed.contains(point);
}

const testing = std.testing;

test "an armed point stays armed until it is disarmed" {
    var fault: Fault = .empty;

    fault.arm(.tray_create);

    try testing.expect(fault.is_armed(.tray_create));
    try testing.expect(!fault.is_armed(.icon_load));

    fault.disarm(.tray_create);

    try testing.expect(!fault.is_armed(.tray_create));
}

test "a fresh fault set arms no point" {
    const fault: Fault = .empty;

    for (std.enums.values(Point)) |point| {
        try testing.expect(!fault.is_armed(point));
    }
}
