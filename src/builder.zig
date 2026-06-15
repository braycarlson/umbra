const std = @import("std");

const ui = @import("ui/root.zig");
const win32 = @import("win32/root.zig");

const IconError = ui.IconError;
const IconManager = ui.IconManager;
const MenuError = ui.MenuError;
const MenuManager = ui.MenuManager;

pub const IconBuilder = struct {
    deferred_error: ?IconError,
    manager: *IconManager,

    pub fn init(manager: *IconManager) IconBuilder {
        return IconBuilder{
            .deferred_error = null,
            .manager = manager,
        };
    }

    pub fn resource(self: IconBuilder, name: []const u8, id: u32) IconBuilder {
        std.debug.assert(name.len > 0);
        std.debug.assert(id > 0);

        if (self.deferred_error != null) {
            return self;
        }

        var result = self;

        result.manager.add_resource(name, id) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn system(self: IconBuilder, name: []const u8, sys: win32.IconSystem) IconBuilder {
        std.debug.assert(name.len > 0);

        if (self.deferred_error != null) {
            return self;
        }

        var result = self;

        result.manager.add_system(name, sys) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn done(self: IconBuilder) IconError!*IconManager {
        if (self.deferred_error) |err| {
            return err;
        }

        return self.manager;
    }
};

pub const MenuBuilder = struct {
    deferred_error: ?MenuError,
    manager: *MenuManager,

    pub fn init(manager: *MenuManager) MenuBuilder {
        return MenuBuilder{
            .deferred_error = null,
            .manager = manager,
        };
    }

    pub fn action(self: MenuBuilder, id: u32, label: []const u8) MenuBuilder {
        std.debug.assert(label.len > 0);

        if (self.deferred_error != null) {
            return self;
        }

        var result = self;

        result.manager.add_action(id, label) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn separator(self: MenuBuilder) MenuBuilder {
        if (self.deferred_error != null) {
            return self;
        }

        var result = self;

        result.manager.add_separator() catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn toggle(self: MenuBuilder, id: u32, label: []const u8, initial: bool) MenuBuilder {
        std.debug.assert(label.len > 0);

        if (self.deferred_error != null) {
            return self;
        }

        var result = self;

        result.manager.add_toggle(id, label, initial) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn radio(self: MenuBuilder, id: u32, label: []const u8, group: []const u8, initial: bool) MenuBuilder {
        std.debug.assert(label.len > 0);
        std.debug.assert(group.len > 0);

        if (self.deferred_error != null) {
            return self;
        }

        var result = self;

        result.manager.add_radio(id, label, group, initial) catch |err| {
            result.deferred_error = err;
        };

        return result;
    }

    pub fn done(self: MenuBuilder) MenuError!*MenuManager {
        if (self.deferred_error) |err| {
            return err;
        }

        return self.manager;
    }
};
