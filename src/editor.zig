const std = @import("std");
const builtin = @import("builtin");
const ui = @import("ui-components");
const scene_mod = @import("scene");
const tree_mod = @import("scene-tree");
const renderer_mod = @import("renderer");
const scene_renderer_mod = @import("scene-renderer");

const Context = ui.Context;
const Color = ui.Color;
const Sizing = ui.Sizing;
const Padding = ui.Padding;
const DrawCommand = ui.DrawCommand;

const Scene = scene_mod.Scene;
const NodeId = scene_mod.NodeId;
const NodeKind = scene_mod.NodeKind;
const SceneTree = tree_mod.SceneTree;
const Renderer2D = renderer_mod.Renderer2D;
const Camera2D = renderer_mod.Camera2D;
const Rect = renderer_mod.Rect;
const SceneRenderer = scene_renderer_mod.SceneRenderer;

const picker_first_id: u64 = 2000;
const tree_first_id: u64 = 1000;
const default_script =
    "const std = @import(\"std\");\n\n" ++
    "pub fn update() void {\n" ++
    "    // Add game logic here.\n" ++
    "}\n";
const scene_file_name = "main.scene";
const scene_directory_name = "zigine";
const scene_field_separator: u8 = 0x1f;
const scene_script_begin = "// ZIGINE_SCENE_BEGIN\n";
const scene_script_end = "// ZIGINE_SCENE_END\n";
const scene_render_call = "        try zigine_scene_tick(surface);\n";

const InspectorField = enum {
    position,
    rotation,
    scale,
    texture_path,
};

const node_kinds = [_]NodeKind{
    .node,
    .node_2d,
    .sprite_2d,
    .camera_2d,
};

const node_kind_names = [_][]const u8{
    "Node",
    "Node2D",
    "Sprite2D",
    "Camera2D",
};

fn rgb(r: u8, g: u8, b: u8) Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}

fn rendererColor(color: Color) renderer_mod.Color {
    return .{ .r = color.r, .g = color.g, .b = color.b, .a = color.a };
}

fn finite(value: f32) bool {
    return std.math.isFinite(value);
}

pub const Theme = enum {
    dark,
    light,
    catppuccin_mocha,
    dracula,
};

const Palette = struct {
    background: Color,
    panel: Color,
    accent: Color,
    text: Color,
    muted: Color,
    border: Color,
    grid: Color,
    grid_axis: Color,
};

fn getPalette(theme: Theme) Palette {
    return switch (theme) {
        .dark => .{
            .background = rgb(30, 30, 30),
            .panel = rgb(40, 40, 40),
            .accent = rgb(80, 160, 255),
            .text = rgb(235, 235, 235),
            .muted = rgb(160, 160, 160),
            .border = rgb(65, 65, 65),
            .grid = rgb(58, 58, 58),
            .grid_axis = rgb(220, 90, 90),
        },
        .light => .{
            .background = rgb(245, 245, 245),
            .panel = rgb(255, 255, 255),
            .accent = rgb(30, 100, 200),
            .text = rgb(35, 35, 35),
            .muted = rgb(110, 110, 110),
            .border = rgb(210, 210, 210),
            .grid = rgb(220, 220, 220),
            .grid_axis = rgb(210, 80, 80),
        },
        .catppuccin_mocha => .{
            .background = rgb(30, 30, 46),
            .panel = rgb(24, 24, 37),
            .accent = rgb(203, 166, 247),
            .text = rgb(205, 214, 244),
            .muted = rgb(166, 173, 200),
            .border = rgb(69, 71, 90),
            .grid = rgb(58, 62, 82),
            .grid_axis = rgb(235, 100, 125),
        },
        .dracula => .{
            .background = rgb(40, 42, 54),
            .panel = rgb(33, 34, 44),
            .accent = rgb(189, 147, 249),
            .text = rgb(248, 248, 242),
            .muted = rgb(160, 160, 160),
            .border = rgb(68, 71, 90),
            .grid = rgb(68, 71, 90),
            .grid_axis = rgb(255, 85, 85),
        },
    };
}

pub const Panel = enum {
    scene,
    script,
    assets,
    output,
    inspector,
};

pub const AssetItem = struct {
    name: [256]u8 = [_]u8{0} ** 256,
    name_len: usize = 0,
    is_texture: bool = false,
    is_scene: bool = false,
    is_script: bool = false,
};

