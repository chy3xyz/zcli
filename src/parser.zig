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

fn parse_one_flag(comptime Cmd: type, args: *std.ArrayList([]const u8), out: *Cmd, allocator: Allocator) ParseError!void {
    _ = allocator;
    if (args.items.len == 0) return;
    const arg = args.items[0];

    if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
        return error.HelpRequested;
    }

    const info = @typeInfo(Cmd).@"struct";

    if (std.mem.startsWith(u8, arg, "--")) {
        const rest = arg[2..];
        const eql_idx = std.mem.indexOf(u8, rest, "=");
        const name = if (eql_idx) |i| rest[0..i] else rest;
        const has_inline_value = eql_idx != null;

        var matched = false;
        inline for (info.field_names, info.field_types) |field_name, field_type| {
            if (comptime command.is_struct(field_type)) continue;
            if (comptime command.field_kind(Cmd, field_name, field_type) != .flag) continue;

            if (std.mem.eql(u8, name, field_name)) {
                const is_bool = comptime field_type == bool or
                    (@typeInfo(field_type) == .optional and
                     @typeInfo(field_type).optional.child == bool);

                if (is_bool) {
                    if (has_inline_value) {
                        const raw_value = rest[eql_idx.? + 1 ..];
                        @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                    } else {
                        @field(out, field_name) = true;
                    }
                    _ = args.orderedRemove(0);
                } else {
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
                    @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                }
                matched = true;
                break;
            }
        }
        if (!matched) return error.UnknownFlag;
    } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
        const rest = arg[1..];
        var idx: usize = 0;
        _ = args.orderedRemove(0);

        while (idx < rest.len) {
            const ch = rest[idx];
            var matched = false;

            inline for (info.field_names, info.field_types) |field_name, field_type| {
                if (comptime command.is_struct(field_type)) continue;
                if (comptime command.field_kind(Cmd, field_name, field_type) != .flag) continue;

                const shortcut = comptime command.field_shortcut(Cmd, field_name);
                const matches_sc = shortcut != null and shortcut.?.len == 1 and shortcut.?[0] == ch;
                const matches_name = field_name.len == 1 and field_name[0] == ch;

                if (matches_sc or matches_name) {
                    matched = true;
                    const is_bool = comptime field_type == bool or
                        (@typeInfo(field_type) == .optional and
                         @typeInfo(field_type).optional.child == bool);

                    if (is_bool) {
                        @field(out, field_name) = true;
                        idx += 1;
                    } else {
                        if (idx + 1 < rest.len and rest[idx + 1] == '=') {
                            const raw_value = rest[idx + 2 ..];
                            @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                            idx = rest.len;
                        } else if (idx + 1 < rest.len) {
                            const raw_value = rest[idx + 1 ..];
                            @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                            idx = rest.len;
                        } else {
                            if (args.items.len == 0) return error.MissingFlagValue;
                            const raw_value = args.orderedRemove(0);
                            @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                            idx = rest.len;
                        }
                    }
                    break;
                }
            }
            if (!matched) return error.UnknownFlag;
        }
    } else {
        return error.UnknownFlag;
    }
}

