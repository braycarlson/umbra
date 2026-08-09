test {
    _ = @import("app.zig");
    _ = @import("builder.zig");
    _ = @import("event/bus.zig");
    _ = @import("event/bus_fuzz.zig");
    _ = @import("event/types.zig");
    _ = @import("fuzz_tests.zig");
    _ = @import("platform/contract.zig");
    _ = @import("runtime/lifecycle.zig");
    _ = @import("runtime/lifecycle_fuzz.zig");
    _ = @import("testing/fuzz.zig");
    _ = @import("tidy.zig");
    _ = @import("ui/icon.zig");
    _ = @import("ui/menu.zig");
    _ = @import("ui/notification.zig");
    _ = @import("ui/state.zig");
    _ = @import("ui/state_fuzz.zig");
    _ = @import("ui/timer.zig");
    _ = @import("ui/tray.zig");
}
