const std = @import("std");

pub fn main() !void {
    // TODO: check the return value of mount

    _ = std.posix.linux.mount("proc", "/proc", "proc", 0, 0);
    _ = std.posix.linux.mount("sysfs", "/sys", "sysfs", 0, 0);
    _ = std.posix.linux.mount("cgroup2", "/sys/fs/cgroup", "cgroup2", 0, 0);
    _ = std.posix.linux.mount("tmpfs", "/run", "tmpfs", 0, 0);

    try std.fs.makeDirAbsolute("/run/upper");
    try std.fs.makeDirAbsolute("/run/work");

    _ = std.posix.linux.mount("dev", "/dev", "devtmpfs", 0, 0);
    _ = std.posix.linux.mount("/dev/sda", "/bundle", "squashfs", std.posix.linux.MS.RDONLY, 0);
    _ = std.posix.linux.mount("overlay", "/mnt", "overlay", std.posix.linux.MS.RDONLY, @intFromPtr("lowerdir=/bundle,upperdir=/run/upper,workdir=/run/work"));

    const argv = &[_:null]?[*:0]const u8{
        "/crun", "run", "-b", "/mnt", "--no-pivot", "crun_docker_c_id", null,
    };

    // TODO: make sure this never returns
    _ = std.posix.linux.execve("/crun", argv, std.c.environ);
}
