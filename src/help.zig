//! Help, usage, and diagnostic rendering.

const std = @import("std");
const command = @import("command.zig");
const Error = @import("error.zig");
const style = @import("style.zig");

const ParseError = Error.ParseError;
const Diagnostic = Error.Diagnostic;

fn write_spaces(writer: anytype, count: usize) !void {
    for (0..count) |_| {
        try writer.print(" ", .{});
    }
}

fn print_default_val(writer: anytype, comptime T: type, ptr: *const anyopaque) !void {
    if (T == bool) {
        const val: *const bool = @ptrCast(@alignCast(ptr));
        try writer.print("{s}", .{if (val.*) "true" else "false"});
    } else if (@typeInfo(T) == .int) {
        const val: *const T = @ptrCast(@alignCast(ptr));
        try writer.print("{d}", .{val.*});
    } else if (@typeInfo(T) == .float) {
        const val: *const T = @ptrCast(@alignCast(ptr));
        try writer.print("{d}", .{val.*});
    } else if (T == []const u8) {
        const val: *const []const u8 = @ptrCast(@alignCast(ptr));
        try writer.print("\"{s}\"", .{val.*});
    } else if (@typeInfo(T) == .@"enum") {
        const val: *const T = @ptrCast(@alignCast(ptr));
        try writer.print("{s}", .{@tagName(val.*)});
    } else if (@typeInfo(T) == .optional) {
        const child = @typeInfo(T).optional.child;
        const val: *const T = @ptrCast(@alignCast(ptr));
        if (val.*) |v| {
            try print_default_val(writer, child, &v);
        } else {
            try writer.print("null", .{});
        }
    } else {
        try writer.print("...", .{});
    }
}

