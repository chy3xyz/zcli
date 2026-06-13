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

fn is_bool(comptime T: type) bool {
    return T == bool;
}

fn is_int(comptime T: type) bool {
    return @typeInfo(T) == .int;
}

fn is_float(comptime T: type) bool {
    return @typeInfo(T) == .float;
}

fn is_string(comptime T: type) bool {
    return T == []const u8;
}

fn is_optional(comptime T: type) bool {
    return @typeInfo(T) == .optional;
}

fn is_enum(comptime T: type) bool {
    return @typeInfo(T) == .@"enum";
}

fn is_struct(comptime T: type) bool {
    return @typeInfo(T) == .@"struct";
}

fn is_variadic(comptime T: type) bool {
    return T == []const []const u8;
}

fn arg_kind(comptime T: type) ArgKind {
    if (is_struct(T)) @compileError("subcommand types are not args");
    if (T == []const []const u8) return .positional;
    return .flag;
}

fn is_supported_flag_type(comptime T: type) bool {
    if (is_bool(T)) return true;
    if (is_int(T)) return true;
    if (is_float(T)) return true;
    if (is_string(T)) return true;
    if (is_enum(T)) return true;
    if (is_optional(T)) return is_supported_flag_type(@typeInfo(T).optional.child);
    return false;
}

pub fn meta(comptime Cmd: type) CommandMeta {
    comptime {
        if (!is_struct(Cmd)) @compileError("command must be a struct");

        var args: []const ArgMeta = &[]ArgMeta{};
        var subcommands: []const CommandMeta = &[]CommandMeta{};

        for (@typeInfo(Cmd).@"struct".fields) |field| {
            if (is_struct(field.type)) {
                const sub = meta(field.type);
                subcommands = subcommands ++ &[1]CommandMeta{sub};
            } else {
                if (!is_supported_flag_type(field.type)) {
                    @compileError("unsupported field type for arg: " ++ field.name);
                }
                const kind = arg_kind(field.type);
                const required = kind == .positional and !is_optional(field.type) and field.type != []const []const u8;
                args = args ++ &[1]ArgMeta{.{
                    .name = field.name,
                    .help = "",
                    .kind = kind,
                    .field_type = field.type,
                    .default_value = field.default_value,
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
