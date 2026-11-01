const std = @import("std");
const sdl3 = @import("sdl3");
const r = @import("renderer");
const text_render = @import("ui-render");

const W: f32 = 800;
const H: f32 = 600;
const Rect = r.Rect;
const Color = r.Color;

const Shot = struct { x: f32, y: f32, enemy: bool };
const Invader = struct { x: f32, y: f32, alive: bool, row: u8 };
const Shield = struct { x: f32, y: f32, health: u8 };

const Game = struct {
    scene_nodes: [zigine_scene.len]ZigineSceneNode = undefined,
    player_x: f32 = W / 2 - 24,
    invaders: [40]Invader = undefined,
    shots: [64]Shot = undefined,
    shot_count: usize = 0,
    shields: [4]Shield = .{ .{ .x = 150, .y = 470, .health = 8 }, .{ .x = 300, .y = 470, .health = 8 }, .{ .x = 450, .y = 470, .health = 8 }, .{ .x = 600, .y = 470, .health = 8 } },
    direction: f32 = 1,
    score: u32 = 0,
    lives: u8 = 3,
    game_over: bool = false,
    victory: bool = false,
    wave_timer: f32 = 0,
    enemy_fire_timer: f32 = 0,

    fn init() Game {
        var g = Game{};
        // The editor scene is the runtime scene. Gameplay mutates these nodes;
        // SDL renders these same nodes below rather than creating another scene.
        g.scene_nodes = zigine_scene;
        for (0..5) |row| for (0..8) |column| {
            const position = g.scene_nodes[2 + row * 8 + column].position;
            g.invaders[row * 8 + column] = .{ .x = position.x + W * 0.5 - 17, .y = position.y + H * 0.5 - 11, .alive = true, .row = @intCast(row) };
        };
        const defender_position = g.scene_nodes[42].position;
        g.player_x = defender_position.x + W * 0.5 - 24;
        return g;
    }

    fn syncScene(self: *Game) void {
        for (self.invaders, 0..) |alien, index| {
            const node_index = 2 + index;
            self.scene_nodes[node_index].visible = alien.alive;
            self.scene_nodes[node_index].position = .{
                .x = alien.x - W * 0.5 + 17,
                .y = alien.y - H * 0.5 + 11,
            };
        }
        self.scene_nodes[42].position = .{
            .x = self.player_x - W * 0.5 + 24,
            .y = H * 0.5 - 33,
        };
    }

    fn fire(self: *Game) void {
        if (self.shot_count < self.shots.len) {
            self.shots[self.shot_count] = .{ .x = self.player_x + 24, .y = H - 68, .enemy = false };
            self.shot_count += 1;
        }
    }

    fn reset(self: *Game) void {
        self.* = Game.init();
    }

    fn shieldWidth(shield: Shield) f32 {
        return 70 * @as(f32, @floatFromInt(shield.health)) / 8.0;
    }

    fn update(self: *Game, dt: f32, move_axis: f32) void {
        if (self.game_over or self.victory) return;
        self.wave_timer += dt;
        self.enemy_fire_timer += dt;
        self.player_x = @max(10, @min(W - 58, self.player_x + move_axis * 300 * dt));
        var edge = false;
        for (&self.invaders) |*alien| if (alien.alive) {
            alien.x += self.direction * 24 * dt;
            if (alien.x < 24 or alien.x > W - 48) edge = true;
        };
        if (edge) {
            self.direction *= -1;
            for (&self.invaders) |*alien| {
                if (alien.alive) alien.y += 12;
            }
        }
        if (self.enemy_fire_timer >= 1.15 and self.shot_count < self.shots.len) {
            self.enemy_fire_timer = 0;
            const start = @as(usize, @intCast(@mod(@as(i32, @intCast(self.score / 10)) + @as(i32, @intFromFloat(self.wave_timer * 7)), 40)));
            var offset: usize = 0;
            while (offset < self.invaders.len) : (offset += 1) {
                const index = (start + offset) % self.invaders.len;
                if (self.invaders[index].alive) {
                    const alien = self.invaders[index];
                    self.shots[self.shot_count] = .{ .x = alien.x + 17, .y = alien.y + 22, .enemy = true };
                    self.shot_count += 1;
                    break;
                }
            }
        }
        var i: usize = 0;
        while (i < self.shot_count) {
            self.shots[i].y += if (self.shots[i].enemy) 170 * dt else -390 * dt;
            var hit = false;
            for (&self.shields) |*shield| if (shield.health > 0 and (Rect{ .x = shield.x, .y = shield.y, .width = Game.shieldWidth(shield.*), .height = 30 }).contains(.{ .x = self.shots[i].x, .y = self.shots[i].y })) {
                shield.health -= 1;
                hit = true;
                break;
            };
            if (!hit and self.shots[i].enemy and (Rect{ .x = self.player_x, .y = H - 42, .width = 48, .height = 18 }).contains(.{ .x = self.shots[i].x, .y = self.shots[i].y })) {
                self.game_over = true;
                hit = true;
            }
            if (!hit and !self.shots[i].enemy) for (&self.invaders) |*alien| if (alien.alive and (Rect{ .x = alien.x, .y = alien.y, .width = 34, .height = 22 }).contains(.{ .x = self.shots[i].x, .y = self.shots[i].y })) {
                alien.alive = false;
                self.score += 10;
                hit = true;
                break;
            };
            if (hit or self.shots[i].y < 0 or self.shots[i].y > H) {
                self.shots[i] = self.shots[self.shot_count - 1];
                self.shot_count -= 1;
            } else i += 1;
        }
        var remaining: usize = 0;
        for (self.invaders) |alien| if (alien.alive) {
            remaining += 1;
            if (alien.y > H - 120) self.game_over = true;
        };
        if (remaining == 0) self.victory = true;
        self.syncScene();
    }

    fn draw(self: *Game, renderer: *r.Renderer2D) !void {
        try renderer.drawRect(.{ .x = 0, .y = 0, .width = W, .height = H }, .{ .r = 7, .g = 12, .b = 28 });
        for (self.invaders, 0..) |alien, index| {
            const node = self.scene_nodes[2 + index];
            if (!node.visible) continue;
            const x = node.position.x + W * 0.5 - 17;
            const y = node.position.y + H * 0.5 - 11;
            try renderer.drawRect(.{ .x = x, .y = y, .width = 48 * node.scale.x, .height = 48 * node.scale.y }, if (alien.row == 0) Color{ .r = 255, .g = 91, .b = 116 } else Color{ .r = 102, .g = 220, .b = 255 });
        }
        const defender = self.scene_nodes[42];
        try renderer.drawRect(.{ .x = defender.position.x + W * 0.5 - 24, .y = defender.position.y + H * 0.5 - 9.6, .width = 48 * defender.scale.x, .height = 48 * defender.scale.y }, .{ .r = 116, .g = 255, .b = 154 });
        for (self.shields) |shield| if (shield.health > 0) {
            const width = Game.shieldWidth(shield);
            try renderer.drawRect(.{ .x = shield.x, .y = shield.y, .width = width, .height = 30 }, .{ .r = 80, .g = 230, .b = 130 });
        };
        for (self.shots[0..self.shot_count]) |shot| try renderer.drawRect(.{ .x = shot.x, .y = shot.y, .width = 4, .height = 12 }, .{ .r = 255, .g = 238, .b = 128 });
        if (self.victory or self.game_over) {
            try renderer.drawRect(.{ .x = 150, .y = 205, .width = 500, .height = 190 }, .{ .r = 13, .g = 34, .b = 70, .a = 245 });
            try renderer.drawRectOutline(.{ .x = 150, .y = 205, .width = 500, .height = 190 }, if (self.victory) Color{ .r = 116, .g = 255, .b = 154 } else Color{ .r = 255, .g = 91, .b = 116 }, 4);
        }
    }
};

