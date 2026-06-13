//! Help, usage, and diagnostic rendering.

const std = @import("std");
const command = @import("command.zig");
const Error = @import("error.zig");
const style = @import("style.zig");

const ParseError = Error.ParseError;
const Diagnostic = Error.Diagnostic;

fn comptime_max_len(comptime Cmd: type) usize {
    const meta = command.meta(Cmd);
    var max_len: usize = 0;
    for (meta.args) |arg| {
        const len = arg.name.len + 2; // "--" + name
        if (len > max_len) max_len = len;
    }
    for (meta.subcommands) |sub| {
        const len = sub.name.len;
        if (len > max_len) max_len = len;
    }
    return max_len;
}

pub fn print_help(writer: anytype, comptime Cmd: type) !void {
    const meta = command.meta(Cmd);
    const s = style.detect_color();
    const max_len = comptime_max_len(Cmd);
    const padding = 5;

    try writer.print("{s}{s}{s}\n\n", .{ s.bold, meta.help, s.reset });

    try writer.print("Usage: {s}", .{meta.name});
    if (meta.subcommands.len > 0) try writer.print(" [command]", .{});
    if (meta.args.len > 0) try writer.print(" [options]", .{});
    try writer.print("\n", .{});

    if (meta.subcommands.len > 0) {
        try writer.print("\nCommands:\n", .{});
        for (meta.subcommands) |sub| {
            const width = padding + max_len - sub.name.len;
            try writer.print("   {s}", .{sub.name});
            try writer.writeByteNTimes(' ', width);
            try writer.print("{s}\n", .{sub.help});
        }
    }

    if (meta.args.len > 0) {
        try writer.print("\nFlags:\n", .{});
        for (meta.args) |arg| {
            const display_len = if (arg.kind == .flag) arg.name.len + 2 else arg.name.len;
            const width = padding + max_len - display_len;
            try writer.print("   ", .{});
            if (arg.kind == .flag) try writer.print("--", .{});
            try writer.print("{s}", .{arg.name});
            try writer.writeByteNTimes(' ', width);
            try writer.print("{s}\n", .{arg.help});
        }
    }
}

pub fn print_usage(writer: anytype, comptime Cmd: type) !void {
    const meta = command.meta(Cmd);
    try writer.print("Usage: {s}", .{meta.name});
    if (meta.subcommands.len > 0) try writer.print(" [command]", .{});
    if (meta.args.len > 0) try writer.print(" [options]", .{});
    try writer.print("\n", .{});
}

pub fn print_diagnostic(writer: anytype, diag: Diagnostic) !void {
    const s = style.detect_color();
    try writer.print("{s}error{s}: {s}\n", .{ s.red, s.reset, @errorName(diag.err) });
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

test "print_help outputs command name" {
    const Cmd = struct { verbose: bool = false };
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);
    try print_help(buf.writer(), Cmd);
    try std.testing.expect(buf.items.len > 0);
}
