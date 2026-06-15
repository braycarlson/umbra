const std = @import("std");

const w32 = @import("win32").everything;

pub const name_max: u16 = 256;

const style_border: u32 = 0x00800000;
const style_caption: u32 = 0x00C00000;
const style_child: u32 = 0x40000000;
const style_clip_children: u32 = 0x02000000;
const style_clip_siblings: u32 = 0x04000000;
const style_disabled: u32 = 0x08000000;
const style_dlg_frame: u32 = 0x00400000;
const style_group: u32 = 0x00020000;
const style_hscroll: u32 = 0x00100000;
const style_maximize: u32 = 0x01000000;
const style_maximize_box: u32 = 0x00010000;
const style_minimize: u32 = 0x20000000;
const style_minimize_box: u32 = 0x00020000;
const style_overlapped: u32 = 0x00000000;
const style_popup: u32 = 0x80000000;
const style_sysmenu: u32 = 0x00080000;
const style_tabstop: u32 = 0x00010000;
const style_thickframe: u32 = 0x00040000;
const style_visible: u32 = 0x10000000;
const style_vscroll: u32 = 0x00200000;

const exstyle_accept_files: u32 = 0x00000010;
const exstyle_app_window: u32 = 0x00040000;
const exstyle_client_edge: u32 = 0x00000200;
const exstyle_composited: u32 = 0x02000000;
const exstyle_context_help: u32 = 0x00000400;
const exstyle_control_parent: u32 = 0x00010000;
const exstyle_dlg_modal_frame: u32 = 0x00000001;
const exstyle_layered: u32 = 0x00080000;
const exstyle_layout_rtl: u32 = 0x00400000;
const exstyle_left: u32 = 0x00000000;
const exstyle_left_scrollbar: u32 = 0x00004000;
const exstyle_mdi_child: u32 = 0x00000040;
const exstyle_no_activate: u32 = 0x08000000;
const exstyle_no_inherit_layout: u32 = 0x00100000;
const exstyle_no_parent_notify: u32 = 0x00000004;
const exstyle_no_redirection_bitmap: u32 = 0x00200000;
const exstyle_overlapped_window: u32 = 0x00000300;
const exstyle_palette_window: u32 = 0x00000188;
const exstyle_right: u32 = 0x00001000;
const exstyle_right_scrollbar: u32 = 0x00000000;
const exstyle_rtl_reading: u32 = 0x00002000;
const exstyle_static_edge: u32 = 0x00020000;
const exstyle_tool_window: u32 = 0x00000080;
const exstyle_topmost: u32 = 0x00000008;
const exstyle_transparent: u32 = 0x00000020;
const exstyle_window_edge: u32 = 0x00000100;

const class_byte_align_client: u32 = 0x1000;
const class_byte_align_window: u32 = 0x2000;
const class_class_dc: u32 = 0x0040;
const class_dbl_clks: u32 = 0x0008;
const class_drop_shadow: u32 = 0x00020000;
const class_global_class: u32 = 0x4000;
const class_hredraw: u32 = 0x0002;
const class_no_close: u32 = 0x0200;
const class_own_dc: u32 = 0x0020;
const class_parent_dc: u32 = 0x0080;
const class_save_bits: u32 = 0x0800;
const class_vredraw: u32 = 0x0001;

const setpos_no_size: u32 = 0x0001;
const setpos_no_move: u32 = 0x0002;
const setpos_no_zorder: u32 = 0x0004;
const setpos_no_redraw: u32 = 0x0008;
const setpos_no_activate: u32 = 0x0010;
const setpos_frame_changed: u32 = 0x0020;
const setpos_show_window: u32 = 0x0040;
const setpos_hide_window: u32 = 0x0080;
const setpos_no_copy_bits: u32 = 0x0100;
const setpos_no_owner_zorder: u32 = 0x0200;
const setpos_no_send_changing: u32 = 0x0400;
const setpos_draw_frame: u32 = 0x0020;
const setpos_defer_erase: u32 = 0x2000;
const setpos_async_window_pos: u32 = 0x4000;