fn present(surface: anytype, commands: []const r.DrawCommand, victory: bool, game_over: bool) !void {
    const scale = @min(@as(f32, @floatFromInt(surface.getWidth())) / W, @as(f32, @floatFromInt(surface.getHeight())) / H);
    const offset_x = (@as(f32, @floatFromInt(surface.getWidth())) - W * scale) * 0.5;
    const offset_y = (@as(f32, @floatFromInt(surface.getHeight())) - H * scale) * 0.5;
    try surface.fillRect(null, surface.mapRgb(4, 7, 18));
    for (commands) |command| switch (command) {
        .rectangle => |rect| try surface.fillRect(.{ .x = @intFromFloat(offset_x + rect.bounds.x * scale), .y = @intFromFloat(offset_y + rect.bounds.y * scale), .w = @intFromFloat(rect.bounds.width * scale), .h = @intFromFloat(rect.bounds.height * scale) }, surface.mapRgb(rect.color.r, rect.color.g, rect.color.b)),
        .line => |line| try surface.fillRect(.{ .x = @intFromFloat(offset_x + @min(line.from.x, line.to.x) * scale), .y = @intFromFloat(offset_y + @min(line.from.y, line.to.y) * scale), .w = @max(1, @as(i32, @intFromFloat(@abs(line.to.x - line.from.x) * scale))), .h = @max(1, @as(i32, @intFromFloat(@abs(line.to.y - line.from.y) * scale))) }, surface.mapRgb(line.color.r, line.color.g, line.color.b)),
    };
    if (victory) try text_render.drawText(surface, .{ .x = offset_x + 246 * scale, .y = offset_y + 225 * scale, .width = 310 * scale, .height = 70 * scale }, "VICTORY!", .{ .r = 255, .g = 238, .b = 128 }, .{ .x = offset_x + 150 * scale, .y = offset_y + 205 * scale, .width = 500 * scale, .height = 190 * scale }, .{ .scale = @max(1, @as(i32, @intFromFloat(6 * scale))), .wrap = false });
    if (game_over) try text_render.drawText(surface, .{ .x = offset_x + 235 * scale, .y = offset_y + 225 * scale, .width = 330 * scale, .height = 70 * scale }, "GAME OVER", .{ .r = 255, .g = 120, .b = 130 }, .{ .x = offset_x + 150 * scale, .y = offset_y + 205 * scale, .width = 500 * scale, .height = 190 * scale }, .{ .scale = @max(1, @as(i32, @intFromFloat(5 * scale))), .wrap = false });
}

