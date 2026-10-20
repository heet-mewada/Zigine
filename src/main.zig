const sdl3 = @import("sdl3");
const std = @import("std");
const editor_module = @import("editor");
const pm = @import("project-manager-ui");
const project_creation = @import("project_creation");
const directory_picker = @import("directory-picker");
const project_registry = @import("project-registry");
const app_settings = @import("app-settings");
const ui = @import("ui-components");
const render = @import("ui/render_sdl.zig");
const renderer2d = @import("renderer");
const sprite_surface_renderer =
    @import("scene/sprite_surface_renderer.zig");

const window_width: usize = 1280;
const window_height: usize = 800;
const fps: u32 = 60;

const Screen = enum {
    project_manager,
    settings,
    editor,
};

const PickerMode = enum {
    project_parent,
    open_project,
    import_project,
    settings_default_directory,
};

fn renderCommands(
    surface: anytype,
    commands: []const ui.DrawCommand,
) !void {
    for (commands) |command| {
        if (command.color.a == 0) continue;

        const bounds = ui.intersectRects(command.bounds, command.clip_bounds);

        const left: i32 = @intFromFloat(@ceil(bounds.x));
        const top: i32 = @intFromFloat(@ceil(bounds.y));
        const right: i32 = @intFromFloat(@floor(bounds.x + bounds.width));
        const bottom: i32 = @intFromFloat(@floor(bounds.y + bounds.height));

        if (right <= left or bottom <= top) continue;

        switch (command.kind) {
            .container, .rectangle => {
                try surface.fillRect(
                    .{
                        .x = left,
                        .y = top,
                        .w = right - left,
                        .h = bottom - top,
                    },
                    surface.mapRgb(
                        command.color.r,
                        command.color.g,
                        command.color.b,
                    ),
                );
            },
            .text => {
                try render.drawText(
                    surface,
                    command.bounds,
                    command.text,
                    command.color,
                    command.clip_bounds,
                    .{
                        .scale = 2,
                        .wrap = true,
                    },
                );
            },
        }
    }
}

fn renderScriptEditor(surface: anytype, editor: anytype) !void {
    if (editor.active_panel != .script) return;

    // Element 54 is the script's text placeholder. Intersect it with the
    // enclosing script panel (52), because a grow-sized child can otherwise
    // report bounds larger than its parent and let custom-drawn text escape.
    const panel_bounds = editor.context.getElementBounds(52) orelse return;
    const placeholder_bounds = editor.context.getElementBounds(54) orelse return;
    const bounds = ui.intersectRects(placeholder_bounds, panel_bounds);
    if (bounds.width <= 0 or bounds.height <= 0) return;

    const source: []const u8 = editor.script_source.items;
    const line_height: f32 = 18;
    const char_width: f32 = 14;
    const gutter_width: f32 = @min(54, @max(0, bounds.width));
    const visible_lines: usize = @max(
        1,
        @as(usize, @intFromFloat(@max(1, bounds.height) / line_height)),
    );

    // Keep the gutter, source text, and caret inside the same clipped region.
    const gutter = ui.intersectRects(.{
        .x = bounds.x,
        .y = bounds.y,
        .width = gutter_width,
        .height = bounds.height,
    }, bounds);
    const code_clip = ui.intersectRects(.{
        .x = bounds.x + gutter_width,
        .y = bounds.y,
        .width = @max(0, bounds.width - gutter_width),
        .height = bounds.height,
    }, bounds);

    if (gutter.width > 0 and gutter.height > 0) {
        try surface.fillRect(.{
            .x = @intFromFloat(@ceil(gutter.x)),
            .y = @intFromFloat(@ceil(gutter.y)),
            .w = @max(0, @as(i32, @intFromFloat(@floor(gutter.x + gutter.width))) - @as(i32, @intFromFloat(@ceil(gutter.x)))),
            .h = @max(0, @as(i32, @intFromFloat(@floor(gutter.y + gutter.height))) - @as(i32, @intFromFloat(@ceil(gutter.y)))),
        }, surface.mapRgb(
            editor.palette.panel.r,
            editor.palette.panel.g,
            editor.palette.panel.b,
        ));
    }

    var line_start: usize = 0;
    var line_number: usize = 0;
    while (line_number < editor.script_scroll_line and line_start < source.len) : (line_number += 1) {
        while (line_start < source.len and source[line_start] != '\n') : (line_start += 1) {}
        if (line_start < source.len) line_start += 1;
    }

    var visible_index: usize = 0;
    while (visible_index < visible_lines and line_start <= source.len) : (visible_index += 1) {
        var line_end = line_start;
        while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}

        const y = bounds.y + @as(f32, @floatFromInt(visible_index)) * line_height;
        const line_bounds = ui.intersectRects(.{
            .x = bounds.x,
            .y = y,
            .width = bounds.width,
            .height = line_height,
        }, bounds);
        if (line_bounds.height > 0) {
            const line_number_text = try std.fmt.allocPrint(
                editor.allocator,
                "{d}",
                .{editor.script_scroll_line + visible_index + 1},
            );
            defer editor.allocator.free(line_number_text);

            try render.drawText(
                surface,
                .{
                    .x = bounds.x + 6,
                    .y = y,
                    .width = @max(0, gutter_width - 10),
                    .height = line_height,
                },
                line_number_text,
                editor.palette.muted,
                gutter,
                .{ .scale = 2, .wrap = false },
            );

            const line = source[line_start..line_end];
            const trimmed = std.mem.trimStart(u8, line, " \t");
            const color = if (std.mem.startsWith(u8, trimmed, "//"))
                ui.Color{ .r = 130, .g = 170, .b = 130, .a = 255 }
            else
                editor.palette.text;

            try render.drawText(
                surface,
                .{
                    .x = bounds.x + gutter_width - @as(f32, @floatFromInt(editor.script_scroll_column)) * char_width,
                    .y = y,
                    .width = code_clip.width,
                    .height = line_height,
                },
                line,
                color,
                code_clip,
                .{ .scale = 2, .wrap = false },
            );

            // Draw a caret only when the caret itself is within the clipped
            // code viewport. Long lines are clipped horizontally, not wrapped.
            if (editor.editing_script) {
                const cursor = @min(editor.script_cursor, source.len);
                var cursor_line: usize = 0;
                for (source[0..cursor]) |ch| {
                    if (ch == '\n') cursor_line += 1;
                }

                if (cursor_line == editor.script_scroll_line + visible_index) {
                    var current_start = cursor;
                    while (current_start > 0 and source[current_start - 1] != '\n') : (current_start -= 1) {}
                    const column = cursor - current_start;
                    const caret_x = bounds.x + gutter_width +
                        @as(f32, @floatFromInt(column -| editor.script_scroll_column)) * char_width;
                    const caret_y = y + 2;
                    if (caret_x >= code_clip.x and caret_x + 2 <= code_clip.x + code_clip.width and
                        caret_y >= code_clip.y and caret_y + 14 <= code_clip.y + code_clip.height)
                    {
                        try surface.fillRect(.{
                            .x = @intFromFloat(@floor(caret_x)),
                            .y = @intFromFloat(@floor(caret_y)),
                            .w = 2,
                            .h = 14,
                        }, surface.mapRgb(
                            editor.palette.accent.r,
                            editor.palette.accent.g,
                            editor.palette.accent.b,
                        ));
                    }
                }
            }
        }

        if (line_end >= source.len) break;
        line_start = line_end + 1;
    }
}

