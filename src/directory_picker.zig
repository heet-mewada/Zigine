const std = @import("std");
const ui = @import("ui-components");

const Context = ui.Context;
const Color = ui.Color;
const Sizing = ui.Sizing;
const Padding = ui.Padding;
const DrawCommand = ui.DrawCommand;

const max_path_length = 512;
const max_entry_name_length = 255;
const max_entries = 64;
const visible_entries = 10;

pub const Action = enum {
    ignored,
    handled,
    cancelled,
    selected,
};

pub const Picker = struct {
    is_open: bool = false,

    path: [max_path_length]u8 = [_]u8{0} ** max_path_length,
    path_len: usize = 0,

    entries: [max_entries][max_entry_name_length]u8 =
        [_][max_entry_name_length]u8{[_]u8{0} ** max_entry_name_length} **
        max_entries,
    entry_lengths: [max_entries]usize = [_]usize{0} ** max_entries,
    entry_count: usize = 0,
    scroll_offset: usize = 0,

    error_message: ?[]const u8 = null,

    pub fn getPath(self: *const Picker) []const u8 {
        return self.path[0..self.path_len];
    }

    pub fn close(self: *Picker) void {
        self.is_open = false;
        self.error_message = null;
    }

    /// Opens the picker at the requested directory when possible.
    /// If the requested directory is unavailable, falls back to HOME.
    pub fn open(
        self: *Picker,
        io: std.Io,
        home: []const u8,
        requested_path: []const u8,
    ) void {
        self.is_open = true;
        self.error_message = null;

        if (requested_path.len > 0) {
            const expanded = expandHome(
                std.heap.page_allocator,
                home,
                requested_path,
            ) catch null;

            if (expanded) |candidate| {
                defer std.heap.page_allocator.free(candidate);

                if (self.setPath(io, candidate)) {
                    return;
                }
            }
        }

        if (!self.setPath(io, home)) {
            self.error_message = "Could not open the home directory.";
        }
    }

    /// Loads the directory and keeps only directories, sorted by name.
    pub fn setPath(
        self: *Picker,
        io: std.Io,
        path: []const u8,
    ) bool {
        if (path.len == 0 or path.len > self.path.len) {
            self.error_message = "Directory path is too long.";
            return false;
        }

        var dir = std.Io.Dir.cwd().openDir(
            io,
            path,
            .{ .iterate = true },
        ) catch |err| {
            self.error_message = switch (err) {
                error.AccessDenied => "Permission denied.",
                error.FileNotFound => "Directory does not exist.",
                error.NotDir => "Path is not a directory.",
                else => "Could not open this directory.",
            };
            return false;
        };
        defer dir.close(io);

        // The source may point into self.path (for example, parentPath()).
        // @memmove safely handles overlapping source and destination slices.
        @memmove(self.path[0..path.len], path);
        self.path_len = path.len;
        @memset(self.path[self.path_len..], 0);

        self.entry_count = 0;
        self.scroll_offset = 0;
        self.error_message = null;

        var iterator = dir.iterate();

        while (true) {
            const maybe_entry = iterator.next(io) catch {
                self.error_message = "Could not read this directory.";
                break;
            };

            const entry = maybe_entry orelse break;

            if (entry.kind != .directory) continue;
            if (std.mem.eql(u8, entry.name, ".") or
                std.mem.eql(u8, entry.name, ".."))
            {
                continue;
            }

            if (entry.name.len == 0 or
                entry.name.len > max_entry_name_length)
            {
                continue;
            }

            if (self.entry_count >= max_entries) continue;

            const index = self.entry_count;
            @memcpy(
                self.entries[index][0..entry.name.len],
                entry.name,
            );
            self.entry_lengths[index] = entry.name.len;
            self.entry_count += 1;
        }

        self.sortEntries();
        return true;
    }

    fn sortEntries(self: *Picker) void {
        var i: usize = 1;

        while (i < self.entry_count) : (i += 1) {
            var j = i;

            while (j > 0 and self.nameLessThan(j, j - 1)) : (j -= 1) {
                const temporary_name = self.entries[j];
                self.entries[j] = self.entries[j - 1];
                self.entries[j - 1] = temporary_name;

                const temporary_len = self.entry_lengths[j];
                self.entry_lengths[j] = self.entry_lengths[j - 1];
                self.entry_lengths[j - 1] = temporary_len;
            }
        }
    }

    fn nameLessThan(
        self: *const Picker,
        a: usize,
        b: usize,
    ) bool {
        const lhs = self.entries[a][0..self.entry_lengths[a]];
        const rhs = self.entries[b][0..self.entry_lengths[b]];

        const common_len = @min(lhs.len, rhs.len);

        for (lhs[0..common_len], rhs[0..common_len]) |lc, rc| {
            const lower_l = std.ascii.toLower(lc);
            const lower_r = std.ascii.toLower(rc);

            if (lower_l < lower_r) return true;
            if (lower_l > lower_r) return false;
        }

        return lhs.len < rhs.len;
    }

    fn childPath(
        allocator: std.mem.Allocator,
        parent: []const u8,
        child: []const u8,
    ) ![]u8 {
        if (std.mem.eql(u8, parent, "/")) {
            return std.fmt.allocPrint(allocator, "/{s}", .{child});
        }

        return std.fmt.allocPrint(
            allocator,
            "{s}/{s}",
            .{ parent, child },
        );
    }

    fn parentPath(path: []const u8) []const u8 {
        if (path.len <= 1) return "/";

        var end = path.len;
        while (end > 1 and path[end - 1] == '/') {
            end -= 1;
        }

        var slash = end;
        while (slash > 0 and path[slash - 1] != '/') {
            slash -= 1;
        }

        if (slash <= 1) return "/";
        return path[0 .. slash - 1];
    }

    fn expandHome(
        allocator: std.mem.Allocator,
        home: []const u8,
        input: []const u8,
    ) !?[]u8 {
        if (std.mem.eql(u8, input, "~")) {
            return try allocator.dupe(u8, home);
        }

        if (std.mem.startsWith(u8, input, "~/")) {
            return try std.fmt.allocPrint(
                allocator,
                "{s}{s}",
                .{ home, input[1..] },
            );
        }

        return try allocator.dupe(u8, input);
    }

    pub fn handleClick(
        self: *Picker,
        io: std.Io,
        context: *const Context,
        position: ui.Vec2,
        home: []const u8,
    ) Action {
        if (!self.is_open) return .ignored;

        const id = context.hitTest(position) orelse return .ignored;

        // The text inside each button has its own ID. Handle both the
        // button container and its label so either can be clicked.
        switch (id) {
            8001, 9001 => {
                const parent = parentPath(self.getPath());
                _ = self.setPath(io, parent);
                return .handled;
            },
            8002, 9002 => {
                _ = self.setPath(io, home);
                return .handled;
            },
            8301, 9301 => {
                self.close();
                return .cancelled;
            },
            8302, 9302 => return .selected,
            else => {},
        }

        // A folder can be clicked on its row, arrow, or text label.
        const is_row_id =
            (id >= 8100 and id < 8100 + visible_entries) or
            (id >= 8150 and id < 8150 + visible_entries) or
            (id >= 8160 and id < 8160 + visible_entries);

        if (is_row_id) {
            const visible_index: usize =
                if (id >= 8160 and id < 8160 + visible_entries)
                    @intCast(id - 8160)
                else if (id >= 8150 and id < 8150 + visible_entries)
                    @intCast(id - 8150)
                else
                    @intCast(id - 8100);

            const entry_index = self.scroll_offset + visible_index;

            if (entry_index >= self.entry_count) return .handled;

            const name = self.entries[entry_index][0..self.entry_lengths[entry_index]];

            const allocator = std.heap.page_allocator;
            const next_path = childPath(
                allocator,
                self.getPath(),
                name,
            ) catch {
                self.error_message = "Could not construct the directory path.";
                return .handled;
            };
            defer allocator.free(next_path);

            _ = self.setPath(io, next_path);
            return .handled;
        }

        return .ignored;
    }

    pub fn scroll(self: *Picker, delta: isize) void {
        const max_offset = self.entry_count -| visible_entries;
        if (delta < 0) {
            self.scroll_offset -|= @intCast(@abs(delta));
        } else {
            self.scroll_offset = @min(
                max_offset,
                self.scroll_offset + @as(usize, @intCast(delta)),
            );
        }
    }

    pub fn build(
        self: *Picker,
        context: *Context,
        width: f32,
        height: f32,
        palette: anytype,
    ) ![]const DrawCommand {
        context.beginFrame(.{ .width = width, .height = height });

        try context.begin(8000, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .padding = Padding.all(24),
            .gap = 12,
        }, palette.background);

        // Header
        try context.begin(8003, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(44),
            .direction = .left_to_right,
            .padding = Padding.xy(12, 0),
            .align_y = .center,
        }, palette.panel);

        try addText(
            context,
            8004,
            "CHOOSE DESTINATION FOLDER",
            440,
            20,
            Sizing.grow(),
            palette.text,
        );

        context.end();

        // Current path
        try context.begin(8005, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(48),
            .direction = .left_to_right,
            .padding = Padding.xy(12, 0),
            .align_y = .center,
        }, palette.card);

        try addText(
            context,
            8006,
            self.getPath(),
            900,
            18,
            Sizing.grow(),
            palette.text,
        );

        context.end();

        // Navigation controls
        try context.begin(8007, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(40),
            .direction = .left_to_right,
            .gap = 8,
        }, palette.background);

        try actionButton(
            context,
            8001,
            "PARENT",
            120,
            palette.card,
            palette,
        );

        try actionButton(
            context,
            8002,
            "HOME",
            100,
            palette.card,
            palette,
        );

        try addText(
            context,
            8008,
            "DIRECTORIES",
            160,
            18,
            Sizing.grow(),
            palette.muted,
        );

        context.end();

        // Folder list and scrollbar
        try context.begin(8009, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .left_to_right,
            .gap = 8,
        }, palette.background);

        try context.begin(8010, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .gap = 4,
        }, palette.background);

        var visible_index: usize = 0;
        while (visible_index < visible_entries) : (visible_index += 1) {
            const entry_index = self.scroll_offset + visible_index;
            if (entry_index >= self.entry_count) break;

            try context.begin(8100 + visible_index, .{
                .width = Sizing.grow(),
                .height = Sizing.fixed(36),
                .direction = .left_to_right,
                .padding = Padding.xy(12, 0),
                .gap = 10,
                .align_y = .center,
            }, palette.card);

            try addText(
                context,
                8150 + visible_index,
                ">",
                16,
                18,
                Sizing.fixed(16),
                palette.accent,
            );

            try addText(
                context,
                8160 + visible_index,
                self.entries[entry_index][0..self.entry_lengths[entry_index]],
                600,
                18,
                Sizing.grow(),
                palette.text,
            );

            context.end();
        }

        if (self.entry_count == 0 and self.error_message == null) {
            try addText(
                context,
                8175,
                "This directory contains no subdirectories.",
                420,
                18,
                Sizing.grow(),
                palette.muted,
            );
        }

        context.end();

        const estimated_track_height: f32 = @max(1, height - 290);
        const scroll_max = self.entry_count -| visible_entries;
        const thumb_height = if (self.entry_count > visible_entries)
            @max(
                24,
                estimated_track_height *
                    (@as(f32, @floatFromInt(visible_entries)) /
                        @as(f32, @floatFromInt(self.entry_count))),
            )
        else
            estimated_track_height;
        const thumb_offset = if (scroll_max > 0)
            (estimated_track_height - thumb_height) *
                (@as(f32, @floatFromInt(self.scroll_offset)) /
                    @as(f32, @floatFromInt(scroll_max)))
        else
            0;

        try context.begin(8011, .{
            .width = Sizing.fixed(14),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .padding = .{
                .top = @max(0, thumb_offset),
                .bottom = @max(0, estimated_track_height - thumb_offset - thumb_height),
            },
        }, palette.panel);
        try context.rect(8012, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(@max(1, thumb_height)),
        }, palette.accent);
        context.end();
        context.end();

        if (self.error_message) |message| {
            try addText(
                context,
                8180,
                message,
                600,
                18,
                Sizing.grow(),
                palette.accent,
            );
        }

        // Confirmation
        try context.begin(8190, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(42),
            .direction = .left_to_right,
            .gap = 8,
        }, palette.background);

        try addText(
            context,
            8191,
            "Select the current folder as the project parent.",
            420,
            18,
            Sizing.grow(),
            palette.muted,
        );

        context.end();

        try context.begin(8192, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(42),
            .direction = .left_to_right,
            .gap = 8,
        }, palette.background);

        try actionButton(
            context,
            8301,
            "CANCEL",
            120,
            palette.card,
            palette,
        );

        try actionButton(
            context,
            8302,
            "SELECT FOLDER",
            180,
            palette.accent,
            palette,
        );

        context.end();
        context.end();

        return context.endFrame();
    }
};

