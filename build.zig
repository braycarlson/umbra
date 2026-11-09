const std = @import("std");

const assert = std.debug.assert;

const Backend = enum {
    native,
    mock,
};

const ExampleUse = enum {
    installed,
    checked,
};

const Steps = struct {
    check: *std.Build.Step,
    ci: *std.Build.Step,
    examples: *std.Build.Step,
    fuzz: *std.Build.Step,
    fuzz_build: *std.Build.Step,
    fuzz_smoke: *std.Build.Step,
    test_all: *std.Build.Step,
    test_fmt: *std.Build.Step,
    test_linux: *std.Build.Step,
    test_mock: *std.Build.Step,
    test_unit: *std.Build.Step,
    test_windows: *std.Build.Step,
};

const Context = struct {
    builder: *std.Build,
    filters: []const []const u8,
    mock_options: *std.Build.Module,
    native_options: *std.Build.Module,
    optimize: std.lang.Optimize,
    steps: Steps,
    target: std.Build.ResolvedTarget,
    umbra: *std.Build.Module,
};

const Example = struct {
    library: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    use: ExampleUse,
};

const format_paths = [_][]const u8{ "build.zig", "examples", "src" };
const example_directory = "examples";
const example_name_bytes_max: u32 = 256;
const linux_query = std.Target.Query{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu };
const windows_query = std.Target.Query{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu };

comptime {
    assert(format_paths.len > 0);
    assert(example_name_bytes_max >= 64);
}