pub const Editor = struct {
    allocator: std.mem.Allocator,
    context: Context = Context.init(),
    active_panel: Panel = .scene,

    theme: Theme = .catppuccin_mocha,
    palette: Palette = getPalette(.catppuccin_mocha),

    scene: *Scene,
    tree: SceneTree,
    renderer: Renderer2D,
    scene_renderer: SceneRenderer = .{},

    root_node: NodeId,
    selected_node: ?NodeId = null,
    camera: Camera2D = .{ .zoom = 1.0 },

    next_node_name: usize = 1,

    rename_target: ?NodeId = null,
    rename_buffer: std.ArrayList(u8) = .empty,

    inspector_target: ?InspectorField = null,
    inspector_buffer: std.ArrayList(u8) = .empty,
    inspector_error: bool = false,

    script_source: std.ArrayList(u8) = .empty,
    script_cursor: usize = 0,
    script_scroll_line: usize = 0,
    script_scroll_column: usize = 0,
    editing_script: bool = false,
    script_dirty: bool = false,
    project_path: ?[]u8 = null,
    script_file_path: ?[]u8 = null,
    script_is_primary: bool = true,

    viewport_rect: Rect = .{
        .x = 225,
        .y = 105,
        .width = 1,
        .height = 1,
    },
    dragging_node: ?NodeId = null,
    drag_start_world: renderer_mod.Vec2 = .{},
    drag_start_position: scene_mod.Vec2 = .{},
    mouse_down_position: ui.Vec2 = .{},
    last_mouse_position: ui.Vec2 = .{},
    panning_camera: bool = false,

    snap_to_grid: bool = false,
    save_requested: bool = false,
    run_requested: bool = false,
    load_scene_requested: bool = false,
    exit_requested: bool = false,
    asset_drag_index: ?usize = null,
    asset_dragging: bool = false,
    asset_drag_origin: ui.Vec2 = .{},
    asset_open_requested: ?usize = null,

    log_messages: [4][64]u8 = [_][64]u8{[_]u8{0} ** 64} ** 4,
    log_lens: [4]usize = [_]usize{0} ** 4,

    terminal_active: bool = false,
    terminal_input: [512]u8 = [_]u8{0} ** 512,
    terminal_input_len: usize = 0,
    terminal_cursor: usize = 0,
    terminal_history: [32][512]u8 = [_][512]u8{[_]u8{0} ** 512} ** 32,
    terminal_history_lens: [32]usize = [_]usize{0} ** 32,
    terminal_history_count: usize = 0,
    terminal_history_index: ?usize = null,
    terminal_lines: [64][192]u8 = [_][192]u8{[_]u8{0} ** 192} ** 64,
    terminal_line_lens: [64]usize = [_]usize{0} ** 64,
    terminal_line_count: usize = 0,
    terminal_cwd_label: [560]u8 = [_]u8{0} ** 560,
    terminal_cwd_label_len: usize = 0,
    terminal_environment: ?*const std.process.Environ.Map = null,

    asset_items: [32]AssetItem = [_]AssetItem{.{}} ** 32,
    asset_count: usize = 0,
    asset_scroll: usize = 0,
    asset_visible_rows: usize = 3,
    tree_scroll: usize = 0,
    tree_visible_rows: usize = 24,

    picker_open: bool = false,
    picker_index: usize = 0,

    pub fn init() !Editor {
        const allocator = std.heap.page_allocator;

        const scene = try allocator.create(Scene);
        errdefer allocator.destroy(scene);

        scene.* = try Scene.init(allocator, "MainScene");
        errdefer scene.deinit();

        const root = try scene.createNode(
            null,
            "MainScene",
            .node_2d,
        );

        var tree = SceneTree.init(allocator, scene);
        errdefer tree.deinit();

        try tree.setRoot(root);
        try tree.enterTree();

        var renderer = Renderer2D.init(allocator);
        errdefer renderer.deinit();

        var editor = Editor{
            .allocator = allocator,
            .scene = scene,
            .tree = tree,
            .renderer = renderer,
            .root_node = root,
            .selected_node = root,
        };
        errdefer editor.script_source.deinit(allocator);

        try editor.script_source.appendSlice(allocator, default_script);

        editor.logMsg("Zigine 2D Scene Editor ready.");
        editor.logMsg("Pan: Middle or Right Drag | Zoom: Wheel");
        editor.logMsg("Select & move nodes directly in 2D Viewport.");

        return editor;
    }

    pub fn setTerminalEnvironment(self: *Editor, environ_map: *const std.process.Environ.Map) void {
        self.terminal_environment = environ_map;
    }

    pub fn logMsg(self: *Editor, msg: []const u8) void {
        var i: usize = 0;
        while (i < 3) : (i += 1) {
            @memcpy(&self.log_messages[i], &self.log_messages[i + 1]);
            self.log_lens[i] = self.log_lens[i + 1];
        }
        const len = @min(msg.len, 63);
        @memcpy(self.log_messages[3][0..len], msg[0..len]);
        self.log_messages[3][len] = 0;
        self.log_lens[3] = len;
        self.terminalWrite("[zigine] ");
        self.terminalWrite(msg);
        self.terminalWrite("\n");
    }

    fn terminalWrite(self: *Editor, text: []const u8) void {
        if (text.len == 0) return;

        var line_start: usize = 0;
        while (line_start < text.len) {
            var line_end = line_start;
            while (line_end < text.len and text[line_end] != '\n') : (line_end += 1) {}

            if (self.terminal_line_count == 0) {
                self.terminal_line_count = 1;
            }

            const current_index = self.terminal_line_count - 1;
            const line = &self.terminal_lines[current_index];
            var line_len = self.terminal_line_lens[current_index];

            const available = line.len -| line_len;
            const copied = @min(available, line_end - line_start);
            if (copied > 0) @memcpy(line[line_len .. line_len + copied], text[line_start .. line_start + copied]);
            line_len += copied;
            self.terminal_line_lens[current_index] = line_len;

            if (line_end < text.len) {
                if (self.terminal_line_count < self.terminal_lines.len) {
                    self.terminal_lines[self.terminal_line_count] = [_]u8{0} ** 192;
                    self.terminal_line_lens[self.terminal_line_count] = 0;
                    self.terminal_line_count += 1;
                } else {
                    var i: usize = 1;
                    while (i < self.terminal_lines.len) : (i += 1) {
                        self.terminal_lines[i - 1] = self.terminal_lines[i];
                        self.terminal_line_lens[i - 1] = self.terminal_line_lens[i];
                    }
                    self.terminal_lines[self.terminal_lines.len - 1] = [_]u8{0} ** 192;
                    self.terminal_line_lens[self.terminal_lines.len - 1] = 0;
                }
            }

            line_start = line_end + 1;
        }
    }

    fn updateTerminalCwd(self: *Editor) void {
        const cwd = self.project_path orelse ".";
        const label = std.fmt.bufPrint(&self.terminal_cwd_label, "CWD: {s}", .{cwd}) catch "CWD: .";
        self.terminal_cwd_label_len = label.len;
    }

    fn terminalEnsureLineBreak(self: *Editor) void {
        if (self.terminal_line_count == 0) return;
        if (self.terminal_line_lens[self.terminal_line_count - 1] > 0) {
            self.terminalWrite("\n");
        }
    }

    pub fn isEditingTerminal(self: *const Editor) bool {
        return self.active_panel == .output and self.terminal_active;
    }

    pub fn focusTerminal(self: *Editor) void {
        self.active_panel = .output;
        self.terminal_active = true;
    }

    pub fn clearTerminal(self: *Editor) void {
        self.terminal_lines = [_][192]u8{[_]u8{0} ** 192} ** 64;
        self.terminal_line_lens = [_]usize{0} ** 64;
        self.terminal_line_count = 0;
    }

    pub fn appendTerminalText(self: *Editor, text: []const u8) void {
        if (!self.isEditingTerminal()) return;
        for (text) |character| {
            if (character < 0x20 or character == 0x7f) continue;
            if (self.terminal_input_len >= self.terminal_input.len) break;
            var i = self.terminal_input_len;
            while (i > self.terminal_cursor) : (i -= 1) {
                self.terminal_input[i] = self.terminal_input[i - 1];
            }
            self.terminal_input[self.terminal_cursor] = character;
            self.terminal_input_len += 1;
            self.terminal_cursor += 1;
        }
    }

    pub fn backspaceTerminal(self: *Editor) void {
        if (!self.isEditingTerminal() or self.terminal_cursor == 0) return;
        var i = self.terminal_cursor;
        while (i < self.terminal_input_len) : (i += 1) {
            self.terminal_input[i - 1] = self.terminal_input[i];
        }
        self.terminal_input_len -= 1;
        self.terminal_cursor -= 1;
        self.terminal_input[self.terminal_input_len] = 0;
    }

    pub fn deleteTerminalCharacter(self: *Editor) void {
        if (!self.isEditingTerminal() or self.terminal_cursor >= self.terminal_input_len) return;
        var i = self.terminal_cursor + 1;
        while (i < self.terminal_input_len) : (i += 1) {
            self.terminal_input[i - 1] = self.terminal_input[i];
        }
        self.terminal_input_len -= 1;
        self.terminal_input[self.terminal_input_len] = 0;
    }

    pub fn moveTerminalCursor(self: *Editor, delta: isize) void {
        if (!self.isEditingTerminal()) return;
        const cursor: isize = @intCast(self.terminal_cursor);
        const length: isize = @intCast(self.terminal_input_len);
        self.terminal_cursor = @intCast(@max(0, @min(length, cursor + delta)));
    }

    pub fn terminalCursorBoundary(self: *Editor, end: bool) void {
        if (!self.isEditingTerminal()) return;
        self.terminal_cursor = if (end) self.terminal_input_len else 0;
    }

    fn setTerminalInput(self: *Editor, value: []const u8) void {
        const len = @min(value.len, self.terminal_input.len);
        @memcpy(self.terminal_input[0..len], value[0..len]);
        @memset(self.terminal_input[len..], 0);
        self.terminal_input_len = len;
        self.terminal_cursor = len;
    }

    pub fn terminalHistory(self: *Editor, delta: i32) void {
        if (!self.isEditingTerminal() or self.terminal_history_count == 0) return;
        if (delta < 0) {
            const next = if (self.terminal_history_index) |index|
                if (index > 0) index - 1 else 0
            else
                self.terminal_history_count - 1;
            self.terminal_history_index = next;
            self.setTerminalInput(self.terminal_history[next][0..self.terminal_history_lens[next]]);
        } else if (self.terminal_history_index) |index| {
            if (index + 1 >= self.terminal_history_count) {
                self.terminal_history_index = null;
                self.setTerminalInput("");
            } else {
                self.terminal_history_index = index + 1;
                self.setTerminalInput(self.terminal_history[index + 1][0..self.terminal_history_lens[index + 1]]);
            }
        }
    }

    pub fn executeTerminal(self: *Editor, io: std.Io) !void {
        if (!self.isEditingTerminal()) return;
        const command = std.mem.trim(u8, self.terminal_input[0..self.terminal_input_len], " \t\r\n");
        if (command.len == 0) return;

        self.terminalEnsureLineBreak();
        self.terminalWrite("> ");
        self.terminalWrite(command);
        self.terminalWrite("\n");

        if (self.terminal_history_count == 0 or
            !std.mem.eql(u8, command, self.terminal_history[self.terminal_history_count - 1][0..self.terminal_history_lens[self.terminal_history_count - 1]]))
        {
            const index = if (self.terminal_history_count < self.terminal_history.len)
                self.terminal_history_count
            else
                self.terminal_history.len - 1;
            if (index > 0 and self.terminal_history_count == self.terminal_history.len) {
                var i: usize = 1;
                while (i < self.terminal_history.len) : (i += 1) {
                    self.terminal_history[i - 1] = self.terminal_history[i];
                    self.terminal_history_lens[i - 1] = self.terminal_history_lens[i];
                }
            }
            const stored = @min(command.len, self.terminal_history[index].len);
            @memcpy(self.terminal_history[index][0..stored], command[0..stored]);
            self.terminal_history_lens[index] = stored;
            if (self.terminal_history_count < self.terminal_history.len) self.terminal_history_count += 1;
        }
        self.terminal_history_index = null;
        self.setTerminalInput("");

        if (std.mem.eql(u8, command, "clear") or
            std.mem.eql(u8, command, "cls"))
        {
            self.clearTerminal();
            return;
        }

        var argv: [5][]const u8 = undefined;
        var argc: usize = 0;
        if (builtin.os.tag == .windows) {
            const powershell = if (self.terminal_environment) |environ_map|
                environ_map.get("POWERSHELL") orelse "powershell.exe"
            else
                "powershell.exe";
            argv[0] = powershell;
            argv[1] = "-NoLogo";
            argv[2] = "-NoProfile";
            argv[3] = "-Command";
            argv[4] = command;
            argc = 5;
        } else {
            const shell = if (self.terminal_environment) |environ_map|
                environ_map.get("SHELL") orelse "/bin/sh"
            else
                "/bin/sh";
            argv[0] = shell;
            argv[1] = "-c";
            argv[2] = command;
            argc = 3;
        }

        const project_path = self.project_path;
        var result: std.process.RunResult = undefined;
        if (project_path) |path| {
            var dir = try std.Io.Dir.cwd().openDir(io, path, .{});
            defer dir.close(io);
            result = try std.process.run(self.allocator, io, .{
                .argv = argv[0..argc],
                .cwd = .{ .dir = dir },
                // Inherit the complete host environment so PATH and shell
                // tools remain available inside the embedded terminal.
                .environ_map = null,
                .stdout_limit = .limited(64 * 1024),
                .stderr_limit = .limited(64 * 1024),
            });
        } else {
            result = try std.process.run(self.allocator, io, .{
                .argv = argv[0..argc],
                .environ_map = null,
                .stdout_limit = .limited(64 * 1024),
                .stderr_limit = .limited(64 * 1024),
            });
        }
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        self.terminalWrite(result.stdout);
        self.terminalWrite(result.stderr);
        switch (result.term) {
            .exited => |code| if (code != 0) {
                var status: [32]u8 = undefined;
                self.terminalWrite(std.fmt.bufPrint(&status, "[exit {d}]\n", .{code}) catch "[command failed]\n");
            },
            else => self.terminalWrite("[process terminated]\n"),
        }
    }

    fn hasExtension(name: []const u8, extension: []const u8) bool {
        return name.len >= extension.len and std.ascii.eqlIgnoreCase(
            name[name.len - extension.len ..],
            extension,
        );
    }

    fn classifyAsset(name: []const u8) struct { texture: bool, scene: bool, script: bool } {
        const texture = hasExtension(name, ".png") or
            hasExtension(name, ".jpg") or
            hasExtension(name, ".jpeg") or
            hasExtension(name, ".gif") or
            hasExtension(name, ".bmp") or
            hasExtension(name, ".webp") or
            hasExtension(name, ".tga") or
            hasExtension(name, ".tif") or
            hasExtension(name, ".tiff");
        const scene = hasExtension(name, ".scene");
        const script = hasExtension(name, ".zig") or
            hasExtension(name, ".zig.zon") or
            hasExtension(name, ".c") or
            hasExtension(name, ".h") or
            hasExtension(name, ".cc") or
            hasExtension(name, ".cpp") or
            hasExtension(name, ".cxx") or
            hasExtension(name, ".hpp") or
            hasExtension(name, ".rs") or
            hasExtension(name, ".py") or
            hasExtension(name, ".lua") or
            hasExtension(name, ".js") or
            hasExtension(name, ".ts") or
            hasExtension(name, ".gd");
        return .{ .texture = texture, .scene = scene, .script = script };
    }

    fn addAsset(self: *Editor, path: []const u8) void {
        if (self.asset_count >= self.asset_items.len or path.len > self.asset_items[0].name.len) return;
        const kind = classifyAsset(path);
        if (!kind.texture and !kind.scene and !kind.script) return;

        var item = &self.asset_items[self.asset_count];
        @memset(item.name[0..], 0);
        @memcpy(item.name[0..path.len], path);
        item.name_len = path.len;
        item.is_texture = kind.texture;
        item.is_scene = kind.scene;
        item.is_script = kind.script;
        self.asset_count += 1;
    }

    fn scanAssetDirectory(self: *Editor, io: std.Io, path: []const u8, prefix: []const u8) void {
        if (self.asset_count >= self.asset_items.len) return;
        var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return;
        defer dir.close(io);

        var iter = dir.iterate();
        while (iter.next(io) catch null) |entry| {
            if (entry.kind != .file) continue;
            var display_path: [256]u8 = undefined;
            const printed = std.fmt.bufPrint(&display_path, "{s}{s}", .{ prefix, entry.name }) catch continue;
            self.addAsset(printed);
            if (self.asset_count >= self.asset_items.len) break;
        }
    }

    pub fn scanAssets(self: *Editor, io: std.Io) void {
        self.asset_count = 0;
        self.asset_scroll = 0;
        const project_dir_path = self.project_path orelse ".";
        self.scanAssetDirectory(io, project_dir_path, "");

        var assets_path: [256]u8 = undefined;
        if (std.fmt.bufPrint(&assets_path, "{s}/assets", .{project_dir_path})) |path| {
            self.scanAssetDirectory(io, path, "assets/");
        } else |_| {}

        var src_path: [256]u8 = undefined;
        if (std.fmt.bufPrint(&src_path, "{s}/src", .{project_dir_path})) |path| {
            self.scanAssetDirectory(io, path, "src/");
        } else |_| {}
    }

    pub fn scrollAssets(self: *Editor, delta: isize) void {
        const max_offset = self.asset_count -| self.asset_visible_rows;
        if (delta < 0) {
            self.asset_scroll -|= @intCast(@abs(delta));
        } else {
            self.asset_scroll = @min(
                max_offset,
                self.asset_scroll + @as(usize, @intCast(delta)),
            );
        }
    }

    pub fn scrollTree(self: *Editor, delta: isize) void {
        const max_offset = self.tree.nodeCount() -| self.tree_visible_rows;
        if (delta < 0) {
            self.tree_scroll -|= @intCast(@abs(delta));
        } else {
            self.tree_scroll = @min(
                max_offset,
                self.tree_scroll + @as(usize, @intCast(delta)),
            );
        }
    }

    pub fn nudgeSelected(self: *Editor, dx: f32, dy: f32) !void {
        const selected = self.selected_node orelse return;
        const node = try self.scene.getConst(selected);
        var t = node.transform;
        t.position.x += dx;
        t.position.y += dy;
        try self.scene.setTransform(selected, t);
    }

    pub fn setPositionSelected(self: *Editor, x: f32, y: f32) !void {
        const selected = self.selected_node orelse return;
        const node = try self.scene.getConst(selected);
        var t = node.transform;
        t.position.x = x;
        t.position.y = y;
        try self.scene.setTransform(selected, t);
    }

    pub fn addRotationSelected(self: *Editor, deg: f32) !void {
        const selected = self.selected_node orelse return;
        const node = try self.scene.getConst(selected);
        var t = node.transform;
        t.rotation += deg * std.math.pi / 180.0;
        try self.scene.setTransform(selected, t);
    }

    pub fn setRotationSelected(self: *Editor, deg: f32) !void {
        const selected = self.selected_node orelse return;
        const node = try self.scene.getConst(selected);
        var t = node.transform;
        t.rotation = deg * std.math.pi / 180.0;
        try self.scene.setTransform(selected, t);
    }

    pub fn setScaleSelected(self: *Editor, sx: f32, sy: f32) !void {
        const selected = self.selected_node orelse return;
        const node = try self.scene.getConst(selected);
        var t = node.transform;
        t.scale.x = sx;
        t.scale.y = sy;
        try self.scene.setTransform(selected, t);
    }

    pub fn flipScaleX(self: *Editor) !void {
        _ = self;
        return error.InvalidScale;
    }

    pub fn flipScaleY(self: *Editor) !void {
        _ = self;
        return error.InvalidScale;
    }

    pub fn clearTextureSelected(self: *Editor) !void {
        const selected = self.selected_node orelse return;
        try self.scene.setTexturePath(selected, "");
        self.logMsg("Cleared texture");
    }

    pub fn setTextureSelected(self: *Editor, path: []const u8) !void {
        const selected = self.selected_node orelse return;
        try self.scene.setTexturePath(selected, path);
        self.logMsg("Set texture");
    }

    pub fn reparentSelectedToRoot(self: *Editor) !void {
        const selected = self.selected_node orelse return;
        if (selected.eql(self.root_node)) return;
        try self.scene.reparent(selected, self.root_node);
        try self.tree.refresh();
        self.logMsg("Reparented node to Root");
    }

    pub fn resetCamera(self: *Editor) void {
        self.camera.position = .{ .x = 0, .y = 0 };
        self.camera.zoom = 1.0;
        self.logMsg("Reset view to (0,0) at 100%");
    }

    pub fn focusSelected(self: *Editor) void {
        const selected = self.selected_node orelse {
            self.resetCamera();
            return;
        };
        if (self.scene.globalTransform(selected)) |gt| {
            const world = gt.transformPoint(.{ .x = 0, .y = 0 });
            self.camera.position = .{ .x = world.x, .y = world.y };
            self.logMsg("Focused camera on selected node");
        } else |_| {
            self.resetCamera();
        }
    }

    pub fn deinit(self: *Editor) void {
        self.rename_buffer.deinit(self.allocator);
        self.inspector_buffer.deinit(self.allocator);
        self.script_source.deinit(self.allocator);
        if (self.project_path) |path| self.allocator.free(path);
        if (self.script_file_path) |path| self.allocator.free(path);
        self.tree.deinit();
        self.renderer.deinit();
        self.scene.deinit();
        self.allocator.destroy(self.scene);
        self.* = undefined;
    }

    /// Leaves the current project without retaining its scene, script,
    /// selection, or filesystem association in the editor instance.
    pub fn closeProject(self: *Editor) !void {
        const replacement = try self.allocator.create(Scene);
        errdefer self.allocator.destroy(replacement);
        replacement.* = try Scene.init(self.allocator, "MainScene");
        errdefer replacement.deinit();

        const replacement_root = try replacement.createNode(null, "MainScene", .node_2d);
        var replacement_tree = SceneTree.init(self.allocator, replacement);
        errdefer replacement_tree.deinit();
        try replacement_tree.setRoot(replacement_root);
        try replacement_tree.enterTree();

        self.tree.deinit();
        self.scene.deinit();
        self.allocator.destroy(self.scene);
        self.scene = replacement;
        self.tree = replacement_tree;
        self.root_node = replacement_root;
        self.selected_node = replacement_root;

        if (self.project_path) |path| self.allocator.free(path);
        self.project_path = null;
        if (self.script_file_path) |path| self.allocator.free(path);
        self.script_file_path = null;
        self.script_is_primary = true;
        self.script_source.clearRetainingCapacity();
        try self.script_source.appendSlice(self.allocator, default_script);
        self.script_cursor = self.script_source.items.len;
        self.script_scroll_line = 0;
        self.script_scroll_column = 0;
        self.script_dirty = false;
        self.editing_script = false;
        self.active_panel = .scene;
        self.next_node_name = 1;
        self.asset_count = 0;
        self.asset_scroll = 0;
        self.tree_scroll = 0;
        self.asset_drag_index = null;
        self.asset_dragging = false;
        self.asset_open_requested = null;
        self.terminal_active = false;
        self.terminal_input = [_]u8{0} ** 512;
        self.terminal_input_len = 0;
        self.terminal_cursor = 0;
        self.terminal_history = [_][512]u8{[_]u8{0} ** 512} ** 32;
        self.terminal_history_lens = [_]usize{0} ** 32;
        self.terminal_history_count = 0;
        self.terminal_history_index = null;
        self.terminal_line_count = 0;
        self.clearTerminal();
        self.picker_open = false;
        self.rename_target = null;
        self.inspector_target = null;
        self.rename_buffer.clearRetainingCapacity();
        self.inspector_buffer.clearRetainingCapacity();
        self.camera.position = .{};
        self.camera.zoom = 1.0;
        self.save_requested = false;
        self.run_requested = false;
        self.load_scene_requested = false;
        self.exit_requested = false;
    }

    pub fn setTheme(self: *Editor, theme: Theme) void {
        self.theme = theme;
        self.palette = getPalette(theme);
    }

    pub fn selectPanel(self: *Editor, selected: Panel) void {
        self.active_panel = selected;
    }

    pub fn isRenaming(self: *const Editor) bool {
        return self.rename_target != null;
    }

    pub fn isEditingInspector(self: *const Editor) bool {
        return self.inspector_target != null;
    }

    pub fn isEditingScript(self: *const Editor) bool {
        return self.editing_script;
    }

    pub fn isNodePickerOpen(self: *const Editor) bool {
        return self.picker_open;
    }

    pub fn wantsTextInput(self: *const Editor) bool {
        return self.isRenaming() or self.isEditingInspector() or self.editing_script or self.isEditingTerminal();
    }

    pub fn cancelTransientMode(self: *Editor) bool {
        if (self.picker_open) {
            self.picker_open = false;
            return true;
        }

        if (self.rename_target != null) {
            self.cancelRename();
            return true;
        }

        if (self.inspector_target != null) {
            self.cancelInspectorEdit();
            return true;
        }

        if (self.editing_script) {
            self.editing_script = false;
            return true;
        }

        if (self.terminal_active) {
            self.terminal_active = false;
            return true;
        }

        self.dragging_node = null;
        self.panning_camera = false;
        return false;
    }

    pub fn openNodePicker(self: *Editor) void {
        if (self.isRenaming() or self.isEditingInspector()) return;
        self.picker_open = true;
        self.picker_index = 0;
    }

    pub fn movePickerSelection(self: *Editor, delta: i32) void {
        if (!self.picker_open) return;

        const count: i32 = @intCast(node_kinds.len);
        const current: i32 = @intCast(self.picker_index);
        self.picker_index = @intCast(@mod(current + delta, count));
    }

    pub fn moveTreeSelection(self: *Editor, delta: i32) void {
        if (self.picker_open or self.isRenaming() or self.isEditingInspector()) return;

        const count = self.tree.nodeCount();
        if (count == 0) return;

        var current: usize = 0;

        if (self.selected_node) |selected| {
            for (0..count) |index| {
                if (self.tree.nodeAt(index)) |id| {
                    if (id.eql(selected)) {
                        current = index;
                        break;
                    }
                }
            }
        }

        const count_i: i64 = @intCast(count);
        const current_i: i64 = @intCast(current);
        const next = @mod(current_i + delta, count_i);

        if (self.tree.nodeAt(@intCast(next))) |id| {
            self.selected_node = id;
        }
    }

    pub fn choosePickerSelection(self: *Editor) !void {
        if (!self.picker_open) return;

        const kind = node_kinds[self.picker_index];
        self.picker_open = false;
        try self.createNodeKind(kind);
    }

    pub fn beginRenameSelectedNode(self: *Editor) !void {
        if (self.picker_open or self.isEditingInspector()) return;

        const selected = self.selected_node orelse return;
        if (selected.eql(self.root_node)) return;
        if (!self.scene.contains(selected)) return;

        const node = try self.scene.getConst(selected);

        self.rename_buffer.clearRetainingCapacity();
        try self.rename_buffer.appendSlice(self.allocator, node.name);
        self.rename_target = selected;
    }

    pub fn appendRenameText(self: *Editor, text: []const u8) !void {
        if (self.rename_target == null) return;
        try self.rename_buffer.appendSlice(self.allocator, text);
    }

    pub fn backspaceRename(self: *Editor) void {
        if (self.rename_target == null) return;
        if (self.rename_buffer.items.len == 0) return;
        self.rename_buffer.items.len -= 1;
    }

    pub fn cancelRename(self: *Editor) void {
        self.rename_target = null;
        self.rename_buffer.clearRetainingCapacity();
    }

    pub fn commitRename(self: *Editor) !void {
        const target = self.rename_target orelse return;

        if (self.rename_buffer.items.len == 0) return error.EmptyName;

        if (!self.scene.contains(target)) {
            self.cancelRename();
            self.selected_node = self.root_node;
            return;
        }

        try self.scene.renameNode(target, self.rename_buffer.items);
        try self.tree.refresh();

        self.selected_node = target;
        self.cancelRename();
    }

    pub fn renameSelectedNode(self: *Editor) !void {
        try self.beginRenameSelectedNode();
    }

    pub fn beginInspectorEdit(self: *Editor, field: InspectorField) !void {
        if (self.picker_open or self.isRenaming()) return;

        const node_id = self.selected_node orelse return;
        const node = try self.scene.getConst(node_id);

        var temporary: [128]u8 = undefined;
        const text = switch (field) {
            .position => try std.fmt.bufPrint(
                &temporary,
                "{d}, {d}",
                .{ node.transform.position.x, node.transform.position.y },
            ),
            .rotation => try std.fmt.bufPrint(
                &temporary,
                "{d}",
                .{node.transform.rotation * 180.0 / std.math.pi},
            ),
            .scale => try std.fmt.bufPrint(
                &temporary,
                "{d}, {d}",
                .{ node.transform.scale.x, node.transform.scale.y },
            ),
            .texture_path => node.texture_path orelse "",
        };

        self.inspector_buffer.clearRetainingCapacity();
        try self.inspector_buffer.appendSlice(self.allocator, text);
        self.inspector_target = field;
        self.inspector_error = false;
    }

    pub fn appendInspectorText(self: *Editor, text: []const u8) !void {
        if (self.inspector_target == null) return;
        try self.inspector_buffer.appendSlice(self.allocator, text);
        self.inspector_error = false;
    }

    pub fn backspaceInspector(self: *Editor) void {
        if (self.inspector_target == null) return;
        if (self.inspector_buffer.items.len == 0) return;

        self.inspector_buffer.items.len -= 1;
        self.inspector_error = false;
    }

    pub fn cancelInspectorEdit(self: *Editor) void {
        self.inspector_target = null;
        self.inspector_error = false;
        self.inspector_buffer.clearRetainingCapacity();
    }

    pub fn commitInspectorEdit(self: *Editor) !void {
        const field = self.inspector_target orelse return;
        const node_id = self.selected_node orelse return;
        const node = try self.scene.getConst(node_id);

        const input = std.mem.trim(
            u8,
            self.inspector_buffer.items,
            " \t\r\n",
        );

        var transform = node.transform;

        switch (field) {
            .position, .scale => {
                var first_text: []const u8 = input;
                var second_text: ?[]const u8 = null;

                if (std.mem.indexOfScalar(u8, input, ',')) |comma| {
                    first_text = std.mem.trim(u8, input[0..comma], " \t");
                    second_text = std.mem.trim(u8, input[comma + 1 ..], " \t");
                } else if (std.mem.indexOfScalar(u8, input, ' ')) |space| {
                    first_text = std.mem.trim(u8, input[0..space], " \t");
                    second_text = std.mem.trim(u8, input[space + 1 ..], " \t");
                }

                const x = std.fmt.parseFloat(f32, first_text) catch {
                    self.inspector_error = true;
                    return error.InvalidInspectorValue;
                };

                const y: f32 = if (second_text) |s|
                    std.fmt.parseFloat(f32, s) catch {
                        self.inspector_error = true;
                        return error.InvalidInspectorValue;
                    }
                else if (field == .scale)
                    x
                else
                    transform.position.y;

                if (!finite(x) or !finite(y)) {
                    self.inspector_error = true;
                    return error.InvalidInspectorValue;
                }

                if (field == .scale and (x < 0 or y < 0)) {
                    self.inspector_error = true;
                    return error.InvalidScale;
                }

                switch (field) {
                    .position => transform.position = .{ .x = x, .y = y },
                    .scale => transform.scale = .{ .x = x, .y = y },
                    .rotation, .texture_path => unreachable,
                }
            },
            .rotation => {
                const degrees = std.fmt.parseFloat(f32, input) catch {
                    self.inspector_error = true;
                    return error.InvalidInspectorValue;
                };

                if (!finite(degrees)) {
                    self.inspector_error = true;
                    return error.InvalidInspectorValue;
                }

                transform.rotation = degrees * std.math.pi / 180.0;
            },
            .texture_path => {
                try self.scene.setTexturePath(node_id, input);
                self.cancelInspectorEdit();
                return;
            },
        }

        try self.scene.setTransform(node_id, transform);
        self.cancelInspectorEdit();
    }

    pub fn beginScriptEdit(self: *Editor) void {
        if (self.picker_open or self.isRenaming() or self.isEditingInspector()) return;

        self.active_panel = .script;
        self.editing_script = true;
        self.script_cursor = @min(self.script_cursor, self.script_source.items.len);
    }

    pub fn moveScriptCursor(self: *Editor, delta: isize) void {
        if (!self.editing_script) return;

        const len: isize = @intCast(self.script_source.items.len);
        const cursor: isize = @intCast(@min(self.script_cursor, self.script_source.items.len));
        self.script_cursor = @intCast(@max(0, @min(len, cursor + delta)));
    }

    pub fn moveScriptCursorToLineBoundary(self: *Editor, to_end: bool) void {
        if (!self.editing_script) return;

        const source = self.script_source.items;
        const cursor = @min(self.script_cursor, source.len);

        var line_start = cursor;
        while (line_start > 0 and source[line_start - 1] != '\n') {
            line_start -= 1;
        }

        if (to_end) {
            var line_end = cursor;
            while (line_end < source.len and source[line_end] != '\n') {
                line_end += 1;
            }
            self.script_cursor = line_end;
        } else {
            self.script_cursor = line_start;
        }
    }

    pub fn moveScriptCursorVertical(self: *Editor, delta: isize) void {
        if (!self.editing_script) return;
        const source = self.script_source.items;
        const cursor = @min(self.script_cursor, source.len);
        var line_start = cursor;
        while (line_start > 0 and source[line_start - 1] != '\n') : (line_start -= 1) {}
        const column = cursor - line_start;
        var target_start = line_start;

        if (delta < 0) {
            if (line_start == 0) return;
            target_start = line_start - 1;
            while (target_start > 0 and source[target_start - 1] != '\n') : (target_start -= 1) {}
        } else {
            var line_end = cursor;
            while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}
            if (line_end >= source.len) return;
            target_start = line_end + 1;
        }

        var target_end = target_start;
        while (target_end < source.len and source[target_end] != '\n') : (target_end += 1) {}
        self.script_cursor = target_start + @min(column, target_end - target_start);
        self.ensureScriptCursorVisible(self.scriptVisibleLines());
    }

    pub fn moveScriptCursorByPage(self: *Editor, delta: isize, visible_lines: usize) void {
        const pages: usize = @intCast(if (delta < 0) -delta else delta);
        var remaining = @max(@as(usize, 1), pages * @max(visible_lines, 1));
        const direction: isize = if (delta < 0) -1 else 1;
        while (remaining > 0) : (remaining -= 1) self.moveScriptCursorVertical(direction);
    }

    pub fn scrollScript(self: *Editor, delta: isize, visible_lines: usize) void {
        const source = self.script_source.items;
        var total_lines: usize = 1;
        for (source) |ch| if (ch == '\n') {
            total_lines += 1;
        };
        const max_scroll = total_lines -| @max(visible_lines, 1);
        if (delta < 0) {
            self.script_scroll_line -|= @intCast(@abs(delta));
        } else {
            self.script_scroll_line = @min(max_scroll, self.script_scroll_line + @as(usize, @intCast(delta)));
        }
        self.script_scroll_line = @min(self.script_scroll_line, max_scroll);
    }

    fn scriptViewportBounds(self: *const Editor) ?Rect {
        const panel = self.context.getElementBounds(52) orelse return null;
        const placeholder = self.context.getElementBounds(54) orelse return null;
        const bounds = ui.intersectRects(placeholder, panel);
        if (bounds.width <= 0 or bounds.height <= 0) return null;
        return .{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width,
            .height = bounds.height,
        };
    }

    fn scriptVisibleColumns(self: *const Editor) usize {
        const bounds = self.scriptViewportBounds() orelse return 80;
        if (bounds.width <= 54) return 1;
        return @max(1, @as(usize, @intFromFloat((bounds.width - 54) / 14)));
    }

    fn longestScriptLine(self: *const Editor) usize {
        var longest: usize = 0;
        var current: usize = 0;
        for (self.script_source.items) |character| {
            if (character == '\n') {
                longest = @max(longest, current);
                current = 0;
            } else {
                current += 1;
            }
        }
        return @max(longest, current);
    }

    pub fn scrollScriptHorizontal(self: *Editor, delta: isize) void {
        const visible = self.scriptVisibleColumns();
        const max_scroll = self.longestScriptLine() -| visible;
        if (delta < 0) {
            self.script_scroll_column -|= @intCast(@abs(delta));
        } else {
            self.script_scroll_column = @min(
                max_scroll,
                self.script_scroll_column + @as(usize, @intCast(delta)),
            );
        }
        self.script_scroll_column = @min(self.script_scroll_column, max_scroll);
    }

    pub fn ensureScriptCursorVisible(self: *Editor, visible_lines: usize) void {
        const source = self.script_source.items;
        const cursor = @min(self.script_cursor, source.len);
        var line: usize = 0;
        for (source[0..cursor]) |ch| if (ch == '\n') {
            line += 1;
        };
        const visible = @max(visible_lines, 1);
        if (line < self.script_scroll_line) self.script_scroll_line = line;
        if (line >= self.script_scroll_line + visible) self.script_scroll_line = line - visible + 1;

        const cursor_line_start = blk: {
            var start = cursor;
            while (start > 0 and source[start - 1] != '\n') : (start -= 1) {}
            break :blk start;
        };
        const column = cursor - cursor_line_start;
        const visible_columns = self.scriptVisibleColumns();
        if (column < self.script_scroll_column) self.script_scroll_column = column;
        if (column >= self.script_scroll_column + visible_columns) {
            self.script_scroll_column = column - visible_columns + 1;
        }
        const max_scroll = self.longestScriptLine() -| visible_columns;
        self.script_scroll_column = @min(self.script_scroll_column, max_scroll);
    }

    pub fn scriptVisibleLines(self: *const Editor) usize {
        const bounds = self.scriptViewportBounds() orelse return 24;
        return @max(1, @as(usize, @intFromFloat(@max(1, bounds.height) / 18)));
    }

    pub fn placeScriptCursor(self: *Editor, position: ui.Vec2) void {
        const bounds = self.scriptViewportBounds() orelse return;
        const line_height: f32 = 18;
        const char_width: f32 = 14;
        const gutter_width: f32 = 54;
        const relative_y = @max(0, position.y - bounds.y);
        const target_line = self.script_scroll_line + @as(usize, @intFromFloat(relative_y / line_height));
        const target_column: usize = self.script_scroll_column +
            @as(usize, @intFromFloat(@max(0, position.x - bounds.x - gutter_width) / char_width));
        const source = self.script_source.items;
        var line: usize = 0;
        var start: usize = 0;
        while (line < target_line and start < source.len) : (line += 1) {
            while (start < source.len and source[start] != '\n') : (start += 1) {}
            if (start < source.len) start += 1;
        }
        var end = start;
        while (end < source.len and source[end] != '\n') : (end += 1) {}
        self.script_cursor = start + @min(target_column, end - start);
        self.ensureScriptCursorVisible(self.scriptVisibleLines());
    }

    pub fn appendScriptText(self: *Editor, text: []const u8) !void {
        if (!self.editing_script or text.len == 0) return;

        const source = &self.script_source;
        const cursor = @min(self.script_cursor, source.items.len);
        try source.ensureUnusedCapacity(self.allocator, text.len);

        const old_len = source.items.len;
        source.items.len = old_len + text.len;
        std.mem.copyBackwards(
            u8,
            source.items[cursor + text.len .. old_len + text.len],
            source.items[cursor..old_len],
        );
        @memcpy(source.items[cursor .. cursor + text.len], text);

        self.script_cursor = cursor + text.len;
        self.script_dirty = true;
        self.ensureScriptCursorVisible(self.scriptVisibleLines());
    }

    pub fn appendScriptNewline(self: *Editor) !void {
        try self.appendScriptText("\n");
    }

    pub fn backspaceScript(self: *Editor) void {
        if (!self.editing_script or self.script_cursor == 0) return;

        const cursor = @min(self.script_cursor, self.script_source.items.len);
        if (cursor == 0) return;

        std.mem.copyForwards(
            u8,
            self.script_source.items[cursor - 1 .. self.script_source.items.len - 1],
            self.script_source.items[cursor..],
        );
        self.script_source.items.len -= 1;
        self.script_cursor = cursor - 1;
        self.script_dirty = true;
        self.ensureScriptCursorVisible(self.scriptVisibleLines());
    }

    pub fn deleteScriptCharacter(self: *Editor) void {
        if (!self.editing_script) return;

        const cursor = @min(self.script_cursor, self.script_source.items.len);
        if (cursor >= self.script_source.items.len) return;

        std.mem.copyForwards(
            u8,
            self.script_source.items[cursor .. self.script_source.items.len - 1],
            self.script_source.items[cursor + 1 ..],
        );
        self.script_source.items.len -= 1;
        self.script_dirty = true;
        self.ensureScriptCursorVisible(self.scriptVisibleLines());
    }

    pub fn toggleSelectedVisibility(self: *Editor) !void {
        const node_id = self.selected_node orelse return;
        const node = try self.scene.getConst(node_id);
        try self.scene.setVisible(node_id, !node.visible);
    }

    /// Associates the editor with a project and loads its primary source file.
    /// Projects without `src/main.zig` start with the default script template.
    pub fn openProject(self: *Editor, io: std.Io, path: []const u8) !void {
        const source_path = try std.fs.path.join(
            self.allocator,
            &.{ path, "src", "main.zig" },
        );
        defer self.allocator.free(source_path);

        const source = std.Io.Dir.cwd().readFileAlloc(
            io,
            source_path,
            self.allocator,
            .limited(1024 * 1024),
        ) catch |err| switch (err) {
            error.FileNotFound => try self.allocator.dupe(u8, default_script),
            else => return err,
        };
        defer self.allocator.free(source);

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);
        const owned_script_path = try self.allocator.dupe(u8, source_path);
        errdefer self.allocator.free(owned_script_path);

        self.script_source.clearRetainingCapacity();
        try self.script_source.appendSlice(self.allocator, source);
        self.script_cursor = self.script_source.items.len;
        self.script_scroll_line = 0;
        self.script_scroll_column = 0;

        if (self.project_path) |old_path| self.allocator.free(old_path);
        self.project_path = owned_path;
        if (self.script_file_path) |old_path| self.allocator.free(old_path);
        self.script_file_path = owned_script_path;
        self.script_is_primary = true;
        self.script_dirty = false;
        self.editing_script = false;
        self.scanAssets(io);

        const loaded = self.loadScene(io) catch |err| blk: {
            std.debug.print("Could not load scene: {s}\n", .{@errorName(err)});
            break :blk false;
        };
        if (!loaded) {
            // Every project starts with the same scene visible in the editor.
            // Persist it immediately so the editor and the generated project
            // never disagree about the starting scene.
            try self.saveScene(io);
        }
    }

    /// Saves the script currently shown in the editor to its asset path.
    pub fn saveScript(self: *Editor, io: std.Io) !void {
        _ = self.project_path orelse return error.NoActiveProject;
        const source_path = self.script_file_path orelse return error.NoScriptFile;

        const file = try std.Io.Dir.cwd().createFile(io, source_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, self.script_source.items);
        self.script_dirty = false;
    }

    fn appendZigString(list: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
        try list.append(allocator, '"');
        for (value) |character| {
            switch (character) {
                '\\' => try list.appendSlice(allocator, "\\\\"),
                '"' => try list.appendSlice(allocator, "\\\""),
                '\n' => try list.appendSlice(allocator, "\\n"),
                '\r' => try list.appendSlice(allocator, "\\r"),
                '\t' => try list.appendSlice(allocator, "\\t"),
                else => try list.append(allocator, character),
            }
        }
        try list.append(allocator, '"');
    }

    fn appendSceneScript(self: *Editor, list: *std.ArrayList(u8)) !void {
        const allocator = self.allocator;
        try list.appendSlice(allocator, scene_script_begin);
        try list.appendSlice(allocator, "pub const ZigineSceneKind = enum { node, node_2d, sprite_2d, camera_2d };\n" ++
            "pub const ZigineSceneVec2 = struct { x: f32, y: f32 };\n" ++
            "pub const ZigineSceneNode = struct {\n" ++
            "    name: []const u8,\n" ++
            "    kind: ZigineSceneKind,\n" ++
            "    parent: i32,\n" ++
            "    visible: bool,\n" ++
            "    position: ZigineSceneVec2,\n" ++
            "    rotation: f32,\n" ++
            "    scale: ZigineSceneVec2,\n" ++
            "    texture_path: []const u8,\n" ++
            "};\n" ++
            "pub const zigine_scene = [_]ZigineSceneNode{\n");

        for (0..self.tree.nodeCount()) |index| {
            const node_id = self.tree.nodeAt(index) orelse continue;
            const node = try self.scene.getConst(node_id);
            const global = try self.scene.globalTransform(node_id);
            const global_scale_x = @sqrt(global.a * global.a + global.b * global.b);
            const global_scale_y = @sqrt(global.c * global.c + global.d * global.d);
            const global_rotation = std.math.atan2(global.b, global.a);

            var parent_index: isize = -1;
            if (node.parent) |parent| {
                for (0..index) |candidate_index| {
                    const candidate = self.tree.nodeAt(candidate_index) orelse continue;
                    if (candidate.eql(parent)) {
                        parent_index = @intCast(candidate_index);
                        break;
                    }
                }
            }

            try list.appendSlice(allocator, "    .{ .name = ");
            try appendZigString(list, allocator, node.name);
            try list.appendSlice(allocator, ", .kind = .");
            try list.appendSlice(allocator, nodeKindText(node.kind));
            try list.appendSlice(allocator, ", .parent = ");
            try list.print(allocator, "{d}", .{parent_index});
            try list.appendSlice(allocator, ", .visible = ");
            try list.appendSlice(allocator, if (node.visible) "true" else "false");
            try list.appendSlice(allocator, ", .position = .{ .x = ");
            try list.print(allocator, "{d}", .{global.tx});
            try list.appendSlice(allocator, ", .y = ");
            try list.print(allocator, "{d}", .{global.ty});
            try list.appendSlice(allocator, " }, .rotation = ");
            try list.print(allocator, "{d}", .{global_rotation});
            try list.appendSlice(allocator, ", .scale = .{ .x = ");
            try list.print(allocator, "{d}", .{global_scale_x});
            try list.appendSlice(allocator, ", .y = ");
            try list.print(allocator, "{d}", .{global_scale_y});
            try list.appendSlice(allocator, " }, .texture_path = ");
            try appendZigString(list, allocator, node.texture_path orelse "");
            try list.appendSlice(allocator, " },\n");
        }

        try list.appendSlice(allocator, "};\n");
        try list.appendSlice(allocator, "pub fn zigine_scene_render(surface: anytype) !void {\n" ++
            "    const origin_x: f32 = @as(f32, @floatFromInt(surface.getWidth())) * 0.5;\n" ++
            "    const origin_y: f32 = @as(f32, @floatFromInt(surface.getHeight())) * 0.5;\n" ++
            "    for (zigine_scene) |node| {\n" ++
            "        if (!node.visible) continue;\n" ++
            "        if (node.kind != .sprite_2d) continue;\n" ++
            "        const base_size: f32 = switch (node.kind) {\n" ++
            "            .sprite_2d => 48.0,\n" ++
            "            .camera_2d => 160.0,\n" ++
            "            .node_2d => 32.0,\n" ++
            "            .node => 24.0,\n" ++
            "        };\n" ++
            "        const width: i32 = @intFromFloat(@max(2.0, base_size * node.scale.x));\n" ++
            "        const height: i32 = @intFromFloat(@max(2.0, base_size * node.scale.y));\n" ++
            "        const x: i32 = @intFromFloat(origin_x + node.position.x - @as(f32, @floatFromInt(width)) * 0.5);\n" ++
            "        const y: i32 = @intFromFloat(origin_y + node.position.y - @as(f32, @floatFromInt(height)) * 0.5);\n" ++
            "        const color = switch (node.kind) {\n" ++
            "            .sprite_2d => surface.mapRgb(90, 170, 255),\n" ++
            "            .camera_2d => surface.mapRgb(255, 190, 80),\n" ++
            "            .node_2d => surface.mapRgb(170, 110, 255),\n" ++
            "            .node => surface.mapRgb(150, 150, 150),\n" ++
            "        };\n" ++
            "        try surface.fillRect(.{ .x = x, .y = y, .w = width, .h = height }, color);\n" ++
            "    }\n" ++
            "}\n");
        try list.appendSlice(allocator, "pub fn zigine_scene_tick(surface: anytype) !void {\n" ++
            "    try zigine_scene_render(surface);\n" ++
            "}\n");
        try list.appendSlice(allocator, scene_script_end);
    }

    fn syncSceneToScript(self: *Editor, io: std.Io) !void {
        const allocator = self.allocator;
        var generated = std.ArrayList(u8).empty;
        defer generated.deinit(allocator);
        try self.appendSceneScript(&generated);

        const source = self.script_source.items;
        var updated = std.ArrayList(u8).empty;
        defer updated.deinit(allocator);

        if (std.mem.indexOf(u8, source, scene_script_begin)) |begin| {
            const end_start = begin + scene_script_begin.len;
            const end = std.mem.indexOfPos(u8, source, end_start, scene_script_end) orelse return error.InvalidSceneScriptBlock;
            try updated.appendSlice(allocator, source[0..begin]);
            try updated.appendSlice(allocator, generated.items);
            try updated.appendSlice(allocator, source[end + scene_script_end.len ..]);
        } else {
            try updated.appendSlice(allocator, source);
            if (updated.items.len > 0 and updated.items[updated.items.len - 1] != '\n') {
                try updated.append(allocator, '\n');
            }
            try updated.append(allocator, '\n');
            try updated.appendSlice(allocator, generated.items);
        }

        const old_tick_call = "        zigine_scene_tick();\n";
        if (std.mem.indexOf(u8, updated.items, old_tick_call) != null) {
            var normalized = std.ArrayList(u8).empty;
            defer normalized.deinit(allocator);
            var cursor: usize = 0;
            while (std.mem.indexOfPos(u8, updated.items, cursor, old_tick_call)) |old_call| {
                try normalized.appendSlice(allocator, updated.items[cursor..old_call]);
                cursor = old_call + old_tick_call.len;
            }
            try normalized.appendSlice(allocator, updated.items[cursor..]);
            updated.clearRetainingCapacity();
            try updated.appendSlice(allocator, normalized.items);
        }

        if (std.mem.indexOf(u8, updated.items, "zigine_scene_tick(surface);") == null) {
            if (std.mem.indexOf(u8, updated.items, "const surface = try window.getSurface();")) |surface_start| {
                const background_start = std.mem.indexOfPos(u8, updated.items, surface_start, "try surface.fillRect") orelse surface_start;
                const insert_at = (std.mem.indexOfPos(u8, updated.items, background_start, ";") orelse background_start) + 1;
                var with_tick = std.ArrayList(u8).empty;
                defer with_tick.deinit(allocator);
                try with_tick.appendSlice(allocator, updated.items[0..insert_at]);
                try with_tick.append(allocator, '\n');
                try with_tick.appendSlice(allocator, scene_render_call);
                try with_tick.appendSlice(allocator, updated.items[insert_at..]);
                updated.clearRetainingCapacity();
                try updated.appendSlice(allocator, with_tick.items);
            }
        }

        self.script_source.clearRetainingCapacity();
        try self.script_source.appendSlice(allocator, updated.items);

        const project_path = self.project_path orelse return error.NoActiveProject;
        const source_path = try std.fs.path.join(allocator, &.{ project_path, "src", "main.zig" });
        defer allocator.free(source_path);
        const file = try std.Io.Dir.cwd().createFile(io, source_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, self.script_source.items);
        self.script_dirty = false;
    }

    pub fn takeSaveRequested(self: *Editor) bool {
        const requested = self.save_requested;
        self.save_requested = false;
        return requested;
    }

    pub fn takeRunRequested(self: *Editor) bool {
        const requested = self.run_requested;
        self.run_requested = false;
        return requested;
    }

    pub fn takeExitRequested(self: *Editor) bool {
        const requested = self.exit_requested;
        self.exit_requested = false;
        return requested;
    }

    /// Runs the active project's configured `run` step from the editor.
    /// The child inherits the terminal, so SDL/raylib diagnostics remain
    /// usable instead of disappearing into the editor process.
    pub fn runProject(self: *Editor, io: std.Io) !void {
        const project_path = self.project_path orelse return error.NoActiveProject;
        var dir = try std.Io.Dir.cwd().openDir(io, project_path, .{});
        defer dir.close(io);
        var child = try std.process.spawn(io, .{
            .argv = &.{ "zig", "build", "run" },
            .cwd = .{ .dir = dir },
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });
        const result = try child.wait(io);
        switch (result) {
            .exited => |code| if (code != 0) return error.ProjectRunFailed,
            else => return error.ProjectRunFailed,
        }
    }

    fn sceneFilePath(self: *const Editor) ![]u8 {
        const project_path = self.project_path orelse return error.NoActiveProject;
        return std.fs.path.join(
            self.allocator,
            &.{ project_path, scene_directory_name, scene_file_name },
        );
    }

    fn nodeKindText(kind: NodeKind) []const u8 {
        return switch (kind) {
            .node => "node",
            .node_2d => "node_2d",
            .sprite_2d => "sprite_2d",
            .camera_2d => "camera_2d",
        };
    }

    fn parseNodeKind(value: []const u8) ?NodeKind {
        if (std.mem.eql(u8, value, "node")) return .node;
        if (std.mem.eql(u8, value, "node_2d")) return .node_2d;
        if (std.mem.eql(u8, value, "sprite_2d")) return .sprite_2d;
        if (std.mem.eql(u8, value, "camera_2d")) return .camera_2d;
        return null;
    }

    /// Writes the active scene in a compact line-oriented format. The format
    /// intentionally keeps scene files reviewable in source control.
    pub fn saveScene(self: *Editor, io: std.Io) !void {
        const scene_path = try self.sceneFilePath();
        defer self.allocator.free(scene_path);

        const project_path = self.project_path orelse return error.NoActiveProject;
        const scene_dir = try std.fs.path.join(
            self.allocator,
            &.{ project_path, scene_directory_name },
        );
        defer self.allocator.free(scene_dir);

        var directory = try std.Io.Dir.cwd().createDirPathOpen(io, scene_dir, .{});
        directory.close(io);

        const file = try std.Io.Dir.cwd().createFile(io, scene_path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, "ZIGINE_SCENE_V1\n");

        for (0..self.tree.nodeCount()) |index| {
            const node_id = self.tree.nodeAt(index) orelse continue;
            const node = try self.scene.getConst(node_id);

            if (std.mem.indexOfAny(u8, node.name, "\n\r" ++ &[_]u8{scene_field_separator}) != null) {
                return error.UnsupportedSceneText;
            }

            const texture_path = node.texture_path orelse "";
            if (std.mem.indexOfAny(u8, texture_path, "\n\r" ++ &[_]u8{scene_field_separator}) != null) {
                return error.UnsupportedSceneText;
            }

            var parent_index: isize = -1;
            if (node.parent) |parent| {
                for (0..index) |candidate_index| {
                    const candidate = self.tree.nodeAt(candidate_index) orelse continue;
                    if (candidate.eql(parent)) {
                        parent_index = @intCast(candidate_index);
                        break;
                    }
                }
                if (parent_index < 0) return error.InvalidSceneHierarchy;
            }

            const line = try std.fmt.allocPrint(
                self.allocator,
                "{s}\x1f{d}\x1f{d}\x1f{d}\x1f{d}\x1f{d}\x1f{d}\x1f{d}\x1f{s}\x1f{s}\n",
                .{
                    nodeKindText(node.kind),
                    parent_index,
                    @intFromBool(node.visible),
                    node.transform.position.x,
                    node.transform.position.y,
                    node.transform.rotation,
                    node.transform.scale.x,
                    node.transform.scale.y,
                    node.name,
                    texture_path,
                },
            );
            defer self.allocator.free(line);
            try file.writeStreamingAll(io, line);
        }

        if (self.script_is_primary) {
            try self.syncSceneToScript(io);
        }
    }

    /// Restores the scene saved by `saveScene`. A missing scene file leaves
    /// the starter scene intact and is not an error.
    pub fn loadScene(self: *Editor, io: std.Io) !bool {
        const scene_path = try self.sceneFilePath();
        defer self.allocator.free(scene_path);

        const contents = std.Io.Dir.cwd().readFileAlloc(
            io,
            scene_path,
            self.allocator,
            .limited(512 * 1024),
        ) catch |err| switch (err) {
            error.FileNotFound => return false,
            else => return err,
        };
        defer self.allocator.free(contents);

        var lines = std.mem.splitScalar(u8, contents, '\n');
        const header = lines.next() orelse return error.InvalidSceneFile;
        if (!std.mem.eql(u8, header, "ZIGINE_SCENE_V1")) return error.InvalidSceneFile;

        const replacement = try self.allocator.create(Scene);
        errdefer self.allocator.destroy(replacement);
        replacement.* = try Scene.init(self.allocator, "MainScene");
        errdefer replacement.deinit();

        var created = std.ArrayList(NodeId).empty;
        defer created.deinit(self.allocator);

        var root: ?NodeId = null;
        while (lines.next()) |line| {
            if (line.len == 0) continue;

            var fields = std.mem.splitScalar(u8, line, scene_field_separator);
            const kind = parseNodeKind(fields.next() orelse return error.InvalidSceneFile) orelse
                return error.InvalidSceneFile;
            const parent_index = try std.fmt.parseInt(isize, fields.next() orelse return error.InvalidSceneFile, 10);
            const visible_number = try std.fmt.parseInt(u8, fields.next() orelse return error.InvalidSceneFile, 10);
            const position_x = try std.fmt.parseFloat(f32, fields.next() orelse return error.InvalidSceneFile);
            const position_y = try std.fmt.parseFloat(f32, fields.next() orelse return error.InvalidSceneFile);
            const rotation = try std.fmt.parseFloat(f32, fields.next() orelse return error.InvalidSceneFile);
            const scale_x = try std.fmt.parseFloat(f32, fields.next() orelse return error.InvalidSceneFile);
            const scale_y = try std.fmt.parseFloat(f32, fields.next() orelse return error.InvalidSceneFile);
            const name = fields.next() orelse return error.InvalidSceneFile;
            const texture_path = fields.next() orelse return error.InvalidSceneFile;
            if (fields.next() != null or name.len == 0 or visible_number > 1) return error.InvalidSceneFile;

            const parent: ?NodeId = if (parent_index < 0)
                null
            else blk: {
                const parent_usize: usize = @intCast(parent_index);
                if (parent_usize >= created.items.len) return error.InvalidSceneHierarchy;
                break :blk created.items[parent_usize];
            };
            if (parent == null and root != null) return error.InvalidSceneHierarchy;

            const node_id = try replacement.createNode(parent, name, kind);
            try replacement.setTransform(node_id, .{
                .position = .{ .x = position_x, .y = position_y },
                .rotation = rotation,
                .scale = .{ .x = scale_x, .y = scale_y },
            });
            try replacement.setVisible(node_id, visible_number == 1);
            try replacement.setTexturePath(node_id, texture_path);
            try created.append(self.allocator, node_id);
            if (parent == null) root = node_id;
        }

        const replacement_root = root orelse return error.InvalidSceneFile;
        var replacement_tree = SceneTree.init(self.allocator, replacement);
        errdefer replacement_tree.deinit();
        try replacement_tree.setRoot(replacement_root);
        try replacement_tree.enterTree();

        self.tree.deinit();
        self.scene.deinit();
        self.allocator.destroy(self.scene);
        self.scene = replacement;
        self.tree = replacement_tree;
        self.root_node = replacement_root;
        self.selected_node = replacement_root;
        self.next_node_name = self.tree.nodeCount();
        return true;
    }

    pub fn createNode(self: *Editor) !void {
        try self.createNodeKind(.node_2d);
    }

    pub fn createNodeKind(self: *Editor, kind: NodeKind) !void {
        const world = self.camera.position;
        try self.createNodeKindAt(kind, .{ .x = world.x, .y = world.y });
    }

    pub fn createNodeKindAt(self: *Editor, kind: NodeKind, world: renderer_mod.Vec2) !void {
        var parent = self.root_node;

        if (self.selected_node) |selected| {
            if (self.scene.contains(selected)) {
                parent = selected;
            }
        }

        const name = try std.fmt.allocPrint(
            self.allocator,
            "Node_{d}",
            .{self.next_node_name},
        );
        defer self.allocator.free(name);

        const created = try self.scene.createNode(parent, name, kind);
        const parent_global = try self.scene.globalTransform(parent);
        const local = parent_global.inverseTransformPoint(.{ .x = world.x, .y = world.y }) orelse
            scene_mod.Vec2{ .x = world.x, .y = world.y };
        try self.scene.setTransform(created, .{ .position = local });
        self.next_node_name += 1;

        try self.tree.refresh();
        self.selected_node = created;
        self.active_panel = .scene;
    }

    pub fn deleteSelectedNode(self: *Editor) !void {
        const selected = self.selected_node orelse return;
        if (selected.eql(self.root_node)) return;

        if (!self.scene.contains(selected)) {
            self.selected_node = self.root_node;
            return;
        }

        try self.scene.removeNode(selected);
        try self.tree.refresh();

        self.selected_node = self.root_node;
        self.cancelInspectorEdit();
        self.cancelRename();
        self.dragging_node = null;
    }

    pub fn duplicateSelectedNode(self: *Editor) !void {
        const selected = self.selected_node orelse return;
        if (selected.eql(self.root_node)) return;
        if (!self.scene.contains(selected)) return;

        const original = try self.scene.getConst(selected);
        const parent = original.parent orelse return;

        const duplicate = try self.duplicateSubtree(selected, parent);
        try self.tree.refresh();
        self.selected_node = duplicate;
    }

    fn duplicateSubtree(
        self: *Editor,
        source_id: NodeId,
        destination_parent: NodeId,
    ) anyerror!NodeId {
        const source = try self.scene.getConst(source_id);

        const source_name = try self.allocator.dupe(u8, source.name);
        defer self.allocator.free(source_name);

        const kind = source.kind;
        const transform = source.transform;
        const visible = source.visible;

        const texture_copy: ?[]u8 = if (source.texture_path) |path|
            try self.allocator.dupe(u8, path)
        else
            null;

        errdefer if (texture_copy) |path| self.allocator.free(path);

        const new_name = try std.fmt.allocPrint(
            self.allocator,
            "{s}_copy",
            .{source_name},
        );
        defer self.allocator.free(new_name);

        const new_id = try self.scene.createNode(
            destination_parent,
            new_name,
            kind,
        );

        const new_node = try self.scene.get(new_id);
        new_node.transform = transform;
        new_node.visible = visible;
        new_node.texture_path = texture_copy;

        const child_count = try self.scene.childCount(source_id);
        for (0..child_count) |index| {
            const child_id = (try self.scene.childAt(source_id, index)) orelse continue;
            _ = try self.duplicateSubtree(child_id, new_id);
        }

        return new_id;
    }

    /// SDL button values: left = 1, middle = 2, right = 3.
    pub fn viewportMouseDown(
        self: *Editor,
        position: ui.Vec2,
        button: u8,
    ) void {
        if (self.isRenaming() or self.isEditingInspector() or self.picker_open) return;
        if (!containsPoint(self.viewport_rect, position)) return;

        self.mouse_down_position = position;
        self.last_mouse_position = position;

        if (button == 2 or button == 3) {
            self.panning_camera = true;
            self.dragging_node = null;
            return;
        }

        if (button != 1) return;

        self.panning_camera = false;

        const world = self.camera.screenToWorld(.{
            .x = position.x,
            .y = position.y,
        });

        if (self.hitTestScene(world)) |node_id| {
            self.selected_node = node_id;
            self.dragging_node = node_id;

            if (self.scene.getConst(node_id)) |node| {
                self.drag_start_position = node.transform.position;
                self.drag_start_world = world;
            } else |_| {
                self.dragging_node = null;
            }
        } else {
            self.selected_node = null;
            self.dragging_node = null;
        }
    }

    pub fn viewportMouseMove(
        self: *Editor,
        position: ui.Vec2,
    ) !void {
        if (self.panning_camera) {
            const zoom = @max(self.camera.zoom, 0.001);
            const dx = position.x - self.last_mouse_position.x;
            const dy = position.y - self.last_mouse_position.y;

            self.camera.position.x -= dx / zoom;
            self.camera.position.y -= dy / zoom;

            self.last_mouse_position = position;
            return;
        }

        self.last_mouse_position = position;

        if (self.asset_drag_index != null and !self.asset_dragging) {
            const dx = position.x - self.asset_drag_origin.x;
            const dy = position.y - self.asset_drag_origin.y;
            if (dx * dx + dy * dy >= 36) {
                self.asset_dragging = true;
            }
        }

        const dragging = self.dragging_node orelse return;
        if (!self.scene.contains(dragging)) {
            self.dragging_node = null;
            return;
        }

        const node_for_bounds = try self.scene.getConst(dragging);
        const global_for_bounds = try self.scene.globalTransform(dragging);
        const scale_x = @sqrt(global_for_bounds.a * global_for_bounds.a + global_for_bounds.b * global_for_bounds.b);
        const scale_y = @sqrt(global_for_bounds.c * global_for_bounds.c + global_for_bounds.d * global_for_bounds.d);
        const base_size: f32 = switch (node_for_bounds.kind) {
            .sprite_2d => 48.0,
            .camera_2d => 160.0,
            .node_2d => 32.0,
            .node => 24.0,
        };
        const half_width = @max(0.0, base_size * scale_x * 0.5 * self.camera.zoom);
        const half_height = @max(
            0.0,
            (if (node_for_bounds.kind == .camera_2d) 90.0 else base_size) * scale_y * 0.5 * self.camera.zoom,
        );
        const min_x = self.viewport_rect.x + @min(half_width, self.viewport_rect.width * 0.5);
        const max_x = self.viewport_rect.x + self.viewport_rect.width - @min(half_width, self.viewport_rect.width * 0.5);
        const min_y = self.viewport_rect.y + @min(half_height, self.viewport_rect.height * 0.5);
        const max_y = self.viewport_rect.y + self.viewport_rect.height - @min(half_height, self.viewport_rect.height * 0.5);
        const clamped_position = ui.Vec2{
            .x = @max(min_x, @min(max_x, position.x)),
            .y = @max(min_y, @min(max_y, position.y)),
        };

        const world = self.camera.screenToWorld(.{
            .x = clamped_position.x,
            .y = clamped_position.y,
        });

        const dx = world.x - self.drag_start_world.x;
        const dy = world.y - self.drag_start_world.y;

        const node = try self.scene.getConst(dragging);
        var transform = node.transform;

        const local_delta = try self.worldDeltaToParentLocal(
            node.parent,
            .{ .x = dx, .y = dy },
        );

        var new_x = self.drag_start_position.x + local_delta.x;
        var new_y = self.drag_start_position.y + local_delta.y;

        if (self.snap_to_grid) {
            const grid_snap: f32 = 16.0;
            new_x = @round(new_x / grid_snap) * grid_snap;
            new_y = @round(new_y / grid_snap) * grid_snap;
        }

        transform.position = .{
            .x = new_x,
            .y = new_y,
        };

        try self.scene.setTransform(dragging, transform);
    }

    pub fn viewportMouseUp(self: *Editor, button: u8) void {
        if (button == 1) self.dragging_node = null;
        if (button == 2 or button == 3) self.panning_camera = false;
        if (button == 1) self.finishAssetDrag();
    }

    pub fn viewportMouseUpAt(self: *Editor, position: ui.Vec2, button: u8) void {
        self.last_mouse_position = position;
        self.viewportMouseUp(button);
    }

    pub fn takeAssetOpenRequested(self: *Editor) ?usize {
        const requested = self.asset_open_requested;
        self.asset_open_requested = null;
        return requested;
    }

    pub fn openScriptAsset(self: *Editor, io: std.Io, index: usize) !void {
        if (index >= self.asset_count) return error.InvalidAsset;
        const item = &self.asset_items[index];
        if (!item.is_script) return error.UnsupportedAsset;

        const project_path = self.project_path orelse return error.NoActiveProject;
        const relative_path = item.name[0..item.name_len];
        const full_path = try std.fs.path.join(
            self.allocator,
            &.{ project_path, relative_path },
        );
        defer self.allocator.free(full_path);

        const source = try std.Io.Dir.cwd().readFileAlloc(
            io,
            full_path,
            self.allocator,
            .limited(1024 * 1024),
        );
        defer self.allocator.free(source);

        const owned_path = try self.allocator.dupe(u8, full_path);
        errdefer self.allocator.free(owned_path);
        self.script_source.clearRetainingCapacity();
        try self.script_source.appendSlice(self.allocator, source);
        self.script_cursor = 0;
        self.script_scroll_line = 0;
        self.script_scroll_column = 0;
        self.script_dirty = false;
        self.editing_script = true;
        self.active_panel = .script;
        if (self.script_file_path) |old_path| self.allocator.free(old_path);
        self.script_file_path = owned_path;
        self.script_is_primary = false;
        self.logMsg(relative_path);
    }

    fn finishAssetDrag(self: *Editor) void {
        const index = self.asset_drag_index orelse return;
        self.asset_drag_index = null;
        const was_dragging = self.asset_dragging;
        self.asset_dragging = false;
        if (!was_dragging) return;
        if (!containsPoint(self.viewport_rect, self.last_mouse_position)) return;
        if (index >= self.asset_count) return;
        const item = &self.asset_items[index];
        if (!item.is_texture) return;
        self.createNodeKindAt(.sprite_2d, self.camera.screenToWorld(.{
            .x = self.last_mouse_position.x,
            .y = self.last_mouse_position.y,
        })) catch |err| {
            self.logMsg(@errorName(err));
            return;
        };
        if (self.selected_node) |node| {
            self.scene.setTexturePath(node, item.name[0..item.name_len]) catch {};
        }
        self.logMsg("Dropped Sprite2D into viewport");
    }

    pub fn viewportMouseWheel(
        self: *Editor,
        position: ui.Vec2,
        delta: f32,
    ) void {
        if (self.isRenaming() or self.isEditingInspector() or self.picker_open) return;
        if (!containsPoint(self.viewport_rect, position)) return;
        if (!finite(delta) or delta == 0) return;

        const old_zoom = @max(self.camera.zoom, 0.001);
        const world_before = self.camera.screenToWorld(.{
            .x = position.x,
            .y = position.y,
        });

        const zoom_factor = std.math.pow(f32, 1.15, @abs(delta));
        const new_zoom = if (delta > 0)
            @min(old_zoom * zoom_factor, 8.0)
        else
            @max(old_zoom / zoom_factor, 0.1);

        self.camera.zoom = new_zoom;

        const center_x = self.viewport_rect.x + self.viewport_rect.width / 2;
        const center_y = self.viewport_rect.y + self.viewport_rect.height / 2;

        self.camera.position.x = world_before.x -
            (position.x - center_x) / new_zoom;
        self.camera.position.y = world_before.y -
            (position.y - center_y) / new_zoom;
    }

    fn worldDeltaToParentLocal(
        self: *Editor,
        parent_id: ?NodeId,
        delta: scene_mod.Vec2,
    ) !scene_mod.Vec2 {
        const parent = parent_id orelse return delta;
        const global = try self.scene.globalTransform(parent);

        const determinant = global.a * global.d - global.b * global.c;
        if (@abs(determinant) < 0.000001) return delta;

        return .{
            .x = (global.d * delta.x - global.c * delta.y) / determinant,
            .y = (-global.b * delta.x + global.a * delta.y) / determinant,
        };
    }

    fn hitTestScene(self: *Editor, world: renderer_mod.Vec2) ?NodeId {
        var index = self.tree.nodeCount();
        while (index > 0) {
            index -= 1;

            const node_id = self.tree.nodeAt(index) orelse continue;
            const node = self.scene.getConst(node_id) catch continue;

            if (!node.visible) continue;

            const global = self.scene.globalTransform(node_id) catch continue;
            const center = global.transformPoint(.{ .x = 0, .y = 0 });

            const scale_x = @sqrt(global.a * global.a + global.b * global.b);
            const scale_y = @sqrt(global.c * global.c + global.d * global.d);

            const base_size: f32 = switch (node.kind) {
                .sprite_2d => 48.0,
                .camera_2d => 160.0,
                .node_2d => 32.0,
                .node => 24.0,
            };

            const half_width = @max(18.0, base_size * scale_x * 0.5);
            const half_height = @max(18.0, (if (node.kind == .camera_2d) 90.0 else base_size) * scale_y * 0.5);

            if (world.x >= center.x - half_width and
                world.x <= center.x + half_width and
                world.y >= center.y - half_height and
                world.y <= center.y + half_height)
            {
                return node_id;
            }
        }

        return null;
    }

    pub fn handleClick(self: *Editor, position: ui.Vec2) void {
        const id = self.context.hitTest(position) orelse {
            if (containsPoint(self.viewport_rect, position)) {
                self.viewportMouseDown(position, 1);
            }
            return;
        };

        if (self.picker_open) {
            if (id >= picker_first_id and id < picker_first_id + node_kinds.len) {
                self.picker_index = @intCast(id - picker_first_id);
                self.choosePickerSelection() catch |err| {
                    std.debug.print(
                        "Could not create node: {s}\n",
                        .{@errorName(err)},
                    );
                };
            }
            return;
        }

        // A new click is a separate interaction. Never carry an old image
        // drag into a viewport, inspector, or toolbar click.
        if (self.asset_drag_index != null and (id < 4000 or id >= 4320)) {
            self.asset_drag_index = null;
            self.asset_dragging = false;
        }

        if (id >= 4000 and id < 4320) {
            const asset_idx = (id - 4000) / 10;
            if (asset_idx < self.asset_count) {
                const item = &self.asset_items[asset_idx];
                if (item.is_texture) {
                    // A press only arms a drag. The Sprite2D is created only
                    // after the pointer moves and is released in the viewport.
                    self.asset_drag_index = @intCast(asset_idx);
                    self.asset_dragging = false;
                    self.asset_drag_origin = position;
                    self.last_mouse_position = position;
                } else if (item.is_scene) {
                    self.asset_drag_index = null;
                    self.asset_dragging = false;
                    self.load_scene_requested = true;
                } else if (item.is_script) {
                    self.asset_drag_index = null;
                    self.asset_dragging = false;
                    self.asset_open_requested = @intCast(asset_idx);
                }
            }
            return;
        }

        if (id >= 3000 and id < 4000) {
            const node_idx = id - 3000;
            if (node_idx < self.tree.nodeCount()) {
                if (self.tree.nodeAt(node_idx)) |nid| {
                    if (self.scene.getConst(nid)) |n| {
                        self.scene.setVisible(nid, !n.visible) catch {};
                        self.logMsg(if (n.visible) "Hidden node" else "Shown node");
                    } else |_| {}
                }
            }
            return;
        }

        if (id >= tree_first_id and id < picker_first_id) {
            const index: usize = @intCast(id - tree_first_id);

            if (index < self.tree.nodeCount()) {
                if (self.tree.nodeAt(index)) |node_id| {
                    self.selected_node = node_id;
                    self.cancelRename();
                    self.cancelInspectorEdit();
                }
            }
            return;
        }

        switch (id) {
            11 => self.exit_requested = true,
            12 => self.active_panel = .scene,
            13 => self.active_panel = .script,
            14, 61, 62, 63 => self.active_panel = .assets,
            17, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100 => self.focusTerminal(),
            71 => self.active_panel = .inspector,

            16 => self.run_requested = true,
            18 => self.save_requested = true,
            19 => self.resetCamera(),
            123 => {
                self.snap_to_grid = !self.snap_to_grid;
                self.logMsg(if (self.snap_to_grid) "Grid snap: ON (16px)" else "Grid snap: OFF");
            },

            32 => self.openNodePicker(),
            33 => self.beginRenameSelectedNode() catch |err| {
                std.debug.print("Could not begin rename: {s}\n", .{@errorName(err)});
            },
            34 => self.deleteSelectedNode() catch |err| {
                std.debug.print("Could not delete node: {s}\n", .{@errorName(err)});
            },

            120, 125, 620, 625 => self.createNodeKind(.sprite_2d) catch {},
            121, 126, 621, 626 => self.createNodeKind(.node_2d) catch {},
            122, 127, 622, 627 => self.createNodeKind(.camera_2d) catch {},
            128, 628 => self.duplicateSelectedNode() catch {},
            129, 629 => self.reparentSelectedToRoot() catch {},
            65, 565 => self.createNodeKind(.sprite_2d) catch {},

            72 => self.beginRenameSelectedNode() catch {},
            75, 76, 176 => self.beginInspectorEdit(.position) catch |err| {
                std.debug.print("Could not edit position: {s}\n", .{@errorName(err)});
            },
            77, 78, 178 => self.beginInspectorEdit(.rotation) catch |err| {
                std.debug.print("Could not edit rotation: {s}\n", .{@errorName(err)});
            },
            79, 80, 180 => self.beginInspectorEdit(.scale) catch |err| {
                std.debug.print("Could not edit scale: {s}\n", .{@errorName(err)});
            },
            82, 85, 182 => self.beginInspectorEdit(.texture_path) catch |err| {
                std.debug.print("Could not edit texture path: {s}\n", .{@errorName(err)});
            },
            83, 84 => self.toggleSelectedVisibility() catch |err| {
                std.debug.print("Could not toggle visibility: {s}\n", .{@errorName(err)});
            },

            301, 801 => self.nudgeSelected(-10, 0) catch {},
            302, 802 => self.nudgeSelected(10, 0) catch {},
            303, 803 => self.nudgeSelected(0, -10) catch {},
            304, 804 => self.nudgeSelected(0, 10) catch {},
            305, 805 => self.setPositionSelected(0, 0) catch {},

            311, 811 => self.setRotationSelected(0) catch {},
            312, 812 => self.addRotationSelected(-90) catch {},
            313, 813 => self.addRotationSelected(90) catch {},
            314, 814 => self.setRotationSelected(180) catch {},

            // Scale is edited directly through the inspector fields.

            331, 831 => self.clearTextureSelected() catch {},

            341, 841 => self.createNode() catch {},
            342, 842 => self.duplicateSelectedNode() catch {},
            343, 843 => self.deleteSelectedNode() catch {},
            344, 844 => self.reparentSelectedToRoot() catch {},
            345, 845 => self.focusSelected(),

            50, 51 => self.viewportMouseDown(position, 1),
            52 => self.beginScriptEdit(),
            54 => {
                self.beginScriptEdit();
                self.placeScriptCursor(position);
            },

            else => {},
        }
    }

    pub fn build(
        self: *Editor,
        width: f32,
        height: f32,
    ) ![]const DrawCommand {
        const c = &self.context;

        c.beginFrame(.{ .width = width, .height = height });

        try c.begin(1, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
        }, self.palette.background);

        try self.buildHeader();
        try self.buildWorkspace();
        try self.buildOutput();

        c.end();

        return c.endFrame();
    }

    pub fn buildSceneViewport(
        self: *Editor,
        width: f32,
        height: f32,
    ) ![]const renderer_mod.DrawCommand {
        if (self.context.getElementBounds(51)) |b| {
            self.viewport_rect = .{
                .x = b.x,
                .y = b.y,
                .width = b.width,
                .height = b.height,
            };
        } else {
            self.viewport_rect = .{
                .x = 225,
                .y = 105,
                .width = @max(1, width - 489),
                .height = @max(1, height - 371),
            };
        }

        self.camera.viewport = self.viewport_rect;
        self.renderer.clear();

        try self.renderer.drawGrid(
            self.camera,
            32,
            rendererColor(self.palette.grid),
            rendererColor(self.palette.grid_axis),
        );

        try self.scene_renderer.render(
            &self.tree,
            &self.renderer,
            self.camera,
        );

        if (self.selected_node) |selected| {
            if (self.scene.contains(selected)) {
                const node = try self.scene.getConst(selected);
                const global = try self.scene.globalTransform(selected);
                const world = global.transformPoint(.{ .x = 0, .y = 0 });
                const center = self.camera.worldToScreen(.{
                    .x = world.x,
                    .y = world.y,
                });

                const scale_x = @sqrt(global.a * global.a + global.b * global.b);
                const scale_y = @sqrt(global.c * global.c + global.d * global.d);
                const base_size: f32 = switch (node.kind) {
                    .sprite_2d => 48.0,
                    .camera_2d => 160.0,
                    .node_2d => 32.0,
                    .node => 24.0,
                };
                const half_w = @max(16.0, base_size * scale_x * 0.5) * self.camera.zoom;
                const half_h = @max(16.0, (if (node.kind == .camera_2d) 90.0 else base_size) * scale_y * 0.5) * self.camera.zoom;

                const bounds = Rect{
                    .x = center.x - half_w,
                    .y = center.y - half_h,
                    .width = half_w * 2,
                    .height = half_h * 2,
                };

                const color = rendererColor(self.palette.accent);
                try self.renderer.drawRectOutline(bounds, color, 2);

                // Corner handles
                const h_size: f32 = 6;
                const corners = [_]renderer_mod.Vec2{
                    .{ .x = bounds.x, .y = bounds.y },
                    .{ .x = bounds.x + bounds.width, .y = bounds.y },
                    .{ .x = bounds.x + bounds.width, .y = bounds.y + bounds.height },
                    .{ .x = bounds.x, .y = bounds.y + bounds.height },
                };
                for (corners) |corner| {
                    try self.renderer.drawRect(
                        .{ .x = corner.x - h_size / 2, .y = corner.y - h_size / 2, .width = h_size, .height = h_size },
                        color,
                    );
                }

                // Translate gizmo arrows: Red (+X) and Green (+Y)
                try self.renderer.drawArrow(center, .{ .x = center.x + 36, .y = center.y }, renderer_mod.Color{ .r = 255, .g = 60, .b = 60, .a = 255 }, 3);
                try self.renderer.drawArrow(center, .{ .x = center.x, .y = center.y + 36 }, renderer_mod.Color{ .r = 60, .g = 255, .b = 60, .a = 255 }, 3);
                try self.renderer.drawRect(
                    .{ .x = center.x - 3, .y = center.y - 3, .width = 6, .height = 6 },
                    renderer_mod.Color{ .r = 255, .g = 220, .b = 0, .a = 255 },
                );
            }
        }

        return self.renderer.getCommands();
    }

    fn buildHeader(self: *Editor) !void {
        const c = &self.context;

        try c.begin(10, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(44),
            .direction = .left_to_right,
            .padding = Padding.xy(14, 0),
            .gap = 14,
            .align_y = .center,
        }, self.palette.panel);

        try addText(c, 11, "PROJECTS", 78, 18, Sizing.fixed(78), self.palette.accent);
        try addText(c, 12, "SCENE", 55, 18, Sizing.fixed(55), if (self.active_panel == .scene) self.palette.accent else self.palette.text);
        try addText(c, 13, "SCRIPT", 60, 18, Sizing.fixed(60), if (self.active_panel == .script) self.palette.accent else self.palette.muted);
        try addText(c, 14, "ASSETS", 60, 18, Sizing.fixed(60), if (self.active_panel == .assets) self.palette.accent else self.palette.muted);
        try addText(c, 17, "OUTPUT", 60, 18, Sizing.fixed(60), if (self.active_panel == .output) self.palette.accent else self.palette.muted);

        try addText(c, 15, "2D VIEW", 80, 18, Sizing.grow(), self.palette.text);

        try addMiniButton(
            c,
            123,
            if (self.snap_to_grid) "SNAP: ON" else "SNAP: OFF",
            85,
            if (self.snap_to_grid) self.palette.accent else self.palette.background,
            if (self.snap_to_grid) self.palette.background else self.palette.text,
        );

        try addMiniButton(c, 19, "RESET VIEW", 90, self.palette.background, self.palette.text);
        try addMiniButton(c, 18, "SAVE", 60, self.palette.accent, self.palette.background);
        try addMiniButton(c, 16, "RUN", 68, rgb(46, 204, 113), self.palette.background);

        c.end();
    }

    fn buildWorkspace(self: *Editor) !void {
        const c = &self.context;

        try c.begin(20, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .left_to_right,
            .gap = 1,
        }, self.palette.border);

        try self.buildSceneTree();
        try self.buildCenter();
        try self.buildInspector();

        c.end();
    }

    fn buildSceneTree(self: *Editor) !void {
        const c = &self.context;

        try c.begin(30, .{
            .width = Sizing.fixed(220),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .padding = Padding.all(10),
            .gap = 8,
        }, self.palette.panel);

        try addText(c, 31, "SCENE TREE", 190, 18, Sizing.grow(), self.palette.text);

        // Quick add row
        try c.begin(130, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(26),
            .direction = .left_to_right,
            .gap = 4,
            .align_y = .center,
        }, self.palette.panel);
        try addMiniButton(c, 125, "+Sprite", 62, self.palette.background, self.palette.accent);
        try addMiniButton(c, 126, "+Node2D", 62, self.palette.background, self.palette.accent);
        try addMiniButton(c, 127, "+Cam", 56, self.palette.background, self.palette.accent);
        c.end();

        try addText(c, 32, "+ Add Any (Ctrl+A)", 190, 18, Sizing.grow(), self.palette.muted);
        try addText(c, 33, "Rename (F2)", 190, 18, Sizing.grow(), self.palette.muted);
        try addText(c, 34, "Delete (Del)", 190, 18, Sizing.grow(), self.palette.muted);

        if (self.picker_open) {
            try c.begin(36, .{
                .width = Sizing.grow(),
                .height = Sizing.fixed(104),
                .direction = .top_to_bottom,
                .padding = Padding.all(4),
                .gap = 3,
            }, self.palette.background);

            try addText(c, 37, "Choose node type", 160, 18, Sizing.grow(), self.palette.accent);

            for (node_kind_names, 0..) |name, index| {
                try addText(
                    c,
                    picker_first_id + index,
                    name,
                    160,
                    18,
                    Sizing.grow(),
                    if (index == self.picker_index) self.palette.accent else self.palette.text,
                );
            }

            c.end();
        }

        try c.begin(35, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(1),
        }, self.palette.border);
        c.end();

        self.tree_visible_rows = @max(
            @as(usize, 1),
            @as(usize, @intFromFloat(@max(1, 650) / 18)),
        );
        self.tree_scroll = @min(
            self.tree_scroll,
            self.tree.nodeCount() -| self.tree_visible_rows,
        );

        try c.begin(38, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .gap = 0,
        }, self.palette.panel);

        const tree_end = @min(
            self.tree.nodeCount(),
            self.tree_scroll + self.tree_visible_rows + 1,
        );
        for (self.tree_scroll..tree_end) |index| {
            const node_id = self.tree.nodeAt(index) orelse continue;
            const node = self.scene.getConst(node_id) catch continue;

            var depth: usize = 0;
            var parent = node.parent;

            while (parent) |parent_id| {
                depth += 1;
                const parent_node = self.scene.getConst(parent_id) catch break;
                parent = parent_node.parent;
            }

            const indent = @min(depth * 10, 40);
            const available_width: f32 = @floatFromInt(
                @as(i32, 190) - @as(i32, @intCast(indent)),
            );

            const is_selected = if (self.selected_node) |selected|
                selected.eql(node_id)
            else
                false;

            const base_name = if (self.rename_target) |target|
                if (target.eql(node_id)) self.rename_buffer.items else node.name
            else
                node.name;

            const prefix = switch (node.kind) {
                .sprite_2d => "[Spr] ",
                .node_2d => "[2D] ",
                .camera_2d => "[Cam] ",
                .node => "[Nod] ",
            };

            var name_buf: [128]u8 = undefined;
            const displayed_name = std.fmt.bufPrint(
                &name_buf,
                "{s}{s}{s}",
                .{ prefix, base_name, if (node.visible) "" else " (off)" },
            ) catch base_name;

            try addText(
                c,
                tree_first_id + index,
                displayed_name,
                available_width,
                18,
                Sizing.grow(),
                if (is_selected) self.palette.accent else if (!node.visible) self.palette.muted else self.palette.text,
            );
        }

        c.end();

        c.end();
    }

    fn buildCenter(self: *Editor) !void {
        const c = &self.context;

        try c.begin(40, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .gap = 1,
        }, self.palette.border);

        try c.begin(41, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(36),
            .direction = .left_to_right,
            .padding = Padding.xy(12, 0),
            .gap = 12,
            .align_y = .center,
        }, self.palette.panel);

        try addText(c, 42, "2D VIEWPORT", 95, 18, Sizing.fixed(95), self.palette.accent);

        var zoom_buffer: [32]u8 = undefined;
        const zoom_label = try std.fmt.bufPrint(
            &zoom_buffer,
            "ZOOM {d}%",
            .{@as(u32, @intFromFloat(@max(0, self.camera.zoom * 100)))},
        );
        try addText(c, 45, zoom_label, 85, 18, Sizing.fixed(85), self.palette.muted);

        try addMiniButton(c, 19, "Center", 58, self.palette.background, self.palette.text);
        try addMiniButton(
            c,
            123,
            if (self.snap_to_grid) "Grid: 16px" else "Grid: Free",
            82,
            if (self.snap_to_grid) self.palette.accent else self.palette.background,
            if (self.snap_to_grid) self.palette.background else self.palette.text,
        );
        try addText(c, 44, "Pan: Right/Middle Drag | Zoom: Wheel", 250, 18, Sizing.grow(), self.palette.muted);

        c.end();

        try c.begin(50, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .padding = Padding.all(12),
        }, self.palette.panel);

        if (self.active_panel == .script) {
            try c.begin(52, .{
                .width = Sizing.grow(),
                .height = Sizing.grow(),
                .direction = .top_to_bottom,
                .padding = Padding.all(12),
            }, self.palette.background);

            try addText(
                c,
                53,
                if (self.editing_script)
                    "SCRIPT - editing (Ctrl+S saves, Esc to stop)"
                else if (self.script_dirty)
                    "SCRIPT - unsaved changes (Ctrl+S saves)"
                else
                    "SCRIPT - click to edit",
                480,
                18,
                Sizing.fixed(22),
                self.palette.accent,
            );
            try addText(
                c,
                54,
                " ",
                1000,
                1000,
                Sizing.grow(),
                self.palette.text,
            );
        } else {
            try c.begin(51, .{
                .width = Sizing.grow(),
                .height = Sizing.grow(),
                .direction = .top_to_bottom,
                .padding = Padding.all(12),
                .gap = 8,
            }, self.palette.background);
        }

        c.end();
        c.end();

        // Assets panel below viewport
        try c.begin(60, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(160),
            .direction = .top_to_bottom,
            .padding = Padding.xy(10, 6),
            .gap = 6,
        }, self.palette.panel);

        try c.begin(64, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(20),
            .direction = .left_to_right,
            .gap = 12,
            .align_y = .center,
        }, self.palette.panel);
        try addText(c, 61, "PROJECT ASSETS", 120, 18, Sizing.fixed(120), if (self.active_panel == .assets) self.palette.accent else self.palette.text);
        try addText(c, 62, "(Click an asset below to assign texture or spawn node)", 380, 18, Sizing.grow(), self.palette.muted);
        c.end();

        if (self.asset_count > 0) {
            try c.begin(63, .{
                .width = Sizing.grow(),
                .height = Sizing.grow(),
                .direction = .left_to_right,
                .gap = 8,
            }, self.palette.background);

            try c.begin(65, .{
                .width = Sizing.grow(),
                .height = Sizing.grow(),
                .direction = .top_to_bottom,
                .gap = 4,
            }, self.palette.background);

            self.asset_visible_rows = @max(
                @as(usize, 1),
                @as(usize, @intFromFloat(@max(1, 112) / 28)),
            );
            self.asset_scroll = @min(
                self.asset_scroll,
                self.asset_count -| self.asset_visible_rows,
            );
            const asset_end = @min(
                self.asset_count,
                self.asset_scroll + self.asset_visible_rows + 1,
            );

            for (self.asset_scroll..asset_end) |i| {
                const item = &self.asset_items[i];
                const row_id: u64 = 4000 + @as(u64, @intCast(i * 10));
                const name = item.name[0..item.name_len];
                const kind_label = if (item.is_texture)
                    "IMAGE"
                else if (item.is_scene)
                    "SCENE"
                else
                    "SOURCE";

                try c.begin(row_id, .{
                    .width = Sizing.grow(),
                    .height = Sizing.fixed(28),
                    .direction = .left_to_right,
                    .padding = Padding.xy(8, 0),
                    .gap = 12,
                    .align_y = .center,
                }, self.palette.background);
                try addText(
                    c,
                    row_id + 1,
                    kind_label,
                    64,
                    16,
                    Sizing.fixed(64),
                    if (item.is_texture) self.palette.accent else self.palette.muted,
                );
                try addText(
                    c,
                    row_id + 2,
                    name,
                    420,
                    16,
                    Sizing.grow(),
                    self.palette.text,
                );
                c.end();
            }
            c.end();

            const track_height: f32 = 112;
            const max_asset_scroll = self.asset_count -| self.asset_visible_rows;
            const thumb_height = if (self.asset_count > self.asset_visible_rows)
                @max(
                    22,
                    track_height *
                        (@as(f32, @floatFromInt(self.asset_visible_rows)) /
                            @as(f32, @floatFromInt(self.asset_count))),
                )
            else
                track_height;
            const thumb_offset = if (max_asset_scroll > 0)
                (track_height - thumb_height) *
                    (@as(f32, @floatFromInt(self.asset_scroll)) /
                        @as(f32, @floatFromInt(max_asset_scroll)))
            else
                0;

            try c.begin(66, .{
                .width = Sizing.fixed(14),
                .height = Sizing.grow(),
                .direction = .top_to_bottom,
                .padding = .{
                    .top = thumb_offset,
                    .bottom = @max(0, track_height - thumb_offset - thumb_height),
                },
            }, self.palette.background);
            try c.rect(67, .{
                .width = Sizing.grow(),
                .height = Sizing.fixed(thumb_height),
            }, self.palette.accent);
            c.end();
            c.end();
        } else {
            try addText(c, 63, "No supported assets found. Add images or source files to the project, assets/, or src/.", 560, 18, Sizing.grow(), self.palette.muted);
        }

        c.end();
        c.end();
    }

    fn buildInspector(self: *Editor) !void {
        const c = &self.context;

        try c.begin(70, .{
            .width = Sizing.fixed(250),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .padding = Padding.all(10),
            .gap = 8,
        }, self.palette.panel);

        try addText(c, 71, "INSPECTOR", 210, 18, Sizing.grow(), if (self.active_panel == .inspector) self.palette.accent else self.palette.text);

        if (self.selected_node) |selected| {
            const node = self.scene.getConst(selected) catch null;

            if (node) |value| {
                try addText(c, 72, value.name, 210, 18, Sizing.grow(), self.palette.accent);
                try addText(
                    c,
                    73,
                    @tagName(value.kind),
                    210,
                    18,
                    Sizing.grow(),
                    self.palette.muted,
                );

                // Position
                try addText(c, 75, "Position (x, y)", 210, 16, Sizing.grow(), self.palette.muted);
                try self.addInspectorValue(.position, 76, value.transform.position.x, value.transform.position.y);
                try c.begin(201, .{
                    .width = Sizing.grow(),
                    .height = Sizing.fixed(24),
                    .direction = .left_to_right,
                    .gap = 4,
                    .align_y = .center,
                }, self.palette.panel);
                try addMiniButton(c, 301, "< -10", 42, self.palette.background, self.palette.text);
                try addMiniButton(c, 302, "+10 >", 42, self.palette.background, self.palette.text);
                try addMiniButton(c, 303, "^ -10", 42, self.palette.background, self.palette.text);
                try addMiniButton(c, 304, "+10 v", 42, self.palette.background, self.palette.text);
                try addMiniButton(c, 305, "0,0", 38, self.palette.background, self.palette.accent);
                c.end();

                // Rotation
                try addText(c, 77, "Rotation (deg)", 210, 16, Sizing.grow(), self.palette.muted);
                try self.addInspectorValue(.rotation, 78, value.transform.rotation * 180.0 / std.math.pi, 0);
                try c.begin(202, .{
                    .width = Sizing.grow(),
                    .height = Sizing.fixed(24),
                    .direction = .left_to_right,
                    .gap = 4,
                    .align_y = .center,
                }, self.palette.panel);
                try addMiniButton(c, 311, "0 deg", 42, self.palette.background, self.palette.accent);
                try addMiniButton(c, 312, "-90 deg", 52, self.palette.background, self.palette.text);
                try addMiniButton(c, 313, "+90 deg", 52, self.palette.background, self.palette.text);
                try addMiniButton(c, 314, "180 deg", 58, self.palette.background, self.palette.text);
                c.end();

                // Scale
                try addText(c, 79, "Scale (x, y)", 210, 16, Sizing.grow(), self.palette.muted);
                try self.addInspectorValue(.scale, 80, value.transform.scale.x, value.transform.scale.y);
                try c.begin(203, .{
                    .width = Sizing.grow(),
                    .height = Sizing.fixed(24),
                    .direction = .left_to_right,
                    .gap = 4,
                    .align_y = .center,
                }, self.palette.panel);
                c.end();

                // Visibility
                try addText(c, 83, "Visibility", 210, 16, Sizing.grow(), self.palette.muted);
                try addText(
                    c,
                    84,
                    if (value.visible) "VISIBLE (click to hide)" else "HIDDEN (click to show)",
                    220,
                    20,
                    Sizing.grow(),
                    if (value.visible) self.palette.accent else self.palette.muted,
                );

                // Texture
                if (value.kind == .sprite_2d) {
                    try addText(c, 85, "Texture path", 210, 16, Sizing.grow(), self.palette.muted);
                    try self.addInspectorTextValue(
                        .texture_path,
                        82,
                        value.texture_path orelse "<none>",
                    );
                    try addMiniButton(c, 331, "Clear Texture", 100, self.palette.background, self.palette.muted);
                }

                if (self.inspector_error) {
                    try addText(c, 86, "Invalid value", 210, 18, Sizing.grow(), rgb(255, 100, 100));
                }

                // Node actions
                try c.begin(204, .{
                    .width = Sizing.grow(),
                    .height = Sizing.fixed(1),
                }, self.palette.border);
                c.end();

                try c.begin(205, .{
                    .width = Sizing.grow(),
                    .height = Sizing.fixed(24),
                    .direction = .left_to_right,
                    .gap = 4,
                    .align_y = .center,
                }, self.palette.panel);
                try addMiniButton(c, 345, "Focus", 52, self.palette.background, self.palette.accent);
                try addMiniButton(c, 342, "Duplicate", 72, self.palette.background, self.palette.text);
                try addMiniButton(c, 343, "Delete", 56, self.palette.background, rgb(255, 90, 90));
                c.end();

                try addMiniButton(c, 344, "Reparent to Root", 130, self.palette.background, self.palette.muted);
            } else {
                self.selected_node = self.root_node;
            }
        } else {
            try addText(c, 72, "No selection", 210, 18, Sizing.grow(), self.palette.muted);
            try c.begin(73, .{
                .width = Sizing.grow(),
                .height = Sizing.fixed(1),
            }, self.palette.border);
            c.end();
            try addText(c, 74, "NODE PROPERTIES", 210, 18, Sizing.grow(), self.palette.accent);
            try addText(c, 75, "Select a scene node in hierarchy or viewport", 210, 18, Sizing.grow(), self.palette.muted);
        }

        c.end();
    }

    fn addInspectorValue(
        self: *Editor,
        field: InspectorField,
        id: u64,
        x: f32,
        y: f32,
    ) !void {
        var temporary: [128]u8 = undefined;
        const value: []const u8 = if (self.inspector_target == field)
            self.inspector_buffer.items
        else switch (field) {
            .position, .scale => try std.fmt.bufPrint(
                &temporary,
                "{d:.2}, {d:.2}",
                .{ x, y },
            ),
            .rotation => try std.fmt.bufPrint(
                &temporary,
                "{d:.2}",
                .{x},
            ),
            .texture_path => unreachable,
        };

        try self.addInspectorInput(field, id, value);
    }

    fn addInspectorTextValue(
        self: *Editor,
        field: InspectorField,
        id: u64,
        value: []const u8,
    ) !void {
        try self.addInspectorInput(
            field,
            id,
            if (self.inspector_target == field)
                self.inspector_buffer.items
            else
                value,
        );
    }

    /// Draws an Inspector value as a persistent, high-contrast input row.
    /// Values are always visible; focus only changes the row accent color.
    fn addInspectorInput(
        self: *Editor,
        field: InspectorField,
        id: u64,
        value: []const u8,
    ) !void {
        const c = &self.context;
        const focused = self.inspector_target == field;

        try c.begin(id, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(28),
            .direction = .left_to_right,
            .padding = Padding.xy(7, 3),
            .align_y = .center,
        }, if (focused) self.palette.border else self.palette.background);

        try addText(
            c,
            id + 100,
            value,
            220,
            18,
            Sizing.grow(),
            if (focused) self.palette.accent else self.palette.text,
        );

        c.end();
    }

    fn buildOutput(self: *Editor) !void {
        const c = &self.context;
        self.updateTerminalCwd();

        try c.begin(90, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(158),
            .direction = .top_to_bottom,
            .padding = Padding.xy(12, 8),
            .gap = 6,
        }, self.palette.panel);

        try c.begin(91, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(22),
            .direction = .left_to_right,
            .gap = 18,
            .align_y = .center,
        }, self.palette.panel);

        try addText(c, 92, "TERMINAL", 100, 18, Sizing.fixed(100), if (self.active_panel == .output) self.palette.accent else self.palette.text);
        try addText(c, 93, self.terminal_cwd_label[0..self.terminal_cwd_label_len], 260, 18, Sizing.grow(), self.palette.muted);
        try addText(c, 94, "Enter: run | Up/Down: history | Ctrl+L: clear", 350, 18, Sizing.fixed(350), self.palette.muted);

        c.end();

        try c.begin(96, .{
            .width = Sizing.grow(),
            .height = Sizing.grow(),
            .direction = .top_to_bottom,
            .padding = Padding.xy(4, 0),
        }, self.palette.background);
        try addText(c, 97, " ", 1000, 72, Sizing.grow(), self.palette.text);
        c.end();

        try c.begin(98, .{
            .width = Sizing.grow(),
            .height = Sizing.fixed(28),
            .direction = .left_to_right,
            .padding = Padding.xy(6, 3),
            .align_y = .center,
        }, if (self.terminal_active) self.palette.border else self.palette.background);
        try addText(c, 99, " ", 20, 18, Sizing.fixed(20), self.palette.accent);
        try addText(c, 100, " ", 900, 18, Sizing.grow(), self.palette.text);
        c.end();

        c.end();
    }
};