fn renderTerminal(surface: anytype, editor: anytype) !void {
    if (editor.active_panel != .output) return;
    const output_bounds = editor.context.getElementBounds(96) orelse return;
    const input_bounds = editor.context.getElementBounds(98) orelse return;
    const clip = ui.intersectRects(output_bounds, output_bounds);
    const line_height: f32 = 18;
    const character_width: f32 = 14;
    const visible_lines: usize = @max(1, @as(usize, @intFromFloat(@max(1, clip.height) / line_height)));
    const visible_columns: usize = @max(1, @as(usize, @intFromFloat(@max(1, output_bounds.width) / character_width)));
    const line_count = editor.terminal_line_count;
    const first = if (line_count > visible_lines)
        line_count - visible_lines
    else
        0;

    var rendered: usize = 0;
    var index = first;
    while (index < line_count and rendered < visible_lines) : ({
        index += 1;
        rendered += 1;
    }) {
        const len = editor.terminal_line_lens[index];
        if (len > 0) {
            const rendered_len = @min(len, visible_columns);
            try render.drawText(
                surface,
                .{
                    .x = output_bounds.x,
                    .y = output_bounds.y + @as(f32, @floatFromInt(rendered)) * line_height,
                    .width = output_bounds.width,
                    .height = line_height,
                },
                editor.terminal_lines[index][0..rendered_len],
                editor.palette.text,
                clip,
                .{ .scale = 2, .wrap = false },
            );
        }
    }

    const prompt_clip = ui.intersectRects(input_bounds, input_bounds);
    try render.drawText(surface, input_bounds, "> ", editor.palette.accent, prompt_clip, .{ .scale = 2, .wrap = false });
    const input_x = input_bounds.x + 20;
    try render.drawText(surface, .{
        .x = input_x,
        .y = input_bounds.y,
        .width = @max(0, input_bounds.width - 20),
        .height = input_bounds.height,
    }, editor.terminal_input[0..editor.terminal_input_len], editor.palette.text, prompt_clip, .{ .scale = 2, .wrap = false });

    if (editor.terminal_active) {
        const cursor_x = input_x + @as(f32, @floatFromInt(editor.terminal_cursor)) * 14;
        try surface.fillRect(.{
            .x = @intFromFloat(@floor(cursor_x)),
            .y = @intFromFloat(@floor(input_bounds.y + 2)),
            .w = 2,
            .h = 14,
        }, surface.mapRgb(editor.palette.accent.r, editor.palette.accent.g, editor.palette.accent.b));
    }
}

