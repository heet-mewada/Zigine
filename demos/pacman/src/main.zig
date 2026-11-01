const std = @import("std");
const sdl3 = @import("sdl3");
const r = @import("renderer");
const text_render = @import("ui-render");

const Tile: f32 = 22;
const MapW = 21;
const MapH = 21;
const ScreenW: f32 = Tile * MapW;
const ScreenH: f32 = Tile * MapH + 42;

const maze = [_][]const u8{
    "#####################",
    "#...................#",
    "#.###.#####.#####.###",
    "#.#.................#",
    "#.#.###.#######.###.#",
    "#...#...........#...#",
    "###.#.###.#.###.#.###",
    "#.....#...#...#.....#",
    "#.###.#.#####.#.###.#",
    "#.#...#...#...#...#.#",
    "#.#.#####.#.#####.#.#",
    "#.#.................#",
    "#.###.#.#######.#.###",
    "#.....#...#...#.....#",
    "###.#.###.#.###.#.###",
    "#...#...........#...#",
    "#.#.###.#######.###.#",
    "#.#.................#",
    "#.###.#####.#####.###",
    "#...................#",
    "#####################",
};

const Cell = struct { x: i32, y: i32 };
const Game = struct {
    scene_nodes: [zigine_scene.len]ZigineSceneNode = undefined,
    player: Cell = .{ .x = 10, .y = 15 },
    ghost: Cell = .{ .x = 9, .y = 9 },
    wanted: Cell = .{ .x = 0, .y = 0 },
    score: u32 = 0,
    pellets: u32 = 0,
    eaten: [MapH][MapW]bool = [_][MapW]bool{[_]bool{false} ** MapW} ** MapH,
    lives: u8 = 3,
    move_timer: f32 = 0,
    ghost_timer: f32 = 0,
    victory: bool = false,
    game_over: bool = false,

    fn init() Game {
        var game = Game{};
        game.scene_nodes = zigine_scene;
        game.player = .{ .x = @intFromFloat((game.scene_nodes[2].position.x + ScreenW * 0.5 - 11) / Tile), .y = @intFromFloat((game.scene_nodes[2].position.y + ScreenH * 0.5 - 11) / Tile) };
        game.ghost = .{ .x = @intFromFloat((game.scene_nodes[3].position.x + ScreenW * 0.5 - 11) / Tile), .y = @intFromFloat((game.scene_nodes[3].position.y + ScreenH * 0.5 - 11) / Tile) };
        for (maze) |row| {
            for (row) |cell| {
                if (cell == '.') game.pellets += 1;
            }
        }
        return game;
    }

    fn isOpen(x: i32, y: i32) bool {
        return x >= 0 and x < MapW and y >= 0 and y < MapH and maze[@intCast(y)][@intCast(x)] != '#';
    }

    fn resetPositions(self: *Game) void {
        self.player = .{ .x = 10, .y = 15 };
        self.ghost = .{ .x = 10, .y = 9 };
        self.scene_nodes[2].position = .{ .x = @as(f32, @floatFromInt(self.player.x * 22 + 11)) - ScreenW * 0.5, .y = @as(f32, @floatFromInt(self.player.y * 22 + 11)) - ScreenH * 0.5 };
        self.scene_nodes[3].position = .{ .x = @as(f32, @floatFromInt(self.ghost.x * 22 + 11)) - ScreenW * 0.5, .y = @as(f32, @floatFromInt(self.ghost.y * 22 + 11)) - ScreenH * 0.5 };
        self.wanted = .{ .x = 0, .y = 0 };
        self.move_timer = 0;
        self.ghost_timer = 0;
    }

    fn setDirection(self: *Game, direction: Cell) void {
        self.wanted = direction;
    }

    fn update(self: *Game, dt: f32) void {
        if (self.victory or self.game_over) return;
        self.move_timer += dt;
        self.ghost_timer += dt;
        if (self.move_timer >= 0.12) {
            self.move_timer -= 0.12;
            const next = Cell{ .x = self.player.x + self.wanted.x, .y = self.player.y + self.wanted.y };
            if (isOpen(next.x, next.y)) self.player = next;
            if (maze[@intCast(self.player.y)][@intCast(self.player.x)] == '.' and !self.eaten[@intCast(self.player.y)][@intCast(self.player.x)]) {
                self.eaten[@intCast(self.player.y)][@intCast(self.player.x)] = true;
                self.score += 10;
                self.pellets -= 1;
                if (self.pellets == 0) self.victory = true;
            }
        }
        if (self.ghost_timer >= 0.2) {
            self.ghost_timer -= 0.2;
            const candidates = [_]Cell{
                .{ .x = self.ghost.x + 1, .y = self.ghost.y },
                .{ .x = self.ghost.x - 1, .y = self.ghost.y },
                .{ .x = self.ghost.x, .y = self.ghost.y + 1 },
                .{ .x = self.ghost.x, .y = self.ghost.y - 1 },
            };
            var best = self.ghost;
            var best_distance: u32 = std.math.maxInt(u32);
            for (candidates) |candidate| if (isOpen(candidate.x, candidate.y)) {
                const distance = @abs(candidate.x - self.player.x) + @abs(candidate.y - self.player.y);
                if (distance < best_distance) {
                    best = candidate;
                    best_distance = distance;
                }
            };
            self.ghost = best;
        }
        if (self.player.x == self.ghost.x and self.player.y == self.ghost.y) {
            self.lives -|= 1;
            if (self.lives == 0) self.game_over = true else self.resetPositions();
        }
        self.scene_nodes[2].position = .{ .x = @as(f32, @floatFromInt(self.player.x * 22 + 11)) - ScreenW * 0.5, .y = @as(f32, @floatFromInt(self.player.y * 22 + 11)) - ScreenH * 0.5 };
        self.scene_nodes[3].position = .{ .x = @as(f32, @floatFromInt(self.ghost.x * 22 + 11)) - ScreenW * 0.5, .y = @as(f32, @floatFromInt(self.ghost.y * 22 + 11)) - ScreenH * 0.5 };
    }

    fn draw(self: *const Game, out: *r.Renderer2D) !void {
        try out.drawRect(.{ .x = 0, .y = 0, .width = ScreenW, .height = ScreenH }, .{ .r = 0, .g = 0, .b = 0 });
        for (maze, 0..) |row, y| for (row, 0..) |cell, x| {
            const px: f32 = @floatFromInt(x * 22);
            const py: f32 = @floatFromInt(y * 22);
            if (cell == '#') {
                try out.drawRect(.{ .x = px + 2, .y = py + 2, .width = 18, .height = 18 }, .{ .r = 18, .g = 38, .b = 180 });
                try out.drawRectOutline(.{ .x = px + 3, .y = py + 3, .width = 16, .height = 16 }, .{ .r = 55, .g = 100, .b = 255 }, 1);
            } else if (cell == '.' and !self.eaten[y][x]) {
                try out.drawRect(.{ .x = px + 9, .y = py + 9, .width = 4, .height = 4 }, .{ .r = 255, .g = 210, .b = 150 });
            }
        };
        try out.drawRect(.{ .x = @floatFromInt(self.player.x * 22 + 4), .y = @floatFromInt(self.player.y * 22 + 4), .width = 14, .height = 14 }, .{ .r = 255, .g = 220, .b = 20 });
        try out.drawRect(.{ .x = @floatFromInt(self.ghost.x * 22 + 4), .y = @floatFromInt(self.ghost.y * 22 + 4), .width = 14, .height = 14 }, .{ .r = 235, .g = 55, .b = 75 });
        if (self.victory or self.game_over) {
            try out.drawRect(.{ .x = 55, .y = 205, .width = 352, .height = 72 }, .{ .r = 5, .g = 10, .b = 55, .a = 245 });
            try out.drawRectOutline(.{ .x = 55, .y = 205, .width = 352, .height = 72 }, if (self.victory) .{ .r = 255, .g = 220, .b = 20 } else .{ .r = 235, .g = 55, .b = 75 }, 3);
        }
    }
};

