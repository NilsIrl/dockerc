const std = @import("std");
const assert = std.debug.assert;
const common = @import("common.zig");

const mkdtemp = common.mkdtemp;
const extract_file = common.extract_file;

const squashfuse_content = @embedFile("tools/squashfuse");
const overlayfs_content = @embedFile("tools/fuse-overlayfs");

const c = @cImport({
    @cInclude("libcrun/container.h");
    @cInclude("libcrun/custom-handler.h");
});

fn getOffset(path: []const u8) !u64 {
    var file = try std.fs.cwd().openFile(path, .{});
    try file.seekFromEnd(-8);

    var buffer: [8]u8 = undefined;
    assert(try file.readAll(&buffer) == 8);

    return std.mem.readInt(u64, buffer[0..8], std.builtin.Endian.big);
}

const eql = std.mem.eql;

// inspired from std.posix.getenv
fn getEnvFull(key: []const u8) ?[:0]const u8 {
    var ptr = std.c.environ;
    while (ptr[0]) |line| : (ptr += 1) {
        var line_i: usize = 0;
        while (line[line_i] != 0 and line[line_i] != '=') : (line_i += 1) {}
        const this_key = line[0..line_i];

        if (!std.mem.eql(u8, this_key, key)) continue;

        return std.mem.sliceTo(line, 0);
    }
    return null;
}

