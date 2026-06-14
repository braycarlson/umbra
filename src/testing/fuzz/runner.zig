const std = @import("std");

const w32 = @import("win32").everything;

const common = @import("common.zig");
const event_fuzz = @import("event.zig");
const lifecycle_fuzz = @import("lifecycle.zig");
const simulator_mod = @import("simulator.zig");
const state_fuzz = @import("state.zig");

const Simulator = simulator_mod.Simulator;

pub const mode_max: u8 = 2;
pub const iteration_max: u32 = 0xFFFFFFFF;
pub const progress_interval: u32 = 1000;
pub const steps_per_sim: u32 = 100;
pub const arg_max: u32 = 64;
pub const seed_prefix_len: u8 = 7;
pub const iterations_prefix_len: u8 = 13;
pub const duration_prefix_len: u8 = 11;

pub const Mode = enum(u8) {
    smoke = 0,
    full = 1,
    stress = 2,

    pub fn is_valid(self: Mode) bool {
        const value = @intFromEnum(self);

        std.debug.assert(mode_max == 2);

        const result = value <= mode_max;

        return result;
    }

    pub fn batch_size(self: Mode) u32 {
        std.debug.assert(self.is_valid());

        const result: u32 = switch (self) {
            .smoke => 10,
            .full => 100,
            .stress => 1000,
        };

        std.debug.assert(result > 0);

        return result;
    }

    pub fn default_iterations(self: Mode) u32 {
        std.debug.assert(self.is_valid());

        const result: u32 = switch (self) {
            .smoke => 100,
            .full => 10000,
            .stress => 100000,
        };

        std.debug.assert(result > 0);

        return result;
    }

    pub fn sim_steps(self: Mode) u32 {
        std.debug.assert(self.is_valid());

        const result: u32 = switch (self) {
            .smoke => 100,
            .full => 500,
            .stress => 1000,
        };

        std.debug.assert(result > 0);

        return result;
    }
};

pub const Config = struct {
    seed: u64,
    mode: Mode,
    iterations: u32,
    duration_seconds: ?u32,

    pub fn is_valid(self: *const Config) bool {
        std.debug.assert(@intFromPtr(self) != 0);

        const valid_mode = self.mode.is_valid();
        const valid_iterations = self.iterations > 0;
        const result = valid_mode and valid_iterations;

        return result;
    }
};

pub const FuzzerResult = struct {
    iterations: u32,
    sim_failures: u32,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var mode: Mode = .full;
    var iterations: ?u32 = null;
    var seed: ?u64 = null;

    var args = try init.minimal.args.iterateAllocator(allocator);
    defer args.deinit();

    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.startsWith(u8, arg, "--seed=")) {
            seed = std.fmt.parseUnsigned(u64, arg[7..], 10) catch null;
        } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
            iterations = std.fmt.parseUnsigned(u32, arg[13..], 10) catch null;
        } else if (std.mem.eql(u8, arg, "--smoke")) {
            mode = .smoke;
        } else if (std.mem.eql(u8, arg, "--full")) {
            mode = .full;
        } else if (std.mem.eql(u8, arg, "--stress")) {
            mode = .stress;
        }
    }

    const config = Config{
        .seed = seed orelse common.get_random_seed(),
        .mode = mode,
        .iterations = iterations orelse mode.default_iterations(),
        .duration_seconds = null,
    };

    _ = run(&config);
}

pub fn run(config: *const Config) FuzzerResult {
    std.debug.assert(@intFromPtr(config) != 0);
    std.debug.assert(config.is_valid());

    var prng = std.Random.DefaultPrng.init(config.seed);
    var sim = Simulator.init(config.seed);
    const start_time: i64 = @intCast(w32.GetTickCount64());

    print_header(config);

    const result = run_fuzzer(config, &prng, &sim, start_time);

    print_footer(&result, start_time);

    return result;
}

fn print_header(config: *const Config) void {
    std.debug.assert(@intFromPtr(config) != 0);
    std.debug.assert(config.is_valid());

    std.debug.print("\nWisp Fuzzer: Starting\n", .{});
    std.debug.print("Seed: {d}\n", .{config.seed});
    std.debug.print("Mode: {s}\n", .{@tagName(config.mode)});
    std.debug.print("Iteration(s): {d}\n", .{config.iterations});
    std.debug.print("\n", .{});
}