fn present(surface: anytype, commands: []const r.DrawCommand, game: *const Game) !void {
    for (commands) |command| switch (command) {
        .rectangle => |rect| {
            const left: i32 = @max(@as(i32, 0), @as(i32, @intFromFloat(rect.bounds.x)));
            const top: i32 = @max(@as(i32, 0), @as(i32, @intFromFloat(rect.bounds.y)));
            const right: i32 = @min(@as(i32, @intFromFloat(ScreenW)), @as(i32, @intFromFloat(rect.bounds.x + rect.bounds.width)));
            const bottom: i32 = @min(@as(i32, @intFromFloat(ScreenH)), @as(i32, @intFromFloat(rect.bounds.y + rect.bounds.height)));
            if (right > left and bottom > top) try surface.fillRect(.{ .x = left, .y = top, .w = right - left, .h = bottom - top }, surface.mapRgb(rect.color.r, rect.color.g, rect.color.b));
        },
        .line => {},
    };
    if (game.victory) try text_render.drawText(surface, .{ .x = 118, .y = 220, .width = 230, .height = 40 }, "YOU WIN!", .{ .r = 255, .g = 220, .b = 20 }, .{ .x = 55, .y = 205, .width = 352, .height = 72 }, .{ .scale = 4, .wrap = false });
    if (game.game_over) try text_render.drawText(surface, .{ .x = 92, .y = 220, .width = 280, .height = 40 }, "GAME OVER", .{ .r = 235, .g = 55, .b = 75 }, .{ .x = 55, .y = 205, .width = 352, .height = 72 }, .{ .scale = 4, .wrap = false });
}