pub fn main() !void {
    const flags = sdl3.InitFlags{ .video = true, .events = true };
    try sdl3.init(flags);
    defer sdl3.quit(flags);
    const window = try sdl3.video.Window.init("Zigine - Space Invaders", 800, 600, .{ .resizable = true });
    defer window.deinit();
    var game = Game.init();
    var renderer = r.Renderer2D.init(std.heap.page_allocator);
    defer renderer.deinit();
    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = 60 } };
    var running = true;
    var move_axis: f32 = 0;
    while (running) {
        const dt = fps_capper.delay();
        while (sdl3.events.poll()) |event| switch (event) {
            .quit, .terminating => running = false,
            .key_down => if (event.key_down.key) |key| switch (key) {
                .left, .a => move_axis = -1,
                .right, .d => move_axis = 1,
                .space => if (game.victory or game.game_over) game.reset() else game.fire(),
                .r => game.reset(),
                .escape => running = false,
                else => {},
            },
            .key_up => if (event.key_up.key) |key| switch (key) {
                .left, .a, .right, .d => move_axis = 0,
                else => {},
            },
            else => {},
        };
        const surface = try window.getSurface();
        renderer.clear();
        game.update(dt, move_axis);
        try game.draw(&renderer);
        try present(surface, renderer.getCommands(), game.victory, game.game_over);
        try window.updateSurface();
    }
}

test "wave initializes with forty invaders" {
    const game = Game.init();
    try std.testing.expectEqual(@as(usize, 40), game.invaders.len);
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
    .{ .name = "SpaceInvaders", .kind = .node_2d, .parent = -1, .visible = true, .position = .{ .x = 0, .y = 0 }, .rotation = 0, .scale = .{ .x = 1, .y = 1 }, .texture_path = "" },
    .{ .name = "Playfield", .kind = .node_2d, .parent = 0, .visible = true, .position = .{ .x = 0, .y = 0 }, .rotation = 0, .scale = .{ .x = 1, .y = 1 }, .texture_path = "" },
    .{ .name = "Invader_0_0", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -283, .y = -209 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_0_1", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -213, .y = -209 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_0_2", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -143, .y = -209 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_0_3", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -73, .y = -209 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_0_4", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -3, .y = -209 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_0_5", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 67, .y = -209 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_0_6", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 137, .y = -209 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_0_7", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 207, .y = -209 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_1_0", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -283, .y = -171 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_1_1", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -213, .y = -171 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_1_2", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -143, .y = -171 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_1_3", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -73, .y = -171 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_1_4", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -3, .y = -171 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_1_5", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 67, .y = -171 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_1_6", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 137, .y = -171 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_1_7", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 207, .y = -171 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_2_0", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -283, .y = -133 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_2_1", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -213, .y = -133 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_2_2", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -143, .y = -133 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_2_3", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -73, .y = -133 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_2_4", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -3, .y = -133 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_2_5", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 67, .y = -133 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_2_6", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 137, .y = -133 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_2_7", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 207, .y = -133 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_3_0", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -283, .y = -95 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_3_1", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -213, .y = -95 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_3_2", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -143, .y = -95 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_3_3", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -73, .y = -95 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_3_4", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -3, .y = -95 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_3_5", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 67, .y = -95 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_3_6", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 137, .y = -95 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_3_7", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 207, .y = -95 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_4_0", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -285.0586, .y = -55.60547 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_4_1", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -213, .y = -57 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_4_2", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -143, .y = -57 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_4_3", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -73, .y = -57 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_4_4", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -3, .y = -57 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_4_5", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 67, .y = -57 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_4_6", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 137, .y = -57 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Invader_4_7", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 207, .y = -57 }, .rotation = 0, .scale = .{ .x = 0.7, .y = 0.45 }, .texture_path = "" },
    .{ .name = "Defender", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -283.9514, .y = 277.0613 }, .rotation = 0, .scale = .{ .x = 1, .y = 0.4 }, .texture_path = "" },
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
