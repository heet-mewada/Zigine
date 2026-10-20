const std = @import("std");
const ui = @import("ui-components");
const project_creation = @import("project_creation");
const project_registry = @import("project-registry");
const app_settings = @import("app-settings");

const Color = ui.Color;
const Sizing = ui.Sizing;
const Padding = ui.Padding;
const Context = ui.Context;
const DrawCommand = ui.DrawCommand;

pub const Theme = enum {
    dark,
    light,
    catppuccin_mocha,
    dracula,
};

pub const Palette = struct {
    background: Color,
    panel: Color,
    card: Color,
    accent: Color,
    text: Color,
    muted: Color,
    border: Color,
    selection: Color,
};

pub const ProjectDialog = struct {
    is_open: bool = false,
    name: [128]u8 = [_]u8{0} ** 128,
    name_len: usize = 0,
    parent_directory: [512]u8 = [_]u8{0} ** 512,
    directory_len: usize = 0,
    selected_template: project_creation.Template = .empty,
    active_field: Field = .name,
    error_message: ?[]const u8 = null,

    pub const Field = enum {
        name,
        parent_directory,
    };

    pub fn open(self: *ProjectDialog) void {
        self.is_open = true;
        self.error_message = null;
        self.setName("MyFirstGame");
        self.setDirectory("~/Documents/Games");
        self.selected_template = .empty;
        self.active_field = .name;
    }

    pub fn close(self: *ProjectDialog) void {
        self.is_open = false;
        self.error_message = null;
    }

    pub fn setName(self: *ProjectDialog, value: []const u8) void {
        const len = @min(value.len, self.name.len);
        @memcpy(self.name[0..len], value[0..len]);
        @memset(self.name[len..], 0);
        self.name_len = len;
    }

    pub fn setDirectory(self: *ProjectDialog, value: []const u8) void {
        const len = @min(value.len, self.parent_directory.len);
        @memcpy(self.parent_directory[0..len], value[0..len]);
        @memset(self.parent_directory[len..], 0);
        self.directory_len = len;
    }

    pub fn appendText(self: *ProjectDialog, value: []const u8) void {
        switch (self.active_field) {
            .name => {
                const remaining = self.name.len - self.name_len;
                var count = @min(remaining, value.len);
                if (count < value.len) {
                    while (count > 0 and (value[count] & 0xC0) == 0x80) {
                        count -= 1;
                    }
                }
                if (count == 0) return;
                @memcpy(self.name[self.name_len..][0..count], value[0..count]);
                self.name_len += count;
            },
            .parent_directory => {
                const remaining =
                    self.parent_directory.len - self.directory_len;
                var count = @min(remaining, value.len);
                if (count < value.len) {
                    while (count > 0 and (value[count] & 0xC0) == 0x80) {
                        count -= 1;
                    }
                }
                if (count == 0) return;
                @memcpy(
                    self.parent_directory[self.directory_len..][0..count],
                    value[0..count],
                );
                self.directory_len += count;
            },
        }
    }

    pub fn backspace(self: *ProjectDialog) void {
        switch (self.active_field) {
            .name => {
                if (self.name_len == 0) return;
                var new_len = self.name_len - 1;
                while (new_len > 0 and (self.name[new_len] & 0xC0) == 0x80) {
                    new_len -= 1;
                }
                self.name_len = new_len;
                self.name[new_len] = 0;
            },
            .parent_directory => {
                if (self.directory_len == 0) return;
                var new_len = self.directory_len - 1;
                while (new_len > 0 and
                    (self.parent_directory[new_len] & 0xC0) == 0x80)
                {
                    new_len -= 1;
                }
                self.directory_len = new_len;
                self.parent_directory[new_len] = 0;
            },
        }
    }

    pub fn getName(self: *const ProjectDialog) []const u8 {
        return self.name[0..self.name_len];
    }

    pub fn getDirectory(self: *const ProjectDialog) []const u8 {
        return self.parent_directory[0..self.directory_len];
    }
};

fn rgb(r: u8, g: u8, b: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}

