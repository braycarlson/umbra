<p align="center">
    <picture>
        <source media="(prefers-color-scheme: dark)" srcset="assets/umbra-lockup-on-dark.svg">
        <source media="(prefers-color-scheme: light)" srcset="assets/umbra-lockup-on-light.svg">
        <img alt="umbra" src="assets/umbra-lockup-on-light.svg" width="375">
    </picture>
</p>

&nbsp;

<p align="center">
    A system tray application framework for Windows and Linux.
</p>

<p align="center">
    <a href="https://github.com/braycarlson/umbra/actions/workflows/ci.yml"><img alt="ci" src="https://img.shields.io/github/actions/workflow/status/braycarlson/umbra/ci.yml?branch=main&amp;style=flat-square&amp;label=ci"></a>
    <a href="https://ziglang.org"><img alt="zig" src="https://img.shields.io/badge/zig-0.16.0-orange.svg?style=flat-square"></a>
    <a href="LICENSE"><img alt="license" src="https://img.shields.io/badge/license-MIT-blue.svg?style=flat-square"></a>
</p>

## Overview

An `App` owns the tray icon, the menu, the notifications, the timers, and a named state,
and hands events to a bus. A handler returns `pass`, `handled`, or `quit`, so the
application never touches a message loop of its own.

## Features

- **Three backends**: The Windows path uses Win32 and `Shell_NotifyIcon`, the Linux path
  registers a `StatusNotifierItem` and serves `com.canonical.dbusmenu`, and a mock backend
  stands in for tests.
- **No client libraries**: The D-Bus client is written here, wire format and socket
  included, so a Linux build links nothing.
- **Builders**: An `IconBuilder` and a `MenuBuilder` declare the tray surface in one chain,
  with toggles, radio groups, separators, and actions.
- **Event bus**: There are thirteen event kinds, from `app_init` and `menu_select` to
  `taskbar_restart`, with 32 handler slots.
- **Platform extras**: The Windows build adds balloons, icon resources, taskbar restart
  recovery, and window messages, each behind a declared capability that fails to compile
  where it is absent.

## Install

The library ships as a Zig package holding one module, also named `umbra`. Fetch it into
your own project and import the module in your `build.zig`.

```
zig fetch --save git+https://github.com/braycarlson/umbra
```

```zig
const umbra = b.dependency("umbra", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("umbra", umbra.module("umbra"));
```

umbra requires Zig 0.16.0.

## Usage

The application is declared, not driven: build the icons and the menu, subscribe to the
events that matter, and hand control to `run`. The full example lives in
`examples/basic.zig`.

```zig
const std = @import("std");

const umbra = @import("umbra");

const App = umbra.App;
const Event = umbra.Event;
const IconBuilder = umbra.IconBuilder;
const MenuBuilder = umbra.MenuBuilder;
const Response = umbra.Response;

const Menu = struct {
    pub const toggle: u32 = 1;
    pub const quit: u32 = 2;
};

pub fn main() !void {
    var app: App = undefined;

    try app.init(.{
        .initial_state = "idle",
        .name = "example",
        .tooltip = "Example",
    });

    defer app.deinit();

    _ = app.configure();

    _ = try IconBuilder.init(&app.icon)
        .stock("default", .application)
        .stock("active", .shield)
        .done();

    _ = try MenuBuilder.init(&app.menu)
        .toggle(Menu.toggle, "Enabled", false)
        .separator()
        .action(Menu.quit, "Quit")
        .done();

    _ = app.bus.on(.menu_select, on_menu_select, &app);

    try app.run();
}

fn on_menu_select(incoming: *const Event, context: ?*anyopaque) Response {
    const app: *App = @ptrCast(@alignCast(context.?));

    switch (incoming.payload.menu_select.id) {
        Menu.toggle => {
            const enabled = app.menu.toggle_item(Menu.toggle) catch false;

            app.icon.set_current(if (enabled) "active" else "default") catch {};

            return .handled;
        },
        Menu.quit => return .quit,
        else => return .pass,
    }
}
```

The state manager emits a `state_change` event, so an application that names its states
can drive the icon and the tooltip from one handler rather than from each call site.

## Support

The framework also carries the pieces a tray application needs beyond the tray itself.

| Namespace | What it gives |
|---|---|
| `umbra.paths` | The configuration and state directories for a named application. |
| `umbra.watcher` | The file watch that reports an edited configuration. |
| `umbra.shell` | The handoff of a path to the desktop's own opener. |
| `umbra.time` | The clock and the sleep the loop needs. |
| `umbra.loop` | The quit and the custom message post. |

## Development

The recipes below wrap `zig build`, and a bare `just` lists them all. The tidy law is a
test rather than a separate linter, so the mechanical rules run with everything else.

| Command | What it runs |
|---|---|
| `just ci` | The formatting check, compilation, and each available suite. |
| `just test` | Each available suite and the formatting check. |
| `just mock` | The full pipeline against the mock backend. |
| `just linux` | The tray tests, on a Linux host with a session bus. |
| `just example [name]` | The named example, built and run. The default is `basic`. |
| `just tidy` | The tidy law on its own. |
| `just fuzz <name> [seed] [events]` | The named fuzzer: `bus`, `dbus_wire`, `dbus_client`, `dbus_dispatch`, `lifecycle`, `state`, `canary`, or `smoke`. |

## Licence

MIT. See [LICENSE](LICENSE).
