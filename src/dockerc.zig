const std = @import("std");
const clap = @import("clap");
const common = @import("common.zig");

const mkdtemp = common.mkdtemp;
const extract_file = common.extract_file;

const debug = std.debug;

const io = std.io;

const skopeo_content = @embedFile("tools/skopeo");
const mksquashfs_content = @embedFile("tools/mksquashfs");
const umoci_content = @embedFile("umoci");

const policy_content = @embedFile("tools/policy.json");

const runtime_content = @embedFile("runtime");

const runtime_content_len_u64 = data: {
    var buf: [8]u8 = undefined;
    std.mem.writeInt(u64, &buf, runtime_content.len, .big);
    break :data buf;
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const temp_dir_path = std.mem.span(mkdtemp("/tmp/dockerc-XXXXXX") orelse @panic("failed to create temp dir"));

    const allocator = gpa.allocator();
    const skopeo_path = try extract_file(temp_dir_path, "skopeo", skopeo_content, allocator);
    defer allocator.free(skopeo_path);

    const umoci_path = try extract_file(temp_dir_path, "umoci", umoci_content, allocator);
    defer allocator.free(umoci_path);

    const mksquashfs_path = try extract_file(temp_dir_path, "mksquashfs", mksquashfs_content, allocator);
    defer allocator.free(mksquashfs_path);

    const policy_path = try extract_file(temp_dir_path, "policy.json", policy_content, allocator);
    defer allocator.free(policy_path);

    const params = comptime clap.parseParamsComptime(
        \\-h, --help               Display this help and exit.
        \\-i, --image <str>        Image to pull.
        \\-o, --output <str>       Output file.
        \\--rootfull               Do not use rootless container.
        \\
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch |err| {
        // Report useful error and exit
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        try clap.help(io.getStdErr().writer(), clap.Help, &params, .{});
        return;
    }

    var missing_args = false;
    if (res.args.image == null) {
        debug.print("no --image specified\n", .{});
        missing_args = true;
    }

    if (res.args.output == null) {
        debug.print("no --output specified\n", .{});
        missing_args = true;
    }

    if (missing_args) {
        debug.print("--help for usage\n", .{});
        return;
    }

    // safe to assert because checked above
    const image = res.args.image.?;
    const output_path = res.args.output.?;

    const destination_arg = try std.fmt.allocPrint(allocator, "oci:{s}/image:latest", .{temp_dir_path});
    defer allocator.free(destination_arg);

    var skopeoProcess = std.ChildProcess.init(&[_][]const u8{ skopeo_path, "copy", "--policy", policy_path, image, destination_arg }, gpa.allocator());
    _ = try skopeoProcess.spawnAndWait();

    const umoci_image_layout_path = try std.fmt.allocPrint(allocator, "{s}/image:latest", .{temp_dir_path});
    defer allocator.free(umoci_image_layout_path);

    const bundle_destination = try std.fmt.allocPrint(allocator, "{s}/bundle", .{temp_dir_path});
    defer allocator.free(bundle_destination);

    const umoci_args = [_][]const u8{
        umoci_path,
        "unpack",
        "--image",
        umoci_image_layout_path,
        bundle_destination,
        "--rootless",
    };
    var umociProcess = std.ChildProcess.init(if (res.args.rootfull == 0) &umoci_args else umoci_args[0 .. umoci_args.len - 1], gpa.allocator());
    _ = try umociProcess.spawnAndWait();

    const offset_arg = try std.fmt.allocPrint(allocator, "{}", .{runtime_content.len});
    defer allocator.free(offset_arg);

    var mksquashfsProcess = std.ChildProcess.init(&[_][]const u8{
        mksquashfs_path,
        bundle_destination,
        output_path,
        "-comp",
        "zstd",
        "-offset",
        offset_arg,
        "-noappend",
    }, gpa.allocator());
    _ = try mksquashfsProcess.spawnAndWait();

    const file = try std.fs.cwd().openFile(output_path, .{
        .mode = .write_only,
    });
    defer file.close();

    try file.writeAll(runtime_content);
    try file.seekFromEnd(0);
    try file.writeAll(&runtime_content_len_u64);
    try file.chmod(0o755);
}
