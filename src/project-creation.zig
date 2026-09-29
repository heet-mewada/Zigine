const std = @import("std");

pub fn createProject(io: std.Io, name: []const u8, minimal: bool) !void {
    std.debug.print("Creating project: {s}\n", .{name});

    const cwd = std.Io.Dir.cwd();

    var dir = try cwd.createDirPathOpen(io, name, .{});
    defer dir.close(io);

    // Build the correct argument list.
    const argv: []const []const u8 = if (minimal)
        &.{ "zig", "init", "-m" }
    else
        &.{ "zig", "init" };

    // Run `zig init` inside the project directory.
    var child = try std.process.spawn(io, .{
        .argv = argv,
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
    try createProject(std.testing.io, "Hi", false);
}

test "non-mini" {
    try createProject(std.testing.io, "Hi2", true);
}