pub fn paletteFor(theme: Theme) Palette {
    return switch (theme) {
        .dark => .{
            .background = rgb(30, 33, 43),
            .panel = rgb(39, 43, 55),
            .card = rgb(48, 54, 68),
            .accent = rgb(65, 139, 191),
            .text = rgb(238, 241, 248),
            .muted = rgb(160, 170, 187),
            .border = rgb(64, 69, 83),
            .selection = rgb(54, 76, 101),
        },
        .light => .{
            .background = rgb(242, 243, 247),
            .panel = rgb(255, 255, 255),
            .card = rgb(232, 235, 242),
            .accent = rgb(40, 112, 180),
            .text = rgb(38, 42, 52),
            .muted = rgb(104, 112, 128),
            .border = rgb(210, 215, 225),
            .selection = rgb(211, 229, 248),
        },
        .catppuccin_mocha => .{
            .background = rgb(30, 30, 46),
            .panel = rgb(24, 24, 37),
            .card = rgb(49, 50, 68),
            .accent = rgb(203, 166, 247),
            .text = rgb(205, 214, 244),
            .muted = rgb(166, 173, 200),
            .border = rgb(69, 71, 90),
            .selection = rgb(69, 71, 90),
        },
        .dracula => .{
            .background = rgb(40, 42, 54),
            .panel = rgb(40, 42, 54),
            .card = rgb(68, 71, 90),
            .accent = rgb(189, 147, 249),
            .text = rgb(248, 248, 242),
            .muted = rgb(189, 147, 249),
            .border = rgb(98, 114, 164),
            .selection = rgb(68, 71, 90),
        },
    };
}

