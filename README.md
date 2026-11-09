# umbra

A system tray application framework for Windows and Linux. The framework collects what each tray tool would otherwise repeat: the tray icon, menus, notifications, timers, file watching, and an event bus. The Windows backend uses Win32 and the Shell notification API, and the Linux backend uses D-Bus and the StatusNotifierItem specification.
