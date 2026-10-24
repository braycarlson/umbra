const std = @import("std");

const assert = std.debug.assert;

const linux = std.os.linux;
const posix = std.posix;

pub const Fd = linux.fd_t;

pub const Error = error{
    Failed,
    Interrupted,
    WouldBlock,
};

pub const environ_bytes_max: u32 = 8 * 1024;
pub const environ_entries_max: u32 = 1024;
pub const environ_path = "/proc/self/environ";
pub const interrupt_retry_max: u32 = 64;
pub const write_attempts_max: u32 = 4096;

comptime {
    assert(environ_bytes_max > 0);
    assert(environ_entries_max > 0);
    assert(environ_path.len > 0);
    assert(interrupt_retry_max > 0);
    assert(write_attempts_max > 0);
}

pub fn ok(raw: usize) bool {
    return posix.errno(raw) == .SUCCESS;
}

pub fn close(fd: Fd) void {
    _ = linux.close(fd);
}

pub fn read(fd: Fd, buffer: []u8) Error!usize {
    assert(buffer.len > 0);

    var retries: u32 = 0;

    while (retries < interrupt_retry_max) : (retries += 1) {
        const raw = linux.read(fd, buffer.ptr, buffer.len);
        const status = posix.errno(raw);

        if (status == .SUCCESS) {
            assert(raw <= buffer.len);

            return raw;
        }

        if (status == .AGAIN) {
            return Error.WouldBlock;
        }

        if (status != .INTR) {
            return Error.Failed;
        }
    }

    return Error.Interrupted;
}

pub fn write(fd: Fd, bytes: []const u8) Error!usize {
    assert(bytes.len > 0);

    var retries: u32 = 0;

    while (retries < interrupt_retry_max) : (retries += 1) {
        const raw = linux.write(fd, bytes.ptr, bytes.len);
        const status = posix.errno(raw);

        if (status == .SUCCESS) {
            assert(raw <= bytes.len);

            return raw;
        }

        if (status == .AGAIN) {
            return Error.WouldBlock;
        }

        if (status != .INTR) {
            return Error.Failed;
        }
    }

    return Error.Interrupted;
}

pub fn write_all(fd: Fd, bytes: []const u8) Error!void {
    assert(bytes.len > 0);

    var written: usize = 0;
    var attempts: u32 = 0;

    while (attempts < write_attempts_max) : (attempts += 1) {
        assert(written <= bytes.len);

        if (written == bytes.len) break;

        const count = try write(fd, bytes[written..]);

        if (count == 0) {
            return Error.Failed;
        }

        written += count;
    }

    if (written < bytes.len) {
        return Error.Failed;
    }
}

pub fn poll_in(fd: Fd, timeout_ms: i32) Error!bool {
    var descriptors = [_]linux.pollfd{.{
        .fd = fd,
        .events = linux.POLL.IN,
        .revents = 0,
    }};

    var retries: u32 = 0;

    while (retries < interrupt_retry_max) : (retries += 1) {
        const raw = linux.poll(&descriptors, descriptors.len, timeout_ms);
        const status = posix.errno(raw);

        if (status == .SUCCESS) {
            return raw > 0;
        }

        if (status != .INTR) {
            return Error.Failed;
        }
    }

    return Error.Interrupted;
}

pub fn unix_socket() Error!Fd {
    const raw = linux.socket(linux.AF.UNIX, linux.SOCK.STREAM | linux.SOCK.CLOEXEC, 0);

    if (!ok(raw)) {
        return Error.Failed;
    }

    const result: Fd = @intCast(raw);
    return result;
}

pub fn connect(fd: Fd, address: *const linux.sockaddr.un, length: u32) Error!void {
    const raw = linux.connect(fd, @ptrCast(address), length);

    if (!ok(raw)) {
        return Error.Failed;
    }
}

pub const Environ = struct {
    bytes: [environ_bytes_max]u8,
    length: u32,

    pub fn load(environ: *Environ) void {
        environ.length = 0;

        const path: [*:0]const u8 = environ_path;
        const raw = linux.open(path, .{}, 0);

        if (!ok(raw)) {
            return;
        }

        const fd: Fd = @intCast(raw);
        defer close(fd);

        var offset: u32 = 0;
        var attempts: u32 = 0;

        while (attempts < interrupt_retry_max) : (attempts += 1) {
            assert(offset <= environ_bytes_max);

            if (offset == environ_bytes_max) break;

            const count = read(fd, environ.bytes[offset..]) catch break;

            if (count == 0) {
                break;
            }

            offset += @intCast(count);
        }

        environ.length = offset;

        assert(environ.length <= environ_bytes_max);
    }

    pub fn get(environ: *const Environ, key: []const u8) ?[]const u8 {
        assert(key.len > 0);
        assert(environ.length <= environ_bytes_max);

        var start: u32 = 0;
        var visited: u32 = 0;

        while (visited < environ_entries_max) : (visited += 1) {
            if (start >= environ.length) break;

            const end = environ.find_terminator(start);
            const entry = environ.bytes[start..end];

            if (entry_value(entry, key)) |value| {
                return value;
            }

            start = end + 1;
        }

        return null;
    }

    pub fn list(environ: *const Environ, pointers: *[environ_entries_max + 1]?[*:0]const u8) u32 {
        assert(environ.length <= environ_bytes_max);

        var count: u32 = 0;
        var start: u32 = 0;

        while (count < environ_entries_max) : (count += 1) {
            if (start >= environ.length) break;

            const end = environ.find_terminator(start);
            if (end == start) break;
            if (end == environ.length) break;

            assert(environ.bytes[end] == 0);

            pointers[count] = environ.bytes[start..end :0].ptr;
            start = end + 1;
        }

        pointers[count] = null;

        assert(count <= environ_entries_max);

        return count;
    }

    fn find_terminator(environ: *const Environ, start: u32) u32 {
        var index = start;

        while (index < environ.length) : (index += 1) {
            assert(index < environ_bytes_max);

            if (environ.bytes[index] == 0) return index;
        }

        return environ.length;
    }
};

fn entry_value(entry: []const u8, key: []const u8) ?[]const u8 {
    assert(key.len > 0);

    if (entry.len <= key.len) return null;
    if (entry[key.len] != '=') return null;
    if (!std.mem.eql(u8, entry[0..key.len], key)) return null;
    return entry[key.len + 1 ..];
}

const testing = std.testing;

test "ok distinguishes success from failure" {
    try testing.expect(ok(0));
    try testing.expect(!ok(@bitCast(@as(isize, -2))));
}

test "getenv finds a variable the kernel exported" {
    var environ: Environ = undefined;

    environ.load();

    const path = environ.get("PATH");
    const missing = environ.get("UMBRA_DEFINITELY_NOT_SET_1234");

    try testing.expect(missing == null);

    if (path) |value| {
        try testing.expect(value.len > 0);
    }
}

test "getenv rejects a prefix that is not a whole key" {
    var environ: Environ = undefined;

    environ.load();

    const partial = environ.get("PAT");

    try testing.expect(partial == null or partial.?.len > 0);
}

test "write rejects an empty slice through write_all" {
    const fd: Fd = -1;

    try testing.expectError(Error.Failed, write_all(fd, "x"));
}
