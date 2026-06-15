const std = @import("std");

const w32 = @import("win32").everything;

pub const handler_max: u8 = 32;
pub const kind_max: u8 = 10;

pub const Kind = enum(u8) {
    app_init = 0,
    app_shutdown = 1,
    tray_left_click = 2,
    tray_right_click = 3,
    tray_double_click = 4,
    menu_select = 5,
    menu_show = 6,
    timer_tick = 7,
    state_change = 8,
    taskbar_restart = 9,
    custom = 10,

    pub fn is_valid(self: Kind) bool {
        const value = @intFromEnum(self);
        const result = value <= kind_max;

        return result;
    }
};

pub const Response = enum(u8) {
    pass = 0,
    handled = 1,
    quit = 2,

    pub fn should_quit(self: Response) bool {
        const result = self == .quit;

        return result;
    }

    pub fn should_stop(self: Response) bool {
        const result = self == .handled or self == .quit;

        return result;
    }
};

pub const Payload = union(Kind) {
    app_init: void,
    app_shutdown: void,
    tray_left_click: void,
    tray_right_click: void,
    tray_double_click: void,
    menu_select: MenuPayload,
    menu_show: void,
    timer_tick: TimerPayload,
    state_change: StatePayload,
    taskbar_restart: void,
    custom: CustomPayload,
};

pub const MenuPayload = struct {
    id: u32,
    checked: bool,
};

pub const TimerPayload = struct {
    id: u32,
    tick: u64,
};

pub const StatePayload = struct {
    from: []const u8,
    to: []const u8,
};

pub const CustomPayload = struct {
    code: u32,
    data: ?*anyopaque,
};

pub const Event = struct {
    kind: Kind,
    payload: Payload,
    timestamp: i64,

    pub fn init(kind: Kind, payload: Payload) Event {
        const result = Event{
            .kind = kind,
            .payload = payload,
            .timestamp = @intCast(w32.GetTickCount64()),
        };

        return result;
    }

    pub fn app_init() Event {
        return Event.init(.app_init, .{ .app_init = {} });
    }

    pub fn app_shutdown() Event {
        return Event.init(.app_shutdown, .{ .app_shutdown = {} });
    }

    pub fn tray_left_click() Event {
        return Event.init(.tray_left_click, .{ .tray_left_click = {} });
    }

    pub fn tray_right_click() Event {
        return Event.init(.tray_right_click, .{ .tray_right_click = {} });
    }

    pub fn tray_double_click() Event {
        return Event.init(.tray_double_click, .{ .tray_double_click = {} });
    }

    pub fn menu_select(id: u32, checked: bool) Event {
        return Event.init(.menu_select, .{
            .menu_select = MenuPayload{ .id = id, .checked = checked },
        });
    }

    pub fn menu_show() Event {
        return Event.init(.menu_show, .{ .menu_show = {} });
    }

    pub fn timer_tick(id: u32, tick: u64) Event {
        return Event.init(.timer_tick, .{
            .timer_tick = TimerPayload{ .id = id, .tick = tick },
        });
    }

    pub fn state_change(from: []const u8, to: []const u8) Event {
        return Event.init(.state_change, .{
            .state_change = StatePayload{ .from = from, .to = to },
        });
    }

    pub fn taskbar_restart() Event {
        return Event.init(.taskbar_restart, .{ .taskbar_restart = {} });
    }

    pub fn custom(code: u32, data: ?*anyopaque) Event {
        return Event.init(.custom, .{
            .custom = CustomPayload{ .code = code, .data = data },
        });
    }
};

pub const HandlerFn = *const fn (event: *const Event, context: ?*anyopaque) Response;

pub const Handler = struct {
    callback: HandlerFn,
    context: ?*anyopaque,
    filter: ?Kind,
    priority: u8,
    enabled: bool,

    pub fn init(callback: HandlerFn) Handler {
        const result = Handler{
            .callback = callback,
            .context = null,
            .filter = null,
            .priority = 100,
            .enabled = true,
        };

        return result;
    }

    pub fn with_context(callback: HandlerFn, context: ?*anyopaque) Handler {
        var result = Handler.init(callback);

        result.context = context;

        return result;
    }

    pub fn with_filter(callback: HandlerFn, filter: Kind) Handler {
        var result = Handler.init(callback);

        result.filter = filter;

        return result;
    }

    pub fn with_priority(callback: HandlerFn, priority: u8) Handler {
        var result = Handler.init(callback);

        result.priority = priority;

        return result;
    }

    pub fn invoke(self: *const Handler, event: *const Event) Response {
        if (!self.enabled) {
            return .pass;
        }

        if (self.filter) |f| {
            if (event.kind != f) {
                return .pass;
            }
        }

        const result = self.callback(event, self.context);

        return result;
    }

    pub fn set_enabled(self: *Handler, enabled: bool) void {
        self.enabled = enabled;
    }
};

