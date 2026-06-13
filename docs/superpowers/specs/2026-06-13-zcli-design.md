# zcli Design Document

**Date:** 2026-06-13  
**Scope:** Reusable Zig CLI framework library  
**Approach:** Struct-driven comptime CLI definition (Scheme B)  
**Style:** Community convention — `snake_case` functions, `TitleCase` types  
**Target Zig Version:** 0.17 (dev)

---

## 1. Background

`zli` is a lightweight Zig CLI framework. Its main strengths are an intuitive builder API and rich help output. However, it suffers from:

- Memory leaks due to incomplete `errdefer` chains.
- Un-testable parsing paths because it calls `std.process.exit(1)` on errors.
- Runtime type checking for flags instead of compile-time safety.
- A monolithic 939-line `Command` struct mixing parsing, rendering, execution, and lifecycle.

`zcli` is a ground-up redesign that keeps `zli`'s ergonomics but applies Zig 0.17 best practices, especially comptime reflection, narrow error sets, strict resource cleanup, and testability.

---

## 2. Goals

1. **Compile-time type safety** — command definitions are plain Zig structs; flags and positional args are typed at compile time.
2. **Testable parser** — parsing returns narrow errors; never calls `std.process.exit`.
3. **Memory safety** — every allocation has a matching `defer`/`errdefer`; `deinit` reverses init order and poisons memory.
4. **Modern help output** — aligned, sectioned, color-aware, `NO_COLOR` compatible.
5. **Minimal API surface** — core parsing + help + diagnostics; no UI widgets in scope.

---

## 3. Non-Goals

- Spinner / progress bar / table widgets (out of scope for this iteration).
- Shell completion generation (future enhancement).
- Environment-variable or config-file overlays (future enhancement).
- Dynamic command trees constructed at runtime.

---

## 4. Architecture

```
src/
├── zcli.zig          // Root module: re-export public API
├── parser.zig        // Pure functional argument parser
├── command.zig       // Comptime command metadata generation
├── help.zig          // Help, usage, and diagnostic rendering
├── error.zig         // Narrow error sets and diagnostics
└── style.zig         // ANSI style constants + NO_COLOR detection
```

### Module responsibilities

| Module | Does | Does NOT |
|--------|------|----------|
| `parser.zig` | Parse `[]const []const u8` into a typed struct | Print, exit, or touch `std.io` |
| `command.zig` | Reflect structs into `CommandMeta` at compile time | Parse raw strings |
| `help.zig` | Render help/usage/diagnostics to a writer | Mutate parser state |
| `error.zig` | Define `ParseError`, `Diagnostic` | Render output |
| `style.zig` | Provide ANSI escape constants | Embed business logic |

---

## 5. Comptime Command Definition

A command is a plain Zig struct. Fields become flags or positional args; doc comments become help text; nested structs become subcommands.

```zig
const RunCmd = struct {
    //! Run your workflow

    /// Run immediately
    now: bool = false,

    /// Script to execute
    script: []const u8,

    /// Environment name
    env: []const u8 = "default",
};

const Root = struct {
    //! Your dev toolkit CLI

    /// Run a workflow
    run: RunCmd,
};
```

### Field type mapping

| Field type | Semantic | CLI form |
|-----------|----------|----------|
| `bool` | Switch flag | `--now` |
| `?bool` | Optional switch flag | `--now` |
| `i32`, `u32`, `i64`, `u64`, etc. | Value flag | `--count 5` / `--count=5` |
| `?i32`, etc. | Optional value flag | `--count 5` |
| `[]const u8` | Value flag | `--env dev` |
| `?[]const u8` | Optional value flag | `--env dev` |
| `enum { ... }` | Enumerated value flag | `--level warn` |
| Subcommand struct | Subcommand | `run` |
| `[]const []const u8` | Variadic positional args | `a b c` |

Default values are taken directly from field initializers. Optional fields default to `null` if no initializer is provided.

### Comptime metadata

```zig
pub const ArgMeta = struct {
    name: []const u8,
    help: []const u8,
    kind: ArgKind,            // .flag or .positional
    field_type: type,
    default_value: ?*const anyopaque,
    required: bool,
};

pub const CommandMeta = struct {
    name: []const u8,
    help: []const u8,
    args: []const ArgMeta,
    subcommands: []const CommandMeta,
};
```

All metadata is `comptime`-known and stored in read-only data.

---

## 6. Parsing Flow

### Parser interface

```zig
pub fn parse(comptime Cmd: type, args: []const []const u8, allocator: Allocator) ParseError!Cmd;
```

- No `std.io` access.
- No `std.process.exit`.
- Allocator failures propagate as `error.OutOfMemory`.

### Parse steps

1. Skip the program name (caller is responsible for slicing `args[1..]`).
2. Match leading non-flag tokens against subcommand names; recurse into the matched subcommand struct.
3. Parse flags:
   - `--name=value` split on `=`.
   - `--name value` consume next token.
   - `-abc` expand into bool flags; non-bool flag must be last in group.
