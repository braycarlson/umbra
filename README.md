# wisp

A cross-platform system tray framework in Zig, with no runtime dependencies beyond the operating
system itself. Windows uses Win32 and the Shell notification API; Linux uses D-Bus and the
StatusNotifierItem specification.
