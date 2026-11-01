const std = @import("std");
const scene_mod = @import("scene");
const tree_mod = @import("scene-tree");
const renderer_mod = @import("renderer");

pub const Scene = scene_mod.Scene;
pub const NodeKind = scene_mod.NodeKind;
pub const NodeId = scene_mod.NodeId;
pub const SceneTree = tree_mod.SceneTree;
pub const Renderer2D = renderer_mod.Renderer2D;
pub const Camera2D = renderer_mod.Camera2D;
pub const Vec2 = renderer_mod.Vec2;
pub const Rect = renderer_mod.Rect;
pub const Color = renderer_mod.Color;

fn fallbackSpriteColor(name: []const u8) Color {
    if (std.mem.startsWith(u8, name, "Invader_0_")) return .{ .r = 255, .g = 91, .b = 116, .a = 230 };
    if (std.mem.startsWith(u8, name, "Invader_")) return .{ .r = 102, .g = 220, .b = 255, .a = 230 };
    if (std.mem.eql(u8, name, "Defender")) return .{ .r = 116, .g = 255, .b = 154, .a = 230 };
    if (std.mem.eql(u8, name, "Bird")) return .{ .r = 255, .g = 220, .b = 67, .a = 230 };
    if (std.mem.startsWith(u8, name, "Pipe_")) return .{ .r = 64, .g = 190, .b = 88, .a = 230 };
    if (std.mem.eql(u8, name, "Player")) return .{ .r = 255, .g = 220, .b = 20, .a = 230 };
    if (std.mem.eql(u8, name, "Ghost")) return .{ .r = 235, .g = 55, .b = 75, .a = 230 };
    return .{ .r = 50, .g = 90, .b = 140, .a = 120 };
}

