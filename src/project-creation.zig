const std = @import("std");

pub fn createProject(io: std.Io, name: []const u8, minimal: bool) !void {
    std.debug.print("Creating project: {s}\n", .{name});

    // Current working directory
    const cwd = std.Io.Dir.cwd();

    // Create and open the project directory
    var dir = try cwd.createDirPathOpen(io, name, .{});
    defer dir.close(io);

    // arguments for zig init
    var argv: [3][]const u8 = undefined;

    argv[0] = "zig";
    argv[1] = "init";

    if (minimal) {
        argv[2] = "-m";
    }

    // Run `zig init` inside the project directory
    var child = try std.process.spawn(io, .{
        .argv = argv[0..3],
        .cwd = .{ .dir = dir },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const result = try child.wait(io);

    switch (result) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print(
                    "zig init failed with exit code {d}\n",
                    .{code},
                );
                return;
            }
        },

        .signal => |signal| {
            std.debug.print(
                "zig init terminated by signal {d}\n",
                .{signal},
            );
            return;
        },

        .stopped => |signal| {
            std.debug.print(
                "zig init stopped by signal {d}\n",
                .{signal},
            );
            return;
        },

        .unknown => |value| {
            std.debug.print(
                "zig init terminated with unknown status {d}\n",
                .{value},
            );
            return;
        },
    }

    std.debug.print("Project created successfully!\n", .{});
}

test "minimal" {
    try createProject(std.testing.io, "Hi", true);
}

test "non-mini" {
    try createProject(std.testing.io, "Hi2", false);
}
