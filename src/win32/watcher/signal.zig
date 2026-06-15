const std = @import("std");

const w32 = @import("win32").everything;

pub const Error = error{
    EventCreationFailed,
};

pub const Signal = struct {
    handle: w32.HANDLE,

    pub fn create() Error!Signal {
        const handle = w32.CreateEventW(null, w32.TRUE, w32.FALSE, null);

        if (handle == null) {
            return Error.EventCreationFailed;
        }

        std.debug.assert(handle != null);

        const result = Signal{
            .handle = handle.?,
        };

        return result;
    }

    pub fn destroy(self: *const Signal) bool {
        std.debug.assert(self.is_valid());

        const status = w32.CloseHandle(self.handle);
        const result = status != 0;

        return result;
    }

    pub fn is_valid(self: *const Signal) bool {
        const address = @intFromPtr(self.handle);
        const result = address != 0;

        return result;
    }

    pub fn reset(self: *const Signal) bool {
        std.debug.assert(self.is_valid());

        const status = w32.ResetEvent(self.handle);
        const result = status != 0;

        return result;
    }

    pub fn set(self: *const Signal) bool {
        std.debug.assert(self.is_valid());

        const status = w32.SetEvent(self.handle);
        const result = status != 0;

        return result;
    }
};