const hwnd_topmost: i64 = -1;
const hwnd_notopmost: i64 = -2;

const wide_string_max: u64 = 65535;
const iteration_max: u64 = 0xFFFFFFFFFFFFFFFF;

pub const Callback = w32.WNDPROC;

pub const Error = error{
    CreationFailed,
    InvalidName,
    RegistrationFailed,
};

pub const Style = struct {
    border: bool = false,
    caption: bool = false,
    child: bool = false,
    clip_children: bool = false,
    clip_siblings: bool = false,
    disabled: bool = false,
    dlg_frame: bool = false,
    group: bool = false,
    hscroll: bool = false,
    maximize: bool = false,
    maximize_box: bool = false,
    minimize: bool = false,
    minimize_box: bool = false,
    overlapped: bool = true,
    popup: bool = false,
    sysmenu: bool = false,
    tabstop: bool = false,
    thickframe: bool = false,
    visible: bool = false,
    vscroll: bool = false,

    pub fn child_window() Style {
        const result = Style{
            .child = true,
            .overlapped = false,
            .visible = true,
        };

        return result;
    }

    pub fn none() Style {
        const result = Style{
            .overlapped = false,
        };

        return result;
    }

    pub fn overlapped_window() Style {
        const result = Style{
            .caption = true,
            .maximize_box = true,
            .minimize_box = true,
            .overlapped = true,
            .sysmenu = true,
            .thickframe = true,
        };

        return result;
    }

    pub fn popup_window() Style {
        const result = Style{
            .border = true,
            .overlapped = false,
            .popup = true,
            .sysmenu = true,
        };

        return result;
    }

    pub fn to_uint(self: Style) u32 {
        var result: u32 = 0;

        if (self.border) result |= style_border;
        if (self.caption) result |= style_caption;
        if (self.child) result |= style_child;
        if (self.clip_children) result |= style_clip_children;
        if (self.clip_siblings) result |= style_clip_siblings;
        if (self.disabled) result |= style_disabled;
        if (self.dlg_frame) result |= style_dlg_frame;
        if (self.group) result |= style_group;
        if (self.hscroll) result |= style_hscroll;
        if (self.maximize) result |= style_maximize;
        if (self.maximize_box) result |= style_maximize_box;
        if (self.minimize) result |= style_minimize;
        if (self.minimize_box) result |= style_minimize_box;
        if (self.overlapped) result |= style_overlapped;
        if (self.popup) result |= style_popup;
        if (self.sysmenu) result |= style_sysmenu;
        if (self.tabstop) result |= style_tabstop;
        if (self.thickframe) result |= style_thickframe;
        if (self.visible) result |= style_visible;
        if (self.vscroll) result |= style_vscroll;

        return result;
    }
};

