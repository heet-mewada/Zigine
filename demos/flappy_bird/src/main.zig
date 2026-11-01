const std = @import("std");
const sdl3 = @import("sdl3");
const r = @import("renderer");
const text_render = @import("ui-render");
const ui = @import("ui-components");
const W: f32 = 480;
const H: f32 = 720;
const Pipe = struct { x: f32, gap_y: f32, passed: bool };
const Game = struct {
    bird_y: f32 = H / 2,
    velocity: f32 = 0,
    score: u32 = 0,
    alive: bool = true,
    time: f32 = 0,
    pipes: [4]Pipe = .{ .{ .x = 520, .gap_y = 260, .passed = false }, .{ .x = 760, .gap_y = 420, .passed = false }, .{ .x = 1000, .gap_y = 310, .passed = false }, .{ .x = 1240, .gap_y = 480, .passed = false } },
    fn flap(self: *Game) void {
        if (self.alive) self.velocity = -285;
    }
    fn reset(self: *Game) void {
        self.* = Game{};
    }
    fn update(self: *Game, dt: f32) void {
        if (!self.alive) return;
        self.time += dt;
        self.velocity += 720 * dt;
        self.bird_y += self.velocity * dt;
        for (&self.pipes) |*pipe| {
            pipe.x -= 150 * dt;
            if (pipe.x < -70) {
                pipe.x += 4 * 240;
                pipe.passed = false;
            }
            if (!pipe.passed and pipe.x < 82) {
                pipe.passed = true;
                self.score += 1;
            }
            const bird = r.Rect{ .x = 72, .y = self.bird_y - 14, .width = 28, .height = 28 };
            if (bird.x + bird.width > pipe.x and bird.x < pipe.x + 56 and (bird.y < pipe.gap_y - 72 or bird.y + bird.height > pipe.gap_y + 72)) self.alive = false;
        }
        if (self.bird_y < 0 or self.bird_y + 28 > H) self.alive = false;
    }
    fn draw(self: *Game, out: *r.Renderer2D) !void {
        try out.drawRect(.{ .x = 0, .y = 0, .width = W, .height = H }, .{ .r = 99, .g = 191, .b = 240 });
        for (self.pipes) |pipe| {
            if (pipe.x + 56 < 0 or pipe.x > W) continue;
            try out.drawRect(.{ .x = pipe.x, .y = 0, .width = 56, .height = pipe.gap_y - 72 }, .{ .r = 64, .g = 190, .b = 88 });
            try out.drawRect(.{ .x = pipe.x, .y = pipe.gap_y + 72, .width = 56, .height = H }, .{ .r = 64, .g = 190, .b = 88 });
        }
        try out.drawRect(.{ .x = 72, .y = self.bird_y, .width = 28, .height = 28 }, .{ .r = 255, .g = 220, .b = 67 });
    }
};
fn present(surface: anytype, commands: []const r.DrawCommand, alive: bool) !void {
    const scale = @min(@as(f32, @floatFromInt(surface.getWidth())) / W, @as(f32, @floatFromInt(surface.getHeight())) / H);
    const offset_x = (@as(f32, @floatFromInt(surface.getWidth())) - W * scale) * 0.5;
    const offset_y = (@as(f32, @floatFromInt(surface.getHeight())) - H * scale) * 0.5;
    try surface.fillRect(null, surface.mapRgb(12, 25, 38));
    for (commands) |command| switch (command) {
        .rectangle => |rect| {
            const left: i32 = @max(@as(i32, 0), @as(i32, @intFromFloat(offset_x + rect.bounds.x * scale)));
            const top: i32 = @max(@as(i32, 0), @as(i32, @intFromFloat(offset_y + rect.bounds.y * scale)));
            const right: i32 = @min(@as(i32, @intFromFloat(@as(f32, @floatFromInt(surface.getWidth())))), @as(i32, @intFromFloat(offset_x + (rect.bounds.x + rect.bounds.width) * scale)));
            const bottom: i32 = @min(@as(i32, @intFromFloat(@as(f32, @floatFromInt(surface.getHeight())))), @as(i32, @intFromFloat(offset_y + (rect.bounds.y + rect.bounds.height) * scale)));
            if (right > left and bottom > top) try surface.fillRect(.{ .x = left, .y = top, .w = right - left, .h = bottom - top }, surface.mapRgb(rect.color.r, rect.color.g, rect.color.b));
        },
        .line => |line| try surface.fillRect(.{ .x = @intFromFloat(offset_x + @min(line.from.x, line.to.x) * scale), .y = @intFromFloat(offset_y + @min(line.from.y, line.to.y) * scale), .w = @max(1, @as(i32, @intFromFloat(@abs(line.to.x - line.from.x) * scale))), .h = @max(1, @as(i32, @intFromFloat(@abs(line.to.y - line.from.y) * scale))) }, surface.mapRgb(line.color.r, line.color.g, line.color.b)),
    };
    if (!alive) {
        const panel: ui.Rect = .{ .x = offset_x + 60 * scale, .y = offset_y + 285 * scale, .width = 360 * scale, .height = 150 * scale };
        try surface.fillRect(.{ .x = @intFromFloat(panel.x), .y = @intFromFloat(panel.y), .w = @intFromFloat(panel.width), .h = @intFromFloat(panel.height) }, surface.mapRgb(18, 34, 62));
        try text_render.drawText(surface, .{ .x = panel.x + 62 * scale, .y = panel.y + 24 * scale, .width = 240 * scale, .height = 42 * scale }, "TRY AGAIN", .{ .r = 255, .g = 238, .b = 128 }, panel, .{ .scale = @max(1, @as(i32, @intFromFloat(4 * scale))), .wrap = false });
        try text_render.drawText(surface, .{ .x = panel.x + 46 * scale, .y = panel.y + 88 * scale, .width = 280 * scale, .height = 30 * scale }, "SPACE TO RETRY", .{ .r = 220, .g = 240, .b = 255 }, panel, .{ .scale = @max(1, @as(i32, @intFromFloat(2 * scale))), .wrap = false });
    }
}