fn renderSceneCommands(
    surface: anytype,
    commands: []const renderer2d.DrawCommand,
    viewport: renderer2d.Rect,
) !void {
    const clip = sdl3.rect.IRect{
        .x = @intFromFloat(@ceil(viewport.x)),
        .y = @intFromFloat(@ceil(viewport.y)),
        .w = @intFromFloat(@floor(viewport.width)),
        .h = @intFromFloat(@floor(viewport.height)),
    };
    if (clip.w <= 0 or clip.h <= 0) return;

    _ = surface.setClipRect(clip);
    defer _ = surface.setClipRect(null);

    for (commands) |command| {
        switch (command) {
            .rectangle => |rect| {
                if (rect.color.a == 0) continue;
                if (rect.bounds.width <= 0 or rect.bounds.height <= 0) continue;

                const left: i32 = @intFromFloat(@floor(rect.bounds.x));
                const top: i32 = @intFromFloat(@floor(rect.bounds.y));
                const right: i32 = @intFromFloat(
                    @ceil(rect.bounds.x + rect.bounds.width),
                );
                const bottom: i32 = @intFromFloat(
                    @ceil(rect.bounds.y + rect.bounds.height),
                );

                if (right <= left or bottom <= top) continue;

                try surface.fillRect(
                    .{
                        .x = left,
                        .y = top,
                        .w = right - left,
                        .h = bottom - top,
                    },
                    surface.mapRgb(
                        rect.color.r,
                        rect.color.g,
                        rect.color.b,
                    ),
                );
            },
            .line => |line| {
                if (line.color.a == 0) continue;

                const x1: i32 = @intFromFloat(@round(line.from.x));
                const y1: i32 = @intFromFloat(@round(line.from.y));
                const x2: i32 = @intFromFloat(@round(line.to.x));
                const y2: i32 = @intFromFloat(@round(line.to.y));

                const thickness: i32 = @max(
                    1,
                    @as(i32, @intFromFloat(@round(line.thickness))),
                );

                const delta_x = @abs(x2 - x1);
                const delta_y = @abs(y2 - y1);

                const color = surface.mapRgb(
                    line.color.r,
                    line.color.g,
                    line.color.b,
                );

                if (delta_x <= delta_y) {
                    try surface.fillRect(
                        .{
                            .x = x1 - @divTrunc(thickness, 2),
                            .y = @min(y1, y2),
                            .w = thickness,
                            .h = @intCast(@max(1, delta_y)),
                        },
                        color,
                    );
                } else {
                    try surface.fillRect(
                        .{
                            .x = @min(x1, x2),
                            .y = y1 - @divTrunc(thickness, 2),
                            .w = @intCast(@max(1, delta_x)),
                            .h = thickness,
                        },
                        color,
                    );
                }
            },
        }
    }
}

fn expandHomePath(
    allocator: std.mem.Allocator,
    home: []const u8,
    path: []const u8,
) ![]u8 {
    if (std.mem.eql(u8, path, "~")) {
        return allocator.dupe(u8, home);
    }

    if (std.mem.startsWith(u8, path, "~/")) {
        return std.fmt.allocPrint(
            allocator,
            "{s}{s}",
            .{ home, path[1..] },
        );
    }

    return allocator.dupe(u8, path);
}

fn persistRegistry(
    io: std.Io,
    registry: *const project_registry.Registry,
    environ: *const std.process.Environ.Map,
) void {
    registry.save(io, std.heap.page_allocator, environ) catch |err| {
        std.debug.print(
            "Could not save project registry: {s}\n",
            .{@errorName(err)},
        );
    };
}

fn persistSettings(
    io: std.Io,
    settings: *const app_settings.Settings,
    environ: *const std.process.Environ.Map,
) void {
    settings.save(io, std.heap.page_allocator, environ) catch |err| {
        std.debug.print(
            "Could not save settings: {s}\n",
            .{@errorName(err)},
        );
    };
}

fn themeToManager(theme: app_settings.Theme) pm.Theme {
    return switch (theme) {
        .dark => .dark,
        .light => .light,
        .catppuccin_mocha => .catppuccin_mocha,
        .dracula => .dracula,
    };
}

fn themeToEditor(theme: app_settings.Theme) editor_module.Theme {
    return switch (theme) {
        .dark => .dark,
        .light => .light,
        .catppuccin_mocha => .catppuccin_mocha,
        .dracula => .dracula,
    };
}

fn registerProject(
    io: std.Io,
    registry: *project_registry.Registry,
    environ: *const std.process.Environ.Map,
    path: []const u8,
) !void {
    _ = try registry.addInMemory(path);
    persistRegistry(io, registry, environ);
}