pub const ExStyle = struct {
    accept_files: bool = false,
    app_window: bool = false,
    client_edge: bool = false,
    composited: bool = false,
    context_help: bool = false,
    control_parent: bool = false,
    dlg_modal_frame: bool = false,
    layered: bool = false,
    layout_rtl: bool = false,
    left: bool = false,
    left_scrollbar: bool = false,
    mdi_child: bool = false,
    no_activate: bool = false,
    no_inherit_layout: bool = false,
    no_parent_notify: bool = false,
    no_redirection_bitmap: bool = false,
    overlapped_window: bool = false,
    palette_window: bool = false,
    right: bool = false,
    right_scrollbar: bool = false,
    rtl_reading: bool = false,
    static_edge: bool = false,
    tool_window: bool = false,
    topmost: bool = false,
    transparent: bool = false,
    window_edge: bool = false,

    pub fn none() ExStyle {
        const result = ExStyle{};

        return result;
    }

    pub fn tool() ExStyle {
        const result = ExStyle{
            .tool_window = true,
        };

        return result;
    }

    pub fn topmost_tool() ExStyle {
        const result = ExStyle{
            .tool_window = true,
            .topmost = true,
        };

        return result;
    }

    pub fn to_uint(self: ExStyle) u32 {
        var result: u32 = 0;

        if (self.accept_files) result |= exstyle_accept_files;
        if (self.app_window) result |= exstyle_app_window;
        if (self.client_edge) result |= exstyle_client_edge;
        if (self.composited) result |= exstyle_composited;
        if (self.context_help) result |= exstyle_context_help;
        if (self.control_parent) result |= exstyle_control_parent;
        if (self.dlg_modal_frame) result |= exstyle_dlg_modal_frame;
        if (self.layered) result |= exstyle_layered;
        if (self.layout_rtl) result |= exstyle_layout_rtl;
        if (self.left) result |= exstyle_left;
        if (self.left_scrollbar) result |= exstyle_left_scrollbar;
        if (self.mdi_child) result |= exstyle_mdi_child;
        if (self.no_activate) result |= exstyle_no_activate;
        if (self.no_inherit_layout) result |= exstyle_no_inherit_layout;
        if (self.no_parent_notify) result |= exstyle_no_parent_notify;
        if (self.no_redirection_bitmap) result |= exstyle_no_redirection_bitmap;
        if (self.overlapped_window) result |= exstyle_overlapped_window;
        if (self.palette_window) result |= exstyle_palette_window;
        if (self.right) result |= exstyle_right;
        if (self.right_scrollbar) result |= exstyle_right_scrollbar;
        if (self.rtl_reading) result |= exstyle_rtl_reading;
        if (self.static_edge) result |= exstyle_static_edge;
        if (self.tool_window) result |= exstyle_tool_window;
        if (self.topmost) result |= exstyle_topmost;
        if (self.transparent) result |= exstyle_transparent;
        if (self.window_edge) result |= exstyle_window_edge;

        return result;
    }
};

pub const ClassStyle = struct {
    byte_align_client: bool = false,
    byte_align_window: bool = false,
    class_dc: bool = false,
    dbl_clks: bool = true,
    drop_shadow: bool = false,
    global_class: bool = false,
    hredraw: bool = false,
    no_close: bool = false,
    own_dc: bool = false,
    parent_dc: bool = false,
    save_bits: bool = false,
    vredraw: bool = false,

    pub fn none() ClassStyle {
        const result = ClassStyle{
            .dbl_clks = false,
        };

        return result;
    }

    pub fn to_uint(self: ClassStyle) u32 {
        var result: u32 = 0;

        if (self.byte_align_client) result |= class_byte_align_client;
        if (self.byte_align_window) result |= class_byte_align_window;
        if (self.class_dc) result |= class_class_dc;
        if (self.dbl_clks) result |= class_dbl_clks;
        if (self.drop_shadow) result |= class_drop_shadow;
        if (self.global_class) result |= class_global_class;
        if (self.hredraw) result |= class_hredraw;
        if (self.no_close) result |= class_no_close;
        if (self.own_dc) result |= class_own_dc;
        if (self.parent_dc) result |= class_parent_dc;
        if (self.save_bits) result |= class_save_bits;
        if (self.vredraw) result |= class_vredraw;

        return result;
    }
};

pub const ShowCommand = enum(i32) {
    force_minimize = 11,
    hide = 0,
    minimize = 6,
    restore = 9,
    show = 5,
    show_default = 10,
    show_maximized = 3,
    show_min_no_active = 7,
    show_minimized = 2,
    show_na = 8,
    show_no_activate = 4,
    show_normal = 1,
};