fn containsPoint(rect: Rect, point: ui.Vec2) bool {
    return point.x >= rect.x and
        point.y >= rect.y and
        point.x < rect.x + rect.width and
        point.y < rect.y + rect.height;
}

fn addMiniButton(
    c: *Context,
    id: u64,
    label: []const u8,
    width: f32,
    bg_color: Color,
    text_color: Color,
) !void {
    try c.begin(id, .{
        .width = Sizing.fixed(width),
        .height = Sizing.fixed(24),
        .direction = .left_to_right,
        .padding = Padding.xy(4, 2),
        .align_y = .center,
    }, bg_color);
    try addText(c, id + 500, label, width - 4, 16, Sizing.grow(), text_color);
    c.end();
}

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

test "editor builds a draw-command tree" {
    var editor = try Editor.init();
    defer editor.deinit();

    const commands = try editor.build(1280, 800);

    try std.testing.expect(commands.len > 20);
    try std.testing.expectEqual(@as(u64, 1), commands[0].id);
    try std.testing.expectEqual(@as(usize, 1), editor.scene.nodeCount());
}

test "editor theme updates its palette" {
    var editor = try Editor.init();
    defer editor.deinit();

    editor.setTheme(.dracula);

    try std.testing.expectEqual(Theme.dracula, editor.theme);
    try std.testing.expectEqual(@as(u8, 40), editor.palette.background.r);
    try std.testing.expectEqual(@as(u8, 189), editor.palette.accent.r);
}

