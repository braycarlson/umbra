const std = @import("std");

const types = @import("types.zig");

const Event = types.Event;
const Kind = types.Kind;
const Response = types.Response;

pub const HandlerFn = *const fn (event: *const Event, context: ?*anyopaque) Response;

pub const Handler = struct {
    callback: HandlerFn,
    context: ?*anyopaque,
    enabled: bool,
    filter: ?Kind,
    priority: u8,

    pub fn init(callback: HandlerFn) Handler {
        const result = Handler{
            .callback = callback,
            .context = null,
            .enabled = true,
            .filter = null,
            .priority = 100,
        };

        std.debug.assert(result.enabled == true);
        std.debug.assert(result.priority == 100);

        return result;
    }

    pub fn with_context(self: Handler, context: ?*anyopaque) Handler {
        var result = self;

        result.context = context;

        std.debug.assert(result.context == context);

        return result;
    }

    pub fn with_filter(self: Handler, filter: Kind) Handler {
        std.debug.assert(filter.is_valid());

        var result = self;

        result.filter = filter;

        std.debug.assert(result.filter != null);

        return result;
    }

    pub fn with_priority(self: Handler, priority: u8) Handler {
        var result = self;

        result.priority = priority;

        std.debug.assert(result.priority == priority);

        return result;
    }

    pub fn invoke(self: *const Handler, event: *const Event) Response {
        if (!self.enabled) {
            return .pass;
        }

        if (self.filter) |filter| {
            std.debug.assert(filter.is_valid());

            if (event.kind != filter) {
                return .pass;
            }
        }

        const result = self.callback(event, self.context);

        return result;
    }
};

pub const Subscription = struct {
    bus: *Bus,
    index: u8,

    pub fn set_enabled(self: *const Subscription, enabled: bool) void {
        std.debug.assert(self.index < types.handler_max);

        self.bus.set_enabled(self.index, enabled);
    }

    pub fn unsubscribe(self: *const Subscription) void {
        std.debug.assert(self.index < types.handler_max);

        self.bus.remove(self.index);
    }
};

pub const Bus = struct {
    count: u8,
    dispatching: bool,
    handlers: [types.handler_max]?Handler,

    pub fn init() Bus {
        const result = Bus{
            .count = 0,
            .dispatching = false,
            .handlers = [_]?Handler{null} ** types.handler_max,
        };

        std.debug.assert(result.count == 0);
        std.debug.assert(result.dispatching == false);

        return result;
    }

    pub fn deinit(self: *Bus) void {
        self.clear();

        std.debug.assert(self.count == 0);
    }

    pub fn clear(self: *Bus) void {
        var index: u8 = 0;

        while (index < types.handler_max) : (index += 1) {
            self.handlers[index] = null;
        }

        self.count = 0;

        std.debug.assert(self.count == 0);
    }

    pub fn emit(self: *Bus, event: *const Event) Response {
        std.debug.assert(event.kind.is_valid());

        if (self.dispatching) {
            return .pass;
        }

        self.dispatching = true;

        defer {
            self.dispatching = false;
        }

        var sorted: [types.handler_max]?*const Handler = [_]?*const Handler{null} ** types.handler_max;
        var sorted_count: u8 = 0;

        sorted_count = collect_handlers(self, &sorted);

        std.debug.assert(sorted_count <= types.handler_max);

        sort_handlers_by_priority(&sorted, sorted_count);

        const result = dispatch_to_handlers(&sorted, sorted_count, event);

        return result;
    }

    pub fn emit_kind(self: *Bus, kind: Kind) Response {
        std.debug.assert(kind.is_valid());

        const event = Event.create(kind, @unionInit(types.Payload, @tagName(kind), {}));

        std.debug.assert(event.kind == kind);

        const result = self.emit(&event);

        return result;
    }

    pub fn handler_count(self: *const Bus) u8 {
        std.debug.assert(self.count <= types.handler_max);

        return self.count;
    }

    pub fn on(self: *Bus, kind: Kind, callback: HandlerFn, context: ?*anyopaque) ?Subscription {
        std.debug.assert(kind.is_valid());

        const handler = Handler.init(callback).with_filter(kind).with_context(context);
        const result = self.subscribe(handler);

        return result;
    }

    pub fn on_any(self: *Bus, callback: HandlerFn, context: ?*anyopaque) ?Subscription {
        const handler = Handler.init(callback).with_context(context);
        const result = self.subscribe(handler);

        return result;
    }

    pub fn remove(self: *Bus, index: u8) void {
        std.debug.assert(index < types.handler_max);

        if (self.handlers[index] != null) {
            self.handlers[index] = null;

            std.debug.assert(self.count > 0);

            self.count -= 1;
        }
    }

    pub fn set_enabled(self: *Bus, index: u8, enabled: bool) void {
        std.debug.assert(index < types.handler_max);

        if (self.handlers[index]) |*handler| {
            handler.enabled = enabled;

            std.debug.assert(handler.enabled == enabled);
        }
    }

    pub fn subscribe(self: *Bus, handler: Handler) ?Subscription {
        if (self.count >= types.handler_max) {
            return null;
        }

        const slot_index = find_empty_slot(self);

        if (slot_index == null) {
            return null;
        }

        std.debug.assert(slot_index.? < types.handler_max);

        self.handlers[slot_index.?] = handler;
        self.count += 1;

        std.debug.assert(self.count <= types.handler_max);

        const result = Subscription{
            .bus = self,
            .index = slot_index.?,
        };

        return result;
    }
};

fn collect_handlers(bus: *Bus, sorted: *[types.handler_max]?*const Handler) u8 {
    var sorted_count: u8 = 0;
    var index: u8 = 0;

    while (index < types.handler_max) : (index += 1) {
        std.debug.assert(sorted_count <= types.handler_max);

        if (bus.handlers[index]) |*handler| {
            sorted[sorted_count] = handler;
            sorted_count += 1;
        }
    }

    std.debug.assert(sorted_count <= types.handler_max);

    return sorted_count;
}

fn dispatch_to_handlers(sorted: *[types.handler_max]?*const Handler, sorted_count: u8, event: *const Event) Response {
    std.debug.assert(sorted_count <= types.handler_max);

    if (sorted_count == 0) {
        return .pass;
    }

    var index: u8 = 0;

    while (index < sorted_count) : (index += 1) {
        std.debug.assert(index < types.handler_max);

        if (sorted[index]) |handler| {
            const response = handler.invoke(event);

            if (response.should_stop()) {
                return response;
            }
        }
    }

    return .pass;
}

fn find_empty_slot(bus: *Bus) ?u8 {
    var index: u8 = 0;

    while (index < types.handler_max) : (index += 1) {
        if (bus.handlers[index] == null) {
            return index;
        }
    }

    return null;
}

fn sort_handlers_by_priority(sorted: *[types.handler_max]?*const Handler, sorted_count: u8) void {
    std.debug.assert(sorted_count <= types.handler_max);

    if (sorted_count <= 1) {
        return;
    }

    var outer_index: u8 = 0;

    while (outer_index < sorted_count) : (outer_index += 1) {
        std.debug.assert(outer_index < types.handler_max);

        var inner_index: u8 = outer_index + 1;

        while (inner_index < sorted_count) : (inner_index += 1) {
            std.debug.assert(inner_index < types.handler_max);

            const priority_outer = sorted[outer_index].?.priority;
            const priority_inner = sorted[inner_index].?.priority;

            if (priority_inner < priority_outer) {
                const temporary = sorted[outer_index];

                sorted[outer_index] = sorted[inner_index];
                sorted[inner_index] = temporary;
            }
        }
    }
}
