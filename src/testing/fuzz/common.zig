const std = @import("std");

const w32 = @import("win32").everything;

pub const iteration_max: u32 = 1024;
pub const shuffle_max: u8 = 16;
pub const weight_max: u32 = 1024;
pub const seed_buffer_size: u8 = 8;
pub const priority_max: u8 = 255;
pub const env_seed_name = "FUZZ_SEED";

pub fn get_random_seed() u64 {
    var counter: w32.LARGE_INTEGER = undefined;

    if (w32.QueryPerformanceCounter(&counter) == 0) {
        const timestamp: u64 = w32.GetTickCount64();

        std.debug.assert(timestamp > 0 or timestamp == 0);

        return timestamp;
    }

    const result: u64 = @bitCast(counter.QuadPart);

    std.debug.assert(result > 0 or result == 0);

    return result;
}

pub fn get_seed_from_env() u64 {
    var buffer: [64:0]u8 = undefined;

    const len = w32.GetEnvironmentVariableA(env_seed_name, &buffer, buffer.len + 1);

    if (len == 0 or len > buffer.len) {
        return get_random_seed();
    }

    const result = parse_seed(buffer[0..len]);

    return result;
}

pub fn parse_seed(text: []const u8) u64 {
    std.debug.assert(text.len > 0 or text.len == 0);

    const result = std.fmt.parseUnsigned(u64, text, 10) catch {
        return get_random_seed();
    };

    std.debug.assert(result > 0 or result == 0);

    return result;
}

pub fn random_enum(comptime E: type, random: *std.Random) E {
    std.debug.assert(@intFromPtr(random) != 0);

    const fields = @typeInfo(E).@"enum".fields;

    comptime std.debug.assert(fields.len > 0);
    comptime std.debug.assert(fields.len <= iteration_max);

    const idx = random.intRangeLessThan(usize, 0, fields.len);

    std.debug.assert(idx < fields.len);

    const values = comptime blk: {
        var arr: [fields.len]E = undefined;
        for (fields, 0..) |f, i| {
            arr[i] = @enumFromInt(f.value);
        }
        break :blk arr;
    };

    const result = values[idx];

    return result;
}

pub fn random_enum_excluding(comptime E: type, random: *std.Random, exclude: E) E {
    std.debug.assert(@intFromPtr(random) != 0);

    const fields = @typeInfo(E).@"enum".fields;

    comptime std.debug.assert(fields.len > 1);
    comptime std.debug.assert(fields.len <= iteration_max);

    const values = comptime blk: {
        var arr: [fields.len]E = undefined;
        for (fields, 0..) |f, i| {
            arr[i] = @enumFromInt(f.value);
        }
        break :blk arr;
    };

    var attempts: u8 = 0;
    var result = values[random.intRangeLessThan(usize, 0, fields.len)];

    while (result == exclude and attempts < shuffle_max) : (attempts += 1) {
        std.debug.assert(attempts < shuffle_max);

        result = values[random.intRangeLessThan(usize, 0, fields.len)];
    }

    std.debug.assert(attempts <= shuffle_max);

    if (result == exclude) {
        for (values) |candidate| {
            if (candidate != exclude) {
                return candidate;
            }
        }
    }

    std.debug.assert(result != exclude);

    return result;
}

pub fn random_bool(random: *std.Random) bool {
    std.debug.assert(@intFromPtr(random) != 0);

    const value = random.intRangeLessThan(u8, 0, 2);

    std.debug.assert(value == 0 or value == 1);

    const result = value == 1;

    return result;
}

pub fn random_bool_weighted(random: *std.Random, true_probability: u8) bool {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(true_probability <= 100);

    const roll = random.intRangeLessThan(u8, 0, 100);

    std.debug.assert(roll < 100);

    const result = roll < true_probability;

    return result;
}

pub fn random_from_slice(comptime T: type, random: *std.Random, items: []const T) T {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(items.len > 0);
    std.debug.assert(items.len <= iteration_max);

    const idx = random.intRangeLessThan(usize, 0, items.len);

    std.debug.assert(idx < items.len);

    const result = items[idx];

    return result;
}

pub fn random_priority(random: *std.Random) u8 {
    std.debug.assert(@intFromPtr(random) != 0);

    const result = random.intRangeAtMost(u8, 0, priority_max);

    std.debug.assert(result <= priority_max);

    return result;
}

