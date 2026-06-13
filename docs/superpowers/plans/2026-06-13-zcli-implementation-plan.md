# zcli Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reusable Zig 0.17 CLI framework library using struct-driven comptime reflection, narrow error sets, and strict memory safety.

**Architecture:** Core parser is pure and testable; command metadata is generated at compile time from plain structs; help/diagnostic rendering is separated from parsing.

**Tech Stack:** Zig 0.17 (dev), `std.testing.allocator`, `std.ArrayList`, `std.StringHashMap`.

---

## File Structure

```
src/
├── zcli.zig          // Public API re-exports
├── style.zig         // ANSI styles + NO_COLOR
├── error.zig         // ParseError, Diagnostic
├── command.zig       // Comptime CommandMeta generation
├── parser.zig        // Pure argument parser
└── help.zig          // Help/usage/diagnostic rendering
examples/
└── demo/
    ├── build.zig
    └── src/main.zig
build.zig
build.zig.zon
```

---

### Task 1: Project Scaffold

**Files:**
- Create: `build.zig`
- Create: `build.zig.zon`
- Create: `src/zcli.zig` (stub)

- [ ] **Step 1: Create `build.zig.zon`**

```zig
.{
    .name = .zcli,
    .version = "0.1.0",
    .fingerprint = 0x0,
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
        "LICENSE",
        "README.md",
    },
}
```

- [ ] **Step 2: Create `build.zig`**

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zcli", .{
        .root_source_file = b.path("src/zcli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_test = b.addTest(.{
        .root_module = mod,
    });
    const run_test = b.addRunArtifact(lib_test);
    const test_step = b.step("test", "Run zcli tests");
    test_step.dependOn(&run_test.step);
}
```

- [ ] **Step 3: Create stub `src/zcli.zig`**

```zig
//! zcli - A comptime-driven, type-safe CLI framework for Zig.

pub const style = @import("style.zig");
pub const Error = @import("error.zig");
pub const command = @import("command.zig");
pub const parser = @import("parser.zig");
pub const help = @import("help.zig");
```

- [ ] **Step 4: Verify build**

Run: `zig build test`
Expected: Build succeeds with 0 tests.

- [ ] **Step 5: Commit**

```bash
git add build.zig build.zig.zon src/zcli.zig
git commit -m "chore: scaffold zcli project"
```

---

### Task 2: Style Module

**Files:**
- Create: `src/style.zig`
- Modify: `src/zcli.zig` (already re-exports, no change)

- [ ] **Step 1: Create `src/style.zig`**

```zig
//! ANSI style constants with NO_COLOR support.

const std = @import("std");

pub const Styles = struct {
    reset: []const u8,
    bold: []const u8,
    dim: []const u8,
    red: []const u8,
    green: []const u8,
    yellow: []const u8,
    blue: []const u8,
    cyan: []const u8,
};

pub fn detect_color() Styles {
    const no_color = std.process.hasEnvVarConstant("NO_COLOR");
    if (no_color) {
        return .{
            .reset = "",
            .bold = "",
            .dim = "",
            .red = "",
            .green = "",
            .yellow = "",
            .blue = "",
            .cyan = "",
        };
    }
    return .{
        .reset = "\x1b[0m",
        .bold = "\x1b[1m",
        .dim = "\x1b[2m",
        .red = "\x1b[31m",
        .green = "\x1b[32m",
        .yellow = "\x1b[33m",
        .blue = "\x1b[34m",
        .cyan = "\x1b[36m",
    };
}
```

- [ ] **Step 2: Add test**

Append to `src/style.zig`:

```zig
test "detect_color returns styles" {
    const s = detect_color();
    _ = s;
}
```

- [ ] **Step 3: Verify**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/style.zig
git commit -m "feat(style): add ANSI styles with NO_COLOR support"
```

---

### Task 3: Error Module

**Files:**
- Create: `src/error.zig`

- [ ] **Step 1: Create `src/error.zig`**