pub const ProjectManager = struct {
    context: Context,
    theme: Theme = .catppuccin_mocha,
    dialog: ProjectDialog = .{},
    recent_scroll: usize = 0,
    recent_visible_rows: usize = 1,

    pub fn init() ProjectManager {
        return .{ .context = Context.init() };
    }

    pub fn setTheme(self: *ProjectManager, theme: Theme) void {
        self.theme = theme;
    }

    pub fn getPalette(self: *const ProjectManager) Palette {
        return paletteFor(self.theme);
    }

    pub fn build(
        self: *ProjectManager,
        width: f32,
        height: f32,
        registry: *const project_registry.Registry,
    ) ![]const DrawCommand {
        const c = &self.context;
        const p = paletteFor(self.theme);
        const compact = height < 800 or width < 850;
        const page_padding: f32 = if (compact) 16 else 24;
        const section_gap: f32 = if (compact) 10 else 14;
        const header_height: f32 = if (compact) 42 else 48;
        const row_height: f32 = if (compact) 58 else 68;
        const settings_height: f32 = if (compact) 48 else 56;
        self.recent_visible_rows = @max(
            @as(usize, 1),
            @as(usize, @intFromFloat(@max(1, height - 330) / row_height)),
        );
        const max_recent_scroll = registry.count -| self.recent_visible_rows;
        self.recent_scroll = @min(self.recent_scroll, max_recent_scroll);
        const available_width = @max(0, width - page_padding * 2);
        const action_gap: f32 = 10;
        const action_width = @max(
            120,
            @min(200, (available_width - action_gap * 2) / 3),
        );

        c.beginFrame(.{ .width = width, .height = height });

        try c.begin(1, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
        }, p.background);

        try c.begin(2, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(header_height),
            .direction = .left_to_right,
            .padding = Padding.xy(16, 0),
            .gap = 12,
            .align_y = .center,
        }, p.panel);

        try addText(c, 3, "ZIGINE", 90, 20, Sizing.fixed(90), p.accent);
        try addText(c, 4, "2D GAME ENGINE", 220, 20, Sizing.grow(), p.text);
        c.end();

        try c.begin(10, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .padding = Padding.all(page_padding),
            .gap = section_gap,
        }, p.background);

        try addText(
            c,
            11,
            "WELCOME TO ZIGINE",
            360,
            26,
            Sizing.grow(),
            p.text,
        );

        // Project actions: the standalone Scene Editor button is removed.
        try c.begin(20, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(if (compact) 38 else 42),
            .direction = .left_to_right,
            .gap = action_gap,
        }, p.background);

        try actionButton(c, 21, "NEW PROJECT", action_width, p.card, p, false);
        try actionButton(c, 22, "IMPORT PROJECT", action_width, p.card, p, false);
        try actionButton(c, 23, "OPEN PROJECT", action_width, p.card, p, false);
        c.end();

        if (self.dialog.is_open) {
            try c.begin(200, .{
                .width = Sizing.grow(),
                .height = Sizing.fixed(300),
                .direction = .top_to_bottom,
                .padding = Padding.all(16),
                .gap = 10,
            }, p.panel);

            try addText(c, 201, "CREATE NEW PROJECT", 320, 24, Sizing.grow(), p.text);
            try addText(c, 202, "PROJECT NAME", 160, 16, Sizing.grow(), p.muted);

            try c.begin(203, .{
                .width = Sizing.grow(),
                .height = Sizing.fixed(36),
                .direction = .left_to_right,
                .padding = Padding.xy(10, 0),
                .align_y = .center,
            }, p.card);
            try addText(
                c,
                204,
                self.dialog.getName(),
                480,
                18,
                Sizing.grow(),
                p.text,
            );
            c.end();

            try addText(
                c,
                205,
                "DESTINATION DIRECTORY",
                240,
                16,
                Sizing.grow(),
                p.muted,
            );

            try c.begin(206, .{
                .width = Sizing.grow(),
                .height = Sizing.fixed(36),
                .direction = .left_to_right,
                .padding = Padding.xy(10, 0),
                .align_y = .center,
            }, p.card);
            try addText(
                c,
                207,
                self.dialog.getDirectory(),
                600,
                18,
                Sizing.grow(),
                p.text,
            );
            c.end();

            try addText(c, 208, "PROJECT TYPE", 160, 16, Sizing.grow(), p.muted);

            try c.begin(209, .{
                .width = Sizing.grow(),
                .height = Sizing.fixed(36),
                .direction = .left_to_right,
                .gap = 8,
            }, p.panel);

            try actionButton(
                c,
                210,
                "EMPTY ZIG",
                140,
                if (self.dialog.selected_template == .empty) p.accent else p.card,
                p,
                self.dialog.selected_template == .empty,
            );
            try actionButton(
                c,
                220,
                "SDL3",
                100,
                if (self.dialog.selected_template == .sdl3) p.accent else p.card,
                p,
                self.dialog.selected_template == .sdl3,
            );
            try actionButton(
                c,
                230,
                "RAYLIB",
                110,
                if (self.dialog.selected_template == .raylib) p.accent else p.card,
                p,
                self.dialog.selected_template == .raylib,
            );
            c.end();

            if (self.dialog.error_message) |message| {
                try addText(c, 240, message, 600, 18, Sizing.grow(), rgb(243, 139, 168));
            }

            try c.begin(250, .{
                .width = Sizing.grow(),
                .height = Sizing.fixed(38),
                .direction = .left_to_right,
                .gap = 10,
            }, p.panel);
            try actionButton(c, 251, "CANCEL", 120, p.card, p, false);
            try actionButton(c, 261, "CREATE PROJECT", 180, p.accent, p, true);
            c.end();
            c.end();
        }

        try addText(c, 30, "RECENT PROJECTS", 240, 20, Sizing.grow(), p.text);

        try c.begin(35, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .gap = 8,
        }, p.background);

        if (registry.count == 0) {
            try addText(
                c,
                31,
                "No recent projects yet. Create, import, or open a project.",
                560,
                18,
                Sizing.grow(),
                p.muted,
            );
        } else {
            const end = @min(registry.count, self.recent_scroll + self.recent_visible_rows + 1);
            for (self.recent_scroll..end) |i| {
                const project = registry.get(i) orelse continue;
                try projectRow(
                    c,
                    1000 + @as(u64, @intCast((i - self.recent_scroll) * 10)),
                    project.getName(),
                    project.getPath(),
                    "PROJECT",
                    row_height,
                    p,
                );
            }
        }
        c.end();

        try c.begin(70, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(settings_height),
            .direction = .left_to_right,
            .padding = Padding.xy(12, 6),
            .gap = 12,
            .align_y = .center,
        }, p.panel);
        try c.rect(71, .{
            .width = Sizing.fixed(3),
            .height = Sizing.grow(),
        }, p.accent);
        try addText(c, 72, "SETTINGS", 120, 18, Sizing.fixed(120), p.accent);
        try addText(
            c,
            73,
            "APPLICATION PREFERENCES AND THEME",
            360,
            18,
            Sizing.grow(),
            p.muted,
        );
        c.end();

        c.end();
        c.end();
        return c.endFrame();
    }

    pub fn scrollRecent(self: *ProjectManager, delta: isize, total: usize) void {
        const max_scroll = total -| self.recent_visible_rows;
        if (delta < 0) {
            self.recent_scroll -|= @intCast(@abs(delta));
        } else {
            self.recent_scroll = @min(
                max_scroll,
                self.recent_scroll + @as(usize, @intCast(delta)),
            );
        }
    }

    pub fn buildSettings(
        self: *ProjectManager,
        width: f32,
        height: f32,
        settings: *const app_settings.Settings,
    ) ![]const DrawCommand {
        const c = &self.context;
        const p = paletteFor(self.theme);

        c.beginFrame(.{ .width = width, .height = height });

        try c.begin(800, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
        }, p.background);

        try c.begin(801, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(54),
            .direction = .left_to_right,
            .padding = Padding.xy(16, 0),
            .gap = 12,
            .align_y = .center,
        }, p.panel);
        try actionButton(c, 810, "< BACK", 120, p.card, p, false);
        try addText(c, 811, "SETTINGS", 240, 22, Sizing.grow(), p.text);
        c.end();

        try c.begin(820, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .padding = Padding.all(24),
            .gap = 12,
        }, p.background);

        try addText(c, 821, "APPEARANCE", 240, 22, Sizing.grow(), p.accent);
        try addText(
            c,
            822,
            "Choose the theme used throughout Zigine.",
            520,
            18,
            Sizing.grow(),
            p.muted,
        );

        try c.begin(823, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(44),
            .direction = .left_to_right,
            .gap = 10,
        }, p.background);

        const theme_buttons = [_]struct {
            id: u64,
            label: []const u8,
            theme: Theme,
        }{
            .{ .id = 830, .label = "DARK", .theme = .dark },
            .{ .id = 831, .label = "LIGHT", .theme = .light },
            .{ .id = 832, .label = "CATPPUCCIN", .theme = .catppuccin_mocha },
            .{ .id = 833, .label = "DRACULA", .theme = .dracula },
        };

        for (theme_buttons) |item| {
            try actionButton(
                c,
                item.id,
                item.label,
                if (width < 900) 145 else 190,
                if (self.theme == item.theme) p.accent else p.card,
                p,
                self.theme == item.theme,
            );
        }
        c.end();

        try addText(
            c,
            850,
            "DEFAULT PROJECT DIRECTORY",
            360,
            20,
            Sizing.grow(),
            p.text,
        );
        try addText(
            c,
            851,
            settings.getDefaultProjectDirectory(),
            640,
            18,
            Sizing.grow(),
            p.muted,
        );
        try c.begin(852, .{
            .width = Sizing.fixed(190),
            .height = Sizing.fixed(34),
            .direction = .left_to_right,
            .padding = Padding.xy(12, 0),
            .align_y = .center,
        }, p.card);

        try addText(
            c,
            952,
            "CHANGE DIRECTORY",
            166,
            16,
            Sizing.grow(),
            p.text,
        );
        c.end();
        try addText(
            c,
            853,
            "Preferences are stored in settings.toml.",
            420,
            18,
            Sizing.grow(),
            p.muted,
        );

        c.end();
        c.end();
        return c.endFrame();
    }
};

