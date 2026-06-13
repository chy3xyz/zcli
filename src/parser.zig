//! Pure argument parser. No IO, no exit.

const std = @import("std");
const Error = @import("error.zig");
const command = @import("command.zig");

const ParseError = Error.ParseError;
const Allocator = std.mem.Allocator;

fn parse_flag_value(comptime T: type, raw: []const u8) ParseError!T {
    if (T == bool) {
        if (std.mem.eql(u8, raw, "true")) return true;
        if (std.mem.eql(u8, raw, "false")) return false;
        return error.InvalidFlagValue;
    }
    if (@typeInfo(T) == .int) {
        return std.fmt.parseInt(T, raw, 10) catch return error.InvalidFlagValue;
    }
    if (@typeInfo(T) == .float) {
        return std.fmt.parseFloat(T, raw) catch return error.InvalidFlagValue;
    }
    if (T == []const u8) {
        return raw;
    }
    if (@typeInfo(T) == .@"enum") {
        return std.meta.stringToEnum(T, raw) orelse return error.InvalidFlagValue;
    }
    if (@typeInfo(T) == .optional) {
        return try parse_flag_value(@typeInfo(T).optional.child, raw);
    }
    @compileError("unsupported flag type: " ++ @typeName(T));
}

fn field_default(comptime field: std.builtin.Type.StructField) ?field.type {
    if (field.default_value) |ptr| {
        const v: *const field.type = @ptrCast(@alignCast(ptr));
        return v.*;
    }
    return null;
}

fn find_arg_meta(meta: command.CommandMeta, name: []const u8) ?command.ArgMeta {
    for (meta.args) |arg| {
        if (std.mem.eql(u8, arg.name, name)) return arg;
    }
    return null;
}

fn parse_into(comptime Cmd: type, args: *std.ArrayList([]const u8), out: *Cmd, allocator: Allocator) ParseError!void {
    const meta = command.meta(Cmd);

    // Apply defaults.
    inline for (@typeInfo(Cmd).@"struct".fields) |field| {
        if (command.is_struct(field.type)) continue;
        if (field.default_value) |ptr| {
            const v: *const field.type = @ptrCast(@alignCast(ptr));
            @field(out, field.name) = v.*;
        }
    }

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
            const rest = arg[2..];
            const eql_idx = std.mem.indexOf(u8, rest, "=");
            const name = if (eql_idx) |i| rest[0..i] else rest;
            const has_inline_value = eql_idx != null;

            const arg_meta = find_arg_meta(meta, name) orelse return error.UnknownFlag;
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

            @field(out, arg_meta.name) = try parse_flag_value(arg_meta.field_type, raw_value);
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            const name = arg[1..];
            const arg_meta = find_arg_meta(meta, name) orelse return error.UnknownFlag;
            if (arg_meta.kind != .flag) return error.UnknownFlag;

            _ = args.orderedRemove(0);

            if (arg_meta.field_type == bool or
                (@typeInfo(arg_meta.field_type) == .optional and
                 @typeInfo(arg_meta.field_type).optional.child == bool))
            {
                @field(out, arg_meta.name) = true;
            } else {
                if (args.items.len == 0) return error.MissingFlagValue;
                const raw_value = args.orderedRemove(0);
                @field(out, arg_meta.name) = try parse_flag_value(arg_meta.field_type, raw_value);
            }
        } else {
            try positionals.append(allocator, args.orderedRemove(0));
        }
    }

    // Parse positional args.
    var pos_idx: usize = 0;
    inline for (@typeInfo(Cmd).@"struct".fields) |field| {
        if (command.is_struct(field.type)) continue;
        const arg_meta = find_arg_meta(meta, field.name).?;
        if (arg_meta.kind != .positional) continue;

        if (field.type == []const []const u8) {
            const slice = try allocator.alloc([]const u8, positionals.items.len - pos_idx);
            for (slice, positionals.items[pos_idx..]) |*s, p| s.* = p;
            @field(out, field.name) = slice;
            pos_idx = positionals.items.len;
        } else if (@typeInfo(field.type) == .optional) {
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

pub fn parse(comptime Cmd: type, raw_args: []const []const u8, allocator: Allocator) ParseError!command.Result(Cmd) {
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, raw_args);

    const meta = command.meta(Cmd);

    if (meta.subcommands.len > 0 and args.items.len > 0 and !std.mem.startsWith(u8, args.items[0], "-")) {
        const first = args.items[0];
        inline for (@typeInfo(Cmd).@"struct".fields) |field| {
            if (command.is_struct(field.type) and std.mem.eql(u8, field.name, first)) {
                _ = args.orderedRemove(0);
                var value: Cmd = undefined;
                @field(value, field.name) = try parse(field.type, args.items, allocator);
                return command.Result(Cmd){
                    .active = @field(std.meta.FieldEnum(Cmd), field.name),
                    .value = value,
                };
            }
        }
        return error.UnknownCommand;
    }

    var result: Cmd = undefined;
    try parse_into(Cmd, &args, &result, allocator);
    return result;
}

pub fn free(comptime Cmd: type, value: *command.Result(Cmd), allocator: Allocator) void {
    const ResultType = command.Result(Cmd);
    if (ResultType == Cmd) {
        free_cmd(Cmd, value, allocator);
    } else {
        free_parent(Cmd, value, allocator);
    }
}

fn free_cmd(comptime Cmd: type, value: *Cmd, allocator: Allocator) void {
    inline for (@typeInfo(Cmd).@"struct".fields) |field| {
        if (command.is_struct(field.type)) {
            free(field.type, &@field(value, field.name), allocator);
        } else if (field.type == []const []const u8) {
            allocator.free(@field(value, field.name));
        }
    }
}

fn free_parent(comptime Cmd: type, value: *command.Result(Cmd), allocator: Allocator) void {
    const active = value.active;
    switch (active) {
        inline else => |tag| {
            const field_name = @tagName(tag);
            const FieldType = @TypeOf(@field(value.value, field_name));
            free(FieldType, &@field(value.value, field_name), allocator);
        },
    }
}

test "parse bool flag" {
    const Cmd = struct { verbose: bool = false };
    const result = try parse(Cmd, &.{"--verbose"}, std.testing.allocator);
    defer free(Cmd, @constCast(&result), std.testing.allocator);
    try std.testing.expectEqual(true, result);
}

test "parse int flag" {
    const Cmd = struct { count: u32 = 0 };
    const result = try parse(Cmd, &.{"--count", "5"}, std.testing.allocator);
    defer free(Cmd, @constCast(&result), std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 5), result);
}

test "unknown flag errors" {
    const Cmd = struct { verbose: bool = false };
    const err = parse(Cmd, &.{"--verboce"}, std.testing.allocator);
    try std.testing.expectError(error.UnknownFlag, err);
}

test "parse subcommand" {
    const RunCmd = struct {
        now: bool = false,
        script: []const u8,
    };
    const Root = struct {
        run: RunCmd,
    };
    const result = try parse(Root, &.{"run", "--now", "deploy.sh"}, std.testing.allocator);
    defer free(Root, @constCast(&result), std.testing.allocator);
    try std.testing.expectEqualStrings("deploy.sh", result.value.run.script);
    try std.testing.expectEqual(true, result.value.run.now);
}