pub const Subscription = struct {
    index: u8,
    bus: *EventBus,

    pub fn unsubscribe(self: *const Subscription) void {
        self.bus.remove(self.index);
    }

    pub fn set_enabled(self: *const Subscription, enabled: bool) void {
        self.bus.set_enabled(self.index, enabled);
    }
};

pub const EventBus = struct {
    handlers: [handler_max]?Handler,
    count: u8,
    dispatching: bool,

    pub fn init() EventBus {
        const result = EventBus{
            .handlers = [_]?Handler{null} ** handler_max,
            .count = 0,
            .dispatching = false,
        };

        return result;
    }

    pub fn deinit(self: *EventBus) void {
        self.clear();
    }

    pub fn subscribe(self: *EventBus, handler: Handler) ?Subscription {
        if (self.count >= handler_max) {
            return null;
        }

        var slot: ?u8 = null;
        var i: u8 = 0;

        while (i < handler_max) : (i += 1) {
            if (self.handlers[i] == null) {
                slot = i;

                break;
            }
        }

        if (slot == null) {
            return null;
        }

        self.handlers[slot.?] = handler;
        self.count += 1;

        const result = Subscription{
            .index = slot.?,
            .bus = self,
        };

        return result;
    }

    pub fn on(
        self: *EventBus,
        kind: Kind,
        callback: HandlerFn,
        context: ?*anyopaque,
    ) ?Subscription {
        var handler = Handler.with_filter(callback, kind);

        handler.context = context;

        const result = self.subscribe(handler);

        return result;
    }

    pub fn on_any(self: *EventBus, callback: HandlerFn, context: ?*anyopaque) ?Subscription {
        const handler = Handler.with_context(callback, context);
        const result = self.subscribe(handler);

        return result;
    }

    pub fn remove(self: *EventBus, index: u8) void {
        if (index >= handler_max) {
            return;
        }

        if (self.handlers[index] != null) {
            self.handlers[index] = null;
            self.count -= 1;
        }
    }

    pub fn set_enabled(self: *EventBus, index: u8, enabled: bool) void {
        if (index >= handler_max) {
            return;
        }

        if (self.handlers[index]) |*handler| {
            handler.enabled = enabled;
        }
    }

    pub fn emit(self: *EventBus, event: *const Event) Response {
        if (self.dispatching) {
            return .pass;
        }

        self.dispatching = true;

        defer {
            self.dispatching = false;
        }

        var sorted: [handler_max]?*const Handler = [_]?*const Handler{null} ** handler_max;
        var sorted_count: u8 = 0;

        var i: u8 = 0;

        while (i < handler_max) : (i += 1) {
            if (self.handlers[i]) |*handler| {
                sorted[sorted_count] = handler;
                sorted_count += 1;
            }
        }

        var j: u8 = 0;

        while (j < sorted_count) : (j += 1) {
            var k: u8 = j + 1;

            while (k < sorted_count) : (k += 1) {
                const a = sorted[j].?.priority;
                const b = sorted[k].?.priority;

                if (b < a) {
                    const temp = sorted[j];

                    sorted[j] = sorted[k];
                    sorted[k] = temp;
                }
            }
        }

        var m: u8 = 0;

        while (m < sorted_count) : (m += 1) {
            if (sorted[m]) |handler| {
                const response = handler.invoke(event);

                if (response.should_stop()) {
                    return response;
                }
            }
        }

        return .pass;
    }

    pub fn emit_kind(self: *EventBus, kind: Kind) Response {
        const event = Event.init(kind, @unionInit(Payload, @tagName(kind), {}));
        const result = self.emit(&event);

        return result;
    }

    pub fn clear(self: *EventBus) void {
        var i: u8 = 0;

        while (i < handler_max) : (i += 1) {
            self.handlers[i] = null;
        }

        self.count = 0;
    }

    pub fn handler_count(self: *const EventBus) u8 {
        const result = self.count;

        return result;
    }
};