fn addText(
    c: *Context,
    id: u64,
    value: []const u8,
    measured_width: f32,
    measured_height: f32,
    width: Sizing,
    color: Color,
) !void {
    try c.text(
        id,
        value,
        .{ .width = measured_width, .height = measured_height },
        .{ .width = width, .height = Sizing.fixed(measured_height) },
        color,
    );
}

fn actionButton(
    c: *Context,
    id: u64,
    label: []const u8,
    width: f32,
    background: Color,
    p: Palette,
    highlighted: bool,
) !void {
    try c.begin(id, .{
        .width = Sizing.fixed(width),
        .height = Sizing.grow(),
        .direction = .left_to_right,
        .padding = Padding.xy(12, 0),
        .align_y = .center,
    }, background);

    try addText(
        c,
        id + 100,
        label,
        width - 24,
        16,
        Sizing.grow(),
        if (highlighted) p.background else p.text,
    );
    c.end();
}

fn projectRow(
    c: *Context,
    id: u64,
    name: []const u8,
    path: []const u8,
    kind: []const u8,
    row_height: f32,
    p: Palette,
) !void {
    try c.begin(id, .{
        .width = Sizing.grow(),
        .height = Sizing.fixed(row_height),
        .direction = .left_to_right,
        .padding = Padding.xy(12, 6),
        .gap = 14,
        .align_y = .center,
    }, p.card);

    try addText(c, id + 1, kind, 90, 16, Sizing.fixed(90), p.accent);

    try c.begin(id + 2, .{
        .width = Sizing.grow(),
        .height = Sizing.grow(),
        .direction = .top_to_bottom,
        .gap = 3,
    }, p.card);

    try addText(c, id + 3, name, 240, 18, Sizing.grow(), p.text);
    try addText(c, id + 4, path, 400, 16, Sizing.grow(), p.muted);
    c.end();

    try addText(c, id + 5, ">", 16, 18, Sizing.fixed(16), p.muted);
    c.end();
}

test "all themes provide opaque colors" {
    for ([_]Theme{ .dark, .light, .catppuccin_mocha, .dracula }) |theme| {
        const palette = paletteFor(theme);
        try std.testing.expectEqual(@as(u8, 255), palette.background.a);
        try std.testing.expectEqual(@as(u8, 255), palette.text.a);
    }
}