fn print_footer(result: *const FuzzerResult, start_time: i64) void {
    std.debug.assert(@intFromPtr(result) != 0);

    const now_ms: i64 = @intCast(w32.GetTickCount64());
    const elapsed_ms: i64 = now_ms - start_time;

    std.debug.print("\nWisp Fuzzer: Completed\n", .{});
    std.debug.print("Iteration(s): {d}\n", .{result.iterations});
    std.debug.print("Simulation Failure(s): {d}\n", .{result.sim_failures});
    std.debug.print("Elapsed: {d} ms\n", .{elapsed_ms});

    if (elapsed_ms > 0) {
        const rate = result.iterations * 1000 / @as(u32, @intCast(elapsed_ms));

        std.debug.print("Rate: {d} iter/s\n", .{rate});
    }
}

fn run_fuzzer(config: *const Config, prng: *std.Random.DefaultPrng, sim: *Simulator, start_time: i64) FuzzerResult {
    std.debug.assert(@intFromPtr(config) != 0);
    std.debug.assert(@intFromPtr(prng) != 0);
    std.debug.assert(@intFromPtr(sim) != 0);
    std.debug.assert(config.is_valid());

    var iteration: u32 = 0;
    var sim_failures: u32 = 0;

    while (iteration < config.iterations) : (iteration += 1) {
        std.debug.assert(iteration < config.iterations);

        const iter_seed = prng.random().int(u64);

        sim.reseed(iter_seed);

        if (sim.run(config.mode.sim_steps())) |failure| {
            std.debug.print("\nFailure at iteration {d}:\n", .{iteration});
            std.debug.print("  Step: {d}, Invariant: {s}, Seed: {d}\n", .{ failure.step, failure.invariant, failure.seed });
            sim_failures += 1;
        }

        run_component_tests(iter_seed, config.mode) catch {};

        if (iteration > 0 and iteration % progress_interval == 0) {
            const elapsed_ms: i64 = @as(i64, @intCast(w32.GetTickCount64())) - start_time;

            std.debug.print("Progress: {d} iterations in {d} ms\n", .{ iteration, elapsed_ms });
        }
    }

    std.debug.assert(iteration == config.iterations);

    const result = FuzzerResult{
        .iterations = iteration,
        .sim_failures = sim_failures,
    };

    return result;
}

fn run_component_tests(seed: u64, mode: Mode) !void {
    std.debug.assert(mode.is_valid());

    var prng = std.Random.DefaultPrng.init(seed);
    var random = prng.random();

    const batch_size = mode.batch_size();

    std.debug.assert(batch_size > 0);

    try event_fuzz.fuzz_bus(&random, batch_size);
    try event_fuzz.fuzz_handler(&random, batch_size);
    try lifecycle_fuzz.fuzz_lifecycle(&random, batch_size);
    try lifecycle_fuzz.fuzz_transitions(seed, batch_size);
    try state_fuzz.fuzz_state_manager(&random, batch_size);
    try state_fuzz.fuzz_state_transitions(&random, batch_size);
}

const testing = std.testing;

test "Fuzzer smoke" {
    const config = Config{
        .seed = 42,
        .mode = .smoke,
        .iterations = 10,
        .duration_seconds = null,
    };

    std.debug.assert(config.is_valid());

    var prng = std.Random.DefaultPrng.init(config.seed);
    var sim = Simulator.init(config.seed);
    var iteration: u32 = 0;

    while (iteration < config.iterations) : (iteration += 1) {
        std.debug.assert(iteration < config.iterations);

        const iter_seed = prng.random().int(u64);

        sim.reseed(iter_seed);

        const failure = sim.run(config.mode.sim_steps());

        try testing.expect(failure == null);

        try run_component_tests(iter_seed, config.mode);
    }

    std.debug.assert(iteration == config.iterations);
}

test "Mode is_valid" {
    try testing.expect(Mode.smoke.is_valid());
    try testing.expect(Mode.full.is_valid());
    try testing.expect(Mode.stress.is_valid());
}

test "Mode batch_size" {
    try testing.expectEqual(@as(u32, 10), Mode.smoke.batch_size());
    try testing.expectEqual(@as(u32, 100), Mode.full.batch_size());
    try testing.expectEqual(@as(u32, 1000), Mode.stress.batch_size());
}

test "Config is_valid" {
    const valid_config = Config{
        .seed = 42,
        .mode = .smoke,
        .iterations = 100,
        .duration_seconds = null,
    };

    try testing.expect(valid_config.is_valid());

    const invalid_config = Config{
        .seed = 42,
        .mode = .smoke,
        .iterations = 0,
        .duration_seconds = null,
    };

    try testing.expect(!invalid_config.is_valid());
}
