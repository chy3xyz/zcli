const std = @import("std");
const zcli = @import("zcli");

const RunCmd = struct {
    //! Run your workflow
    /// Run immediately
    now: bool = false,
    /// Script to execute
    script: []const u8,
};

const VersionCmd = struct {
    //! Show version
};

const Root = struct {
    //! Your dev toolkit CLI
    /// Run a workflow
    run: RunCmd,
    /// Show version
    version: VersionCmd,
};

fn handle_run(run: RunCmd) !void {
    std.debug.print("Running {s} (now={})\n", .{ run.script, run.now });
}

fn handle_version(_: VersionCmd) !void {
    std.debug.print("demo 0.1.0\n", .{});
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;

    var args = std.ArrayList([]const u8).empty;
    defer args.deinit(allocator);

    var it = init.minimal.args.iterate();
    _ = it.skip();
    while (it.next()) |arg| {
        try args.append(allocator, arg);
    }

    var errbuf: [1024]u8 = undefined;
    var err_writer = std.Io.File.Writer.init(.stderr(), init.io, &errbuf);
    const stderr = &err_writer.interface;

    const parsed = zcli.parse(Root, args.items, allocator) catch |err| {
        try zcli.print_diagnostic(stderr, .{ .err = err });
        try stderr.flush();
        std.process.exit(1);
    };
    defer zcli.free(Root, &parsed, allocator);

    try zcli.execute(Root, parsed, .{
        .run = handle_run,
        .version = handle_version,
    });

    try stderr.flush();
}