test "terminal keeps command history and captured output" {
    var editor = try Editor.init();
    defer editor.deinit();

    editor.focusTerminal();
    editor.appendTerminalText("printf terminal-ok");
    try editor.executeTerminal(std.testing.io);

    var found_output = false;
    for (0..editor.terminal_lines.len) |index| {
        if (std.mem.indexOf(u8, editor.terminal_lines[index][0..editor.terminal_line_lens[index]], "terminal-ok") != null) {
            found_output = true;
            break;
        }
    }
    try std.testing.expect(found_output);
    editor.terminalHistory(-1);
    try std.testing.expectEqualStrings("printf terminal-ok", editor.terminal_input[0..editor.terminal_input_len]);
}

test "terminal captures output from the project working directory" {
    var editor = try Editor.init();
    defer editor.deinit();

    editor.project_path = try editor.allocator.dupe(u8, ".");
    editor.focusTerminal();
    editor.appendTerminalText("printf project-terminal-ok");
    try editor.executeTerminal(std.testing.io);

    var found_output = false;
    for (0..editor.terminal_line_count) |index| {
        if (std.mem.indexOf(u8, editor.terminal_lines[index][0..editor.terminal_line_lens[index]], "project-terminal-ok") != null) {
            found_output = true;
            break;
        }
    }
    try std.testing.expect(found_output);
}

