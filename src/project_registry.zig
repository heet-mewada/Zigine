const std = @import("std");

pub const max_projects = 64;
pub const max_path_length = 1024;
const max_registry_bytes = 128 * 1024;

pub const ConfigLocation = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ConfigLocation {
        return .{ .allocator = allocator };
    }

    /// Returns the platform-appropriate Zigine configuration directory.
    /// The caller owns the returned memory.
    pub fn directory(
        self: ConfigLocation,
        environ: *const std.process.Environ.Map,
    ) ![]u8 {
        if (comptime @import("builtin").os.tag == .windows) {
            if (environ.get("APPDATA")) |appdata| {
                return std.fs.path.join(
                    self.allocator,
                    &.{ appdata, "Zigine" },
                );
            }

            return error.ConfigurationDirectoryUnavailable;
        }

        if (comptime @import("builtin").os.tag == .macos) {
            const home = environ.get("HOME") orelse
                return error.ConfigurationDirectoryUnavailable;

            return std.fs.path.join(
                self.allocator,
                &.{ home, "Library", "Application Support", "Zigine" },
            );
        }

        const home = environ.get("HOME") orelse
            return error.ConfigurationDirectoryUnavailable;

        if (environ.get("XDG_CONFIG_HOME")) |xdg| {
            if (xdg.len > 0 and std.fs.path.isAbsolute(xdg)) {
                return std.fs.path.join(
                    self.allocator,
                    &.{ xdg, "zigine" },
                );
            }
        }

        return std.fs.path.join(
            self.allocator,
            &.{ home, ".config", "zigine" },
        );
    }

    pub fn registryFile(
        self: ConfigLocation,
        environ: *const std.process.Environ.Map,
    ) ![]u8 {
        const dir = try self.directory(environ);
        defer self.allocator.free(dir);

        return std.fs.path.join(
            self.allocator,
            &.{ dir, "projects.txt" },
        );
    }
};

pub const Project = struct {
    path: [max_path_length]u8 = [_]u8{0} ** max_path_length,
    path_len: usize = 0,

    pub fn getPath(self: *const Project) []const u8 {
        return self.path[0..self.path_len];
    }

    pub fn getName(self: *const Project) []const u8 {
        const path = self.getPath();
        const trimmed = std.mem.trimEnd(u8, path, "/\\");

        if (trimmed.len == 0) return path;

        if (std.fs.path.basename(trimmed).len > 0) {
            return std.fs.path.basename(trimmed);
        }

        // Handles a filesystem root such as C:\ on Windows.
        return trimmed;
    }
};

pub const Registry = struct {
    projects: [max_projects]Project =
        [_]Project{.{}} ** max_projects,
    count: usize = 0,

    pub fn get(
        self: *const Registry,
        index: usize,
    ) ?*const Project {
        if (index >= self.count) return null;
        return &self.projects[index];
    }

    pub fn find(self: *const Registry, path: []const u8) ?usize {
        for (self.projects[0..self.count], 0..) |*project, i| {
            if (std.mem.eql(u8, project.getPath(), path)) {
                return i;
            }
        }

        return null;
    }

    pub fn addInMemory(
        self: *Registry,
        path: []const u8,
    ) !bool {
        if (path.len == 0 or path.len > max_path_length) {
            return error.InvalidProjectPath;
        }

        if (std.mem.indexOfAny(u8, path, "\r\n") != null) {
            return error.InvalidProjectPath;
        }

        var project = Project{};
        @memcpy(project.path[0..path.len], path);
        project.path_len = path.len;

        if (self.find(path)) |existing| {
            var i = existing;
            while (i > 0) : (i -= 1) {
                self.projects[i] = self.projects[i - 1];
            }
            self.projects[0] = project;
            return false;
        }
        if (self.count >= max_projects) return error.RegistryFull;

        var i = self.count;
        while (i > 0) : (i -= 1) {
            self.projects[i] = self.projects[i - 1];
        }
        self.projects[0] = project;
        self.count += 1;
        return true;
    }

    pub fn remove(self: *Registry, index: usize) void {
        if (index >= self.count) return;

        var i = index;
        while (i + 1 < self.count) : (i += 1) {
            self.projects[i] = self.projects[i + 1];
        }

        self.count -= 1;
        self.projects[self.count] = .{};
    }

    /// Persists paths only. It does not copy, move, or edit projects.
    pub fn save(
        self: *const Registry,
        io: std.Io,
        allocator: std.mem.Allocator,
        environ: *const std.process.Environ.Map,
    ) !void {
        const location = ConfigLocation.init(allocator);
        const dir_path = try location.directory(environ);
        defer allocator.free(dir_path);

        var dir = try std.Io.Dir.cwd().createDirPathOpen(
            io,
            dir_path,
            .{},
        );
        dir.close(io);

        const file_path = try location.registryFile(environ);
        defer allocator.free(file_path);

        const file = try std.Io.Dir.cwd().createFile(
            io,
            file_path,
            .{},
        );
        defer file.close(io);

        for (self.projects[0..self.count]) |*project| {
            try file.writeStreamingAll(io, project.getPath());
            try file.writeStreamingAll(io, "\n");
        }
    }

    pub fn load(
        self: *Registry,
        io: std.Io,
        allocator: std.mem.Allocator,
        environ: *const std.process.Environ.Map,
    ) !void {
        self.count = 0;

        const location = ConfigLocation.init(allocator);
        const file_path = try location.registryFile(environ);
        defer allocator.free(file_path);

        const contents = std.Io.Dir.cwd().readFileAlloc(
            io,
            file_path,
            allocator,
            .limited(max_registry_bytes),
        ) catch |err| switch (err) {
            error.FileNotFound => return,
            else => return err,
        };
        defer allocator.free(contents);

        var lines = std.mem.tokenizeScalar(u8, contents, '\n');

        while (lines.next()) |line| {
            const path = std.mem.trim(u8, line, "\r \t");
            if (path.len == 0) continue;

            _ = try self.addInMemory(path);
        }
    }
};

test "recent projects stay newest first" {
    var registry = Registry{};

    try std.testing.expect(try registry.addInMemory("/games/first"));
    try std.testing.expect(try registry.addInMemory("/games/second"));
    try std.testing.expectEqualStrings(
        "/games/second",
        registry.get(0).?.getPath(),
    );

    try std.testing.expect(!try registry.addInMemory("/games/first"));
    try std.testing.expectEqualStrings(
        "/games/first",
        registry.get(0).?.getPath(),
    );
    try std.testing.expectEqualStrings(
        "/games/second",
        registry.get(1).?.getPath(),
    );
}
