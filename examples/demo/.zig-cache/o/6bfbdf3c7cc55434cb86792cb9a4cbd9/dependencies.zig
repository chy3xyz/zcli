pub const packages = struct {
    pub const @"../.." = struct {
        pub const build_root = "/Users/n0x/w4_proj/zig_ws/zcli/examples/demo/../..";
        pub const build_zig = @import("../..");
        pub const deps: []const struct { []const u8, []const u8 } = &.{
        };
    };
};

pub const root_deps: []const struct { []const u8, []const u8 } = &.{
    .{ "zcli", "../.." },
};