test "closing a project resets editor state" {
    var editor = try Editor.init();
    defer editor.deinit();

    editor.project_path = try editor.allocator.dupe(u8, "temporary-project");
    try editor.createNode();
    try editor.closeProject();

    try std.testing.expect(editor.project_path == null);
    try std.testing.expectEqual(@as(usize, 1), editor.scene.nodeCount());
    try std.testing.expectEqual(editor.root_node, editor.selected_node.?);
    try std.testing.expectEqualStrings(default_script, editor.script_source.items);
}

test "editor can create, rename, and delete a node" {
    var editor = try Editor.init();
    defer editor.deinit();

    try editor.createNode();

    const selected = editor.selected_node orelse return error.TestUnexpectedResult;
    try editor.beginRenameSelectedNode();
    editor.rename_buffer.clearRetainingCapacity();
    try editor.rename_buffer.appendSlice(editor.allocator, "Player");
    try editor.commitRename();

    const node = try editor.scene.getConst(selected);
    try std.testing.expectEqualStrings("Player", node.name);

    try editor.deleteSelectedNode();
    try std.testing.expectEqual(@as(usize, 1), editor.tree.nodeCount());

    editor.selected_node = editor.root_node;
    try editor.deleteSelectedNode();
    try std.testing.expectEqual(@as(usize, 1), editor.tree.nodeCount());
}