4. Apply struct field defaults for missing flags.
5. Parse positional args in declaration order; enforce `required` and `variadic` constraints.
6. Return the populated struct.

### Narrow error set

```zig
pub const ParseError = error{
    UnknownFlag,
    MissingFlagValue,
    InvalidFlagValue,
    MissingPositionalArg,
    TooManyPositionalArgs,
    UnknownCommand,
    DuplicateFlag,
    OutOfMemory,
};
```

Each error carries a `Diagnostic`:

```zig
pub const Diagnostic = struct {
    err: ParseError,
    flag: ?[]const u8 = null,
    expected: ?[]const u8 = null,
    got: ?[]const u8 = null,
};
```

---

## 7. Help and Usage Rendering

### Renderer interface

```zig
pub fn print_help(writer: anytype, comptime Cmd: type, options: HelpOptions) !void;
pub fn print_usage(writer: anytype, comptime Cmd: type) !void;
pub fn print_diagnostic(writer: anytype, diag: Diagnostic, comptime Cmd: type) !void;
```

Renderers only write to the supplied writer so tests can capture output in `ArrayList(u8)`.

### Help output format

```text
Your dev toolkit CLI

Usage: blitz [command] [options]

Commands:
   run     Run your workflow
   version Show version

Flags:
   -h, --help    Show help

Run 'blitz [command] --help' for more information.
```

Alignment width is computed at compile time from metadata. `NO_COLOR` disables ANSI escapes.

---

## 8. Memory Safety Strategy

Every allocation has an immediate `defer` or `errdefer`:

```zig
var result = try allocator.create(Command);
errdefer allocator.destroy(result);
```

Container deinit is paired with initialization:

```zig
var args = std.ArrayList([]const u8).empty;
defer args.deinit(allocator);
```

`deinit` reverses init order and poisons:

```zig
pub fn deinit(self: *Self, allocator: Allocator) void {
    self.args.deinit(allocator);
    self.flags.deinit();
    self.* = undefined;
}
```

Optional resources use `defer if`:

```zig
var message: ?[]const u8 = null;
defer if (message) |m| allocator.free(m);
```

### Heap-allocated parse results

Because parsed structs may contain heap-allocated strings or slices, provide:

```zig
pub fn free(comptime Cmd: type, value: *Cmd, allocator: Allocator) void;
```

This recursively releases all allocator-owned fields.

---

## 9. Public API Example

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

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const parsed = zcli.parse(Root, args[1..], allocator) catch |err| {
        try zcli.render_diagnostic(std.io.getStdErr().writer(), err);
        std.process.exit(1);
    };
    defer zcli.free(Root, &parsed, allocator);

    switch (parsed.command) {
        .run => |run| std.debug.print("{s} now={}\n", .{ run.script, run.now }),
    }
}
```

### Subcommand dispatch

The parse result exposes subcommands as a tagged union:

```zig
switch (parsed.command) {
    .run => |run| handle_run(run),
    .version => handle_version(),
}
```

An optional `execute` helper can map subcommands to handler functions:

```zig
try zcli.execute(Root, args[1..], allocator, .{
    .run = handle_run,
    .version = handle_version,
});
```

---

## 10. Testing Strategy

- **Unit tests in every module** using `std.testing.allocator` for leak detection.
- **No-IO parser tests** by passing string arrays directly.
- **Help rendering tests** by writing to `ArrayList(u8)` and checking output.
- **Example project** under `examples/` for manual validation and documentation.
- **CI via `zig build test`** in GitHub Actions.

Example test:

```zig
test "parse bool flag" {
    const Cmd = struct { now: bool = false };
    const parsed = try zcli.parse(Cmd, &.{"--now"}, std.testing.allocator);
    defer zcli.free(Cmd, &parsed, std.testing.allocator);
    try std.testing.expectEqual(true, parsed.now);
}
```

---

## 11. Comparison with zli

| Concern | zli | zcli |
|---------|-----|------|
| Definition style | Builder API (`addFlag`, `addCommand`) | Plain struct + comptime reflection |
| Flag access | `ctx.flag("now", bool)` runtime lookup | `run.now` compile-time typed |
| Error handling | `std.process.exit(1)` inside parser | Returns `ParseError` |
| Type safety | Runtime union `.Bool`/`.Int`/`.String` | Compile-time struct fields |
| Memory safety | Incomplete `errdefer`, no poison | Strict `errdefer`, reverse deinit, poison |
| Testability | Hard to unit test | Parser is pure and testable |
| Architecture | Monolithic `Command` | Split parser / command / help / error |

---

## 12. Open Questions / Future Work

- Should positional args be disambiguated from subcommands by type annotation or by naming convention?
- Should the parser support `--` terminator explicitly?
- Shell completion, config files, and environment-variable binding are deferred to future iterations.
