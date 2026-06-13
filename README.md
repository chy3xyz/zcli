# zcli

[![Zig Version](https://img.shields.io/badge/Zig-0.17-orange.svg?logo=zig)](https://ziglang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-lightgrey.svg)](LICENSE)

A comptime-driven, type-safe CLI framework for Zig 0.17.

**Why zcli?** Define commands as plain Zig structs. Fields become flags or positional arguments; nested structs become subcommands. The parser is pure and testable: it returns narrow errors instead of calling `std.process.exit`.

## Installation

Add zcli as a dependency in your `build.zig.zon`:

```sh
zig fetch --save=zcli https://github.com/chy3xyz/zcli/archive/main.tar.gz
```

Then in `build.zig`:

```zig
const zcli_dep = b.dependency("zcli", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zcli", zcli_dep.module("zcli"));
```

## Quick Start

```zig
const std = @import("std");
const zcli = @import("zcli");

const RunCmd = struct {
    //! Run your workflow
    /// Run immediately
    now: bool = false,
    /// Script to execute
    script: []const u8,
};

const Root = struct {
    //! Your dev toolkit CLI
    /// Run a workflow
    run: RunCmd,
};

fn handle_run(run: RunCmd) !void {
    std.debug.print("Running {s} (now={})\n", .{ run.script, run.now });
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);

    var it = init.minimal.args.iterate();
    _ = it.skip();
    while (it.next()) |arg| try args.append(allocator, arg);

    const parsed = zcli.parse(Root, args.items, allocator) catch |err| {
        std.debug.print("error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer zcli.free(Root, &parsed, allocator);

    try zcli.execute(Root, parsed, .{ .run = handle_run });
}
```

Run it:

```sh
zig build run -- run --now deploy.sh
# Output: Running deploy.sh (now=true)
```

## Supported Types

| Type | CLI Form |
|------|----------|
| `bool` | `--verbose` |
| `u32`, `i64`, ... | `--count 5` or `--count=5` |
| `f32`, `f64` | `--ratio 1.5` |
| `[]const u8` | `--name alice` or positional `<name>` |
| `?T` | Optional flag/argument |
| `[]const []const u8` | Variadic positional arguments |
| `enum { ... }` | `--level warn` |

## API Overview

- `zcli.parse(Cmd, args, allocator)` — parse arguments into a typed result.
- `zcli.free(Cmd, &result, allocator)` — free heap-allocated fields.
- `zcli.execute(Cmd, result, handlers)` — dispatch parent commands to handler functions.
- `zcli.print_help(writer, Cmd)` — render help.
- `zcli.print_diagnostic(writer, diagnostic)` — render a parse error.

## Design Principles

- **Compile-time type safety:** Command definitions are plain structs; type mismatches are caught at compile time.
- **Testable parser:** Parsing returns `ParseError`; never calls `std.process.exit`.
- **Memory safety:** Every allocation has a matching cleanup path.
- **Modular architecture:** Parser, metadata, help renderer, and error types are separate modules.

## Comparison with zli

zcli is inspired by [zli](https://github.com/xcaeser/zli) but takes a different approach:

| | zli | zcli |
|---|-----|------|
| Definition | Builder API | Plain struct + comptime reflection |
| Flag access | Runtime lookup | Compile-time typed field access |
| Error handling | `std.process.exit(1)` | Returns `ParseError` |
| Type safety | Runtime union | Compile-time struct fields |

## Development

```sh
zig build test
```

See `examples/demo/` for a complete working CLI.

## License

MIT. See [LICENSE](LICENSE).
