const std = @import("std");
const assert = std.debug.assert;
const common = @import("common.zig");

const mkdtemp = common.mkdtemp;
const extract_file = common.extract_file;

const squashfuse_content = @embedFile("tools/squashfuse");
const crun_content = @embedFile("tools/crun");
const overlayfs_content = @embedFile("tools/fuse-overlayfs");

fn getOffset(path: []const u8) !u64 {
    var file = try std.fs.cwd().openFile(path, .{});
    try file.seekFromEnd(-8);

    var buffer: [8]u8 = undefined;
    assert(try file.readAll(&buffer) == 8);

    return std.mem.readInt(u64, buffer[0..8], std.builtin.Endian.big);
}

const eql = std.mem.eql;

fn processArgs(file: std.fs.File, allocator: std.mem.Allocator) !void {
    // const file = try std.fs.openFileAbsolute(path, .{ .mode = .read_write });

    var jsonReader = std.json.reader(allocator, file.reader());

    // TODO: having to specify max_value_len seems like a bug
    var root_value = try std.json.Value.jsonParse(allocator, &jsonReader, .{ .max_value_len = 99999999 });

    const argVal = args: {
        switch (root_value) {
            .object => |*object| {
                const processVal = object.getPtr("process") orelse @panic("no process key");
                switch (processVal.*) {
                    .object => |*process| {
                        const argsVal = process.getPtr("args") orelse @panic("no args key");
                        switch (argsVal.*) {
                            .array => |*argsArr| {
                                break :args argsArr;
                            },
                            else => return error.InvalidJSON,
                        }
                    },
                    else => return error.InvalidJSON,
                }
            },
            else => return error.InvalidJSON,
        }
    };

    var args = std.process.args();
    _ = args.next() orelse @panic("there should be an executable");

    while (args.next()) |arg| {
        if (eql(u8, arg, "-p")) {
            _ = args.next();
            @panic("not implemented");
        } else if (eql(u8, arg, "-v")) {
            _ = args.next();
            @panic("not implemented");
        } else if (eql(u8, arg, "--")) {
            while (args.next()) |arg_inner| {
                try argVal.append(std.json.Value{ .string = arg_inner });
            }
        } else {
            try argVal.append(std.json.Value{ .string = arg });
        }
    }

    try file.setEndPos(0);
    try file.seekTo(0);
    var jsonWriter = std.json.writeStream(file.writer(), .{ .whitespace = .indent_tab });

    try std.json.Value.jsonStringify(root_value, &jsonWriter);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    // defer _ = gpa.deinit();
    var args = std.process.args();
    const executable_path = args.next() orelse unreachable;

    const temp_dir_path = std.mem.span(mkdtemp("/tmp/dockerc-XXXXXX") orelse @panic("failed to create temp dir"));

    const squashfuse_path = try extract_file(temp_dir_path, "squashfuse", squashfuse_content, allocator);
    defer allocator.free(squashfuse_path);

    const crun_path = try extract_file(temp_dir_path, "crun", crun_content, allocator);
    defer allocator.free(crun_path);

    const overlayfs_path = try extract_file(temp_dir_path, "fuse-overlayfs", overlayfs_content, allocator);
    defer allocator.free(overlayfs_path);

    const filesystem_bundle_dir_null = try std.fmt.allocPrintZ(allocator, "{s}/{s}", .{ temp_dir_path, "bundle.squashfs" });
    defer allocator.free(filesystem_bundle_dir_null);

    try std.fs.makeDirAbsolute(filesystem_bundle_dir_null);

    const mount_dir_path = try std.fmt.allocPrint(allocator, "{s}/mount", .{temp_dir_path});
    defer allocator.free(mount_dir_path);

    const offsetArg = try std.fmt.allocPrint(allocator, "offset={}", .{try getOffset(executable_path)});
    defer allocator.free(offsetArg);

    const args_buf = [_][]const u8{ squashfuse_path, "-o", offsetArg, executable_path, filesystem_bundle_dir_null };

    var mountProcess = std.ChildProcess.init(&args_buf, gpa.allocator());
    _ = try mountProcess.spawnAndWait();

    const overlayfs_options = try std.fmt.allocPrint(allocator, "lowerdir={s},upperdir={s}/upper,workdir={s}/upper", .{
        filesystem_bundle_dir_null,
        temp_dir_path,
        temp_dir_path,
    });
    defer allocator.free(overlayfs_options);

    const tmpDir = try std.fs.openDirAbsolute(temp_dir_path, .{});
    try tmpDir.makeDir("upper");
    try tmpDir.makeDir("work");
    try tmpDir.makeDir("mount");

    var overlayfsProcess = std.ChildProcess.init(&[_][]const u8{ overlayfs_path, "-o", overlayfs_options, mount_dir_path }, allocator);
    _ = try overlayfsProcess.spawnAndWait();

    const file = try tmpDir.openFile("mount/config.json", .{ .mode = .read_write });
    defer file.close();
    try processArgs(file, allocator);

    var crunProcess = std.ChildProcess.init(&[_][]const u8{ crun_path, "run", "-b", mount_dir_path, "crun_docker_c_id" }, gpa.allocator());
    _ = try crunProcess.spawnAndWait();

    var umountOverlayProcess = std.ChildProcess.init(&[_][]const u8{ "umount", mount_dir_path }, gpa.allocator());
    _ = try umountOverlayProcess.spawnAndWait();

    var umountProcess = std.ChildProcess.init(&[_][]const u8{ "umount", filesystem_bundle_dir_null }, gpa.allocator());
    _ = try umountProcess.spawnAndWait();

    // TODO: clean up /tmp
}