fn getContainerFromArgs(file: std.fs.File, rootfs_absolute_path: []const u8, parentAllocator: std.mem.Allocator) ![*c]c.libcrun_container_t {
    var arena = std.heap.ArenaAllocator.init(parentAllocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var jsonReader = std.json.reader(allocator, file.reader());

    // TODO: having to specify max_value_len seems like a bug
    var root_value = try std.json.Value.jsonParse(allocator, &jsonReader, .{ .max_value_len = 99999999 });

    var args_json: *std.ArrayList(std.json.Value) = undefined;
    var env_json: *std.ArrayList(std.json.Value) = undefined;
    var mounts_json: *std.ArrayList(std.json.Value) = undefined;

    switch (root_value) {
        .object => |*object| {
            const processVal = object.getPtr("process") orelse @panic("no process key");
            switch (processVal.*) {
                .object => |*process| {
                    const argsVal = process.getPtr("args") orelse @panic("no args key");
                    switch (argsVal.*) {
                        .array => |*argsArr| {
                            args_json = argsArr;
                        },
                        else => return error.InvalidJSON,
                    }

                    if (process.getPtr("env")) |envVal| {
                        switch (envVal.*) {
                            .array => |*envArr| {
                                env_json = envArr;
                            },
                            else => return error.InvalidJSON,
                        }
                    } else {
                        var array = std.json.Array.init(allocator);
                        env_json = &array;
                        try process.put("env", std.json.Value{ .array = array });
                    }
                },
                else => return error.InvalidJSON,
            }

            if (object.getPtr("mounts")) |mountsVal| {
                switch (mountsVal.*) {
                    .array => |*mountsArr| {
                        mounts_json = mountsArr;
                    },
                    else => return error.InvalidJSON,
                }
            } else {
                var array = std.json.Array.init(allocator);
                mounts_json = &array;
                try object.put("mounts", std.json.Value{ .array = array });
            }

            const rootVal = object.getPtr("root") orelse @panic("no root key");
            switch (rootVal.*) {
                .object => |*root| {
                    try root.put("path", std.json.Value{ .string = rootfs_absolute_path });
                },
                else => return error.InvalidJSON,
            }
        },
        else => return error.InvalidJSON,
    }

    var args = std.process.args();
    _ = args.next() orelse @panic("there should be an executable");

    while (args.next()) |arg| {
        if (eql(u8, arg, "-e") or eql(u8, arg, "--env")) {
            const environment_variable = args.next() orelse @panic("expected environment variable");
            if (std.mem.indexOfScalar(u8, environment_variable, '=')) |_| {
                try env_json.append(std.json.Value{ .string = environment_variable });
            } else {
                try env_json.append(std.json.Value{ .string = getEnvFull(environment_variable) orelse @panic("environment variable does not exist") });
            }
        } else if (eql(u8, arg, "-v") or eql(u8, arg, "--volume")) {
            const volume_syntax = args.next() orelse @panic("expected volume syntax");

            var mount = std.json.ObjectMap.init(allocator);

            var options = std.json.Array.init(allocator);
            try options.append(std.json.Value{ .string = "rw" });
            try options.append(std.json.Value{ .string = "rbind" });
            try mount.put("options", std.json.Value{ .array = options });

            const separator = std.mem.indexOfScalar(u8, volume_syntax, ':') orelse @panic("no volume destination specified");

            if (volume_syntax[0] == '/') {
                try mount.put("source", std.json.Value{ .string = volume_syntax[0..separator] });
            } else {
                try mount.put("source", std.json.Value{ .string = try std.fs.cwd().realpathAlloc(allocator, volume_syntax[0..separator]) });
            }
            try mount.put("destination", std.json.Value{ .string = volume_syntax[separator + 1 ..] });

            try mounts_json.append(std.json.Value{ .object = mount });
        } else if (eql(u8, arg, "--")) {
            while (args.next()) |arg_inner| {
                try args_json.append(std.json.Value{ .string = arg_inner });
            }
        } else {
            try args_json.append(std.json.Value{ .string = arg });
        }
    }

    const stringified_config = stringified_config: {
        var list = std.ArrayList(u8).init(allocator);
        errdefer list.deinit();
        try std.json.stringifyArbitraryDepth(allocator, root_value, .{}, list.writer());
        break :stringified_config try list.toOwnedSliceSentinel(0);
    };

    var err: c.libcrun_error_t = null;
    const container = c.libcrun_container_load_from_memory(stringified_config, &err);
    if (container == null) {
        std.debug.panic("failed to load config: {s}\n", .{err.*.msg});
    }

    return container;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = std.process.args();
    const executable_path = args.next() orelse unreachable;

    const temp_dir_path = std.mem.span(mkdtemp("/tmp/dockerc-XXXXXX") orelse @panic("failed to create temp dir"));

    const squashfuse_path = try extract_file(temp_dir_path, "squashfuse", squashfuse_content, allocator);
    defer allocator.free(squashfuse_path);

    const overlayfs_path = try extract_file(temp_dir_path, "fuse-overlayfs", overlayfs_content, allocator);
    defer allocator.free(overlayfs_path);

    const filesystem_bundle_dir_null = try std.fmt.allocPrintZ(allocator, "{s}/{s}", .{ temp_dir_path, "bundle.squashfs" });
    defer allocator.free(filesystem_bundle_dir_null);

    try std.fs.makeDirAbsolute(filesystem_bundle_dir_null);

    const mount_dir_path = try std.fmt.allocPrintZ(allocator, "{s}/mount", .{temp_dir_path});
    defer allocator.free(mount_dir_path);

    const offsetArg = try std.fmt.allocPrint(allocator, "offset={}", .{try getOffset(executable_path)});
    defer allocator.free(offsetArg);

    const args_buf = [_][]const u8{ squashfuse_path, "-o", offsetArg, executable_path, filesystem_bundle_dir_null };

    var mountProcess = std.ChildProcess.init(&args_buf, allocator);
    _ = try mountProcess.spawnAndWait();

    const overlayfs_options = try std.fmt.allocPrint(allocator, "lowerdir={s},upperdir={s}/upper,workdir={s}/work", .{
        filesystem_bundle_dir_null,
        temp_dir_path,
        temp_dir_path,
    });
    defer allocator.free(overlayfs_options);

    const container = container: {
        // Indent so that handles to files in mounted dir are closed by the end
        // to avoid umounting from being blocked.
        var tmpDir = try std.fs.openDirAbsolute(temp_dir_path, .{});
        defer tmpDir.close();
        try tmpDir.makeDir("upper");
        try tmpDir.makeDir("work");
        try tmpDir.makeDir("mount");

        var overlayfsProcess = std.ChildProcess.init(&[_][]const u8{ overlayfs_path, "-o", overlayfs_options, mount_dir_path }, allocator);
        _ = try overlayfsProcess.spawnAndWait();

        const rootfs_absolute_path = try std.fmt.allocPrint(allocator, "{s}/mount/rootfs", .{temp_dir_path});
        defer allocator.free(rootfs_absolute_path);

        const file = try tmpDir.openFile("mount/config.json", .{ .mode = .read_only });
        defer file.close();

        break :container try getContainerFromArgs(file, rootfs_absolute_path, allocator);
    };
    defer c.libcrun_container_free(container);

    var crun_context = c.libcrun_context_t{
        .bundle = mount_dir_path,
        .id = temp_dir_path[13..],
        .fifo_exec_wait_fd = -1,
        .preserve_fds = 0,
        .listen_fds = 0,
    };

    var err: c.libcrun_error_t = null;
    if (c.libcrun_init_logging(&crun_context.output_handler, &crun_context.output_handler_arg, crun_context.id, null, &err) < 0) {
        std.debug.panic("unreachable but not using the unreachable keyword for forward compatibility", .{});
    }

    crun_context.handler_manager = c.libcrun_handler_manager_create(&err);
    if (crun_context.handler_manager == null) {
        std.debug.panic("failed to create handler manager ({d}): {s}\n", .{ err.*.status, err.*.msg });
    }

    const ret = c.libcrun_container_run(&crun_context, container, 0, &err);

    if (ret != 0) {
        if (err != null) {
            std.debug.panic("failed to run container ({d}): {s}\n", .{ ret, err.*.msg });
        } else {
            std.debug.panic("failed to run container ({d})\n", .{ret});
        }
    }

    var umountOverlayProcess = std.ChildProcess.init(&[_][]const u8{ "umount", mount_dir_path }, allocator);
    _ = try umountOverlayProcess.spawnAndWait();

    var umountProcess = std.ChildProcess.init(&[_][]const u8{ "umount", filesystem_bundle_dir_null }, allocator);
    _ = try umountProcess.spawnAndWait();

    // TODO: clean up /tmp
}
