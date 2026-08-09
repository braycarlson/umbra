set windows-shell := ["cmd.exe", "/c"]

# Default recipe
default:
    @just --list

# Run the whole continuous integration pipeline
ci:
    zig build ci --summary all

# Compile every artifact without running it
check:
    zig build check --summary all

# Compile every artifact for Linux from any host
check-linux:
    zig build check -Dtarget=x86_64-linux-gnu --summary all

# Compile every artifact for Windows from any host
check-windows:
    zig build check -Dtarget=x86_64-windows-gnu --summary all

# Build the library and install artifacts
build:
    zig build

# Run every available suite and the formatting check
test:
    zig build test --summary all

# Run the colocated unit tests and the tidy law, optionally filtered: just unit tidy
unit filter="":
    zig build test:unit --summary all -- {{filter}}

# Run the full pipeline against the mock backend, optionally filtered
mock filter="":
    zig build test:mock --summary all -- {{filter}}

# Run the Linux backend tests on a Linux host, optionally filtered
linux filter="":
    zig build test:linux --summary all -- {{filter}}

# Run the Windows backend tests on a Windows host, optionally filtered
windows filter="":
    zig build test:windows --summary all -- {{filter}}

# Run the tidy check on its own
tidy:
    zig build test:unit -- tidy

# Check that every source file is formatted
fmt:
    zig build test:fmt

# Format every source file in place
format:
    zig fmt build.zig src examples

# Compile the fuzzer without running it
fuzz-build:
    zig build fuzz:build --summary all

# Run every fuzzer briefly with a fixed seed
smoke:
    zig build fuzz:smoke --summary all

# Fuzz the event bus against its invariants
fuzz-bus seed="" events="":
    zig build fuzz -- bus {{seed}} {{events}}

# Fuzz the D-Bus wire parser with corrupted frames
fuzz-dbus seed="" events="":
    zig build fuzz -- dbus_wire {{seed}} {{events}}

# Fuzz the application lifecycle state machine
fuzz-lifecycle seed="" events="":
    zig build fuzz -- lifecycle {{seed}} {{events}}

# Fuzz the state manager and its history ring
fuzz-state seed="" events="":
    zig build fuzz -- state {{seed}} {{events}}

# Run the canary, which fails on some seeds by design
fuzz-canary seed="" events="":
    zig build fuzz -- canary {{seed}} {{events}}

# Run any fuzzer by name: just fuzz bus 12345 50000
fuzz name="smoke" seed="" events="":
    zig build fuzz -- {{name}} {{seed}} {{events}}

# Reproduce a reported failure: just reproduce bus 12345
reproduce name seed:
    zig build fuzz -- {{name}} {{seed}}

# Run every fuzzer back to back with one seed: just fuzz-all 12345
fuzz-all seed="" events="":
    just fuzz-bus {{seed}} {{events}}
    just fuzz-dbus {{seed}} {{events}}
    just fuzz-lifecycle {{seed}} {{events}}
    just fuzz-state {{seed}} {{events}}

# Build all examples
examples:
    zig build examples

# Build and run a specific example
[unix]
example name="basic":
    zig build examples
    ./zig-out/bin/{{name}}

# Build and run a specific example
[windows]
example name="basic":
    zig build examples
    .\zig-out\bin\{{name}}.exe

# Build with release safety checks
release:
    zig build -Doptimize=ReleaseSafe

# Build the smallest release binary
release-small:
    zig build -Doptimize=ReleaseSmall

# Clean build artifacts
[unix]
clean:
    rm -rf zig-out .zig-cache

# Clean build artifacts
[windows]
clean:
    if exist zig-out rmdir /s /q zig-out
    if exist .zig-cache rmdir /s /q .zig-cache
