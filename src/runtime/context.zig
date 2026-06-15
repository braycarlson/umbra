const std = @import("std");

pub fn Context(comptime T: type) type {
    return struct {
        ptr: *T,

        const Self = @This();

        pub fn init(ptr: *T) Self {
            return Self{ .ptr = ptr };
        }

        pub fn get(self: Self) *T {
            return self.ptr;
        }
    };
}

pub const AnyContext = struct {
    ptr: *anyopaque,
    type_id: u64,

    pub fn init(comptime T: type, ptr: *T) AnyContext {
        const result = AnyContext{
            .ptr = @ptrCast(ptr),
            .type_id = type_hash(T),
        };

        std.debug.assert(result.type_id != 0);

        return result;
    }

    pub fn cast(self: AnyContext, comptime T: type) ?*T {
        std.debug.assert(self.type_id != 0);

        if (self.type_id != type_hash(T)) {
            return null;
        }

        const result: *T = @ptrCast(@alignCast(self.ptr));

        return result;
    }

    fn type_hash(comptime T: type) u64 {
        return @intCast(@intFromPtr(@typeName(T).ptr));
    }
};