fn parse_into(comptime Cmd: type, args: *std.ArrayList([]const u8), out: *Cmd, allocator: Allocator) ParseError!void {
    const info = @typeInfo(Cmd).@"struct";

    // Apply defaults.
    inline for (info.field_names, info.field_types, info.field_attrs) |name, field_type, attrs| {
        if (comptime command.is_struct(field_type)) continue;
        if (attrs.default_value_ptr) |ptr| {
            const v: *const field_type = @ptrCast(@alignCast(ptr));
            @field(out, name) = v.*;
        }
    }

    var positionals = std.ArrayList([]const u8).empty;
    defer positionals.deinit(allocator);

    var seen_mask: u64 = 0;
    var slice_lists: std.StringHashMap(std.ArrayList([]const u8)) = std.StringHashMap(std.ArrayList([]const u8)).init(allocator);
    defer {
        var it = slice_lists.valueIterator();
        while (it.next()) |list| {
            list.deinit(allocator);
        }
        slice_lists.deinit();
    }

    while (args.items.len > 0) {
        const arg = args.items[0];

        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            return error.HelpRequested;
        }

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

            var matched = false;
            inline for (info.field_names, info.field_types, 0..) |field_name, field_type, field_idx| {
                if (comptime command.is_struct(field_type)) continue;
                if (comptime command.field_kind(Cmd, field_name, field_type) != .flag) continue;

                if (std.mem.eql(u8, name, field_name)) {
                    if (comptime field_type == []const []const u8) {
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
                        var gop = try slice_lists.getOrPut(field_name);
                        if (!gop.found_existing) {
                            gop.value_ptr.* = std.ArrayList([]const u8).empty;
                        }
                        try gop.value_ptr.append(allocator, raw_value);
                    } else {
                        const mask = @as(u64, 1) << @truncate(field_idx);
                        if ((seen_mask & mask) != 0) return error.DuplicateFlag;
                        seen_mask |= mask;

                        const is_bool = comptime field_type == bool or
                            (@typeInfo(field_type) == .optional and
                             @typeInfo(field_type).optional.child == bool);

                        if (is_bool) {
                            if (has_inline_value) {
                                const raw_value = rest[eql_idx.? + 1 ..];
                                @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                            } else {
                                @field(out, field_name) = true;
                            }
                            _ = args.orderedRemove(0);
                        } else {
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
                            @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                        }
                    }
                    matched = true;
                    break;
                }
            }
            if (!matched) return error.UnknownFlag;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            const rest = arg[1..];
            var idx: usize = 0;
            _ = args.orderedRemove(0);

            while (idx < rest.len) {
                const ch = rest[idx];
                var matched = false;

                inline for (info.field_names, info.field_types, 0..) |field_name, field_type, field_idx| {
                    if (comptime command.is_struct(field_type)) continue;
                    if (comptime command.field_kind(Cmd, field_name, field_type) != .flag) continue;

                    const shortcut = comptime command.field_shortcut(Cmd, field_name);
                    const matches_sc = shortcut != null and shortcut.?.len == 1 and shortcut.?[0] == ch;
                    const matches_name = field_name.len == 1 and field_name[0] == ch;

                    if (matches_sc or matches_name) {
                        matched = true;

                        if (comptime field_type == []const []const u8) {
                            const raw_value = blk: {
                                if (idx + 1 < rest.len and rest[idx + 1] == '=') {
                                    const val = rest[idx + 2 ..];
                                    idx = rest.len;
                                    break :blk val;
                                } else if (idx + 1 < rest.len) {
                                    const val = rest[idx + 1 ..];
                                    idx = rest.len;
                                    break :blk val;
                                } else {
                                    if (args.items.len == 0) return error.MissingFlagValue;
                                    const val = args.orderedRemove(0);
                                    idx = rest.len;
                                    break :blk val;
                                }
                            };
                            var gop = try slice_lists.getOrPut(field_name);
                            if (!gop.found_existing) {
                                gop.value_ptr.* = std.ArrayList([]const u8).empty;
                            }
                            try gop.value_ptr.append(allocator, raw_value);
                        } else {
                            const mask = @as(u64, 1) << @truncate(field_idx);
                            if ((seen_mask & mask) != 0) return error.DuplicateFlag;
                            seen_mask |= mask;

                            const is_bool = comptime field_type == bool or
                                (@typeInfo(field_type) == .optional and
                                 @typeInfo(field_type).optional.child == bool);

                            if (is_bool) {
                                @field(out, field_name) = true;
                                idx += 1;
                            } else {
                                if (idx + 1 < rest.len and rest[idx + 1] == '=') {
                                    const raw_value = rest[idx + 2 ..];
                                    @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                                    idx = rest.len;
                                } else if (idx + 1 < rest.len) {
                                    const raw_value = rest[idx + 1 ..];
                                    @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                                    idx = rest.len;
                                } else {
                                    if (args.items.len == 0) return error.MissingFlagValue;
                                    const raw_value = args.orderedRemove(0);
                                    @field(out, field_name) = try parse_flag_value(field_type, raw_value);
                                    idx = rest.len;
                                }
                            }
                        }
                        break;
                    }
                }
                if (!matched) return error.UnknownFlag;
            }
        } else {
            try positionals.append(allocator, args.orderedRemove(0));
        }
    }

    // Set slice flags collected
    inline for (info.field_names, info.field_types) |name, field_type| {
        if (comptime command.is_struct(field_type)) continue;
        if (comptime command.field_kind(Cmd, name, field_type) == .flag and field_type == []const []const u8) {
            if (slice_lists.get(name)) |list| {
                @field(out, name) = try list.toOwnedSlice(allocator);
            } else {
                @field(out, name) = &.{};
            }
        }
    }

    // Parse positional args.
    var pos_idx: usize = 0;
    inline for (info.field_names, info.field_types) |name, field_type| {
        if (comptime command.is_struct(field_type)) continue;
        if (comptime command.field_kind(Cmd, name, field_type) != .positional) continue;

        if (comptime field_type == []const []const u8) {
            const slice = try allocator.alloc([]const u8, positionals.items.len - pos_idx);
            for (slice, positionals.items[pos_idx..]) |*s, p| s.* = p;
            @field(out, name) = slice;
            pos_idx = positionals.items.len;
        } else if (comptime @typeInfo(field_type) == .optional) {
            if (pos_idx < positionals.items.len) {
                @field(out, name) = positionals.items[pos_idx];
                pos_idx += 1;
            } else {
                @field(out, name) = null;
            }
        } else {
            if (pos_idx >= positionals.items.len) return error.MissingPositionalArg;
            @field(out, name) = positionals.items[pos_idx];
            pos_idx += 1;
        }
    }

    if (pos_idx < positionals.items.len) return error.TooManyPositionalArgs;
}

