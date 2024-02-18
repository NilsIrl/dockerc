const std = @import("std");

pub extern fn mkdtemp(in: [*:0]const u8) ?[*:0]const u8;

// TODO: ideally we can use memfd_create
// The problem is that zig doesn't have fexecve support by default so it would
// be a pain to find the location of the file.
pub fn extract_file(tmpDir: []const u8, name: []const u8, data: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ tmpDir, name });

    const file = try std.fs.createFileAbsolute(path, .{ .mode = 0o700 });
    defer file.close();
    try file.writeAll(data);

    return path;
}