pub fn weighted_select(comptime T: type, random: *std.Random, items: []const T, weights: []const u32) T {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(items.len > 0);
    std.debug.assert(items.len == weights.len);
    std.debug.assert(items.len <= iteration_max);

    const total = compute_weight_total(weights);

    std.debug.assert(total > 0);
    std.debug.assert(total <= weight_max * items.len);

    var choice = random.intRangeLessThan(u32, 0, total);
    var i: u32 = 0;

    while (i < weights.len and i < iteration_max) : (i += 1) {
        std.debug.assert(i < weights.len);

        if (choice < weights[i]) {
            std.debug.assert(i < items.len);

            return items[i];
        }

        choice -= weights[i];
    }

    std.debug.assert(i == weights.len or i == iteration_max);
    std.debug.assert(items.len > 0);

    const result = items[items.len - 1];

    return result;
}

fn compute_weight_total(weights: []const u32) u32 {
    std.debug.assert(weights.len > 0);
    std.debug.assert(weights.len <= iteration_max);

    var total: u32 = 0;
    var i: u32 = 0;

    while (i < weights.len and i < iteration_max) : (i += 1) {
        std.debug.assert(i < weights.len);
        std.debug.assert(total <= weight_max * iteration_max);

        total += weights[i];
    }

    std.debug.assert(i == weights.len or i == iteration_max);
    std.debug.assert(total > 0);

    return total;
}

pub fn shuffle(comptime T: type, random: *std.Random, items: []T) void {
    std.debug.assert(@intFromPtr(random) != 0);
    std.debug.assert(items.len <= iteration_max);

    if (items.len <= 1) {
        return;
    }

    std.debug.assert(items.len > 1);

    var i: usize = items.len - 1;

    while (i > 0) : (i -= 1) {
        std.debug.assert(i > 0);
        std.debug.assert(i < items.len);

        const j = random.intRangeLessThan(usize, 0, i + 1);

        std.debug.assert(j <= i);

        const temp = items[i];

        items[i] = items[j];
        items[j] = temp;
    }
}

const testing = std.testing;

test "random_bool produces both values" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var true_count: u32 = 0;
    var false_count: u32 = 0;
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);

        if (random_bool(&random)) {
            true_count += 1;
        } else {
            false_count += 1;
        }
    }

    std.debug.assert(i == 100);

    try testing.expect(true_count > 0);
    try testing.expect(false_count > 0);
}

test "random_bool_weighted respects probability" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var true_count: u32 = 0;
    var i: u32 = 0;

    while (i < 1000) : (i += 1) {
        std.debug.assert(i < 1000);

        if (random_bool_weighted(&random, 80)) {
            true_count += 1;
        }
    }

    std.debug.assert(i == 1000);

    try testing.expect(true_count > 700);
    try testing.expect(true_count < 900);
}

test "weighted_select respects weights" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    const items = [_]u8{ 'A', 'B', 'C' };
    const weights = [_]u32{ 100, 50, 50 };
    var a_count: u32 = 0;
    var i: u32 = 0;

    while (i < 1000) : (i += 1) {
        std.debug.assert(i < 1000);

        const result = weighted_select(u8, &random, &items, &weights);

        if (result == 'A') {
            a_count += 1;
        }
    }

    std.debug.assert(i == 1000);

    try testing.expect(a_count > 400);
}

test "shuffle changes order" {
    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var items = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const original = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8 };

    shuffle(u8, &random, &items);

    var same_count: u8 = 0;
    var i: u8 = 0;

    while (i < items.len) : (i += 1) {
        std.debug.assert(i < items.len);

        if (items[i] == original[i]) {
            same_count += 1;
        }
    }

    std.debug.assert(i == items.len);

    try testing.expect(same_count < 8);
}

test "random_enum produces valid values" {
    const TestEnum = enum(u8) {
        first = 0,
        second = 1,
        third = 2,
    };

    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var seen = [_]bool{ false, false, false };
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);

        const value = random_enum(TestEnum, &random);

        seen[@intFromEnum(value)] = true;
    }

    std.debug.assert(i == 100);
    std.debug.assert(seen[0] and seen[1] and seen[2]);

    try testing.expect(seen[0]);
    try testing.expect(seen[1]);
    try testing.expect(seen[2]);
}

test "random_enum_excluding respects exclusion" {
    const TestEnum = enum(u8) {
        first = 0,
        second = 1,
        third = 2,
    };

    var prng = std.Random.DefaultPrng.init(42);
    var random = prng.random();
    var i: u32 = 0;

    while (i < 100) : (i += 1) {
        std.debug.assert(i < 100);

        const value = random_enum_excluding(TestEnum, &random, .first);

        std.debug.assert(value != .first);

        try testing.expect(value != .first);
    }

    std.debug.assert(i == 100);
}
