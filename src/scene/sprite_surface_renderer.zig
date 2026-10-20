const std = @import("std");
const sdl3 = @import("sdl3");

const Entry = struct {
    path: []u8,
    surface: ?sdl3.surface.Surface,
};

/// Software-surface sprite renderer.
///
/// The cache owns its paths and loaded surfaces. Scene nodes retain
/// ownership of their own texture_path strings.
pub const SpriteSurfaceRenderer = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,

    pub fn init(allocator: std.mem.Allocator) SpriteSurfaceRenderer {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SpriteSurfaceRenderer) void {
        for (self.entries.items) |entry| {
            if (entry.surface) |surface| {
                surface.deinit();
            }
            self.allocator.free(entry.path);
        }

        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    fn loadCached(
        self: *SpriteSurfaceRenderer,
        path: []const u8,
        project_path: ?[]const u8,
    ) !?sdl3.surface.Surface {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.path, path)) {
                return entry.surface;
            }
        }

        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);

        var loaded_surface: ?sdl3.surface.Surface = null;

        // 1. Direct path
        if (self.allocator.dupeZ(u8, path)) |term1| {
            defer self.allocator.free(term1);
            if (sdl3.image.loadFile(term1)) |surf| {
                loaded_surface = surf;
            } else |_| {}
        } else |_| {}

        // 2. Try project_path + path
        if (loaded_surface == null and project_path != null) {
            if (std.fs.path.join(self.allocator, &.{ project_path.?, path })) |p2| {
                defer self.allocator.free(p2);
                if (self.allocator.dupeZ(u8, p2)) |term2| {
                    defer self.allocator.free(term2);
                    if (sdl3.image.loadFile(term2)) |surf| {
                        loaded_surface = surf;
                    } else |_| {}
                } else |_| {}
            } else |_| {}
        }

        // 3. Try project_path + "assets" + path
        if (loaded_surface == null and project_path != null) {
            if (std.fs.path.join(self.allocator, &.{ project_path.?, "assets", path })) |p3| {
                defer self.allocator.free(p3);
                if (self.allocator.dupeZ(u8, p3)) |term3| {
                    defer self.allocator.free(term3);
                    if (sdl3.image.loadFile(term3)) |surf| {
                        loaded_surface = surf;
                    } else |_| {}
                } else |_| {}
            } else |_| {}
        }

        // 4. Try cwd + "assets" + path
        if (loaded_surface == null) {
            if (std.fs.path.join(self.allocator, &.{ "assets", path })) |p4| {
                defer self.allocator.free(p4);
                if (self.allocator.dupeZ(u8, p4)) |term4| {
                    defer self.allocator.free(term4);
                    if (sdl3.image.loadFile(term4)) |surf| {
                        loaded_surface = surf;
                    } else |_| {}
                } else |_| {}
            } else |_| {}
        }

        if (loaded_surface) |loaded| {
            try self.entries.append(self.allocator, .{
                .path = owned_path,
                .surface = loaded,
            });
            return loaded;
        }

        std.debug.print(
            "Could not load sprite '{s}'\n",
            .{path},
        );

        try self.entries.append(self.allocator, .{
            .path = owned_path,
            .surface = null,
        });

        return null;
    }

    fn ancestorsVisible(
        scene: anytype,
        node_id: anytype,
    ) bool {
        var current_id: ?@TypeOf(node_id) = node_id;

        while (current_id) |id| {
            const node = scene.getConst(id) catch return false;

            if (!node.visible) return false;
            current_id = node.parent;
        }

        return true;
    }

    /// Draws Sprite2D nodes in active scene-tree order.
    ///
    /// `camera.worldToScreen()` supplies screen coordinates, while
    /// `viewport` defines the clipping rectangle in window coordinates.
    pub fn render(
        self: *SpriteSurfaceRenderer,
        target: anytype,
        scene: anytype,
        tree: anytype,
        camera: anytype,
        viewport: anytype,
        project_path: ?[]const u8,
    ) !void {
        const clip = sdl3.rect.IRect{
            .x = @intFromFloat(@ceil(viewport.x)),
            .y = @intFromFloat(@ceil(viewport.y)),
            .w = @intFromFloat(@floor(viewport.width)),
            .h = @intFromFloat(@floor(viewport.height)),
        };

        if (clip.w <= 0 or clip.h <= 0) return;

        _ = target.setClipRect(clip);
        defer _ = target.setClipRect(null);

        for (0..tree.nodeCount()) |index| {
            const node_id = tree.nodeAt(index) orelse continue;
            const node = scene.getConst(node_id) catch continue;

            if (node.kind != .sprite_2d) continue;
            if (!ancestorsVisible(scene, node_id)) continue;

            const path = node.texture_path orelse continue;
            if (path.len == 0) continue;

            const source = (try self.loadCached(path, project_path)) orelse continue;

            const transform = scene.globalTransform(node_id) catch continue;

            const world_position = transform.transformPoint(.{});
            const screen_position = camera.worldToScreen(.{
                .x = world_position.x,
                .y = world_position.y,
            });

            // Calculate the lengths of the transformed basis vectors.
            // This accounts for parent scaling and non-rotated scaling.
            const scale_x = @sqrt(
                transform.a * transform.a +
                    transform.b * transform.b,
            );
            const scale_y = @sqrt(
                transform.c * transform.c +
                    transform.d * transform.d,
            );

            const zoom = @abs(camera.zoom);

            const draw_width = @max(
                1,
                @as(i32, @intFromFloat(@round(
                    @as(f32, @floatFromInt(source.getWidth())) *
                        scale_x * zoom,
                ))),
            );

            const draw_height = @max(
                1,
                @as(i32, @intFromFloat(@round(
                    @as(f32, @floatFromInt(source.getHeight())) *
                        scale_y * zoom,
                ))),
            );

            // Sprite2D is centered on its origin.
            const destination = sdl3.rect.IRect{
                .x = @intFromFloat(@round(
                    screen_position.x - @as(f32, @floatFromInt(draw_width)) / 2,
                )),
                .y = @intFromFloat(@round(
                    screen_position.y - @as(f32, @floatFromInt(draw_height)) / 2,
                )),
                .w = draw_width,
                .h = draw_height,
            };

            try source.blitScaled(
                null,
                target,
                destination,
                .nearest,
            );
        }
    }
};