pub const SetPosFlags = struct {
    async_window_pos: bool = false,
    defer_erase: bool = false,
    draw_frame: bool = false,
    frame_changed: bool = false,
    hide_window: bool = false,
    no_activate: bool = false,
    no_copy_bits: bool = false,
    no_move: bool = false,
    no_owner_zorder: bool = false,
    no_redraw: bool = false,
    no_send_changing: bool = false,
    no_size: bool = false,
    no_zorder: bool = false,
    show_window: bool = false,

    pub fn to_uint(self: SetPosFlags) u32 {
        var result: u32 = 0;

        if (self.no_size) result |= setpos_no_size;
        if (self.no_move) result |= setpos_no_move;
        if (self.no_zorder) result |= setpos_no_zorder;
        if (self.no_redraw) result |= setpos_no_redraw;
        if (self.no_activate) result |= setpos_no_activate;
        if (self.frame_changed) result |= setpos_frame_changed;
        if (self.show_window) result |= setpos_show_window;
        if (self.hide_window) result |= setpos_hide_window;
        if (self.no_copy_bits) result |= setpos_no_copy_bits;
        if (self.no_owner_zorder) result |= setpos_no_owner_zorder;
        if (self.no_send_changing) result |= setpos_no_send_changing;
        if (self.draw_frame) result |= setpos_draw_frame;
        if (self.defer_erase) result |= setpos_defer_erase;
        if (self.async_window_pos) result |= setpos_async_window_pos;

        return result;
    }
};

pub const cw_usedefault: i32 = @bitCast(@as(u32, 0x80000000));

pub const Config = struct {
    background: ?w32.HBRUSH = null,
    callback: Callback,
    class_style: ClassStyle = .{},
    context: ?*anyopaque = null,
    cursor: ?w32.HCURSOR = null,
    ex_style: ExStyle = ExStyle.none(),
    height: i32 = cw_usedefault,
    icon: ?w32.HICON = null,
    icon_small: ?w32.HICON = null,
    instance: ?w32.HINSTANCE = null,
    menu: ?w32.HMENU = null,
    name: [:0]const u16,
    parent: ?w32.HWND = null,
    register_taskbar_message: bool = true,
    style: Style = Style.none(),
    width: i32 = cw_usedefault,
    window_name: ?[:0]const u16 = null,
    x: i32 = cw_usedefault,
    y: i32 = cw_usedefault,
};

fn register_class(config: *const Config, instance: w32.HINSTANCE) Error!void {
    std.debug.assert(config.name.len > 0);

    var class = std.mem.zeroes(w32.WNDCLASSEXW);

    class.cbSize = @sizeOf(w32.WNDCLASSEXW);
    class.hbrBackground = config.background;
    class.hCursor = config.cursor;
    class.hIcon = config.icon;
    class.hIconSm = config.icon_small;
    class.hInstance = instance;
    class.lpfnWndProc = config.callback;
    class.lpszClassName = config.name;
    class.style = @bitCast(config.class_style.to_uint());

    const atom = w32.RegisterClassExW(&class);

    if (atom == 0) {
        const err = w32.GetLastError();

        if (err != w32.WIN32_ERROR.ERROR_CLASS_ALREADY_EXISTS) {
            return Error.RegistrationFailed;
        }
    }
}

