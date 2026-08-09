const std = @import("std");

const assert = std.debug.assert;

pub const BOOL = i32;
pub const ATOM = u16;
pub const WPARAM = usize;
pub const LPARAM = isize;
pub const LRESULT = isize;

pub const HANDLE = *opaque {};
pub const HBITMAP = *opaque {};
pub const HBRUSH = *opaque {};
pub const HCURSOR = *opaque {};
pub const HDC = *opaque {};
pub const HICON = *opaque {};
pub const HINSTANCE = *opaque {};
pub const HMENU = *opaque {};
pub const HWND = *opaque {};

pub const WNDPROC = *const fn (HWND, u32, WPARAM, LPARAM) callconv(.winapi) LRESULT;

pub const TRUE: BOOL = 1;
pub const FALSE: BOOL = 0;

pub const INFINITE: u32 = 0xFFFFFFFF;
pub const S_OK: i32 = 0;

pub const WAIT_OBJECT_0: u32 = 0x00000000;

pub const ERROR_IO_PENDING: u32 = 997;
pub const ERROR_CLASS_ALREADY_EXISTS: u32 = 1410;

pub const GWLP_USERDATA: i32 = -21;

pub const IMAGE_ICON: u32 = 1;
pub const LR_DEFAULTSIZE: u32 = 0x00000040;
pub const LR_LOADFROMFILE: u32 = 0x00000010;
pub const LR_SHARED: u32 = 0x00008000;

pub const DIB_RGB_COLORS: u32 = 0;
pub const BI_RGB: u32 = 0;

pub const NIM_ADD: u32 = 0x00000000;
pub const NIM_MODIFY: u32 = 0x00000001;
pub const NIM_DELETE: u32 = 0x00000002;
pub const NIM_SETFOCUS: u32 = 0x00000003;
pub const NIM_SETVERSION: u32 = 0x00000004;

pub const NIF_MESSAGE: u32 = 0x00000001;
pub const NIF_ICON: u32 = 0x00000002;
pub const NIF_TIP: u32 = 0x00000004;
pub const NIF_STATE: u32 = 0x00000008;
pub const NIF_INFO: u32 = 0x00000010;
pub const NIF_SHOWTIP: u32 = 0x00000080;

pub const MF_BYPOSITION: u32 = 0x00000400;

pub const MIIM_STATE: u32 = 0x00000001;
pub const MIIM_ID: u32 = 0x00000002;
pub const MIIM_SUBMENU: u32 = 0x00000004;
pub const MIIM_CHECKMARKS: u32 = 0x00000008;
pub const MIIM_DATA: u32 = 0x00000020;
pub const MIIM_STRING: u32 = 0x00000040;
pub const MIIM_BITMAP: u32 = 0x00000080;
pub const MIIM_FTYPE: u32 = 0x00000100;

pub const MFT_STRING: u32 = 0x00000000;
pub const MFT_BITMAP: u32 = 0x00000004;
pub const MFT_SEPARATOR: u32 = 0x00000800;
pub const MFT_OWNERDRAW: u32 = 0x00000100;

pub const OPEN_EXISTING: u32 = 3;
pub const INVALID_HANDLE_VALUE: HANDLE = @ptrFromInt(std.math.maxInt(usize));

pub const FILE_SHARE_READ: u32 = 0x00000001;
pub const FILE_SHARE_WRITE: u32 = 0x00000002;
pub const FILE_SHARE_DELETE: u32 = 0x00000004;

pub const FILE_NOTIFY_CHANGE_LAST_WRITE: u32 = 0x00000010;

