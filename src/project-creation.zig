const std = @import("std");

pub const Template = enum {
    empty,
    raylib,
    sdl3,
    custom,
};

pub const ProjectConfig = struct {
    name: []const u8,
    parent_directory: []const u8 = ".",
    template: Template = .empty,
    minimal: bool = false,
    custom_template_path: ?[]const u8 = null,
};

pub const ProjectInfo = struct {
    name: []const u8,
    path: []const u8,
    template: Template,
};

pub const ProjectError = error{
    InvalidProjectName,
    DestinationExists,
    MissingTemplatePath,
    ProjectInitFailed,
    TemplateCopyFailed,
};

/// Backwards-compatible entry point used by the current project manager.
pub fn createProject(
    io: std.Io,
    name: []const u8,
    minimal: bool,
) !void {
    try createConfiguredProject(io, .{
        .name = name,
        .template = .empty,
        .minimal = minimal,
    });
}

/// Creates a project from the selected configuration.
///
/// Built-in templates are expected in:
///   templates/raylib
///   templates/sdl3
///
/// A custom template can be supplied through custom_template_path.
pub fn createConfiguredProject(
    io: std.Io,
    config: ProjectConfig,
) !void {
    try validateProjectName(config.name);

    if (config.parent_directory.len == 0) {
        return error.InvalidProjectName;
    }

    const allocator = std.heap.page_allocator;
    const cwd = std.Io.Dir.cwd();

    // Create or open the chosen parent directory.
    var parent = try cwd.createDirPathOpen(
        io,
        config.parent_directory,
        .{},
    );
    defer parent.close(io);

    // Do not overwrite an existing project.
    if (parent.openDir(io, config.name, .{})) |existing| {
        var dir = existing;
        dir.close(io);
        return error.DestinationExists;
    } else |err| {
        if (err != error.FileNotFound) return err;
    }

    // Create the project directory itself.
    try parent.createDir(io, config.name, .default_dir);

    var project_dir = try parent.openDir(io, config.name, .{});
    defer project_dir.close(io);

    switch (config.template) {
        .empty => {
            try runZigInit(io, project_dir, config.minimal);
        },
        .raylib, .sdl3, .custom => {
            const source_path = switch (config.template) {
                .raylib => "templates/raylib",
                .sdl3 => "templates/sdl3",
                .custom => config.custom_template_path orelse
                    return error.MissingTemplatePath,
                .empty => unreachable,
            };

            try copyTemplate(
                io,
                allocator,
                source_path,
                config.parent_directory,
                config.name,
            );
        },
    }

    std.debug.print(
        "Project '{s}' created successfully.\n",
        .{config.name},
    );
}

fn validateProjectName(name: []const u8) ProjectError!void {
    if (name.len == 0 or name.len > 64) {
        return error.InvalidProjectName;
    }

    if (std.mem.eql(u8, name, ".") or
        std.mem.eql(u8, name, ".."))
    {
        return error.InvalidProjectName;
    }

    for (name) |character| {
        const valid =
            std.ascii.isAlphanumeric(character) or
            character == '_' or
            character == '-';

        if (!valid) return error.InvalidProjectName;
    }
}

fn runZigInit(
    io: std.Io,
    project_dir: std.Io.Dir,
    minimal: bool,
) !void {
    const argv: []const []const u8 = if (minimal)
        &.{ "zig", "init", "-m" }
    else
        &.{ "zig", "init" };

    var child = try std.process.spawn(io, .{
        .argv = argv,
        .cwd = .{ .dir = project_dir },
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const result = try child.wait(io);

    switch (result) {
        .exited => |code| {
            if (code != 0) {
                return error.ProjectInitFailed;
            }
        },
        .signal => return error.ProjectInitFailed,
        .stopped => return error.ProjectInitFailed,
        .unknown => return error.ProjectInitFailed,
    }
}

fn copyTemplate(
    io: std.Io,
    allocator: std.mem.Allocator,
    source_path: []const u8,
    parent_path: []const u8,
    project_name: []const u8,
) !void {
    // Copy the contents of the template directory into the new project.
    // The source must exist and contain the desired starter files.
    const source = try std.fmt.allocPrint(
        allocator,
        "{s}/.",
        .{source_path},
    );
    defer allocator.free(source);

    const destination = try std.fmt.allocPrint(
        allocator,
        "{s}/{s}",
        .{ parent_path, project_name },
    );
    defer allocator.free(destination);

    const argv = [_][]const u8{
        "cp",
        "-a",
        source,
        destination,
    };

    var child = try std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    });

    const result = try child.wait(io);

    switch (result) {
        .exited => |code| {
            if (code != 0) return error.TemplateCopyFailed;
        },
        .signal => return error.TemplateCopyFailed,
        .stopped => return error.TemplateCopyFailed,
        .unknown => return error.TemplateCopyFailed,
    }
}

test "project names reject unsafe path characters" {
    try validateProjectName("MyGame");
    try validateProjectName("my-game_2");

    try std.testing.expectError(
        error.InvalidProjectName,
        validateProjectName("../outside"),
    );

    try std.testing.expectError(
        error.InvalidProjectName,
        validateProjectName(""),
    );
}