pub const Window = struct {
    handle: w32.HWND,
    instance: w32.HINSTANCE,
    msg_taskbar: u32,

    pub fn create(config: *const Config) Error!Window {
        std.debug.assert(config.name.len > 0);
        std.debug.assert(config.name.len < name_max);

        if (config.name.len == 0) {
            return Error.InvalidName;
        }

        const instance = config.instance orelse @as(w32.HINSTANCE, @ptrCast(w32.GetModuleHandleW(null)));

        std.debug.assert(@intFromPtr(instance) != 0);

        try register_class(config, instance);

        const window_title = config.window_name orelse config.name;

        const handle = w32.CreateWindowExW(
            @bitCast(config.ex_style.to_uint()),
            config.name,
            window_title,
            @bitCast(config.style.to_uint()),
            config.x,
            config.y,
            config.width,
            config.height,
            config.parent,
            config.menu,
            instance,
            null,
        );

        if (handle == null) {
            return Error.CreationFailed;
        }

        std.debug.assert(handle != null);

        if (config.context) |ctx| {
            _ = w32.SetWindowLongPtrW(handle.?, w32.GWLP_USERDATA, @bitCast(@intFromPtr(ctx)));
        }

        var msg_taskbar: u32 = 0;

        if (config.register_taskbar_message) {
            const taskbar_name = std.unicode.utf8ToUtf16LeStringLiteral("TaskbarCreated");

            msg_taskbar = w32.RegisterWindowMessageW(taskbar_name);
        }

        const result = Window{
            .handle = handle.?,
            .instance = instance,
            .msg_taskbar = msg_taskbar,
        };

        std.debug.assert(result.handle == handle.?);

        return result;
    }

    pub fn begin_paint(self: *const Window, paint_struct: *w32.PAINTSTRUCT) ?w32.HDC {
        std.debug.assert(self.is_valid());

        const result = w32.BeginPaint(self.handle, paint_struct);

        return result;
    }

    pub fn client_to_screen(self: *const Window, point: *w32.POINT) bool {
        std.debug.assert(self.is_valid());

        const result = w32.ClientToScreen(self.handle, point) != 0;

        return result;
    }

    pub fn context(comptime T: type, hwnd: w32.HWND) ?*T {
        const address: i64 = w32.GetWindowLongPtrW(hwnd, w32.GWLP_USERDATA);

        if (address == 0) {
            return null;
        }

        const result: ?*T = @ptrFromInt(@as(u64, @intCast(address)));

        return result;
    }

    pub fn destroy(self: *const Window) bool {
        std.debug.assert(self.is_valid());

        const result = w32.DestroyWindow(self.handle) != 0;

        return result;
    }

    pub fn enable(self: *const Window, enabled: bool) bool {
        std.debug.assert(self.is_valid());

        const result = w32.EnableWindow(self.handle, if (enabled) w32.TRUE else w32.FALSE) != 0;

        return result;
    }

    pub fn end_paint(self: *const Window, paint_struct: *const w32.PAINTSTRUCT) bool {
        std.debug.assert(self.is_valid());

        const result = w32.EndPaint(self.handle, paint_struct) != 0;

        return result;
    }

    pub fn get_client_rect(self: *const Window) ?w32.RECT {
        std.debug.assert(self.is_valid());

        var rect: w32.RECT = undefined;

        if (w32.GetClientRect(self.handle, &rect) == 0) {
            return null;
        }

        return rect;
    }

    pub fn get_dc(self: *const Window) ?w32.HDC {
        std.debug.assert(self.is_valid());

        const result = w32.GetDC(self.handle);

        return result;
    }

    pub fn get_ex_style(self: *const Window) u32 {
        std.debug.assert(self.is_valid());

        const result: u32 = @bitCast(@as(i32, @truncate(w32.GetWindowLongPtrW(self.handle, w32.GWL_EXSTYLE))));

        return result;
    }

    pub fn get_parent(self: *const Window) ?w32.HWND {
        std.debug.assert(self.is_valid());

        const result = w32.GetParent(self.handle);

        return result;
    }

    pub fn get_rect(self: *const Window) ?w32.RECT {
        std.debug.assert(self.is_valid());

        var rect: w32.RECT = undefined;

        if (w32.GetWindowRect(self.handle, &rect) == 0) {
            return null;
        }

        return rect;
    }

    pub fn get_style(self: *const Window) u32 {
        std.debug.assert(self.is_valid());

        const result: u32 = @bitCast(@as(i32, @truncate(w32.GetWindowLongPtrW(self.handle, w32.GWL_STYLE))));

        return result;
    }

    pub fn get_text(self: *const Window, buffer: []u16) i32 {
        std.debug.assert(buffer.len > 0);
        std.debug.assert(self.is_valid());

        const result = w32.GetWindowTextW(self.handle, @ptrCast(buffer.ptr), @intCast(buffer.len));

        return result;
    }

    pub fn get_text_length(self: *const Window) i32 {
        std.debug.assert(self.is_valid());

        const result = w32.GetWindowTextLengthW(self.handle);

        return result;
    }

    pub fn invalidate(self: *const Window, erase: bool) bool {
        std.debug.assert(self.is_valid());

        const result = w32.InvalidateRect(self.handle, null, if (erase) w32.TRUE else w32.FALSE) != 0;

        return result;
    }

    pub fn invalidate_rect(self: *const Window, rect: *const w32.RECT, erase: bool) bool {
        std.debug.assert(self.is_valid());

        const result = w32.InvalidateRect(self.handle, rect, if (erase) w32.TRUE else w32.FALSE) != 0;

        return result;
    }

    pub fn is_enabled(self: *const Window) bool {
        std.debug.assert(self.is_valid());

        const result = w32.IsWindowEnabled(self.handle) != 0;

        return result;
    }

    pub fn is_maximized(self: *const Window) bool {
        std.debug.assert(self.is_valid());

        const result = w32.IsZoomed(self.handle) != 0;

        return result;
    }

    pub fn is_minimized(self: *const Window) bool {
        std.debug.assert(self.is_valid());

        const result = w32.IsIconic(self.handle) != 0;

        return result;
    }

    pub fn is_valid(self: *const Window) bool {
        const result = w32.IsWindow(self.handle) != 0;

        return result;
    }

    pub fn is_visible(self: *const Window) bool {
        std.debug.assert(self.is_valid());

        const result = w32.IsWindowVisible(self.handle) != 0;

        return result;
    }

    pub fn kill_timer(self: *const Window, id: u64) bool {
        std.debug.assert(self.is_valid());

        const result = w32.KillTimer(self.handle, id) != 0;

        return result;
    }

    pub fn move(self: *const Window, x: i32, y: i32) bool {
        std.debug.assert(self.is_valid());

        const result = self.set_pos(x, y, 0, 0, SetPosFlags{ .no_size = true, .no_zorder = true });

        return result;
    }

    pub fn post(self: *const Window, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) bool {
        std.debug.assert(self.is_valid());

        const result = w32.PostMessageW(self.handle, message, wparam, lparam) != 0;

        return result;
    }

    pub fn release_capture() bool {
        const result = w32.ReleaseCapture() != 0;

        return result;
    }

    pub fn release_dc(self: *const Window, hdc: w32.HDC) bool {
        std.debug.assert(self.is_valid());

        const result = w32.ReleaseDC(self.handle, hdc) != 0;

        return result;
    }

    pub fn resize(self: *const Window, width: i32, height: i32) bool {
        std.debug.assert(self.is_valid());

        const result = self.set_pos(0, 0, width, height, SetPosFlags{ .no_move = true, .no_zorder = true });

        return result;
    }

    pub fn screen_to_client(self: *const Window, point: *w32.POINT) bool {
        std.debug.assert(self.is_valid());

        const result = w32.ScreenToClient(self.handle, point) != 0;

        return result;
    }

    pub fn send(self: *const Window, message: u32, wparam: w32.WPARAM, lparam: w32.LPARAM) w32.LRESULT {
        std.debug.assert(self.is_valid());

        const result = w32.SendMessageW(self.handle, message, wparam, lparam);

        return result;
    }

    pub fn set_capture(self: *const Window) ?w32.HWND {
        std.debug.assert(self.is_valid());

        const result = w32.SetCapture(self.handle);

        return result;
    }

    pub fn set_context(self: *const Window, context_ptr: *anyopaque) void {
        std.debug.assert(self.is_valid());

        _ = w32.SetWindowLongPtrW(self.handle, w32.GWLP_USERDATA, @bitCast(@intFromPtr(context_ptr)));
    }

    pub fn set_ex_style(self: *const Window, style: u32) void {
        std.debug.assert(self.is_valid());

        _ = w32.SetWindowLongPtrW(self.handle, w32.GWL_EXSTYLE, @as(i64, @bitCast(@as(i64, @intCast(style)))));
    }

    pub fn set_focus(self: *const Window) ?w32.HWND {
        std.debug.assert(self.is_valid());

        const result = w32.SetFocus(self.handle);

        return result;
    }

    pub fn set_foreground(self: *const Window) bool {
        std.debug.assert(self.is_valid());

        const result = w32.SetForegroundWindow(self.handle) != 0;

        return result;
    }

    pub fn set_parent(self: *const Window, parent: ?w32.HWND) ?w32.HWND {
        std.debug.assert(self.is_valid());

        const result = w32.SetParent(self.handle, parent);

        return result;
    }

    pub fn set_pos(self: *const Window, x: i32, y: i32, width: i32, height: i32, flags: SetPosFlags) bool {
        std.debug.assert(self.is_valid());

        const result = w32.SetWindowPos(self.handle, null, x, y, width, height, @bitCast(flags.to_uint())) != 0;

        return result;
    }

    pub fn set_style(self: *const Window, style: u32) void {
        std.debug.assert(self.is_valid());

        _ = w32.SetWindowLongPtrW(self.handle, w32.GWL_STYLE, @as(i64, @bitCast(@as(i64, @intCast(style)))));
    }

    pub fn set_text(self: *const Window, text_content: []const u8) bool {
        std.debug.assert(text_content.len < name_max);
        std.debug.assert(self.is_valid());

        var wide: [name_max]u16 = undefined;

        const length = std.unicode.utf8ToUtf16Le(&wide, text_content) catch return false;

        wide[length] = 0;

        const result = w32.SetWindowTextW(self.handle, @ptrCast(&wide)) != 0;

        return result;
    }

    pub fn set_timer(self: *const Window, id: u64, interval_ms: u32) u64 {
        std.debug.assert(interval_ms > 0);
        std.debug.assert(self.is_valid());

        const result = w32.SetTimer(self.handle, id, interval_ms, null);

        return result;
    }

    pub fn set_topmost(self: *const Window, topmost: bool) bool {
        std.debug.assert(self.is_valid());

        const insert: ?w32.HWND = if (topmost)
            @ptrFromInt(@as(u64, @bitCast(hwnd_topmost)))
        else
            @ptrFromInt(@as(u64, @bitCast(hwnd_notopmost)));

        const result = w32.SetWindowPos(self.handle, insert, 0, 0, 0, 0, .{ .NOMOVE = 1, .NOSIZE = 1 }) != 0;

        return result;
    }

    pub fn show(self: *const Window, command: ShowCommand) bool {
        std.debug.assert(self.is_valid());

        const result = w32.ShowWindow(self.handle, @intFromEnum(command)) != 0;

        return result;
    }

    pub fn update(self: *const Window) bool {
        std.debug.assert(self.is_valid());

        const result = w32.UpdateWindow(self.handle) != 0;

        return result;
    }
};