pub fn print_help(writer: anytype, comptime Cmd: type) !void {
    const info = @typeInfo(Cmd).@"struct";
    const s = style.detect_color();
    const meta = comptime command.meta(Cmd);

    if (meta.help.len > 0) {
        try writer.print("{s}{s}{s} - {s}\n\n", .{ s.bold, meta.name, s.reset, meta.help });
    } else {
        try writer.print("{s}{s}{s}\n\n", .{ s.bold, meta.name, s.reset });
    }

    try writer.print("Usage: {s}", .{meta.name});

    var has_flags = false;
    var has_positionals = false;

    inline for (info.field_names, info.field_types) |name, field_type| {
        if (comptime command.is_struct(field_type)) continue;
        const kind = comptime command.field_kind(Cmd, name, field_type);
        if (kind == .flag) {
            has_flags = true;
        } else {
            has_positionals = true;
        }
    }

    if (has_flags or true) try writer.print(" [options]", .{});

    inline for (info.field_names, info.field_types, info.field_attrs) |name, field_type, attrs| {
        if (comptime command.is_struct(field_type)) continue;
        const kind = comptime command.field_kind(Cmd, name, field_type);
        if (kind == .positional) {
            const is_opt = comptime @typeInfo(field_type) == .optional;
            const is_variadic = comptime field_type == []const []const u8;
            const has_default = attrs.default_value_ptr != null;
            if (!is_opt and !is_variadic and !has_default) {
                try writer.print(" <{s}>", .{name});
            } else if (is_variadic) {
                try writer.print(" [{s}...]", .{name});
            } else {
                try writer.print(" [{s}]", .{name});
            }
        }
    }

    if (meta.subcommands.len > 0) try writer.print(" <command>", .{});
    try writer.print("\n", .{});

    var max_width: usize = 10; // min width for "-h, --help"

    inline for (info.field_names, info.field_types) |name, field_type| {
        if (comptime command.is_struct(field_type)) {
            if (name.len > max_width) max_width = name.len;
        } else {
            const kind = comptime command.field_kind(Cmd, name, field_type);
            if (kind == .positional) {
                if (name.len + 2 > max_width) max_width = name.len + 2;
            } else {
                var len = name.len + 2;
                if (comptime command.field_shortcut(Cmd, name)) |sc| {
                    len += sc.len + 4;
                }
                if (len > max_width) max_width = len;
            }
        }
    }

    const padding = 4;

    if (meta.subcommands.len > 0) {
        try writer.print("\nCommands:\n", .{});
        inline for (info.field_names, info.field_types) |name, field_type| {
            if (comptime command.is_struct(field_type)) {
                const sub_help = comptime command.cmd_help(field_type);
                const parent_sub_help = comptime command.field_help(Cmd, name);
                const help_str = if (parent_sub_help.len > 0) parent_sub_help else sub_help;
                const spaces = max_width + padding - name.len;
                try writer.print("   {s}", .{name});
                try write_spaces(writer, spaces);
                try writer.print("{s}\n", .{help_str});
            }
        }
    }

    if (has_positionals) {
        try writer.print("\nPositional Arguments:\n", .{});
        inline for (info.field_names, info.field_types, info.field_attrs) |name, field_type, attrs| {
            if (comptime command.is_struct(field_type)) continue;
            const kind = comptime command.field_kind(Cmd, name, field_type);
            if (kind == .positional) {
                const help_str = comptime command.field_help(Cmd, name);
                const display_name = name;
                const spaces = max_width + padding - display_name.len;
                try writer.print("   {s}", .{display_name});
                try write_spaces(writer, spaces);
                try writer.print("{s}", .{help_str});
                if (attrs.default_value_ptr == null and @typeInfo(field_type) != .optional and field_type != []const []const u8) {
                    try writer.print(" (required)", .{});
                }
                try writer.print("\n", .{});
            }
        }
    }

    try writer.print("\nFlags:\n", .{});
    inline for (info.field_names, info.field_types, info.field_attrs) |name, field_type, attrs| {
        if (comptime command.is_struct(field_type)) continue;
        const kind = comptime command.field_kind(Cmd, name, field_type);
        if (kind == .flag) {
            const shortcut = comptime command.field_shortcut(Cmd, name);
            const help_str = comptime command.field_help(Cmd, name);

            var len = name.len + 2;
            if (shortcut) |sc| len += sc.len + 4;

            const spaces = max_width + padding - len;

            try writer.print("   ", .{});
            if (shortcut) |sc| {
                try writer.print("-{s}, ", .{sc});
            }
            try writer.print("--{s}", .{name});
            try write_spaces(writer, spaces);
            try writer.print("{s}", .{help_str});

            if (attrs.default_value_ptr) |ptr| {
                try writer.print(" [default: ", .{});
                try print_default_val(writer, field_type, ptr);
                try writer.print("]", .{});
            }
            try writer.print("\n", .{});
        }
    }

    const help_len = 10;
    const spaces = max_width + padding - help_len;
    try writer.print("   -h, --help", .{});
    try write_spaces(writer, spaces);
    try writer.print("Print help information\n", .{});
}

pub fn print_usage(writer: anytype, comptime Cmd: type) !void {
    const info = @typeInfo(Cmd).@"struct";
    const meta = command.meta(Cmd);
    try writer.print("Usage: {s}", .{meta.name});
    var has_subcommands = false;
    var has_flags = false;
    inline for (info.field_names, info.field_types) |name, field_type| {
        if (comptime command.is_struct(field_type)) has_subcommands = true;
        if (comptime command.field_kind(Cmd, name, field_type) == .flag) has_flags = true;
    }
    if (has_subcommands) try writer.print(" <command>", .{});
    if (has_flags) try writer.print(" [options]", .{});
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

test "print_help renders shortcut" {
    const Cmd = struct {
        verbose: bool = false,
        pub const zcli_options = .{
            .verbose = .{ .shortcut = "v" },
        };
    };
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);
    try print_help(buf.writer(), Cmd);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "-v, --verbose") != null);
}

test "print_help renders subcommand help and defaults" {
    const SubCmd = struct {
        pub const zcli_help = "Perform action";
        now: bool = true,
    };
    const RootCmd = struct {
        pub const zcli_help = "Root CLI tool";
        sub: SubCmd,
    };
    var buf = std.ArrayList(u8).empty;
    defer buf.deinit(std.testing.allocator);
    try print_help(buf.writer(), RootCmd);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Root CLI tool") != null);
    try std.testing.expect(std.mem.indexOf(u8, buf.items, "Perform action") != null);
}