pub fn main() !void {
    const flags = sdl3.InitFlags{ .video = true, .events = true };
    try sdl3.init(flags);
    defer sdl3.quit(flags);
    const window = try sdl3.video.Window.init("Zigine - Flappy Bird", 480, 720, .{});
    defer window.deinit();
    var game = Game{};
    var out = r.Renderer2D.init(std.heap.page_allocator);
    defer out.deinit();
    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = 60 } };
    var running = true;
    while (running) {
        const dt = fps_capper.delay();
        while (sdl3.events.poll()) |event| switch (event) {
            .quit, .terminating => running = false,
            .key_down => if (event.key_down.key) |key| switch (key) {
                .space => if (game.alive) game.flap() else game.reset(),
                .r => game.reset(),
                .escape => running = false,
                else => {},
            },
            else => {},
        };
        out.clear();
        game.update(dt);
        try game.draw(&out);
        const surface = try window.getSurface();
        try present(surface, out.getCommands(), game.alive);
        try window.updateSurface();
    }
}
test "flap gives upward velocity" {
    var game = Game{};
    game.flap();
    try std.testing.expect(game.velocity < 0);
}

// ZIGINE_SCENE_BEGIN
pub const ZigineSceneKind = enum { node, node_2d, sprite_2d, camera_2d };
pub const ZigineSceneVec2 = struct { x: f32, y: f32 };
pub const ZigineSceneNode = struct {
    name: []const u8,
    kind: ZigineSceneKind,
    parent: i32,
    visible: bool,
    position: ZigineSceneVec2,
    rotation: f32,
    scale: ZigineSceneVec2,
    texture_path: []const u8,
};
pub const zigine_scene = [_]ZigineSceneNode{
    .{ .name = "FlappyBird", .kind = .node_2d, .parent = -1, .visible = true, .position = .{ .x = 0, .y = 0 }, .rotation = 0, .scale = .{ .x = 1, .y = 1 }, .texture_path = "" },
    .{ .name = "World", .kind = .node_2d, .parent = 0, .visible = true, .position = .{ .x = 0, .y = 0 }, .rotation = 0, .scale = .{ .x = 1, .y = 1 }, .texture_path = "" },
    .{ .name = "Bird", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -168, .y = 0.14453125 }, .rotation = 0, .scale = .{ .x = 0.6, .y = 0.6 }, .texture_path = "" },
    .{ .name = "Pipe_1", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 280, .y = -100 }, .rotation = 0, .scale = .{ .x = 1, .y = 1 }, .texture_path = "" },
    .{ .name = "Pipe_2", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 520, .y = 60 }, .rotation = 0, .scale = .{ .x = 1, .y = 1 }, .texture_path = "" },
    .{ .name = "Camera2D", .kind = .camera_2d, .parent = 0, .visible = true, .position = .{ .x = 0, .y = 0 }, .rotation = 0, .scale = .{ .x = 1, .y = 1 }, .texture_path = "" },
};
pub fn zigine_scene_render(surface: anytype) !void {
    const origin_x: f32 = @as(f32, @floatFromInt(surface.getWidth())) * 0.5;
    const origin_y: f32 = @as(f32, @floatFromInt(surface.getHeight())) * 0.5;
    for (zigine_scene) |node| {
        if (!node.visible) continue;
        if (node.kind != .sprite_2d) continue;
        const base_size: f32 = switch (node.kind) {
            .sprite_2d => 48.0,
            .camera_2d => 160.0,
            .node_2d => 32.0,
            .node => 24.0,
        };
        const width: i32 = @intFromFloat(@max(2.0, base_size * node.scale.x));
        const height: i32 = @intFromFloat(@max(2.0, base_size * node.scale.y));
        const x: i32 = @intFromFloat(origin_x + node.position.x - @as(f32, @floatFromInt(width)) * 0.5);
        const y: i32 = @intFromFloat(origin_y + node.position.y - @as(f32, @floatFromInt(height)) * 0.5);
        const color = switch (node.kind) {
            .sprite_2d => surface.mapRgb(90, 170, 255),
            .camera_2d => surface.mapRgb(255, 190, 80),
            .node_2d => surface.mapRgb(170, 110, 255),
            .node => surface.mapRgb(150, 150, 150),
        };
        try surface.fillRect(.{ .x = x, .y = y, .w = width, .h = height }, color);
        try zigine_scene_tick(surface);

    }
}
pub fn zigine_scene_tick(surface: anytype) !void {
    try zigine_scene_render(surface);
}
// ZIGINE_SCENE_END