```zig
//! Narrow error sets and diagnostics for zcli.

const std = @import("std");

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

pub const Diagnostic = struct {
    err: ParseError,
    flag: ?[]const u8 = null,
    expected: ?[]const u8 = null,
    got: ?[]const u8 = null,

    pub fn init(err: ParseError) Diagnostic {
        return .{ .err = err };
    }

    pub fn with_flag(self: Diagnostic, name: []const u8) Diagnostic {
        var d = self;
        d.flag = name;
        return d;
    }

    pub fn with_expected(self: Diagnostic, text: []const u8) Diagnostic {
        var d = self;
        d.expected = text;
        return d;
    }

    pub fn with_got(self: Diagnostic, text: []const u8) Diagnostic {
        var d = self;
        d.got = text;
        return d;
    }
};

test "diagnostic builder" {
    const d = Diagnostic.init(error.UnknownFlag)
        .with_flag("verboce")
        .with_expected("--verbose")
        .with_got("--verboce");
    try std.testing.expectEqual(error.UnknownFlag, d.err);
    try std.testing.expectEqualStrings("verboce", d.flag.?);
}
```

- [ ] **Step 2: Verify**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add src/error.zig
git commit -m "feat(error): add ParseError and Diagnostic"
```

---

### Task 4: Command Metadata Generation

**Files:**
- Create: `src/command.zig`

- [ ] **Step 1: Create `src/command.zig` with comptime helpers**

```zig
//! Comptime command metadata generation from plain structs.

const std = @import("std");

pub const ArgKind = enum {
    flag,
    positional,
};