pub fn parse(comptime Cmd: type, raw_args: []const []const u8, allocator: Allocator) ParseError!command.Result(Cmd) {
    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);
    try args.appendSlice(allocator, raw_args);

    const is_leaf = comptime command.Result(Cmd) == Cmd;

    if (!is_leaf) {
        var parent_val: Cmd = undefined;

        const info = @typeInfo(Cmd).@"struct";
        inline for (info.field_names, info.field_types, info.field_attrs) |name, field_type, attrs| {
            if (comptime !command.is_struct(field_type)) {
                if (attrs.default_value_ptr) |ptr| {
                    const v: *const field_type = @ptrCast(@alignCast(ptr));
                    @field(parent_val, name) = v.*;
                }
            }
        }

        while (args.items.len > 0) {
            const first = args.items[0];

            if (std.mem.eql(u8, first, "--help") or std.mem.eql(u8, first, "-h")) {
                return error.HelpRequested;
            }

            var matched_sub = false;
            inline for (info.field_names, info.field_types) |name, field_type| {
                if (comptime command.is_struct(field_type)) {
                    if (std.mem.eql(u8, name, first)) {
                        matched_sub = true;
                        _ = args.orderedRemove(0);
                        @field(parent_val, name) = try parse(field_type, args.items, allocator);
                        return command.Result(Cmd){
                            .active = @field(std.meta.FieldEnum(Cmd), name),
                            .value = parent_val,
                        };
                    }
                }
            }

            if (!matched_sub and std.mem.startsWith(u8, first, "-")) {
                try parse_one_flag(Cmd, &args, &parent_val, allocator);
            } else {
                return error.UnknownCommand;
            }
        }
        return error.UnknownCommand;
    }

    var result: Cmd = undefined;
    try parse_into(Cmd, &args, &result, allocator);
    return result;
}

pub fn free(comptime Cmd: type, value: *const command.Result(Cmd), allocator: Allocator) void {
    const ResultType = command.Result(Cmd);
    if (ResultType == Cmd) {
        free_cmd(Cmd, @ptrCast(value), allocator);
    } else {
        free_parent(Cmd, value, allocator);
    }
}

fn free_cmd(comptime Cmd: type, value: *const Cmd, allocator: Allocator) void {
    const info = @typeInfo(Cmd).@"struct";
    inline for (info.field_names, info.field_types) |name, field_type| {
        if (comptime command.is_struct(field_type)) {
            free(field_type, &@field(value, name), allocator);
        } else if (comptime field_type == []const []const u8) {
            const slice = @field(value, name);
            if (slice.len > 0) {
                allocator.free(slice);
            }
        }
    }
}