pub const WM_DESTROY: u32 = 0x0002;
pub const WM_TIMER: u32 = 0x0113;
pub const WM_CONTEXTMENU: u32 = 0x007B;
pub const WM_MOUSEMOVE: u32 = 0x0200;
pub const WM_LBUTTONDOWN: u32 = 0x0201;
pub const WM_LBUTTONUP: u32 = 0x0202;
pub const WM_LBUTTONDBLCLK: u32 = 0x0203;
pub const WM_RBUTTONDOWN: u32 = 0x0204;
pub const WM_RBUTTONUP: u32 = 0x0205;
pub const WM_RBUTTONDBLCLK: u32 = 0x0206;
pub const WM_MBUTTONDOWN: u32 = 0x0207;
pub const WM_MBUTTONUP: u32 = 0x0208;
pub const WM_MBUTTONDBLCLK: u32 = 0x0209;
pub const WM_APP: u32 = 0x8000;

comptime {
    assert(WM_APP == 0x8000);
    assert(NIF_SHOWTIP == 0x80);
    assert(MIIM_FTYPE == 0x100);
}

pub const GUID = extern struct {
    Data1: u32 = 0,
    Data2: u16 = 0,
    Data3: u16 = 0,
    Data4: [8]u8 = [_]u8{0} ** 8,
};

pub const POINT = extern struct {
    x: i32,
    y: i32,
};

pub const RECT = extern struct {
    left: i32,
    top: i32,
    right: i32,
    bottom: i32,
};

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    time: u32,
    pt: POINT,
};

pub const WNDCLASSEXW = extern struct {
    cbSize: u32,
    style: u32,
    lpfnWndProc: ?WNDPROC,
    cbClsExtra: i32,
    cbWndExtra: i32,
    hInstance: ?HINSTANCE,
    hIcon: ?HICON,
    hCursor: ?HCURSOR,
    hbrBackground: ?HBRUSH,
    lpszMenuName: ?[*:0]const u16,
    lpszClassName: ?[*:0]const u16,
    hIconSm: ?HICON,
};

pub const ICONINFO = extern struct {
    fIcon: BOOL,
    xHotspot: u32,
    yHotspot: u32,
    hbmMask: ?HBITMAP,
    hbmColor: ?HBITMAP,
};

pub const BITMAPINFOHEADER = extern struct {
    biSize: u32,
    biWidth: i32,
    biHeight: i32,
    biPlanes: u16,
    biBitCount: u16,
    biCompression: u32,
    biSizeImage: u32,
    biXPelsPerMeter: i32,
    biYPelsPerMeter: i32,
    biClrUsed: u32,
    biClrImportant: u32,
};

pub const RGBQUAD = extern struct {
    rgbBlue: u8,
    rgbGreen: u8,
    rgbRed: u8,
    rgbReserved: u8,
};

pub const BITMAPINFO = extern struct {
    bmiHeader: BITMAPINFOHEADER,
    bmiColors: [1]RGBQUAD,
};

pub const NOTIFYICONDATAW = extern struct {
    cbSize: u32,
    hWnd: ?HWND,
    uID: u32,
    uFlags: u32,
    uCallbackMessage: u32,
    hIcon: ?HICON,
    szTip: [128]u16,
    dwState: u32,
    dwStateMask: u32,
    szInfo: [256]u16,
    uVersionOrTimeout: u32,
    szInfoTitle: [64]u16,
    dwInfoFlags: u32,
    guidItem: GUID,
    hBalloonIcon: ?HICON,
};

pub const NOTIFYICONIDENTIFIER = extern struct {
    cbSize: u32,
    hWnd: ?HWND,
    uID: u32,
    guidItem: GUID,
};

pub const MENUITEMINFOW = extern struct {
    cbSize: u32,
    fMask: u32,
    fType: u32,
    fState: u32,
    wID: u32,
    hSubMenu: ?HMENU,
    hbmpChecked: ?HBITMAP,
    hbmpUnchecked: ?HBITMAP,
    dwItemData: usize,
    dwTypeData: ?[*:0]u16,
    cch: u32,
    hbmpItem: ?HBITMAP,
};

pub const OVERLAPPED = extern struct {
    Internal: usize,
    InternalHigh: usize,
    Offset: u32,
    OffsetHigh: u32,
    hEvent: ?HANDLE,
};