fn openRecentProject(
    io: std.Io,
    index: usize,
    registry: *project_registry.Registry,
    environ: *const std.process.Environ.Map,
    screen: *Screen,
    editor: *editor_module.Editor,
) bool {
    const project = registry.get(index) orelse return false;
    var path_copy: [project_registry.max_path_length]u8 = undefined;
    const project_path = project.getPath();
    @memcpy(path_copy[0..project_path.len], project_path);
    const path = path_copy[0..project_path.len];

    std.debug.print(
        "Selected project: {s}\n",
        .{path},
    );

    editor.openProject(io, path) catch |err| {
        std.debug.print("Could not open project: {s}\n", .{@errorName(err)});
        return false;
    };

    // Opening a project makes it the most recently used project. Keep the
    // in-memory order and the persisted registry in sync.
    _ = registry.addInMemory(path) catch |err| {
        std.debug.print("Could not update recent projects: {s}\n", .{@errorName(err)});
        return false;
    };
    persistRegistry(io, registry, environ);

    screen.* = .editor;
    return true;
}

fn handleProjectManagerClick(
    io: std.Io,
    manager: *pm.ProjectManager,
    picker: *directory_picker.Picker,
    home: []const u8,
    position: ui.Vec2,
    screen: *Screen,
    registry: *project_registry.Registry,
    settings: *app_settings.Settings,
    environ: *const std.process.Environ.Map,
    picker_mode: *PickerMode,
    editor: *editor_module.Editor,
) bool {
    const dialog = &manager.dialog;
    const id = manager.context.hitTest(position) orelse return false;

    if (dialog.is_open) {
        switch (id) {
            203, 204 => {
                dialog.active_field = .name;
                dialog.error_message = null;
                return true;
            },
            206, 207 => {
                dialog.active_field = .parent_directory;
                dialog.error_message = null;
                picker_mode.* = .project_parent;
                picker.open(io, home, dialog.getDirectory());
                return true;
            },
            210, 310 => {
                dialog.selected_template = .empty;
                dialog.error_message = null;
                return true;
            },
            220, 320 => {
                dialog.selected_template = .sdl3;
                dialog.error_message = null;
                return true;
            },
            230, 330 => {
                dialog.selected_template = .raylib;
                dialog.error_message = null;
                return true;
            },
            251, 351 => {
                dialog.close();
                return true;
            },
            261, 361 => {
                const name = dialog.getName();
                const directory = dialog.getDirectory();

                if (name.len == 0) {
                    dialog.error_message = "Enter a project name.";
                    return true;
                }
                if (directory.len == 0) {
                    dialog.error_message = "Enter a destination directory.";
                    return true;
                }

                const allocator = std.heap.page_allocator;
                const expanded_directory = expandHomePath(
                    allocator,
                    home,
                    directory,
                ) catch |err| {
                    dialog.error_message = @errorName(err);
                    return true;
                };
                defer allocator.free(expanded_directory);

                project_creation.createConfiguredProject(
                    io,
                    .{
                        .name = name,
                        .parent_directory = expanded_directory,
                        .template = dialog.selected_template,
                        .minimal = false,
                    },
                ) catch |err| {
                    dialog.error_message = @errorName(err);
                    std.debug.print(
                        "Could not create project: {s}\n",
                        .{@errorName(err)},
                    );
                    return true;
                };

                const project_path = std.fs.path.join(
                    allocator,
                    &.{ expanded_directory, name },
                ) catch |err| {
                    dialog.error_message = @errorName(err);
                    return true;
                };
                defer allocator.free(project_path);

                registerProject(io, registry, environ, project_path) catch |err| {
                    std.debug.print(
                        "Project was created, but could not be registered: {s}\n",
                        .{@errorName(err)},
                    );
                };

                std.debug.print(
                    "Created project '{s}' in '{s}'.\n",
                    .{ name, expanded_directory },
                );

                dialog.close();
                editor.openProject(io, project_path) catch |err| {
                    std.debug.print("Could not open project: {s}\n", .{@errorName(err)});
                    return true;
                };
                screen.* = .editor;
                return true;
            },
            else => return true,
        }
    }

    switch (id) {
        21, 121 => {
            dialog.open();
            dialog.setDirectory(settings.getDefaultProjectDirectory());
            return true;
        },
        22, 122 => {
            picker_mode.* = .import_project;
            picker.open(io, home, home);
            return true;
        },
        23, 123 => {
            picker_mode.* = .open_project;
            picker.open(io, home, home);
            return true;
        },
        24, 124 => {
            screen.* = .editor;
            return true;
        },
        1000...1639 => {
            const card = (id - 1000) / 10;
            const card_part = (id - 1000) % 10;
            if (card_part < 6) {
                _ = openRecentProject(
                    io,
                    manager.recent_scroll + @as(usize, @intCast(card)),
                    registry,
                    environ,
                    screen,
                    editor,
                );
            }
            return true;
        },
        70...73 => {
            screen.* = .settings;
            return true;
        },
        else => return false,
    }
}

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const home = init.environ_map.get("HOME") orelse
        init.environ_map.get("USERPROFILE") orelse
        "/";

    var settings = app_settings.Settings.load(
        io,
        std.heap.page_allocator,
        init.environ_map,
    ) catch |err| blk: {
        std.debug.print(
            "Could not load settings: {s}\n",
            .{@errorName(err)},
        );
        break :blk app_settings.Settings{};
    };

    var registry = project_registry.Registry{};
    registry.load(
        io,
        std.heap.page_allocator,
        init.environ_map,
    ) catch |err| {
        std.debug.print(
            "Could not load project registry: {s}\n",
            .{@errorName(err)},
        );
    };

    var picker_mode: PickerMode = .project_parent;

    const init_flags = sdl3.InitFlags{
        .video = true,
        .events = true,
    };

    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    const window = try sdl3.video.Window.init(
        "Zigine - 2D Game Engine",
        window_width,
        window_height,
        .{
            .resizable = true,
            .maximized = true,
        },
    );
    defer window.deinit();

    var manager = pm.ProjectManager.init();
    manager.setTheme(themeToManager(settings.theme));

    var picker = directory_picker.Picker{};
    var picker_context = ui.Context.init();

    var editor = try editor_module.Editor.init();
    defer editor.deinit();
    editor.setTerminalEnvironment(init.environ_map);

    // Keep loaded sprite surfaces cached between frames.
    var sprite_renderer = sprite_surface_renderer.SpriteSurfaceRenderer.init(
        std.heap.page_allocator,
    );
    defer sprite_renderer.deinit();

    editor.setTheme(themeToEditor(settings.theme));

    var screen: Screen = .project_manager;
    var running = true;
    var text_input_active = false;

    defer {
        if (text_input_active) {
            sdl3.keyboard.stopTextInput(window) catch {};
        }
    }

    var fps_capper = sdl3.extras.FramerateCapper(f32){
        .mode = .{ .limited = fps },
    };

    while (running) {
        _ = fps_capper.delay();

        var clicked_position: ?ui.Vec2 = null;
        var clicked_button: u8 = 0;
        var released_button: ?u8 = null;
        var released_position: ?ui.Vec2 = null;
        var mouse_move_position: ?ui.Vec2 = null;
        var wheel_event: ?struct {
            position: ui.Vec2,
            delta: f32,
            horizontal: f32,
            shift: bool,
        } = null;

        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit, .terminating => running = false,

                .key_down => {
                    if (event.key_down.key) |key| {
                        const ctrl_pressed =
                            event.key_down.mod.left_control or
                            event.key_down.mod.right_control;

                        if (screen == .editor) {
                            if (ctrl_pressed and key == .s) {
                                editor.saveScript(io) catch |err| {
                                    std.debug.print(
                                        "Could not save script: {s}\n",
                                        .{@errorName(err)},
                                    );
                                };
                                editor.saveScene(io) catch |err| {
                                    std.debug.print(
                                        "Could not save scene: {s}\n",
                                        .{@errorName(err)},
                                    );
                                };
                            } else if (editor.isRenaming()) {
                                if (key == .escape) {
                                    editor.cancelRename();
                                } else if (key == .return_key) {
                                    try editor.commitRename();
                                } else if (key == .backspace) {
                                    editor.backspaceRename();
                                }
                            } else if (editor.isEditingInspector()) {
                                if (key == .escape) {
                                    editor.cancelInspectorEdit();
                                } else if (key == .return_key) {
                                    editor.commitInspectorEdit() catch |err| {
                                        std.debug.print(
                                            "Could not apply Inspector value: {s}\n",
                                            .{@errorName(err)},
                                        );
                                    };
                                } else if (key == .backspace) {
                                    editor.backspaceInspector();
                                }
                            } else if (editor.isEditingTerminal()) {
                                if (key == .escape) {
                                    _ = editor.cancelTransientMode();
                                } else if (ctrl_pressed and key == .l) {
                                    editor.clearTerminal();
                                } else if (key == .return_key) {
                                    editor.executeTerminal(io) catch |err| editor.logMsg(@errorName(err));
                                } else if (key == .backspace) {
                                    editor.backspaceTerminal();
                                } else if (key == .delete) {
                                    editor.deleteTerminalCharacter();
                                } else if (key == .left) {
                                    editor.moveTerminalCursor(-1);
                                } else if (key == .right) {
                                    editor.moveTerminalCursor(1);
                                } else if (key == .home) {
                                    editor.terminalCursorBoundary(false);
                                } else if (key == .end) {
                                    editor.terminalCursorBoundary(true);
                                } else if (key == .up) {
                                    editor.terminalHistory(-1);
                                } else if (key == .down) {
                                    editor.terminalHistory(1);
                                }
                            } else if (editor.isEditingScript()) {
                                if (key == .escape) {
                                    _ = editor.cancelTransientMode();
                                } else if (key == .return_key) {
                                    try editor.appendScriptNewline();
                                } else if (key == .backspace) {
                                    editor.backspaceScript();
                                } else if (key == .delete) {
                                    editor.deleteScriptCharacter();
                                } else if (key == .left) {
                                    editor.moveScriptCursor(-1);
                                    editor.ensureScriptCursorVisible(editor.scriptVisibleLines());
                                } else if (key == .right) {
                                    editor.moveScriptCursor(1);
                                    editor.ensureScriptCursorVisible(editor.scriptVisibleLines());
                                } else if (key == .up) {
                                    editor.moveScriptCursorVertical(-1);
                                } else if (key == .down) {
                                    editor.moveScriptCursorVertical(1);
                                } else if (key == .page_up) {
                                    editor.moveScriptCursorByPage(-1, editor.scriptVisibleLines());
                                } else if (key == .page_down) {
                                    editor.moveScriptCursorByPage(1, editor.scriptVisibleLines());
                                } else if (key == .home) {
                                    editor.moveScriptCursorToLineBoundary(false);
                                } else if (key == .end) {
                                    editor.moveScriptCursorToLineBoundary(true);
                                } else if (key == .tab) {
                                    try editor.appendScriptText("    ");
                                }
                            } else if (editor.isNodePickerOpen()) {
                                if (key == .escape) {
                                    _ = editor.cancelTransientMode();
                                } else if (key == .up) {
                                    editor.movePickerSelection(-1);
                                } else if (key == .down) {
                                    editor.movePickerSelection(1);
                                } else if (key == .return_key) {
                                    try editor.choosePickerSelection();
                                }
                            } else {
                                if (key == .escape) {
                                    if (!editor.cancelTransientMode()) {
                                        editor.closeProject() catch |err| {
                                            editor.logMsg(@errorName(err));
                                        };
                                        screen = .project_manager;
                                    }
                                } else if (ctrl_pressed and key == .a) {
                                    editor.openNodePicker();
                                } else if (ctrl_pressed and key == .d) {
                                    try editor.duplicateSelectedNode();
                                } else if (key == .up) {
                                    editor.moveTreeSelection(-1);
                                } else if (key == .down) {
                                    editor.moveTreeSelection(1);
                                } else if (key == .func2) {
                                    try editor.beginRenameSelectedNode();
                                } else if (key == .delete) {
                                    try editor.deleteSelectedNode();
                                }
                            }
                        } else if (key == .escape) {
                            if (picker.is_open) {
                                picker.close();
                            } else if (screen == .settings) {
                                screen = .project_manager;
                            } else if (manager.dialog.is_open) {
                                manager.dialog.close();
                            } else {
                                running = false;
                            }
                        } else if (screen == .project_manager and
                            manager.dialog.is_open and
                            !picker.is_open and
                            key == .backspace)
                        {
                            manager.dialog.backspace();
                        } else if (screen == .project_manager and
                            manager.dialog.is_open and
                            !picker.is_open and
                            key == .tab)
                        {
                            manager.dialog.active_field =
                                switch (manager.dialog.active_field) {
                                    .name => .parent_directory,
                                    .parent_directory => .name,
                                };
                        }
                    }
                },

                .text_input => |text_event| {
                    if (screen == .editor and editor.isRenaming()) {
                        try editor.appendRenameText(text_event.text);
                    } else if (screen == .editor and editor.isEditingInspector()) {
                        try editor.appendInspectorText(text_event.text);
                    } else if (screen == .editor and editor.isEditingScript()) {
                        try editor.appendScriptText(text_event.text);
                    } else if (screen == .editor and editor.isEditingTerminal()) {
                        editor.appendTerminalText(text_event.text);
                    } else if (screen == .project_manager and
                        manager.dialog.is_open and
                        !picker.is_open)
                    {
                        manager.dialog.appendText(text_event.text);
                    }
                },

                .mouse_button_down => {
                    clicked_position = .{
                        .x = event.mouse_button_down.x,
                        .y = event.mouse_button_down.y,
                    };
                    clicked_button = @intFromEnum(event.mouse_button_down.button);
                },

                .mouse_button_up => {
                    released_button = @intFromEnum(event.mouse_button_up.button);
                    released_position = .{
                        .x = event.mouse_button_up.x,
                        .y = event.mouse_button_up.y,
                    };
                },

                .mouse_motion => {
                    mouse_move_position = .{
                        .x = event.mouse_motion.x,
                        .y = event.mouse_motion.y,
                    };
                },

                .mouse_wheel => {
                    wheel_event = .{
                        .position = .{
                            .x = event.mouse_wheel.x,
                            .y = event.mouse_wheel.y,
                        },
                        .delta = event.mouse_wheel.scroll_y,
                        .horizontal = event.mouse_wheel.scroll_x,
                        .shift = sdl3.keyboard.getModState().shiftDown(),
                    };
                },

                else => {},
            }
        }

        if (!running) break;

        if (screen == .project_manager) {
            if (wheel_event) |wheel| {
                if (picker.is_open) {
                    if (picker_context.hitTest(wheel.position)) |id| {
                        if (id == 8009 or id == 8010 or id == 8011 or
                            (id >= 8100 and id < 8110) or
                            (id >= 8150 and id < 8160) or
                            (id >= 8160 and id < 8170))
                        {
                            const rows: isize = @max(
                                @as(isize, 1),
                                @as(isize, @intFromFloat(@abs(wheel.delta))),
                            );
                            picker.scroll(if (wheel.delta < 0) rows else -rows);
                        }
                    }
                } else if (!manager.dialog.is_open) {
                    if (manager.context.hitTest(wheel.position)) |id| {
                        // The recent-project container is 35 and each visible
                        // card occupies a ten-ID block starting at 1000.
                        if (id == 35 or (id >= 1000 and id < 1640)) {
                            const rows: isize = @max(
                                @as(isize, 1),
                                @as(isize, @intFromFloat(@abs(wheel.delta))),
                            );
                            manager.scrollRecent(
                                if (wheel.delta < 0) rows else -rows,
                                registry.count,
                            );
                        }
                    }
                }
            }

            if (clicked_position) |position| {
                if (picker.is_open) {
                    switch (picker.handleClick(
                        io,
                        &picker_context,
                        position,
                        home,
                    )) {
                        .selected => {
                            const selected_path = picker.getPath();

                            switch (picker_mode) {
                                .project_parent => {
                                    manager.dialog.setDirectory(selected_path);
                                },
                                .open_project, .import_project => {
                                    registerProject(
                                        io,
                                        &registry,
                                        init.environ_map,
                                        selected_path,
                                    ) catch |err| {
                                        picker.error_message = @errorName(err);
                                        continue;
                                    };

                                    std.debug.print(
                                        "{s} project: {s}\n",
                                        .{
                                            if (picker_mode == .import_project)
                                                "Imported"
                                            else
                                                "Selected",
                                            selected_path,
                                        },
                                    );
                                    editor.openProject(io, selected_path) catch |err| {
                                        picker.error_message = @errorName(err);
                                        continue;
                                    };
                                    screen = .editor;
                                },
                                .settings_default_directory => {
                                    settings.setDefaultProjectDirectory(
                                        selected_path,
                                    ) catch |err| {
                                        picker.error_message = @errorName(err);
                                        continue;
                                    };
                                    persistSettings(io, &settings, init.environ_map);
                                },
                            }

                            picker.close();
                            manager.dialog.error_message = null;
                        },
                        .cancelled, .handled, .ignored => {},
                    }
                } else {
                    _ = handleProjectManagerClick(
                        io,
                        &manager,
                        &picker,
                        home,
                        position,
                        &screen,
                        &registry,
                        &settings,
                        init.environ_map,
                        &picker_mode,
                        &editor,
                    );
                }
            }
        } else if (screen == .settings) {
            if (clicked_position) |position| {
                if (picker.is_open) {
                    switch (picker.handleClick(
                        io,
                        &picker_context,
                        position,
                        home,
                    )) {
                        .selected => {
                            const selected_path = picker.getPath();

                            settings.setDefaultProjectDirectory(
                                selected_path,
                            ) catch |err| {
                                picker.error_message = @errorName(err);
                                continue;
                            };

                            persistSettings(io, &settings, init.environ_map);
                            picker.close();
                        },
                        .cancelled, .handled, .ignored => {},
                    }
                } else if (manager.context.hitTest(position)) |id| {
                    switch (id) {
                        810, 910 => screen = .project_manager,
                        830, 930 => {
                            settings.theme = .dark;
                            manager.setTheme(.dark);
                            editor.setTheme(.dark);
                            persistSettings(io, &settings, init.environ_map);
                        },
                        831, 931 => {
                            settings.theme = .light;
                            manager.setTheme(.light);
                            editor.setTheme(.light);
                            persistSettings(io, &settings, init.environ_map);
                        },
                        832, 932 => {
                            settings.theme = .catppuccin_mocha;
                            manager.setTheme(.catppuccin_mocha);
                            editor.setTheme(.catppuccin_mocha);
                            persistSettings(io, &settings, init.environ_map);
                        },
                        833, 933 => {
                            settings.theme = .dracula;
                            manager.setTheme(.dracula);
                            editor.setTheme(.dracula);
                            persistSettings(io, &settings, init.environ_map);
                        },
                        842, 942 => {
                            settings.ui_scale = @max(
                                0.75,
                                settings.ui_scale - 0.05,
                            );
                            persistSettings(io, &settings, init.environ_map);
                        },
                        843, 943 => {
                            settings.ui_scale = @min(
                                1.5,
                                settings.ui_scale + 0.05,
                            );
                            persistSettings(io, &settings, init.environ_map);
                        },
                        852, 952 => {
                            picker_mode = .settings_default_directory;
                            picker.open(
                                io,
                                home,
                                settings.getDefaultProjectDirectory(),
                            );
                        },
                        else => {},
                    }
                }
            }
        } else {
            if (clicked_position) |position| {
                if (clicked_button == 1) {
                    editor.handleClick(position);
                    if (editor.takeAssetOpenRequested()) |asset_index| {
                        editor.openScriptAsset(io, asset_index) catch |err| {
                            editor.logMsg(@errorName(err));
                        };
                    }
                } else if (clicked_button == 2) {
                    editor.viewportMouseDown(position, clicked_button);
                }
            }

            if (mouse_move_position) |position| {
                editor.viewportMouseMove(position) catch |err| {
                    std.debug.print(
                        "Viewport mouse movement failed: {s}\n",
                        .{@errorName(err)},
                    );
                };
            }

            if (wheel_event) |wheel| {
                if (editor.active_panel == .assets) {
                    if (editor.context.hitTest(wheel.position)) |id| {
                        if (id == 60 or id == 63 or id == 65 or id == 66 or
                            (id >= 4000 and id < 4320))
                        {
                            const rows: isize = @max(
                                @as(isize, 1),
                                @as(isize, @intFromFloat(@abs(wheel.delta))),
                            );
                            editor.scrollAssets(if (wheel.delta < 0) rows else -rows);
                        }
                    }
                } else if (editor.active_panel == .script and
                    editor.context.getElementBounds(54) != null and
                    editor.context.hitTest(wheel.position) == 54)
                {
                    if (wheel.shift) {
                        const horizontal_delta = if (wheel.horizontal != 0) wheel.horizontal else wheel.delta;
                        editor.scrollScriptHorizontal(@as(isize, @intFromFloat(horizontal_delta)));
                    } else {
                        editor.scrollScript(-@as(isize, @intFromFloat(wheel.delta)), editor.scriptVisibleLines());
                    }
                } else if (editor.context.hitTest(wheel.position)) |id| {
                    if (id == 30 or id == 38 or (id >= 1000 and id < 2000)) {
                        const rows: isize = @max(
                            @as(isize, 1),
                            @as(isize, @intFromFloat(@abs(wheel.delta))),
                        );
                        editor.scrollTree(if (wheel.delta < 0) rows else -rows);
                    } else {
                        editor.viewportMouseWheel(wheel.position, wheel.delta);
                    }
                } else {
                    editor.viewportMouseWheel(wheel.position, wheel.delta);
                }
            }

            if (released_button) |button| {
                editor.viewportMouseUpAt(released_position orelse editor.last_mouse_position, button);
            }

            if (editor.takeExitRequested()) {
                editor.closeProject() catch |err| editor.logMsg(@errorName(err));
                screen = .project_manager;
            }

            if (editor.takeSaveRequested()) {
                editor.saveScript(io) catch |err| editor.logMsg(@errorName(err));
                editor.saveScene(io) catch |err| editor.logMsg(@errorName(err));
            }
            if (editor.takeRunRequested()) {
                editor.saveScript(io) catch |err| editor.logMsg(@errorName(err));
                editor.saveScene(io) catch |err| editor.logMsg(@errorName(err));
                editor.logMsg("Running project; close the game window to return to the editor.");
                editor.runProject(io) catch |err| editor.logMsg(@errorName(err));
            }
        }

        const should_enable_text_input =
            (screen == .project_manager and
                manager.dialog.is_open and
                !picker.is_open) or
            (screen == .editor and editor.wantsTextInput());

        if (should_enable_text_input and !text_input_active) {
            try sdl3.keyboard.startTextInput(window);
            text_input_active = true;
        } else if (!should_enable_text_input and text_input_active) {
            try sdl3.keyboard.stopTextInput(window);
            text_input_active = false;
        }

        const surface = try window.getSurface();
        const viewport_width: f32 = @floatFromInt(surface.getWidth());
        const viewport_height: f32 = @floatFromInt(surface.getHeight());

        const commands = switch (screen) {
            .project_manager => if (picker.is_open)
                try picker.build(
                    &picker_context,
                    viewport_width,
                    viewport_height,
                    manager.getPalette(),
                )
            else
                try manager.build(
                    viewport_width,
                    viewport_height,
                    &registry,
                ),

            .settings => if (picker.is_open)
                try picker.build(
                    &picker_context,
                    viewport_width,
                    viewport_height,
                    manager.getPalette(),
                )
            else
                try manager.buildSettings(
                    viewport_width,
                    viewport_height,
                    &settings,
                ),

            .editor => try editor.build(
                viewport_width,
                viewport_height,
            ),
        };

        var scene_commands: []const renderer2d.DrawCommand = &.{};
        if (screen == .editor and editor.active_panel != .script) {
            scene_commands = try editor.buildSceneViewport(
                viewport_width,
                viewport_height,
            );
        }

        const palette = manager.getPalette();
        try surface.fillRect(
            null,
            surface.mapRgb(
                palette.background.r,
                palette.background.g,
                palette.background.b,
            ),
        );

        try renderCommands(surface, commands);
        if (screen == .editor and editor.active_panel == .output) {
            try renderTerminal(surface, &editor);
        }
        if (screen == .editor and editor.active_panel == .script) {
            try renderScriptEditor(surface, &editor);
        }

        if (screen == .editor and editor.active_panel != .script) {
            try renderSceneCommands(surface, scene_commands, editor.viewport_rect);

            // Render Sprite2D textures over the scene's grid and geometry.
            // The renderer clips sprite drawing to the scene viewport.
            try sprite_renderer.render(
                surface,
                editor.scene,
                &editor.tree,
                editor.camera,
                editor.viewport_rect,
                if (editor.project_path) |path| path else null,
            );
        }

        try window.updateSurface();
    }
}