pub fn build(builder: *std.Build) void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const backend = builder.option(Backend, "backend", "Backend selection: native or mock") orelse
        .native;

    const filters = builder.option(
        []const []const u8,
        "test-filter",
        "Skip tests that do not match any filter",
    ) orelse &.{};

    const build_options = create_options(builder, backend == .mock);

    const umbra = builder.addModule("umbra", .{
        .root_source_file = builder.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    umbra.addImport("build_options", build_options);

    const context = Context{
        .builder = builder,
        .filters = filters,
        .mock_options = create_options(builder, true),
        .native_options = create_options(builder, false),
        .optimize = optimize,
        .steps = create_steps(builder),
        .target = target,
        .umbra = umbra,
    };

    add_format(context);
    add_unit_tests(context);
    add_mock_tests(context);
    add_linux_tests(context);
    add_windows_tests(context);
    add_fuzz(context);
    add_examples(context);

    context.steps.ci.dependOn(context.steps.test_fmt);
    context.steps.ci.dependOn(context.steps.check);
    context.steps.ci.dependOn(context.steps.test_unit);
    context.steps.ci.dependOn(context.steps.test_mock);
    context.steps.ci.dependOn(context.steps.test_linux);
    context.steps.ci.dependOn(context.steps.test_windows);
    context.steps.ci.dependOn(context.steps.fuzz_smoke);

    builder.default_step.dependOn(context.steps.check);
}

fn create_options(builder: *std.Build, mock: bool) *std.Build.Module {
    const options = builder.addOptions();

    options.addOption([]const u8, "library", "umbra");
    options.addOption(bool, "backend_mock", mock);

    return options.createModule();
}

fn create_steps(builder: *std.Build) Steps {
    return .{
        .check = builder.step("check", "Compile every artifact without running it"),
        .ci = builder.step("ci", "Run every check, test, and fuzz smoke"),
        .examples = builder.step("examples", "Build every example"),
        .fuzz = builder.step("fuzz", "Run a fuzzer: zig build fuzz -- <fuzzer> [seed] [events]"),
        .fuzz_build = builder.step("fuzz:build", "Compile the fuzzers without running them"),
        .fuzz_smoke = builder.step("fuzz:smoke", "Run every fuzzer briefly with a fixed seed"),
        .test_all = builder.step("test", "Run every test suite and the format check"),
        .test_fmt = builder.step("test:fmt", "Check that every source file is formatted"),
        .test_linux = builder.step("test:linux", "Run the Linux backend tests on a Linux host"),
        .test_mock = builder.step("test:mock", "Run the end to end tests against the mock backend"),
        .test_unit = builder.step("test:unit", "Run the unit tests and the tidy check"),
        .test_windows = builder.step(
            "test:windows",
            "Run the Windows backend tests on a Windows host",
        ),
    };
}

fn add_format(context: Context) void {
    assert(context.steps.test_fmt != context.steps.test_all);
    assert(context.steps.ci != context.steps.test_fmt);

    const builder = context.builder;
    const format = builder.addFmt(.{ .paths = builder.pathList(&format_paths), .check = true });

    context.steps.test_fmt.dependOn(&format.step);
    context.steps.test_all.dependOn(&format.step);
}

fn add_unit_tests(context: Context) void {
    assert(context.steps.test_unit != context.steps.test_all);
    assert(context.mock_options != context.native_options);

    const builder = context.builder;

    const module = builder.createModule(.{
        .root_source_file = builder.path("src/unit_tests.zig"),
        .target = builder.graph.host,
        .optimize = context.optimize,
        .imports = &.{.{ .name = "build_options", .module = context.mock_options }},
    });

    const suite = builder.addTest(.{ .root_module = module, .filters = context.filters });
    const run = builder.addRunArtifact(suite);

    run.has_side_effects = true;
    run.setCwd(builder.path("."));

    context.steps.test_unit.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
    context.steps.check.dependOn(&suite.step);
}

fn add_mock_tests(context: Context) void {
    assert(context.steps.test_mock != context.steps.test_all);
    assert(context.mock_options != context.native_options);

    const builder = context.builder;

    const module = builder.createModule(.{
        .root_source_file = builder.path("src/mock_tests.zig"),
        .target = builder.graph.host,
        .optimize = context.optimize,
        .imports = &.{.{ .name = "build_options", .module = context.mock_options }},
    });

    const suite = builder.addTest(.{ .root_module = module, .filters = context.filters });
    const run = builder.addRunArtifact(suite);

    run.setCwd(builder.path("."));

    context.steps.test_mock.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
    context.steps.check.dependOn(&suite.step);
}

fn add_linux_tests(context: Context) void {
    assert(context.steps.test_linux != context.steps.test_all);
    assert(context.native_options != context.mock_options);

    const builder = context.builder;

    if (builder.graph.host.result.os.tag != .linux) {
        return;
    }

    const module = builder.createModule(.{
        .root_source_file = builder.path("src/linux_tests.zig"),
        .target = builder.graph.host,
        .optimize = context.optimize,
        .imports = &.{.{ .name = "build_options", .module = context.native_options }},
    });

    const suite = builder.addTest(.{ .root_module = module, .filters = context.filters });
    const run = builder.addRunArtifact(suite);

    run.setCwd(builder.path("."));

    context.steps.test_linux.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
    context.steps.check.dependOn(&suite.step);
}

fn add_windows_tests(context: Context) void {
    assert(context.steps.test_windows != context.steps.test_all);
    assert(context.native_options != context.mock_options);

    const builder = context.builder;

    const resolved = if (context.target.result.os.tag == .windows)
        context.target
    else
        builder.resolveTargetQuery(windows_query);

    assert(resolved.result.os.tag == .windows);

    const module = builder.createModule(.{
        .root_source_file = builder.path("src/windows_tests.zig"),
        .target = resolved,
        .optimize = context.optimize,
        .imports = &.{.{ .name = "build_options", .module = context.native_options }},
    });

    const suite = builder.addTest(.{ .root_module = module, .filters = context.filters });

    context.steps.check.dependOn(&suite.step);

    if (builder.graph.host.result.os.tag != .windows) {
        return;
    }

    const run = builder.addRunArtifact(suite);

    run.setCwd(builder.path("."));

    context.steps.test_windows.dependOn(&run.step);
    context.steps.test_all.dependOn(&run.step);
}

fn add_fuzz(context: Context) void {
    assert(context.steps.fuzz != context.steps.fuzz_smoke);
    assert(context.steps.fuzz_build != context.steps.check);

    const builder = context.builder;

    const module = builder.createModule(.{
        .root_source_file = builder.path("src/fuzz_tests.zig"),
        .target = builder.graph.host,
        .optimize = context.optimize,
        .imports = &.{.{ .name = "build_options", .module = context.mock_options }},
    });

    const exe = builder.addExecutable(.{ .name = "fuzz", .root_module = module });

    builder.installArtifact(exe);

    const run = builder.addRunArtifact(exe);

    run.setCwd(builder.path("."));
    run.addPassthruArgs();

    const smoke = builder.addRunArtifact(exe);

    smoke.setCwd(builder.path("."));
    smoke.addArg("smoke");

    context.steps.fuzz.dependOn(&run.step);
    context.steps.fuzz_build.dependOn(&exe.step);
    context.steps.fuzz_smoke.dependOn(&smoke.step);
    context.steps.check.dependOn(&exe.step);
}

fn add_examples(context: Context) void {
    assert(context.steps.examples != context.steps.check);
    assert(context.umbra != context.native_options);

    const builder = context.builder;
    const windows = context.target.result.os.tag == .windows;

    add_example_directory(context, .{
        .library = context.umbra,
        .target = context.target,
        .use = .installed,
    });

    const other = builder.resolveTargetQuery(if (windows) linux_query else windows_query);

    assert(other.result.os.tag != context.target.result.os.tag);

    const library = builder.createModule(.{
        .root_source_file = builder.path("src/root.zig"),
        .target = other,
        .optimize = context.optimize,
        .imports = &.{.{ .name = "build_options", .module = context.native_options }},
    });

    add_example_directory(context, .{ .library = library, .target = other, .use = .checked });
}

fn add_example_directory(context: Context, example: Example) void {
    assert(context.steps.examples != context.steps.check);
    assert(example.library != context.mock_options);

    const builder = context.builder;
    const io = builder.graph.io;

    var dir = builder.root.openDir(io, example_directory, .{ .iterate = true }) catch return;
    defer dir.close(io);

    builder.dependOnDirectoryContents(builder.path(example_directory));

    var iterator = dir.iterate();

    while (iterator.next(io) catch null) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;

        const name = entry.name[0 .. entry.name.len - ".zig".len];

        var path_buffer: [example_name_bytes_max]u8 = undefined;

        const path = std.mem.print(
            &path_buffer,
            "{s}/{s}",
            .{ example_directory, entry.name },
        ) catch continue;

        const module = builder.createModule(.{
            .root_source_file = builder.path(path),
            .target = example.target,
            .optimize = context.optimize,
            .imports = &.{.{ .name = "umbra", .module = example.library }},
        });

        const exe = builder.addExecutable(.{ .name = name, .root_module = module });

        switch (example.use) {
            .installed => add_example_run(context, exe, name),
            .checked => context.steps.check.dependOn(&exe.step),
        }
    }
}

fn add_example_run(context: Context, exe: *std.Build.Step.Compile, name: []const u8) void {
    assert(context.steps.examples != context.steps.check);
    assert(name.len > 0);
    assert(name.len < example_name_bytes_max);

    const builder = context.builder;
    const install = builder.addInstallArtifact(exe, .{});

    context.steps.examples.dependOn(&install.step);
    context.steps.check.dependOn(&exe.step);

    var run_name_buffer: [example_name_bytes_max]u8 = undefined;
    const run_name = std.mem.print(&run_name_buffer, "run-{s}", .{name}) catch return;

    var description_buffer: [example_name_bytes_max]u8 = undefined;

    const description = std.mem.print(
        &description_buffer,
        "Run the {s} example",
        .{name},
    ) catch return;

    const run = builder.addRunArtifact(exe);

    run.step.dependOn(&install.step);

    builder.step(run_name, description).dependOn(&run.step);
}