pub const FILE_NOTIFY_INFORMATION = extern struct {
    NextEntryOffset: u32,
    Action: u32,
    FileNameLength: u32,
    FileName: [1]u16,
};

pub const SECURITY_ATTRIBUTES = extern struct {
    nLength: u32,
    lpSecurityDescriptor: ?*anyopaque,
    bInheritHandle: BOOL,
};

pub extern "kernel32" fn CloseHandle(hObject: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn CancelIo(hFile: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn CreateEventW(
    lpEventAttributes: ?*SECURITY_ATTRIBUTES,
    bManualReset: BOOL,
    bInitialState: BOOL,
    lpName: ?[*:0]const u16,
) callconv(.winapi) ?HANDLE;
pub extern "kernel32" fn CreateFileW(
    lpFileName: [*:0]const u16,
    dwDesiredAccess: u32,
    dwShareMode: u32,
    lpSecurityAttributes: ?*SECURITY_ATTRIBUTES,
    dwCreationDisposition: u32,
    dwFlagsAndAttributes: u32,
    hTemplateFile: ?HANDLE,
) callconv(.winapi) HANDLE;
pub extern "kernel32" fn GetEnvironmentVariableW(
    lpName: [*:0]const u16,
    lpBuffer: ?[*]u16,
    nSize: u32,
) callconv(.winapi) u32;
pub extern "kernel32" fn GetLastError() callconv(.winapi) u32;
pub extern "kernel32" fn GetModuleHandleW(
    lpModuleName: ?[*:0]const u16,
) callconv(.winapi) ?HINSTANCE;
pub extern "kernel32" fn GetOverlappedResult(
    hFile: HANDLE,
    lpOverlapped: *OVERLAPPED,
    lpNumberOfBytesTransferred: *u32,
    bWait: BOOL,
) callconv(.winapi) BOOL;
pub extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
pub extern "kernel32" fn ReadDirectoryChangesW(
    hDirectory: HANDLE,
    lpBuffer: *anyopaque,
    nBufferLength: u32,
    bWatchSubtree: BOOL,
    dwNotifyFilter: u32,
    lpBytesReturned: ?*u32,
    lpOverlapped: ?*OVERLAPPED,
    lpCompletionRoutine: ?*anyopaque,
) callconv(.winapi) BOOL;
pub extern "kernel32" fn ResetEvent(hEvent: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn SetEvent(hEvent: HANDLE) callconv(.winapi) BOOL;
pub extern "kernel32" fn Sleep(dwMilliseconds: u32) callconv(.winapi) void;
pub extern "kernel32" fn WaitForMultipleObjects(
    nCount: u32,
    lpHandles: [*]const HANDLE,
    bWaitAll: BOOL,
    dwMilliseconds: u32,
) callconv(.winapi) u32;

pub extern "gdi32" fn CreateBitmap(
    nWidth: i32,
    nHeight: i32,
    nPlanes: u32,
    nBitCount: u32,
    lpBits: ?*const anyopaque,
) callconv(.winapi) ?HBITMAP;
pub extern "gdi32" fn CreateDIBSection(
    hdc: ?HDC,
    pbmi: *const BITMAPINFO,
    usage: u32,
    ppvBits: *?*anyopaque,
    hSection: ?HANDLE,
    offset: u32,
) callconv(.winapi) ?HBITMAP;
pub extern "gdi32" fn DeleteObject(ho: HBITMAP) callconv(.winapi) BOOL;

pub extern "user32" fn CreateIconIndirect(piconinfo: *ICONINFO) callconv(.winapi) ?HICON;
pub extern "user32" fn CreateMenu() callconv(.winapi) ?HMENU;
pub extern "user32" fn CreatePopupMenu() callconv(.winapi) ?HMENU;
pub extern "user32" fn CreateWindowExW(
    dwExStyle: u32,
    lpClassName: ?[*:0]const u16,
    lpWindowName: ?[*:0]const u16,
    dwStyle: u32,
    X: i32,
    Y: i32,
    nWidth: i32,
    nHeight: i32,
    hWndParent: ?HWND,
    hMenu: ?HMENU,
    hInstance: ?HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.winapi) ?HWND;
pub extern "user32" fn DefWindowProcW(
    hWnd: HWND,
    Msg: u32,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.winapi) LRESULT;
pub extern "user32" fn DeleteMenu(
    hMenu: HMENU,
    uPosition: u32,
    uFlags: u32,
) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyIcon(hIcon: HICON) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyMenu(hMenu: HMENU) callconv(.winapi) BOOL;
pub extern "user32" fn DestroyWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn DispatchMessageW(lpMsg: *const MSG) callconv(.winapi) LRESULT;
pub extern "user32" fn GetCursorPos(lpPoint: *POINT) callconv(.winapi) BOOL;
pub extern "user32" fn GetMenuItemCount(hMenu: ?HMENU) callconv(.winapi) i32;
pub extern "user32" fn GetMessageW(
    lpMsg: *MSG,
    hWnd: ?HWND,
    wMsgFilterMin: u32,
    wMsgFilterMax: u32,
) callconv(.winapi) BOOL;
pub extern "user32" fn InsertMenuItemW(
    hmenu: HMENU,
    item: u32,
    fByPosition: BOOL,
    lpmi: *const MENUITEMINFOW,
) callconv(.winapi) BOOL;
pub extern "user32" fn IsWindow(hWnd: ?HWND) callconv(.winapi) BOOL;
pub extern "user32" fn KillTimer(hWnd: ?HWND, uIDEvent: usize) callconv(.winapi) BOOL;
pub extern "user32" fn LoadIconW(
    hInstance: ?HINSTANCE,
    lpIconName: [*:0]align(1) const u16,
) callconv(.winapi) ?HICON;
pub extern "user32" fn LoadImageW(
    hInst: ?HINSTANCE,
    name: [*:0]align(1) const u16,
    type: u32,
    cx: i32,
    cy: i32,
    fuLoad: u32,
) callconv(.winapi) ?HANDLE;
pub extern "user32" fn PostMessageW(
    hWnd: ?HWND,
    Msg: u32,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.winapi) BOOL;
pub extern "user32" fn PostQuitMessage(nExitCode: i32) callconv(.winapi) void;
pub extern "user32" fn RegisterClassExW(unnamedParam1: *const WNDCLASSEXW) callconv(.winapi) ATOM;
pub extern "user32" fn RegisterWindowMessageW(lpString: [*:0]const u16) callconv(.winapi) u32;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.winapi) BOOL;
pub extern "user32" fn SetTimer(
    hWnd: ?HWND,
    nIDEvent: usize,
    uElapse: u32,
    lpTimerFunc: ?*anyopaque,
) callconv(.winapi) usize;
pub extern "user32" fn SetWindowLongPtrW(
    hWnd: HWND,
    nIndex: i32,
    dwNewLong: isize,
) callconv(.winapi) isize;
pub extern "user32" fn TrackPopupMenuEx(
    hMenu: HMENU,
    uFlags: u32,
    x: i32,
    y: i32,
    hwnd: HWND,
    lptpm: ?*anyopaque,
) callconv(.winapi) BOOL;
pub extern "user32" fn TranslateMessage(lpMsg: *const MSG) callconv(.winapi) BOOL;

pub extern "shell32" fn ShellExecuteW(
    hwnd: ?HWND,
    lpOperation: ?[*:0]const u16,
    lpFile: [*:0]const u16,
    lpParameters: ?[*:0]const u16,
    lpDirectory: ?[*:0]const u16,
    nShowCmd: i32,
) callconv(.winapi) ?HINSTANCE;
pub extern "shell32" fn Shell_NotifyIconW(
    dwMessage: u32,
    lpData: *const NOTIFYICONDATAW,
) callconv(.winapi) BOOL;
pub extern "shell32" fn Shell_NotifyIconGetRect(
    identifier: *const NOTIFYICONIDENTIFIER,
    iconLocation: *RECT,
) callconv(.winapi) i32;

const testing = std.testing;

test "handle types are pointer sized" {
    try testing.expectEqual(@sizeOf(usize), @sizeOf(HWND));
    try testing.expectEqual(@sizeOf(usize), @sizeOf(HICON));
    try testing.expectEqual(@sizeOf(usize), @sizeOf(HMENU));
}

test "NOTIFYICONDATAW matches the documented layout" {
    try testing.expectEqual(@as(usize, 0), @offsetOf(NOTIFYICONDATAW, "cbSize"));
    try testing.expectEqual(@as(usize, 8), @offsetOf(NOTIFYICONDATAW, "hWnd"));
    try testing.expectEqual(@as(usize, 16), @offsetOf(NOTIFYICONDATAW, "uID"));
    try testing.expectEqual(@as(usize, 20), @offsetOf(NOTIFYICONDATAW, "uFlags"));
    try testing.expectEqual(@as(usize, 24), @offsetOf(NOTIFYICONDATAW, "uCallbackMessage"));
    try testing.expectEqual(@as(usize, 32), @offsetOf(NOTIFYICONDATAW, "hIcon"));
    try testing.expectEqual(@as(usize, 40), @offsetOf(NOTIFYICONDATAW, "szTip"));
    try testing.expectEqual(@as(usize, 296), @offsetOf(NOTIFYICONDATAW, "dwState"));
    try testing.expectEqual(@as(usize, 304), @offsetOf(NOTIFYICONDATAW, "szInfo"));
    try testing.expectEqual(@as(usize, 816), @offsetOf(NOTIFYICONDATAW, "uVersionOrTimeout"));
    try testing.expectEqual(@as(usize, 820), @offsetOf(NOTIFYICONDATAW, "szInfoTitle"));
    try testing.expectEqual(@as(usize, 948), @offsetOf(NOTIFYICONDATAW, "dwInfoFlags"));
    try testing.expectEqual(@as(usize, 952), @offsetOf(NOTIFYICONDATAW, "guidItem"));
    try testing.expectEqual(@as(usize, 968), @offsetOf(NOTIFYICONDATAW, "hBalloonIcon"));
    try testing.expectEqual(@as(usize, 976), @sizeOf(NOTIFYICONDATAW));
}

test "MENUITEMINFOW matches the documented layout" {
    try testing.expectEqual(@as(usize, 0), @offsetOf(MENUITEMINFOW, "cbSize"));
    try testing.expectEqual(@as(usize, 4), @offsetOf(MENUITEMINFOW, "fMask"));
    try testing.expectEqual(@as(usize, 16), @offsetOf(MENUITEMINFOW, "wID"));
    try testing.expectEqual(@as(usize, 24), @offsetOf(MENUITEMINFOW, "hSubMenu"));
    try testing.expectEqual(@as(usize, 80), @sizeOf(MENUITEMINFOW));
}

test "WNDCLASSEXW matches the documented layout" {
    try testing.expectEqual(@as(usize, 0), @offsetOf(WNDCLASSEXW, "cbSize"));
    try testing.expectEqual(@as(usize, 8), @offsetOf(WNDCLASSEXW, "lpfnWndProc"));
    try testing.expectEqual(@as(usize, 80), @sizeOf(WNDCLASSEXW));
}

test "GUID is sized as documented" {
    try testing.expectEqual(@as(usize, 16), @sizeOf(GUID));
}

test "the message constants match the Windows headers" {
    try testing.expectEqual(@as(u32, 0x0002), WM_DESTROY);
    try testing.expectEqual(@as(u32, 0x0113), WM_TIMER);
    try testing.expectEqual(@as(u32, 0x8001), WM_APP + 1);
    try testing.expectEqual(@as(u32, 1410), ERROR_CLASS_ALREADY_EXISTS);
}