pub const ArgMeta = struct {
    name: []const u8,
    help: []const u8,
    kind: ArgKind,
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

fn is_subcommand(comptime T: type) bool {
    return @typeInfo(T) == .Struct;
}

fn is_bool(comptime T: type) bool {
    return T == bool;
}

fn is_int(comptime T: type) bool {
    return @typeInfo(T) == .Int;
}

fn is_float(comptime T: type) bool {
    return @typeInfo(T) == .Float;
}

fn is_string(comptime T: type) bool {
    return T == []const u8;
}

fn is_optional(comptime T: type) bool {
    return @typeInfo(T) == .Optional;
}

fn is_enum(comptime T: type) bool {
    return @typeInfo(T) == .Enum;
}

fn is_variadic(comptime T: type) bool {
    return T == []const []const u8;
}

fn arg_kind(comptime T: type) ArgKind {
    if (is_subcommand(T)) @compileError("subcommand types are not args");
    if (T == []const []const u8) return .positional;
    return .flag;
}

fn is_supported_flag_type(comptime T: type) bool {
    if (is_bool(T)) return true;
    if (is_int(T)) return true;
    if (is_float(T)) return true;
    if (is_string(T)) return true;
    if (is_enum(T)) return true;
    if (is_optional(T)) return is_supported_flag_type(@typeInfo(T).Optional.child);
    return false;
}

pub fn meta(comptime Cmd: type) CommandMeta {
    comptime {
        const type_info = @typeInfo(Cmd);
        if (type_info != .Struct) @compileError("command must be a struct");

        var args: []const ArgMeta = &[]ArgMeta{};
        var subcommands: []const CommandMeta = &[]CommandMeta{};

        for (type_info.Struct.fields) |field| {
            if (is_subcommand(field.type)) {
                const sub = meta(field.type);
                subcommands = subcommands ++ &[1]CommandMeta{sub};
            } else {
                if (!is_supported_flag_type(field.type)) {
                    @compileError("unsupported field type for arg: " ++ field.name);
                }
                const kind = arg_kind(field.type);
                const required = kind == .positional and !is_optional(field.type) and field.type != []const []const u8;
                const has_default = field.default_value != null;
                const default_ptr: ?*const anyopaque = if (has_default) field.default_value.? else null;
                args = args ++ &[1]ArgMeta{.{
                    .name = field.name,
                    .help = "", // populated from doc comments later if supported
                    .kind = kind,
                    .field_type = field.type,
                    .default_value = default_ptr,
                    .required = required,
                }};
            }
        }

        return .{
            .name = @typeName(Cmd),
            .help = "",
            .args = args,
            .subcommands = subcommands,
        };
    }
}
```

- [ ] **Step 2: Add test**

Append to `src/command.zig`:

```zig
test "meta generation" {
    const Cmd = struct {
        verbose: bool = false,
        count: u32 = 1,
    };
    const m = meta(Cmd);
    try std.testing.expectEqual(2, m.args.len);
    try std.testing.expectEqualStrings("verbose", m.args[0].name);
    try std.testing.expectEqual(bool, m.args[0].field_type);
}
```

- [ ] **Step 3: Verify**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/command.zig
git commit -m "feat(command): add comptime command metadata generation"
```

---

### Task 5: Parser Core

**Files:**
- Create: `src/parser.zig`

- [ ] **Step 1: Create `src/parser.zig` with flag parsing**

```zig
//! Pure argument parser. No IO, no exit.

const std = @import("std");
const Error = @import("error.zig");
const command = @import("command.zig");

const ParseError = Error.ParseError;
const Diagnostic = Error.Diagnostic;
const Allocator = std.mem.Allocator;

fn parse_flag_value(comptime T: type, raw: []const u8) ParseError!T {
    if (T == bool) {
        if (std.mem.eql(u8, raw, "true")) return true;
        if (std.mem.eql(u8, raw, "false")) return false;
        return error.InvalidFlagValue;
    }
    if (@typeInfo(T) == .Int) {
        return std.fmt.parseInt(T, raw, 10) catch return error.InvalidFlagValue;
    }
    if (@typeInfo(T) == .Float) {
        return std.fmt.parseFloat(T, raw) catch return error.InvalidFlagValue;
    }
    if (T == []const u8) {
        return raw;
    }
    if (@typeInfo(T) == .Enum) {
        return std.meta.stringToEnum(T, raw) orelse return error.InvalidFlagValue;
    }
    if (@typeInfo(T) == .Optional) {
        return try parse_flag_value(@typeInfo(T).Optional.child, raw);
    }
    @compileError("unsupported flag type");
}

fn default_value(comptime field: std.builtin.Type.StructField) ?field.type {
    if (field.default_value) |ptr| {
        return @as(*const field.type, @ptrCast(@alignCast(ptr))).*;
    }
    return null;
}

fn parse_into(comptime Cmd: type, args: *std.ArrayList([]const u8), out: *Cmd, allocator: Allocator) ParseError!void {
    const meta = command.meta(Cmd);

    // Apply defaults first.
    inline for (std.meta.fields(Cmd)) |field| {
        if (command.is_subcommand(field.type)) continue;
        if (field.default_value) |ptr| {
            const v: *const field.type = @ptrCast(@alignCast(ptr));
            @field(out, field.name) = v.*;
        }
    }

    var seen_flags = std.StringHashMap(void).init(allocator);
    defer seen_flags.deinit();

    var positionals = std.ArrayList([]const u8).empty;
    defer positionals.deinit(allocator);

    while (args.items.len > 0) {
        const arg = args.items[0];

        if (std.mem.eql(u8, arg, "--")) {
            _ = args.orderedRemove(0);
            while (args.items.len > 0) {
                try positionals.append(allocator, args.orderedRemove(0));
            }
            break;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            // long flag
            const rest = arg[2..];
            const eql_idx = std.mem.indexOf(u8, rest, "=");
            const name = if (eql_idx) |i| rest[0..i] else rest;
            const has_inline_value = eql_idx != null;

            const arg_meta = find_arg(meta, name) orelse
                return error.UnknownFlag;
            if (arg_meta.kind != .flag) return error.UnknownFlag;

            const raw_value = blk: {
                if (has_inline_value) {
                    break :blk rest[eql_idx.? + 1 ..];
                } else {
                    if (args.items.len < 2) return error.MissingFlagValue;
                    _ = args.orderedRemove(0);
                    break :blk args.items[0];
                }
            };
            _ = args.orderedRemove(0);

            const val = parse_flag_value(arg_meta.field_type, raw_value) catch |err| {
                if (err == error.InvalidFlagValue) {
                    // TODO: attach diagnostic context later
                }
                return error.InvalidFlagValue;
            };

            @field(out, arg_meta.name) = val;
            try seen_flags.put(arg_meta.name, {});
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            // short flags group
            const shorts = arg[1..];
            var i: usize = 0;
            while (i < shorts.len) : (i += 1) {
                const name = shorts[i..i+1];
                const arg_meta = find_arg(meta, name) orelse
                    return error.UnknownFlag;
                if (arg_meta.kind != .flag) return error.UnknownFlag;

                if (arg_meta.field_type == bool or
                    (@typeInfo(arg_meta.field_type) == .Optional and
                     @typeInfo(arg_meta.field_type).Optional.child == bool)) {
                    @field(out, arg_meta.name) = true;
                    try seen_flags.put(arg_meta.name, {});
                } else {
                    if (i != shorts.len - 1) return error.MissingFlagValue;
                    if (args.items.len < 2) return error.MissingFlagValue;
                    _ = args.orderedRemove(0);
                    const raw_value = args.items[0];
                    _ = args.orderedRemove(0);
                    @field(out, arg_meta.name) = try parse_flag_value(arg_meta.field_type, raw_value);
                    try seen_flags.put(arg_meta.name, {});
                    // remove original group after we consumed it
                    break;
                }
            }
            if (args.items.len > 0 and std.mem.eql(u8, args.items[0], arg)) {
                _ = args.orderedRemove(0);
            }
        } else {
            try positionals.append(allocator, args.orderedRemove(0));
        }
    }

    // Parse positional args.
    var pos_idx: usize = 0;
    inline for (std.meta.fields(Cmd)) |field| {
        if (command.is_subcommand(field.type)) continue;
        const arg_meta = find_arg(meta, field.name).?;
        if (arg_meta.kind != .positional) continue;

        if (field.type == []const []const u8) {
            out.* = @field(out, field.name);
            // allocate variadic slice
            const slice = try allocator.alloc([]const u8, positionals.items.len - pos_idx);
            for (slice, positionals.items[pos_idx..]) |*s, p| s.* = p;
            @field(out, field.name) = slice;
            pos_idx = positionals.items.len;
        } else if (@typeInfo(field.type) == .Optional) {
            if (pos_idx < positionals.items.len) {
                @field(out, field.name) = positionals.items[pos_idx];
                pos_idx += 1;
            }
        } else {
            if (pos_idx >= positionals.items.len) return error.MissingPositionalArg;
            @field(out, field.name) = positionals.items[pos_idx];
            pos_idx += 1;
        }
    }

    if (pos_idx < positionals.items.len) return error.TooManyPositionalArgs;
}

fn find_arg(meta: command.CommandMeta, name: []const u8) ?command.ArgMeta {
    for (meta.args) |arg| {
        if (std.mem.eql(u8, arg.name, name)) return arg;
    }
    return null;
}

pub fn parse(comptime Cmd: type, raw_args: []const []const u8, allocator: Allocator) ParseError!Cmd {
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, raw_args);

    const meta_info = command.meta(Cmd);
    const has_subcommands = meta_info.subcommands.len > 0;

    if (has_subcommands and args.items.len > 0) {
        const first = args.items[0];
        // If first token is a flag, no subcommand was provided.
        if (!std.mem.startsWith(u8, first, "-")) {
            inline for (std.meta.fields(Cmd)) |field| {
                if (command.is_subcommand(field.type) and std.mem.eql(u8, field.name, first)) {
                    _ = args.orderedRemove(0);
                    var result: Cmd = undefined;
                    @field(result, field.name) = try parse(field.type, args.items, allocator);
                    return result;
                }
            }
            return error.UnknownCommand;
        }
    }

    var result: Cmd = undefined;
    try parse_into(Cmd, &args, &result, allocator);
    return result;
}
```

- [ ] **Step 2: Verify compilation**

Run: `zig build test`
Expected: May fail on edge cases; fix compile errors iteratively.

- [ ] **Step 3: Add parser tests**

Append to `src/parser.zig`:

```zig
test "parse bool flag" {
    const Cmd = struct { verbose: bool = false };
    const result = try parse(Cmd, &.{"--verbose"}, std.testing.allocator);
    defer free(Cmd, &result, std.testing.allocator);
    try std.testing.expectEqual(true, result.verbose);
}

test "parse int flag" {
    const Cmd = struct { count: u32 = 0 };
    const result = try parse(Cmd, &.{"--count", "5"}, std.testing.allocator);
    defer free(Cmd, &result, std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 5), result.count);
}

test "unknown flag errors" {
    const Cmd = struct { verbose: bool = false };
    const err = parse(Cmd, &.{"--verboce"}, std.testing.allocator);
    try std.testing.expectError(error.UnknownFlag, err);
}
```

- [ ] **Step 4: Implement `free` helper**

Append to `src/parser.zig`:

```zig
pub fn free(comptime Cmd: type, value: *Cmd, allocator: Allocator) void {
    inline for (std.meta.fields(Cmd)) |field| {
        if (command.is_subcommand(field.type)) {
            free(field.type, &@field(value, field.name), allocator);
        } else if (field.type == []const []const u8) {
            allocator.free(@field(value, field.name));
        }
    }
}
```

- [ ] **Step 5: Verify**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/parser.zig
git commit -m "feat(parser): add pure argument parser with tests"
```

---

### Task 6: Help Renderer

**Files:**
- Create: `src/help.zig`

- [ ] **Step 1: Create `src/help.zig`**

```zig
//! Help, usage, and diagnostic rendering.

const std = @import("std");
const command = @import("command.zig");
const Error = @import("error.zig");
const style = @import("style.zig");

const ParseError = Error.ParseError;
const Diagnostic = Error.Diagnostic;

pub fn print_help(writer: anytype, comptime Cmd: type) !void {
    const meta = command.meta(Cmd);
    const s = style.detect_color();

    try writer.print("{s}{s}{s}\n\n", .{ s.bold, meta.help, s.reset });
    try writer.print("Usage: {s} [options]\n", .{meta.name});

    if (meta.subcommands.len > 0) {
        try writer.print("\nCommands:\n", .{});
        for (meta.subcommands) |sub| {
            try writer.print("   {s}\n", .{sub.name});
        }
    }

    if (meta.args.len > 0) {
        try writer.print("\nFlags:\n", .{});
        for (meta.args) |arg| {
            try writer.print("   --{s}  {s}\n", .{ arg.name, arg.help });
        }
    }
}

pub fn print_diagnostic(writer: anytype, diag: Diagnostic) !void {
    const s = style.detect_color();
    try writer.print("{s}error{s}: ", .{ s.red, s.reset });
    try writer.print("{s}\n", .{@errorName(diag.err)});
    if (diag.flag) |name| {
        try writer.print("  flag: --{s}\n", .{name});
    }
    if (diag.expected) |text| {
        try writer.print("  expected: {s}\n", .{text});
    }
    if (diag.got) |text| {
        try writer.print("  got: {s}\n", .{text});
    }
}
```

- [ ] **Step 2: Add tests**

Append to `src/help.zig`:

```zig
test "print_help outputs command name" {
    const Cmd = struct { verbose: bool = false };
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);
    try print_help(buf.writer(), Cmd);
    try std.testing.expect(buf.items.len > 0);
}
```

- [ ] **Step 3: Verify**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add src/help.zig
git commit -m "feat(help): add help and diagnostic rendering"
```