pub const Loop = struct {
    pub fn peek() ?w32.MSG {
        var message: w32.MSG = undefined;

        if (w32.PeekMessageW(&message, null, 0, 0, .{ .REMOVE = 1 }) == 0) {
            return null;
        }

        return message;
    }

    pub fn process_pending() bool {
        var processed = false;
        var iteration: u32 = 0;
        const process_iteration_max: u32 = 10000;

        while (iteration < process_iteration_max) : (iteration += 1) {
            const message = peek() orelse break;

            if (message.message == w32.WM_QUIT) {
                return true;
            }

            _ = w32.TranslateMessage(&message);
            _ = w32.DispatchMessageW(&message);

            processed = true;
        }

        return processed;
    }

    pub fn quit() void {
        w32.PostQuitMessage(0);
    }

    pub fn quit_with_code(code: i32) void {
        w32.PostQuitMessage(code);
    }

    pub fn run() void {
        var message: w32.MSG = undefined;
        var iteration: u64 = 0;

        while (iteration < iteration_max) : (iteration += 1) {
            const status = w32.GetMessageW(&message, null, 0, 0);

            if (status <= 0) {
                return;
            }

            _ = w32.TranslateMessage(&message);
            _ = w32.DispatchMessageW(&message);
        }
    }

    pub fn wait_message() bool {
        const result = w32.WaitMessage() != 0;

        return result;
    }
};
