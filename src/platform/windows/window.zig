const std = @import("std");

const w32 = @import("win32.zig");

const assert = std.debug.assert;

pub const name_max: u32 = 256;

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

    pub fn none() Style {
        const result = Style{
            .overlapped = false,
        };

        return result;
    }

    pub fn to_uint(style: Style) u32 {
        var result: u32 = 0;

        if (style.border) result |= style_border;
        if (style.caption) result |= style_caption;
        if (style.child) result |= style_child;
        if (style.clip_children) result |= style_clip_children;
        if (style.clip_siblings) result |= style_clip_siblings;
        if (style.disabled) result |= style_disabled;
        if (style.dlg_frame) result |= style_dlg_frame;
        if (style.group) result |= style_group;
        if (style.hscroll) result |= style_hscroll;
        if (style.maximize) result |= style_maximize;
        if (style.maximize_box) result |= style_maximize_box;
        if (style.minimize) result |= style_minimize;
        if (style.minimize_box) result |= style_minimize_box;
        if (style.overlapped) result |= style_overlapped;
        if (style.popup) result |= style_popup;
        if (style.sysmenu) result |= style_sysmenu;
        if (style.tabstop) result |= style_tabstop;
        if (style.thickframe) result |= style_thickframe;
        if (style.visible) result |= style_visible;
        if (style.vscroll) result |= style_vscroll;

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
        return ExStyle{};
    }

    pub fn to_uint(style: ExStyle) u32 {
        var result: u32 = 0;

        if (style.accept_files) result |= exstyle_accept_files;
        if (style.app_window) result |= exstyle_app_window;
        if (style.client_edge) result |= exstyle_client_edge;
        if (style.composited) result |= exstyle_composited;
        if (style.context_help) result |= exstyle_context_help;
        if (style.control_parent) result |= exstyle_control_parent;
        if (style.dlg_modal_frame) result |= exstyle_dlg_modal_frame;
        if (style.layered) result |= exstyle_layered;
        if (style.layout_rtl) result |= exstyle_layout_rtl;
        if (style.left) result |= exstyle_left;
        if (style.left_scrollbar) result |= exstyle_left_scrollbar;
        if (style.mdi_child) result |= exstyle_mdi_child;
        if (style.no_activate) result |= exstyle_no_activate;
        if (style.no_inherit_layout) result |= exstyle_no_inherit_layout;
        if (style.no_parent_notify) result |= exstyle_no_parent_notify;
        if (style.no_redirection_bitmap) result |= exstyle_no_redirection_bitmap;
        if (style.overlapped_window) result |= exstyle_overlapped_window;
        if (style.palette_window) result |= exstyle_palette_window;
        if (style.right) result |= exstyle_right;
        if (style.right_scrollbar) result |= exstyle_right_scrollbar;
        if (style.rtl_reading) result |= exstyle_rtl_reading;
        if (style.static_edge) result |= exstyle_static_edge;
        if (style.tool_window) result |= exstyle_tool_window;
        if (style.topmost) result |= exstyle_topmost;
        if (style.transparent) result |= exstyle_transparent;
        if (style.window_edge) result |= exstyle_window_edge;

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

    pub fn to_uint(style: ClassStyle) u32 {
        var result: u32 = 0;

        if (style.byte_align_client) result |= class_byte_align_client;
        if (style.byte_align_window) result |= class_byte_align_window;
        if (style.class_dc) result |= class_class_dc;
        if (style.dbl_clks) result |= class_dbl_clks;
        if (style.drop_shadow) result |= class_drop_shadow;
        if (style.global_class) result |= class_global_class;
        if (style.hredraw) result |= class_hredraw;
        if (style.no_close) result |= class_no_close;
        if (style.own_dc) result |= class_own_dc;
        if (style.parent_dc) result |= class_parent_dc;
        if (style.save_bits) result |= class_save_bits;
        if (style.vredraw) result |= class_vredraw;

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
    style: Style = Style.none(),
    width: i32 = cw_usedefault,
    window_name: ?[:0]const u16 = null,
    x: i32 = cw_usedefault,
    y: i32 = cw_usedefault,
};

fn register_class(config: *const Config, instance: w32.HINSTANCE) Error!void {
    assert(config.name.len > 0);

    var class = std.mem.zeroes(w32.WNDCLASSEXW);

    class.cbSize = @sizeOf(w32.WNDCLASSEXW);
    class.hbrBackground = config.background;
    class.hCursor = config.cursor;
    class.hIcon = config.icon;
    class.hIconSm = config.icon_small;
    class.hInstance = instance;
    class.lpfnWndProc = config.callback;
    class.lpszClassName = config.name;
    class.style = config.class_style.to_uint();

    const atom = w32.RegisterClassExW(&class);

    if (atom == 0) {
        const err = w32.GetLastError();

        if (err != w32.ERROR_CLASS_ALREADY_EXISTS) {
            return Error.RegistrationFailed;
        }
    }
}

pub const Window = struct {
    handle: w32.HWND,
    instance: w32.HINSTANCE,

    pub fn create(config: *const Config) Error!Window {
        assert(config.name.len > 0);
        assert(config.name.len < name_max);

        if (config.name.len == 0) {
            return Error.InvalidName;
        }

        const module: w32.HINSTANCE = @ptrCast(w32.GetModuleHandleW(null));
        const instance = config.instance orelse module;

        assert(@intFromPtr(instance) != 0);

        try register_class(config, instance);

        const window_title = config.window_name orelse config.name;

        const created = w32.CreateWindowExW(
            config.ex_style.to_uint(),
            config.name,
            window_title,
            config.style.to_uint(),
            config.x,
            config.y,
            config.width,
            config.height,
            config.parent,
            config.menu,
            instance,
            null,
        );

        if (created == null) {
            return Error.CreationFailed;
        }

        assert(created != null);

        if (config.context) |ctx| {
            _ = w32.SetWindowLongPtrW(created.?, w32.GWLP_USERDATA, @bitCast(@intFromPtr(ctx)));
        }

        const result = Window{
            .handle = created.?,
            .instance = instance,
        };

        assert(result.handle == created.?);

        return result;
    }

    pub fn destroy(window: *const Window) bool {
        assert(window.is_valid());

        return w32.DestroyWindow(window.handle) != 0;
    }

    pub fn is_valid(window: *const Window) bool {
        return w32.IsWindow(window.handle) != 0;
    }
};

pub const Handle = w32.HWND;

var current: ?Window = null;

pub fn open(config: *const Config) Error!void {
    if (current != null) {
        return Error.CreationFailed;
    }

    current = try Window.create(config);

    assert(current != null);
}

pub fn close() void {
    const live = current orelse return;

    _ = live.destroy();

    current = null;

    assert(current == null);
}

pub fn is_open() bool {
    return current != null;
}

pub fn handle() ?Handle {
    const live = current orelse return null;

    return live.handle;
}

pub fn post(message: u32, wparam: u64, lparam: i64) bool {
    const target = handle() orelse return false;

    const native_wparam: w32.WPARAM = @truncate(wparam);
    const native_lparam: w32.LPARAM = @truncate(lparam);

    return w32.PostMessageW(target, message, native_wparam, native_lparam) != 0;
}

const testing = std.testing;

test "an empty window style converts to no bits" {
    const style = Style.none();

    try testing.expectEqual(@as(u32, 0), style.to_uint());
}

test "a window style carries its border flag" {
    const style = Style{ .border = true, .overlapped = false };

    try testing.expectEqual(@as(u32, 0x00800000), style.to_uint());
}

test "a window style carries its caption flag" {
    const style = Style{ .caption = true, .overlapped = false };

    try testing.expectEqual(@as(u32, 0x00C00000), style.to_uint());
}

test "a window style carries its visible flag" {
    const style = Style{ .visible = true, .overlapped = false };

    try testing.expectEqual(@as(u32, 0x10000000), style.to_uint());
}

test "a window style carries its popup flag" {
    const style = Style{ .popup = true, .overlapped = false };

    try testing.expectEqual(@as(u32, 0x80000000), style.to_uint());
}

test "a window style carries its overlapped flag" {
    const style = Style{ .overlapped = true };

    try testing.expectEqual(@as(u32, 0x00000000), style.to_uint());
}

test "a window style combines several flags" {
    const style = Style{
        .border = true,
        .caption = true,
        .visible = true,
        .overlapped = false,
    };

    try testing.expectEqual(@as(u32, 0x10C00000), style.to_uint());
}

test "an empty window style holds no flags" {
    const style = Style.none();

    try testing.expect(!style.border);
    try testing.expect(!style.caption);
    try testing.expect(!style.child);
    try testing.expect(!style.clip_children);
    try testing.expect(!style.clip_siblings);
    try testing.expect(!style.disabled);
    try testing.expect(!style.dlg_frame);
    try testing.expect(!style.group);
    try testing.expect(!style.hscroll);
    try testing.expect(!style.maximize);
    try testing.expect(!style.maximize_box);
    try testing.expect(!style.minimize);
    try testing.expect(!style.minimize_box);
    try testing.expect(!style.overlapped);
    try testing.expect(!style.popup);
    try testing.expect(!style.thickframe);
    try testing.expect(!style.sysmenu);
    try testing.expect(!style.tabstop);
    try testing.expect(!style.visible);
    try testing.expect(!style.vscroll);
}

test "an empty extended style converts to no bits" {
    const style = ExStyle.none();

    try testing.expectEqual(@as(u32, 0), style.to_uint());
}

test "an extended style carries its topmost flag" {
    const style = ExStyle{ .topmost = true };

    try testing.expectEqual(@as(u32, 0x00000008), style.to_uint());
}

test "an extended style carries its transparent flag" {
    const style = ExStyle{ .transparent = true };

    try testing.expectEqual(@as(u32, 0x00000020), style.to_uint());
}

test "an extended style carries its tool window flag" {
    const style = ExStyle{ .tool_window = true };

    try testing.expectEqual(@as(u32, 0x00000080), style.to_uint());
}

test "an extended style carries its app window flag" {
    const style = ExStyle{ .app_window = true };

    try testing.expectEqual(@as(u32, 0x00040000), style.to_uint());
}

test "an extended style carries its layered flag" {
    const style = ExStyle{ .layered = true };

    try testing.expectEqual(@as(u32, 0x00080000), style.to_uint());
}

test "an empty extended style holds no flags" {
    const style = ExStyle.none();

    try testing.expect(!style.accept_files);
    try testing.expect(!style.app_window);
    try testing.expect(!style.client_edge);
    try testing.expect(!style.composited);
    try testing.expect(!style.context_help);
    try testing.expect(!style.control_parent);
    try testing.expect(!style.dlg_modal_frame);
    try testing.expect(!style.layered);
    try testing.expect(!style.layout_rtl);
    try testing.expect(!style.left);
    try testing.expect(!style.left_scrollbar);
    try testing.expect(!style.mdi_child);
    try testing.expect(!style.no_activate);
    try testing.expect(!style.no_inherit_layout);
    try testing.expect(!style.no_parent_notify);
    try testing.expect(!style.no_redirection_bitmap);
    try testing.expect(!style.overlapped_window);
    try testing.expect(!style.palette_window);
    try testing.expect(!style.right);
    try testing.expect(!style.right_scrollbar);
    try testing.expect(!style.rtl_reading);
    try testing.expect(!style.static_edge);
    try testing.expect(!style.tool_window);
    try testing.expect(!style.topmost);
    try testing.expect(!style.transparent);
    try testing.expect(!style.window_edge);
}

test "a default class style converts to no bits" {
    const style = ClassStyle{};

    try testing.expectEqual(@as(u32, 0x0008), style.to_uint());
}

test "a class style carries its vertical redraw flag" {
    const style = ClassStyle{ .vredraw = true };

    try testing.expectEqual(@as(u32, 0x0009), style.to_uint());
}

test "a class style carries its horizontal redraw flag" {
    const style = ClassStyle{ .hredraw = true };

    try testing.expectEqual(@as(u32, 0x000A), style.to_uint());
}

test "a class style carries its double click flag" {
    const style = ClassStyle{ .dbl_clks = true };

    try testing.expectEqual(@as(u32, 0x0008), style.to_uint());
}

test "a class style combines several flags" {
    const style = ClassStyle{
        .vredraw = true,
        .hredraw = true,
        .dbl_clks = true,
    };

    try testing.expectEqual(@as(u32, 0x000B), style.to_uint());
}
