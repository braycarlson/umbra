# umbra

A system tray application framework for Windows and Linux.

## Overview

The framework collects what each tray tool would otherwise repeat: the tray icon, nested menus, notifications, timers, file watching, and an event bus. The Windows backend uses Win32 and the Shell notification API, and the Linux backend uses D-Bus and the StatusNotifierItem specification. The target selects the backend, so a Windows build from Linux needs only `-Dtarget=x86_64-windows-gnu`.

## Usage

```zig
var app: umbra.App = undefined;

try app.init(.{ .name = "Example" });
defer app.deinit();

_ = try umbra.IconBuilder.init(&app.icons).stock("default", .application).done();
_ = try umbra.MenuBuilder.init(&app.menu).action(1, "Quit").done();

try app.bus.attach(Owner, &owner);
try app.run();
```

The `init` call opens the backend, which is the D-Bus connection on Linux and the hidden message window on Windows, and `deinit` closes it. A run tears down the tray, the menu, the timers, and the watchers when its loop exits. The `App` holds the backend state in place, about 1.5 MB on Linux for the D-Bus buffers, so it belongs where that fits, such as the stack of `main`. The `examples/basic.zig` program is the full example.

The `App.config_dir` and `App.state_dir` functions take the program's `std.Io` and resolve the per-user directories without an instance, so a program can open its log before `init` and record why `init` failed. Each returns an absolute path:

```zig
var buffer: [umbra.limits.path_bytes_max]u8 = undefined;

const state = try umbra.App.state_dir(io, &buffer, "Example");
```

## Testing

The `umbra.AppType(umbra.Fake)` type is the same application over an in-memory backend. The fake records each call, delivers a scripted event queue, reads a clock the test advances, and fails a chosen call after `app.platform.fault.arm(.tray_create)`. Its directories are absolute paths under `.zig-cache/tmp/umbra-fake/` in the working directory, the build cache root that `std.testing.tmpDir` also uses, so a test that writes there never touches a real configuration directory. The `zig build test:fake` step runs the end to end tests against it on every host.