test "duplicating a node duplicates its subtree" {
    var editor = try Editor.init();
    defer editor.deinit();

    try editor.createNode();
    const original = editor.selected_node.?;

    try editor.createNode();
    _ = editor.selected_node.?;

    editor.selected_node = original;
    try editor.duplicateSelectedNode();

    const duplicate = editor.selected_node.?;
    try std.testing.expect(!duplicate.eql(original));

    const duplicate_node = try editor.scene.getConst(duplicate);
    try std.testing.expect(duplicate_node.parent.?.eql(editor.root_node));

    try std.testing.expectEqual(@as(usize, 4), editor.scene.nodeCount());
}

test "inspector edits position and rotation" {
    var editor = try Editor.init();
    defer editor.deinit();

    try editor.beginInspectorEdit(.position);
    editor.inspector_buffer.clearRetainingCapacity();
    try editor.inspector_buffer.appendSlice(editor.allocator, "12.5, -4");
    try editor.commitInspectorEdit();

    const node = try editor.scene.getConst(editor.root_node);
    try std.testing.expectEqual(@as(f32, 12.5), node.transform.position.x);
    try std.testing.expectEqual(@as(f32, -4), node.transform.position.y);

    try editor.beginInspectorEdit(.rotation);
    editor.inspector_buffer.clearRetainingCapacity();
    try editor.inspector_buffer.appendSlice(editor.allocator, "90");
    try editor.commitInspectorEdit();

    const updated = try editor.scene.getConst(editor.root_node);
    try std.testing.expectApproxEqAbs(
        std.math.pi / 2.0,
        updated.transform.rotation,
        0.0001,
    );
}