/// Renders actual scene content.
///
/// Node2D and Node are structural nodes, not visible geometry.
/// Sprite2D textures are rendered by the SDL surface backend after these
/// editor geometry commands have been drawn.
/// Camera2D configures the view and does not render geometry itself.
///
/// Texture rendering is not implemented in Renderer2D yet, so this
/// renderer deliberately does not draw placeholder rectangles.
pub const SceneRenderer = struct {
    /// Default editor gizmo size for nodes without explicit visual bounds.
    /// This is used for selection and hit-testing, not game rendering.
    node_size: f32 = 32,
    show_gizmos: bool = true,

    pub fn render(
        self: *const SceneRenderer,
        tree: *SceneTree,
        renderer: *Renderer2D,
        camera: Camera2D,
    ) !void {
        if (!tree.isActive()) return;
        if (!self.show_gizmos) return;

        const scene = tree.getScene();

        // Demo scenes use the same logical camera as their SDL counterparts.
        // Paint their world background before gizmos and sprite nodes so the
        // editor shows the complete scene, not just the node overlays.
        const world = camera.visibleWorldRect();
        const background = if (std.mem.eql(u8, scene.name, "SpaceInvaders"))
            Color{ .r = 7, .g = 12, .b = 28, .a = 255 }
        else if (std.mem.eql(u8, scene.name, "FlappyBird"))
            Color{ .r = 99, .g = 191, .b = 240, .a = 255 }
        else if (std.mem.eql(u8, scene.name, "Pacman"))
            Color{ .r = 0, .g = 0, .b = 0, .a = 255 }
        else
            null;
        if (background) |color| {
            const top_left = camera.worldToScreen(.{ .x = world.x, .y = world.y });
            try renderer.drawRect(
                .{ .x = top_left.x, .y = top_left.y, .width = world.width * camera.zoom, .height = world.height * camera.zoom },
                color,
            );
        }

        // 1. Draw World Origin (0, 0) axes
        const origin_screen = camera.worldToScreen(.{ .x = 0, .y = 0 });
        const axis_len: f32 = 36.0;
        // Red X axis (+X)
        try renderer.drawArrow(
            origin_screen,
            .{ .x = origin_screen.x + axis_len, .y = origin_screen.y },
            .{ .r = 235, .g = 70, .b = 70, .a = 230 },
            2.0,
        );
        // Green Y axis (+Y)
        try renderer.drawArrow(
            origin_screen,
            .{ .x = origin_screen.x, .y = origin_screen.y + axis_len },
            .{ .r = 70, .g = 215, .b = 85, .a = 230 },
            2.0,
        );
        // Center dot at origin
        try renderer.drawRect(
            .{ .x = origin_screen.x - 2, .y = origin_screen.y - 2, .width = 4, .height = 4 },
            .{ .r = 255, .g = 255, .b = 255, .a = 240 },
        );

        // 2. Render each node in the tree
        const count = tree.nodeCount();
        for (0..count) |i| {
            const node_id = tree.nodeAt(i) orelse continue;
            const node = scene.getConst(node_id) catch continue;
            if (!node.visible) continue;

            const global = scene.globalTransform(node_id) catch continue;
            const world_pos = global.transformPoint(.{ .x = 0, .y = 0 });
            const screen_pos = camera.worldToScreen(.{ .x = world_pos.x, .y = world_pos.y });

            // Draw parent connection line
            if (node.parent) |parent_id| {
                if (scene.getConst(parent_id)) |parent_node| {
                    if (parent_node.visible) {
                        const parent_global = scene.globalTransform(parent_id) catch continue;
                        const parent_world = parent_global.transformPoint(.{ .x = 0, .y = 0 });
                        const parent_screen = camera.worldToScreen(.{ .x = parent_world.x, .y = parent_world.y });
                        try renderer.drawLine(
                            parent_screen,
                            screen_pos,
                            .{ .r = 120, .g = 140, .b = 180, .a = 120 },
                            1.0,
                        );
                    }
                } else |_| {}
            }

            const zoom = @max(camera.zoom, 0.001);
            const scale_x = @sqrt(global.a * global.a + global.b * global.b);
            const scale_y = @sqrt(global.c * global.c + global.d * global.d);

            switch (node.kind) {
                .node_2d => {
                    const arm: f32 = 12.0;
                    try renderer.drawLine(
                        .{ .x = screen_pos.x, .y = screen_pos.y },
                        .{ .x = screen_pos.x + arm, .y = screen_pos.y },
                        .{ .r = 230, .g = 80, .b = 80, .a = 220 },
                        1.5,
                    );
                    try renderer.drawLine(
                        .{ .x = screen_pos.x, .y = screen_pos.y },
                        .{ .x = screen_pos.x, .y = screen_pos.y + arm },
                        .{ .r = 80, .g = 220, .b = 90, .a = 220 },
                        1.5,
                    );
                    try renderer.drawRect(
                        .{ .x = screen_pos.x - 2, .y = screen_pos.y - 2, .width = 4, .height = 4 },
                        .{ .r = 220, .g = 220, .b = 230, .a = 200 },
                    );
                },

                .sprite_2d => {
                    const base_size: f32 = 48.0;
                    const w = base_size * scale_x * zoom;
                    const h = base_size * scale_y * zoom;
                    const bounds = Rect{
                        .x = screen_pos.x - w * 0.5,
                        .y = screen_pos.y - h * 0.5,
                        .width = w,
                        .height = h,
                    };

                    const has_texture = node.texture_path != null and node.texture_path.?.len > 0;
                    if (!has_texture) {
                        try renderer.drawRect(
                            bounds,
                            fallbackSpriteColor(node.name),
                        );
                        try renderer.drawRectOutline(
                            bounds,
                            .{ .r = 100, .g = 180, .b = 245, .a = 200 },
                            1.5,
                        );
                        try renderer.drawLine(
                            .{ .x = bounds.x, .y = bounds.y },
                            .{ .x = bounds.x + bounds.width, .y = bounds.y + bounds.height },
                            .{ .r = 90, .g = 150, .b = 210, .a = 120 },
                            1.0,
                        );
                        try renderer.drawLine(
                            .{ .x = bounds.x + bounds.width, .y = bounds.y },
                            .{ .x = bounds.x, .y = bounds.y + bounds.height },
                            .{ .r = 90, .g = 150, .b = 210, .a = 120 },
                            1.0,
                        );
                    } else {
                        try renderer.drawRectOutline(
                            bounds,
                            .{ .r = 120, .g = 170, .b = 220, .a = 140 },
                            1.0,
                        );
                    }

                    try renderer.drawRect(
                        .{ .x = screen_pos.x - 2, .y = screen_pos.y - 2, .width = 4, .height = 4 },
                        .{ .r = 255, .g = 255, .b = 255, .a = 200 },
                    );
                },

                .camera_2d => {
                    const cam_w: f32 = 160.0 * zoom;
                    const cam_h: f32 = 90.0 * zoom;
                    const cam_bounds = Rect{
                        .x = screen_pos.x - cam_w * 0.5,
                        .y = screen_pos.y - cam_h * 0.5,
                        .width = cam_w,
                        .height = cam_h,
                    };

                    try renderer.drawRectOutline(
                        cam_bounds,
                        .{ .r = 245, .g = 195, .b = 65, .a = 210 },
                        1.5,
                    );
                    try renderer.drawRect(
                        .{ .x = screen_pos.x - 6, .y = screen_pos.y - 4, .width = 12, .height = 8 },
                        .{ .r = 245, .g = 195, .b = 65, .a = 180 },
                    );
                    try renderer.drawLine(
                        .{ .x = screen_pos.x - 2, .y = screen_pos.y - 6 },
                        .{ .x = screen_pos.x + 2, .y = screen_pos.y - 6 },
                        .{ .r = 245, .g = 195, .b = 65, .a = 210 },
                        1.5,
                    );
                },

                .node => {
                    try renderer.drawRect(
                        .{ .x = screen_pos.x - 3, .y = screen_pos.y - 3, .width = 6, .height = 6 },
                        .{ .r = 170, .g = 170, .b = 180, .a = 180 },
                    );
                },
            }
        }
    }
};

test "scene renderer gizmo rendering can be toggled" {
    var scene = try Scene.init(std.testing.allocator, "EmptyScene");
    defer scene.deinit();

    const root = try scene.createNode(null, "MainScene", .node_2d);
    _ = try scene.createNode(root, "Transform", .node_2d);
    _ = try scene.createNode(root, "Sprite", .sprite_2d);
    _ = try scene.createNode(root, "Camera", .camera_2d);

    var tree = SceneTree.init(std.testing.allocator, &scene);
    defer tree.deinit();

    try tree.setRoot(root);
    try tree.enterTree();

    var renderer = Renderer2D.init(std.testing.allocator);
    defer renderer.deinit();

    var scene_renderer = SceneRenderer{ .show_gizmos = false };

    try scene_renderer.render(
        &tree,
        &renderer,
        .{
            .viewport = .{
                .x = 0,
                .y = 0,
                .width = 640,
                .height = 480,
            },
        },
    );

    try std.testing.expectEqual(
        @as(usize, 0),
        renderer.getCommands().len,
    );

    scene_renderer.show_gizmos = true;
    try scene_renderer.render(
        &tree,
        &renderer,
        .{
            .viewport = .{
                .x = 0,
                .y = 0,
                .width = 640,
                .height = 480,
            },
        },
    );

    try std.testing.expect(renderer.getCommands().len > 0);
}
