# zcli

[![Zig Version](https://img.shields.io/badge/Zig-0.17-orange.svg?logo=zig)](https://ziglang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

A comptime-driven, type-safe CLI framework for Zig 0.17.

**Why zcli?** Define commands as plain Zig structs. Fields become flags or positional arguments; nested structs become subcommands. The parser is pure and testable: it returns narrow errors (including `error.HelpRequested`) instead of calling `std.process.exit`.

## Key Features

- 🚀 **Zero Boilerplate**: Pure Zig struct reflection replaces imperative Builder APIs.
- ⚡ **Type Safe**: Access parsed flags as compile-time typed fields (`result.verbose`, `result.script`).
- 🎨 **Rich Help Output**: Automatically renders usage, subcommand descriptions, positional arguments, short flags, and default values.
- 🔀 **Subcommands & Parent Flags**: Supports subcommands and parent/global flags placed before subcommands (`myapp --verbose run -n script.sh`).
- 🔤 **POSIX Short Flags**: Supports combined boolean short flags (e.g. `-vf`), inline assignment (`-n=script.sh`), or space-separated values (`-n script.sh`).
- 🧪 **Pure & Testable**: Core parser performs no I/O or `std.process.exit`.

---

## Installation

### 1. Fetch the package

```sh
zig fetch --save=zcli https://github.com/chy3xyz/zcli/archive/v0.3.0.tar.gz
```

This adds an entry to your `build.zig.zon`:

```zig
.{
    .dependencies = .{
        .zcli = .{
            .url = "https://github.com/chy3xyz/zcli/archive/v0.3.0.tar.gz",
            .hash = "<zig-will-fill-this>",
        },
    },
}
```

### 2. Add the module import

In your `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zcli_dep = b.dependency("zcli", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "myapp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("zcli", zcli_dep.module("zcli"));

    b.installArtifact(exe);
}
```

### 3. Use it in `src/main.zig`

```zig
const std = @import("std");
const zcli = @import("zcli");

const RunCmd = struct {
    pub const zcli_help = "Run your workflow";

    now: bool = false,
    script: []const u8,

    pub const zcli_options = .{
        .now = .{ .help = "Run immediately", .shortcut = "n" },
        .script = .{ .help = "Script to execute" },
    };
};

const VersionCmd = struct {
    pub const zcli_help = "Show version";
};

const Root = struct {
    pub const zcli_help = "Your dev toolkit CLI";

    verbose: bool = false,

    run: RunCmd,
    version: VersionCmd,

    pub const zcli_options = .{
        .verbose = .{ .help = "Enable verbose output", .shortcut = "v" },
    };
};

fn handle_run(run: RunCmd) !void {
    std.debug.print("Running {s} (now={})\n", .{ run.script, run.now });
}

fn handle_version(_: VersionCmd) !void {
    std.debug.print("myapp 0.1.0\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);

    var it = init.minimal.args.iterate();
    _ = it.skip();
    while (it.next()) |arg| {
        try args.append(allocator, arg);
    }

    var errbuf: [1024]u8 = undefined;
    var err_writer = std.Io.File.Writer.init(.stderr(), init.io, &errbuf);
    const stderr = &err_writer.interface;

    if (args.items.len == 0) {
        try zcli.print_help(stderr, Root);
        try stderr.flush();
        return;
    }

    const parsed = zcli.parse(Root, args.items, allocator) catch |err| switch (err) {
        error.HelpRequested => {
            try zcli.print_help(stderr, Root);
            try stderr.flush();
            return;
        },
        else => {
            try zcli.print_diagnostic(stderr, .{ .err = err });
            try stderr.flush();
            std.process.exit(1);
        },
    };
    defer zcli.free(Root, &parsed, allocator);

    try zcli.execute(Root, parsed, .{
        .run = handle_run,
        .version = handle_version,
    });

    try stderr.flush();
}
```

### 4. Run it

```sh
zig build run -- --verbose run -n deploy.sh
# Output: Running deploy.sh (now=true)

zig build run -- --help
# Output:
# Root - Your dev toolkit CLI
#
# Usage: Root [options] <command>
#
# Commands:
#    run           Run your workflow
#    version       Show version
#
# Flags:
#    -v, --verbose Enable verbose output [default: false]
#    -h, --help    Print help information
```

---

## Field Options & Help Documentation

You can attach help descriptions, single-character shortcuts, or specify argument kinds via a `zcli_options` struct declaration:

```zig
const RunCmd = struct {
    pub const zcli_help = "Run your workflow";

    now: bool = false,
    script: []const u8,
    include: []const []const u8 = &.{},

    pub const zcli_options = .{
        .now = .{ .help = "Run immediately", .shortcut = "n" },
        .script = .{ .help = "Script to execute" },
        .include = .{ .help = "Include path", .kind = .flag },
    };
};
```

- **Command Description**: Define `pub const zcli_help = "..."` inside a command struct.
- **Shortcuts**: Use `.shortcut = "n"` for `-n`.
- **Argument Kind**: Use `.kind = .flag` or `.kind = .positional` to explicitly override argument categorization.

---

## Supported Types

| Type | CLI Form | Description |
|------|----------|-------------|
| `bool` | `--verbose`, `-v`, or `-vf` | Boolean flag (supports combined short flags) |
| `u32`, `i64`, ... | `--count 5` or `--count=5` | Integer flag |
| `f32`, `f64` | `--ratio 1.5` | Floating point flag |
| `[]const u8` | `--name alice` or `<script>` | String flag or Positional Argument |
| `?T` | `--name alice` or optional positional | Optional flag or argument |
| `[]const []const u8` | `<args...>` or `--include a --include b` | Positional variadic args or Slice flags (`.kind = .flag`) |
| `enum { ... }` | `--level warn` | Enum value matching |

---

## Error Handling

`zcli.parse` returns a narrow error set:

```zig
pub const ParseError = error{
    UnknownFlag,
    MissingFlagValue,
    InvalidFlagValue,
    MissingPositionalArg,
    TooManyPositionalArgs,
    UnknownCommand,
    DuplicateFlag,
    HelpRequested,
    OutOfMemory,
};
```

The parser never calls `std.process.exit`. You can handle `error.HelpRequested` directly or print formatted diagnostics using `zcli.print_diagnostic`:

```zig
const parsed = zcli.parse(Root, args.items, allocator) catch |err| switch (err) {
    error.HelpRequested => {
        try zcli.print_help(writer, Root);
        return;
    },
    else => {
        try zcli.print_diagnostic(writer, .{ .err = err });
        std.process.exit(1);
    },
};
```

---

## API Overview

- `zcli.parse(Cmd, args, allocator)` — Parse CLI arguments into a typed struct or subcommand result.
- `zcli.free(Cmd, &result, allocator)` — Free heap-allocated slice fields.
- `zcli.execute(Cmd, result, handlers)` — Dispatch active subcommand results to corresponding handler functions.
- `zcli.print_help(writer, Cmd)` — Render colorized help output (title, usage, positionals, flags, defaults).
- `zcli.print_usage(writer, Cmd)` — Render standard usage line.
- `zcli.print_diagnostic(writer, diagnostic)` — Render formatted parse error diagnostic.

---

## Testing

```sh
zig build test
```

---

## Demo

Check out `examples/demo/` for a complete working CLI.

---

## Comparison with zli

| Feature | zli | zcli |
|---|-----|------|
| Definition | Builder API | Plain struct + comptime reflection |
| Help Metadata | Doc comments | `zcli_help` & `zcli_options` declarations |
| Subcommands & Parent Flags | Basic | Fully supported (`app --verbose run -n file`) |
| Short Flag Combination | ❌ No | ✅ Supported (`-vf`) |
| Flag Access | Runtime lookup | Compile-time typed struct fields |
| Error Handling | `std.process.exit(1)` | Returns `ParseError` (including `error.HelpRequested`) |
| Type Safety | Runtime union | Compile-time struct reflection |

---

## License

MIT. See [LICENSE](LICENSE).
