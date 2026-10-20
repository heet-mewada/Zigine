const std = @import("std");
const project_registry = @import("project-registry");

pub const max_directory_length = 1024;
const max_settings_bytes = 16 * 1024;

pub const Theme = enum {
    dark,
    light,
    catppuccin_mocha,
    dracula,
};

pub const Settings = struct {
    theme: Theme = .catppuccin_mocha,
    ui_scale: f32 = 1.0,
    default_project_directory: [max_directory_length]u8 = initialDirectory(),
    default_project_directory_len: usize = default_directory.len,

    const default_directory = "~/Documents/Games";

    fn initialDirectory() [max_directory_length]u8 {
        var buffer: [max_directory_length]u8 =
            [_]u8{0} ** max_directory_length;

        @memcpy(
            buffer[0..default_directory.len],
            default_directory,
        );

        return buffer;
    }

    pub fn getDefaultProjectDirectory(
        self: *const Settings,
    ) []const u8 {
        return self.default_project_directory[0..self.default_project_directory_len];
    }

    pub fn setDefaultProjectDirectory(
        self: *Settings,
        path: []const u8,
    ) !void {
        if (path.len == 0 or path.len > max_directory_length) {
            return error.InvalidSetting;
        }

        if (std.mem.indexOfAny(u8, path, "\r\n") != null) {
            return error.InvalidSetting;
        }

        @memcpy(self.default_project_directory[0..path.len], path);
        @memset(self.default_project_directory[path.len..], 0);

        self.default_project_directory_len = path.len;
    }

    pub fn load(
        io: std.Io,
        allocator: std.mem.Allocator,
        environ: *const std.process.Environ.Map,
    ) !Settings {
        var settings = Settings{};

        const location = project_registry.ConfigLocation.init(allocator);
        const directory = try location.directory(environ);
        defer allocator.free(directory);

        const path = try std.fs.path.join(
            allocator,
            &.{ directory, "settings.toml" },
        );
        defer allocator.free(path);

        const contents = std.Io.Dir.cwd().readFileAlloc(
            io,
            path,
            allocator,
            .limited(max_settings_bytes),
        ) catch |err| switch (err) {
            error.FileNotFound => return settings,
            else => return err,
        };
        defer allocator.free(contents);

        var lines = std.mem.tokenizeScalar(u8, contents, '\n');

        while (lines.next()) |raw_line| {
            const line = std.mem.trim(u8, raw_line, " \t\r");

            if (line.len == 0 or line[0] == '#') {
                continue;
            }

            const equals = std.mem.indexOfScalar(u8, line, '=') orelse continue;

            const key = std.mem.trim(u8, line[0..equals], " \t");
            const value = std.mem.trim(u8, line[equals + 1 ..], " \t");

            if (std.mem.eql(u8, key, "theme")) {
                if (parseString(value)) |theme_text| {
                    if (parseTheme(theme_text)) |theme| {
                        settings.theme = theme;
                    }
                }
            } else if (std.mem.eql(u8, key, "ui_scale")) {
                const scale = std.fmt.parseFloat(f32, value) catch continue;

                if (std.math.isFinite(scale) and scale >= 0.75 and scale <= 1.5) {
                    settings.ui_scale = scale;
                }
            } else if (std.mem.eql(u8, key, "default_project_directory")) {
                if (parseString(value)) |directory_text| {
                    settings.setDefaultProjectDirectory(directory_text) catch {};
                }
            }
        }

        return settings;
    }

    pub fn save(
        self: *const Settings,
        io: std.Io,
        allocator: std.mem.Allocator,
        environ: *const std.process.Environ.Map,
    ) !void {
        const location = project_registry.ConfigLocation.init(allocator);
        const directory = try location.directory(environ);
        defer allocator.free(directory);

        var dir = try std.Io.Dir.cwd().createDirPathOpen(
            io,
            directory,
            .{},
        );
        dir.close(io);

        const path = try std.fs.path.join(
            allocator,
            &.{ directory, "settings.toml" },
        );
        defer allocator.free(path);

        const file = try std.Io.Dir.cwd().createFile(io, path, .{});
        defer file.close(io);

        try file.writeStreamingAll(io, "theme = \"");
        try file.writeStreamingAll(io, themeName(self.theme));
        try file.writeStreamingAll(io, "\"\n");

        const scale_text = try std.fmt.allocPrint(
            allocator,
            "ui_scale = {d:.2}\n",
            .{self.ui_scale},
        );
        defer allocator.free(scale_text);

        try file.writeStreamingAll(io, scale_text);
        try file.writeStreamingAll(io, "default_project_directory = \"");
        try writeTomlString(
            file,
            io,
            self.getDefaultProjectDirectory(),
        );
        try file.writeStreamingAll(io, "\"\n");
    }

    fn writeTomlString(
        file: std.Io.File,
        io: std.Io,
        value: []const u8,
    ) !void {
        for (value) |byte| {
            switch (byte) {
                '\\' => try file.writeStreamingAll(io, "\\\\"),
                '"' => try file.writeStreamingAll(io, "\\\""),
                '\n', '\r' => return error.InvalidSetting,
                else => try file.writeStreamingAll(io, &.{byte}),
            }
        }
    }

    fn parseString(value: []const u8) ?[]const u8 {
        if (value.len < 2 or value[0] != '"' or value[value.len - 1] != '"') {
            return null;
        }

        const inner = value[1 .. value.len - 1];

        if (std.mem.indexOfAny(u8, inner, "\r\n") != null) {
            return null;
        }

        return inner;
    }

    fn parseTheme(value: []const u8) ?Theme {
        if (std.mem.eql(u8, value, "dark")) return .dark;
        if (std.mem.eql(u8, value, "light")) return .light;
        if (std.mem.eql(u8, value, "catppuccin_mocha")) return .catppuccin_mocha;
        if (std.mem.eql(u8, value, "dracula")) return .dracula;

        return null;
    }

    fn themeName(theme: Theme) []const u8 {
        return switch (theme) {
            .dark => "dark",
            .light => "light",
            .catppuccin_mocha => "catppuccin_mocha",
            .dracula => "dracula",
        };
    }
};

test "settings accept supported scale range" {
    var settings = Settings{};
    settings.ui_scale = 1.25;

    try std.testing.expectEqual(@as(f32, 1.25), settings.ui_scale);
}

test "settings reject invalid default directory" {
    var settings = Settings{};

    try std.testing.expectError(
        error.InvalidSetting,
        settings.setDefaultProjectDirectory(""),
    );
}

test "settings initialize the default project directory" {
    const settings = Settings{};

    try std.testing.expectEqualStrings(
        "~/Documents/Games",
        settings.getDefaultProjectDirectory(),
    );
}