pub fn main() !void {
    const flags = sdl3.InitFlags{ .video = true, .events = true };
    try sdl3.init(flags);
    defer sdl3.quit(flags);
    const window = try sdl3.video.Window.init("Zigine - Pacman", @intFromFloat(ScreenW), @intFromFloat(ScreenH), .{});
    defer window.deinit();
    var game = Game.init();
    var out = r.Renderer2D.init(std.heap.page_allocator);
    defer out.deinit();
    var capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = 60 } };
    var running = true;
    while (running) {
        const dt = capper.delay();
        while (sdl3.events.poll()) |event| switch (event) {
            .quit, .terminating => running = false,
            .key_down => if (event.key_down.key) |key| switch (key) {
                .left, .a => game.setDirection(.{ .x = -1, .y = 0 }),
                .right, .d => game.setDirection(.{ .x = 1, .y = 0 }),
                .up, .w => game.setDirection(.{ .x = 0, .y = -1 }),
                .down, .s => game.setDirection(.{ .x = 0, .y = 1 }),
                .space => {
                    if (game.victory or game.game_over) game = Game.init();
                },
                .r => game = Game.init(),
                .escape => running = false,
                else => {},
            },
            else => {},
        };
        game.update(dt);
        out.clear();
        try game.draw(&out);
        const surface = try window.getSurface();
        try present(surface, out.getCommands(), &game);
        try window.updateSurface();
    }
}

test "pacman map has a playable start" {
    try std.testing.expect(Game.isOpen(10, 15));
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
    .{ .name = "Pacman", .kind = .node_2d, .parent = -1, .visible = true, .position = .{ .x = 0, .y = 0 }, .rotation = 0, .scale = .{ .x = 1, .y = 1 }, .texture_path = "" },
    .{ .name = "Maze", .kind = .node_2d, .parent = 0, .visible = true, .position = .{ .x = 0, .y = 0 }, .rotation = 0, .scale = .{ .x = 1, .y = 1 }, .texture_path = "" },
    .{ .name = "Player", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = 0, .y = 89 }, .rotation = 0, .scale = .{ .x = 0.34, .y = 0.34 }, .texture_path = "" },
    .{ .name = "Ghost", .kind = .sprite_2d, .parent = 1, .visible = true, .position = .{ .x = -22, .y = -43 }, .rotation = 0, .scale = .{ .x = 0.34, .y = 0.34 }, .texture_path = "" },
    .{ .name = "Camera2D", .kind = .camera_2d, .parent = 0, .visible = true, .position = .{ .x = 0.038604736, .y = 17.074911 }, .rotation = 0, .scale = .{ .x = 13, .y = 13 }, .texture_path = "" },
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