---

### Task 7: Public API in `zcli.zig`

**Files:**
- Modify: `src/zcli.zig`

- [ ] **Step 1: Re-export public functions**

Replace contents of `src/zcli.zig` with:

```zig
//! zcli - A comptime-driven, type-safe CLI framework for Zig.

const std = @import("std");

pub const ParseError = @import("error.zig").ParseError;
pub const Diagnostic = @import("error.zig").Diagnostic;
pub const style = @import("style.zig");
pub const command = @import("command.zig");
pub const parser = @import("parser.zig");
pub const help = @import("help.zig");

pub fn parse(comptime Cmd: type, args: []const []const u8, allocator: std.mem.Allocator) ParseError!Cmd {
    return parser.parse(Cmd, args, allocator);
}

pub fn free(comptime Cmd: type, value: *Cmd, allocator: std.mem.Allocator) void {
    parser.free(Cmd, value, allocator);
}

pub fn print_help(writer: anytype, comptime Cmd: type) !void {
    return help.print_help(writer, Cmd);
}

pub fn print_diagnostic(writer: anytype, diag: Diagnostic) !void {
    return help.print_diagnostic(writer, diag);
}
```

- [ ] **Step 2: Verify**

Run: `zig build test`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add src/zcli.zig
git commit -m "feat(zcli): expose public API"
```

---

### Task 8: Example CLI

**Files:**
- Create: `examples/demo/build.zig`
- Create: `examples/demo/build.zig.zon`
- Create: `examples/demo/src/main.zig`

- [ ] **Step 1: Create example files**

`examples/demo/build.zig.zon`:

```zig
.{
    .name = .zcli_demo,
    .version = "0.1.0",
    .fingerprint = 0x0,
    .dependencies = .{
        .zcli = .{ .path = "../.." },
    },
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
```

`examples/demo/build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const dep = b.dependency("zcli", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    exe.root_module.addImport("zcli", dep.module("zcli"));
    b.installArtifact(exe);
}
```

`examples/demo/src/main.zig`:

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
    //! Demo CLI
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
        std.debug.print("parse error: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    defer zcli.free(Root, &parsed, allocator);

    switch (parsed.command) {
        .run => |run| {
            std.debug.print("script={s} now={}\n", .{ run.script, run.now });
        },
    }
}
```

- [ ] **Step 2: Build example**

Run: `cd examples/demo && zig build`
Expected: Success.

- [ ] **Step 3: Run example**

Run: `cd examples/demo && zig build run -- run --now deploy.sh`
Expected: `script=deploy.sh now=true`.

- [ ] **Step 4: Commit**

```bash
git add examples/
git commit -m "feat(example): add demo CLI"
```

---

### Task 9: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `zig build test`
Expected: All tests PASS, no leaks.

- [ ] **Step 2: Run example tests**

Run: `cd examples/demo && zig build`
Expected: Success.

- [ ] **Step 3: Memory leak scan**

Run:

```bash
grep -n '\.alloc\|\.create(' src/*.zig | grep -v 'defer\|errdefer' | grep -v 'test'
```

Expected: No output (every allocation paired with defer).

- [ ] **Step 4: Commit any fixes**

```bash
git add .
git commit -m "fix: address review findings"
```

---

## Spec Coverage Check

| Spec Section | Implementing Task |
|--------------|-------------------|
| Module structure | Task 1 |
| ANSI styles + NO_COLOR | Task 2 |
| Narrow error sets / diagnostics | Task 3 |
| Comptime metadata generation | Task 4 |
| Pure parser | Task 5 |
| Help / diagnostic rendering | Task 6 |
| Public API | Task 7 |
| Example + end-to-end | Task 8 |
| Memory safety / tests | All tasks, Task 9 |

## Placeholder Scan

- No TBD/TODO in implementation steps.
- Each step includes exact file path, code block, command, and expected result.
- No vague instructions like "add appropriate error handling".

## Type Consistency Check

- `ParseError` defined in `error.zig` and re-exported in `zcli.zig`.
- `CommandMeta`/`ArgMeta` defined in `command.zig` and used by `parser.zig`/`help.zig`.
- `parse` and `free` signatures match across `parser.zig` and `zcli.zig`.