fn addText(
    context: *Context,
    id: u64,
    value: []const u8,
    measured_width: f32,
    measured_height: f32,
    width: Sizing,
    color: Color,
) !void {
    try context.text(
        id,
        value,
        .{
            .width = measured_width,
            .height = measured_height,
        },
        .{
            .width = width,
            .height = Sizing.fixed(measured_height),
        },
        color,
    );
}

fn actionButton(
    context: *Context,
    id: u64,
    label: []const u8,
    width: f32,
    background: Color,
    palette: anytype,
) !void {
    try context.begin(id, .{
        .width = Sizing.fixed(width),
        .height = Sizing.grow(),
        .direction = .left_to_right,
        .padding = Padding.xy(10, 0),
        .align_y = .center,
    }, background);

    // Keep label IDs separate from folder-row IDs and other controls.
    try addText(
        context,
        id + 1000,
        label,
        width - 20,
        18,
        Sizing.grow(),
        if (background.r == palette.accent.r and
            background.g == palette.accent.g and
            background.b == palette.accent.b)
            palette.background
        else
            palette.text,
    );

    context.end();
}

test "parentPath returns the containing directory" {
    try std.testing.expectEqualStrings("/", Picker.parentPath("/"));
    try std.testing.expectEqualStrings("/", Picker.parentPath("/home"));
    try std.testing.expectEqualStrings("/home", Picker.parentPath("/home/user"));
    try std.testing.expectEqualStrings("/home/user", Picker.parentPath("/home/user/zigine"));
    try std.testing.expectEqualStrings("/home/user", Picker.parentPath("/home/user/zigine/"));
}