fn free_parent(comptime Cmd: type, value: *const command.Result(Cmd), allocator: Allocator) void {
    switch (value.active) {
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
    defer free(Cmd, &result, std.testing.allocator);
    try std.testing.expectEqual(true, result);
}

test "parse int flag" {
    const Cmd = struct { count: u32 = 0 };
    const result = try parse(Cmd, &.{"--count", "5"}, std.testing.allocator);
    defer free(Cmd, &result, std.testing.allocator);
    try std.testing.expectEqual(@as(u32, 5), result);
}

test "unknown flag errors" {
    const Cmd = struct { verbose: bool = false };
    const err = parse(Cmd, &.{"--verboce"}, std.testing.allocator);
    try std.testing.expectError(error.UnknownFlag, err);
}

test "parse subcommand with parent flag" {
    const RunCmd = struct {
        now: bool = false,
        script: []const u8,
    };
    const Root = struct {
        verbose: bool = false,
        run: RunCmd,
    };
    const result = try parse(Root, &.{"--verbose", "run", "--now", "deploy.sh"}, std.testing.allocator);
    defer free(Root, &result, std.testing.allocator);
    try std.testing.expectEqual(true, result.value.verbose);
    try std.testing.expectEqualStrings("deploy.sh", result.value.run.script);
    try std.testing.expectEqual(true, result.value.run.now);
}

test "parse positional arg" {
    const Cmd = struct { script: []const u8 };
    const result = try parse(Cmd, &.{"deploy.sh"}, std.testing.allocator);
    defer free(Cmd, &result, std.testing.allocator);
    try std.testing.expectEqualStrings("deploy.sh", result.script);
}

test "parse optional flag" {
    const Cmd = struct { name: ?[]const u8 = null };
    const result = try parse(Cmd, &.{"--name", "alice"}, std.testing.allocator);
    defer free(Cmd, &result, std.testing.allocator);
    try std.testing.expectEqualStrings("alice", result.name.?);
}

test "parse enum flag" {
    const Level = enum { debug, info, warn };
    const Cmd = struct { level: Level = .info };
    const result = try parse(Cmd, &.{"--level", "warn"}, std.testing.allocator);
    defer free(Cmd, &result, std.testing.allocator);
    try std.testing.expectEqual(Level.warn, result.level);
}

test "missing positional arg errors" {
    const Cmd = struct { script: []const u8 };
    const err = parse(Cmd, &.{}, std.testing.allocator);
    try std.testing.expectError(error.MissingPositionalArg, err);
}

test "too many positional args errors" {
    const Cmd = struct { script: []const u8 };
    const err = parse(Cmd, &.{"a", "b"}, std.testing.allocator);
    try std.testing.expectError(error.TooManyPositionalArgs, err);
}

test "parse shortcut flag and combined short flags" {
    const Cmd = struct {
        verbose: bool = false,
        force: bool = false,
        pub const zcli_options = .{
            .verbose = .{ .shortcut = "v" },
            .force = .{ .shortcut = "f" },
        };
    };
    const result = try parse(Cmd, &.{"-vf"}, std.testing.allocator);
    defer free(Cmd, &result, std.testing.allocator);
    try std.testing.expectEqual(true, result.verbose);
    try std.testing.expectEqual(true, result.force);
}

test "parse duplicate flag error" {
    const Cmd = struct {
        count: u32 = 0,
    };
    const err = parse(Cmd, &.{"--count", "1", "--count", "2"}, std.testing.allocator);
    try std.testing.expectError(error.DuplicateFlag, err);
}

test "parse slice flag" {
    const Cmd = struct {
        include: []const []const u8 = &.{},
        pub const zcli_options = .{
            .include = .{ .kind = .flag },
        };
    };
    const result = try parse(Cmd, &.{"--include", "a", "--include", "b"}, std.testing.allocator);
    defer free(Cmd, &result, std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), result.include.len);
    try std.testing.expectEqualStrings("a", result.include[0]);
    try std.testing.expectEqualStrings("b", result.include[1]);
}

test "help requested error" {
    const Cmd = struct { verbose: bool = false };
    const err = parse(Cmd, &.{"--help"}, std.testing.allocator);
    try std.testing.expectError(error.HelpRequested, err);
}

