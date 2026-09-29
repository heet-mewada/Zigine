const std = @import("std");
const builtin = @import("builtin");

pub fn runproject(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir_name: []const u8,
    file_name: []const u8,
    flags: []const []const u8,
    flags_present: bool,
    run_main: bool,
) !void {
    std.debug.print("Running the project {s}\n", .{file_name});

    const cwd = std.Io.Dir.cwd();

    var dir = try cwd.openDir(io, dir_name, .{});
    defer dir.close(io);

    // Build arguments for zig.
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "zig");
    try argv.append(allocator, "build");
    if (!run_main) {
        try argv.append(allocator, file_name);
    } else {
        try argv.append(allocator, "run");
    }
    // Arguments after `--` are passed to the program.
    if (flags_present) {
        try argv.append(allocator, "--");
        try argv.appendSlice(allocator, flags);
    }

    var child = try std.process.spawn(io, .{
        .argv = argv.items,
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
                    "zig failed to run: {d}\n",
                    .{code},
                );
                return;
            }
        },

        .signal => |signal| {
            std.debug.print(
                "zig terminated: {d}\n",
                .{signal},
            );
            return;
        },

        .stopped => |signal| {
            std.debug.print(
                "zig stopped: {d}\n",
                .{signal},
            );
            return;
        },

        .unknown => |value| {
            std.debug.print(
                "zig terminated with unknown: {d}\n",
                .{value},
            );
            return;
        },
    }

    std.debug.print(
        "Project started running successfully!\n",
        .{},
    );
}

pub fn testing_project(
    io: std.Io,
    allocator: std.mem.Allocator,
    dir_name: []const u8,
    file_name: []const u8,
    main_test: bool,
) !void {
    std.debug.print("Testing project: {s}\n", .{file_name});

    const cwd = std.Io.Dir.cwd();

    var dir = try cwd.openDir(io, dir_name, .{});
    defer dir.close(io);

    // Build arguments for testing.
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "zig");
    if (main_test) {
        try argv.append(allocator, "build");
    }
    try argv.append(allocator, "test");

    // An empty filename means `zig test` with no explicit file.
    if (file_name.len != 0) {
        try argv.append(allocator, file_name);
    }

    var child = try std.process.spawn(io, .{
        .argv = argv.items,
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
                    "zig failed to test: {d}\n",
                    .{code},
                );
                return;
            }
        },

        .signal => |signal| {
            std.debug.print(
                "zig terminated: {d}\n",
                .{signal},
            );
            return;
        },

        .stopped => |signal| {
            std.debug.print(
                "zig stopped: {d}\n",
                .{signal},
            );
            return;
        },

        .unknown => |value| {
            std.debug.print(
                "zig terminated with unknown status: {d}\n",
                .{value},
            );
            return;
        },
    }

    std.debug.print(
        "Project testing completed successfully!\n",
        .{},
    );
}

const project_dir = if (builtin.target.os.tag == .windows)
    "Hi\\src"
else
    "Hi/src";

test "running_project" {
    const flags = [_][]const u8{};

    try runproject(
        std.testing.io,
        std.testing.allocator,
        project_dir,
        "main.zig",
        &flags,
        false,
        false,
    );
}

test "running_project_main" {
    const flags = [_][]const u8{};

    try runproject(
        std.testing.io,
        std.testing.allocator,
        project_dir,
        "main.zig",
        &flags,
        false,
        true,
    );
}

test "running_help" {
    const flags = [_][]const u8{"--help"};

    try runproject(
        std.testing.io,
        std.testing.allocator,
        project_dir,
        "main.zig",
        &flags,
        true,
        false,
    );
}

test "testing_project" {
    try testing_project(
        std.testing.io,
        std.testing.allocator,
        project_dir,
        "test.zig",
        false,
    );
}

test "testing_project_main" {
    try testing_project(
        std.testing.io,
        std.testing.allocator,
        project_dir,
        "main.zig",
        true,
    );
}
