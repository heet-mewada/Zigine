const std = @import("std");

// This starter is deliberately dependency-free so a new project builds
// immediately. The render loop is the same seam used by the Raylib backend;
// applications can add raylib-zig without changing the scene/project flow.
pub fn main() void {
    std.debug.print("Zigine Raylib game started.\n", .{});
}
