# zcli

A comptime-driven, type-safe CLI framework for Zig 0.17.

## Design

Define commands as plain Zig structs. Fields become flags or positional arguments; nested structs become subcommands. The parser is pure and testable: it returns narrow errors instead of calling `std.process.exit`.

## Example

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

## Supported Types

- `bool` — switch flag
- Integer types (`u32`, `i64`, ...) — value flag
- Float types (`f32`, `f64`) — value flag
- `[]const u8` — value flag or positional argument
- `?T` — optional flag/argument
- `[]const []const u8` — variadic positional arguments
- `enum` — enumerated value flag

## Testing

```sh
zig build test
```

## License

MIT
