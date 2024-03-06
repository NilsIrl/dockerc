const std = @import("std");
const crun_content = @embedFile("src/tools/crun");



// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    b.reference_trace = 64;

    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});
    // target.result.abi = .musl;

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});


    const runtime = b.addExecutable(.{
        .name = "runtime",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const dockerc = b.addExecutable(.{
        .name = "dockerc",
        .root_source_file = .{ .path = "src/dockerc.zig" },
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const init = b.addExecutable(.{
        .name = "init",
        .root_source_file = .{ .path = "src/init.zig" },
        .target = target,
        .optimize = optimize,
        // for std.c.environ
        .link_libc = true,
    });

    const cpio = b.addWriteFiles();
    _ = cpio.addCopyFile(init.getEmittedBin(), "init");
    _ = cpio.add("etc/resolv.conf", "nameserver 1.1.1.1\n");
    _ = cpio.add("crun", crun_content);

    const mkdir = b.addSystemCommand(&.{"mkdir", "dev", "bundle", "mnt", "proc", "run", "sys", "tmp"});
    mkdir.setCwd(cpio.getDirectory());

    const findCommand = b.addSystemCommand(&.{"find", ".", "-print0"});
    findCommand.setCwd(cpio.getDirectory());
    findCommand.step.dependOn(&mkdir.step);

    const cpioCommand = b.addSystemCommand(&.{"cpio", "--null", "-ov", "--format=newc"});
    cpioCommand.setCwd(cpio.getDirectory());
    cpioCommand.setStdIn(.{.lazy_path=findCommand.captureStdOut()});


    dockerc.root_module.addAnonymousImport("runtime", .{ .root_source_file = runtime.getEmittedBin() });
    dockerc.root_module.addAnonymousImport("cpio", .{ .root_source_file = cpioCommand.captureStdOut() });

    b.installArtifact(dockerc);
    b.installArtifact(init);
}
