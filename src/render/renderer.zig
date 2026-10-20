const std = @import("std");

pub const Vec2 = struct {
    x: f32 = 0,
    y: f32 = 0,
};

pub const Color = struct {
    r: u8 = 255,
    g: u8 = 255,
    b: u8 = 255,
    a: u8 = 255,
};

pub const Rect = struct {
    x: f32 = 0,
    y: f32 = 0,
    width: f32 = 0,
    height: f32 = 0,

    pub fn contains(self: Rect, point: Vec2) bool {
        return point.x >= self.x and point.y >= self.y and
            point.x < self.x + self.width and
            point.y < self.y + self.height;
    }

    pub fn isValid(self: Rect) bool {
        return std.math.isFinite(self.x) and std.math.isFinite(self.y) and
            std.math.isFinite(self.width) and std.math.isFinite(self.height) and
            self.width > 0 and self.height > 0;
    }
};

pub const Camera2D = struct {
    position: Vec2 = .{},
    zoom: f32 = 1.0,
    viewport: Rect = .{},

    /// Converts a world position into viewport pixel coordinates.
    pub fn worldToScreen(
        self: Camera2D,
        world: Vec2,
    ) Vec2 {
        const safe_zoom = if (std.math.isFinite(self.zoom) and self.zoom > 0) self.zoom else 1.0;

        return .{
            .x = self.viewport.x + self.viewport.width * 0.5 +
                (world.x - self.position.x) * safe_zoom,
            .y = self.viewport.y + self.viewport.height * 0.5 +
                (world.y - self.position.y) * safe_zoom,
        };
    }

    /// Converts viewport pixel coordinates into world coordinates.
    pub fn screenToWorld(
        self: Camera2D,
        screen: Vec2,
    ) Vec2 {
        const safe_zoom = if (std.math.isFinite(self.zoom) and self.zoom > 0) self.zoom else 1.0;

        return .{
            .x = self.position.x +
                (screen.x - self.viewport.x - self.viewport.width * 0.5) /
                    safe_zoom,
            .y = self.position.y +
                (screen.y - self.viewport.y - self.viewport.height * 0.5) /
                    safe_zoom,
        };
    }

    pub fn visibleWorldRect(self: Camera2D) Rect {
        const safe_zoom = if (std.math.isFinite(self.zoom) and self.zoom > 0) self.zoom else 1.0;
        const world_width = self.viewport.width / safe_zoom;
        const world_height = self.viewport.height / safe_zoom;

        return .{
            .x = self.position.x - world_width * 0.5,
            .y = self.position.y - world_height * 0.5,
            .width = world_width,
            .height = world_height,
        };
    }
};

pub const DrawCommand = union(enum) {
    rectangle: struct {
        bounds: Rect,
        color: Color,
    },

    line: struct {
        from: Vec2,
        to: Vec2,
        color: Color,
        thickness: f32 = 1,
    },
};

pub const Renderer2D = struct {
    allocator: std.mem.Allocator,
    commands: std.ArrayList(DrawCommand) = .empty,

    pub fn init(allocator: std.mem.Allocator) Renderer2D {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Renderer2D) void {
        self.commands.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn clear(self: *Renderer2D) void {
        self.commands.clearRetainingCapacity();
    }

    pub fn getCommands(self: *const Renderer2D) []const DrawCommand {
        return self.commands.items;
    }

    pub fn drawRect(
        self: *Renderer2D,
        bounds: Rect,
        color: Color,
    ) std.mem.Allocator.Error!void {
        try self.commands.append(self.allocator, .{
            .rectangle = .{
                .bounds = bounds,
                .color = color,
            },
        });
    }

    pub fn drawLine(
        self: *Renderer2D,
        from: Vec2,
        to: Vec2,
        color: Color,
        thickness: f32,
    ) std.mem.Allocator.Error!void {
        try self.commands.append(self.allocator, .{
            .line = .{
                .from = from,
                .to = to,
                .color = color,
                .thickness = thickness,
            },
        });
    }

    pub fn drawRectOutline(
        self: *Renderer2D,
        bounds: Rect,
        color: Color,
        thickness: f32,
    ) std.mem.Allocator.Error!void {
        try self.drawLine(.{ .x = bounds.x, .y = bounds.y }, .{ .x = bounds.x + bounds.width, .y = bounds.y }, color, thickness);
        try self.drawLine(.{ .x = bounds.x + bounds.width, .y = bounds.y }, .{ .x = bounds.x + bounds.width, .y = bounds.y + bounds.height }, color, thickness);
        try self.drawLine(.{ .x = bounds.x + bounds.width, .y = bounds.y + bounds.height }, .{ .x = bounds.x, .y = bounds.y + bounds.height }, color, thickness);
        try self.drawLine(.{ .x = bounds.x, .y = bounds.y + bounds.height }, .{ .x = bounds.x, .y = bounds.y }, color, thickness);
    }

    pub fn drawArrow(
        self: *Renderer2D,
        from: Vec2,
        to: Vec2,
        color: Color,
        thickness: f32,
    ) std.mem.Allocator.Error!void {
        try self.drawLine(from, to, color, thickness);
        const dx = to.x - from.x;
        const dy = to.y - from.y;
        const len = @sqrt(dx * dx + dy * dy);
        if (len > 0.001) {
            const udx = dx / len;
            const udy = dy / len;
            const head_len: f32 = @min(10.0, len * 0.4);
            const perp_x = -udy;
            const perp_y = udx;
            const wing1 = Vec2{
                .x = to.x - udx * head_len + perp_x * (head_len * 0.5),
                .y = to.y - udy * head_len + perp_y * (head_len * 0.5),
            };
            const wing2 = Vec2{
                .x = to.x - udx * head_len - perp_x * (head_len * 0.5),
                .y = to.y - udy * head_len - perp_y * (head_len * 0.5),
            };
            try self.drawLine(to, wing1, color, thickness);
            try self.drawLine(to, wing2, color, thickness);
        }
    }

    /// Draws an editor grid in world-space increments.
    ///
    /// Grid spacing is measured in world units. Camera zoom determines
    /// the distance between grid lines in pixels.
    pub fn drawGrid(
        self: *Renderer2D,
        camera: Camera2D,
        spacing: f32,
        grid_color: Color,
        axis_color: Color,
    ) std.mem.Allocator.Error!void {
        if (spacing <= 0 or camera.zoom <= 0) return;

        const world = camera.visibleWorldRect();
        const right = world.x + world.width;
        const bottom = world.y + world.height;

        const first_x = @floor(world.x / spacing) * spacing;
        const first_y = @floor(world.y / spacing) * spacing;

        // Guard against accidentally producing millions of grid lines.
        const estimated_x = @ceil(world.width / spacing) + 2;
        const estimated_y = @ceil(world.height / spacing) + 2;

        if (estimated_x > 1000 or estimated_y > 1000) return;

        var x = first_x;
        while (x <= right) : (x += spacing) {
            const screen = camera.worldToScreen(.{
                .x = x,
                .y = camera.position.y,
            });

            const color = if (@abs(x) < 0.001) axis_color else grid_color;

            try self.drawLine(
                .{ .x = screen.x, .y = camera.viewport.y },
                .{
                    .x = screen.x,
                    .y = camera.viewport.y + camera.viewport.height,
                },
                color,
                1,
            );
        }

        var y = first_y;
        while (y <= bottom) : (y += spacing) {
            const screen = camera.worldToScreen(.{
                .x = camera.position.x,
                .y = y,
            });

            const color = if (@abs(y) < 0.001) axis_color else grid_color;

            try self.drawLine(
                .{ .x = camera.viewport.x, .y = screen.y },
                .{
                    .x = camera.viewport.x + camera.viewport.width,
                    .y = screen.y,
                },
                color,
                1,
            );
        }
    }
};

// =====================================================================
// Tests
// =====================================================================

test "camera converts world coordinates to screen coordinates" {
    const camera = Camera2D{
        .position = .{ .x = 100, .y = 50 },
        .zoom = 2,
        .viewport = .{
            .x = 200,
            .y = 100,
            .width = 800,
            .height = 600,
        },
    };

    const screen = camera.worldToScreen(.{
        .x = 100,
        .y = 50,
    });

    try std.testing.expectEqual(@as(f32, 600), screen.x);
    try std.testing.expectEqual(@as(f32, 400), screen.y);
}

test "camera converts screen coordinates back to world coordinates" {
    const camera = Camera2D{
        .position = .{ .x = 100, .y = 50 },
        .zoom = 2,
        .viewport = .{
            .x = 200,
            .y = 100,
            .width = 800,
            .height = 600,
        },
    };

    const original = Vec2{ .x = 125, .y = 80 };
    const screen = camera.worldToScreen(original);
    const recovered = camera.screenToWorld(screen);

    try std.testing.expectApproxEqAbs(
        original.x,
        recovered.x,
        0.001,
    );

    try std.testing.expectApproxEqAbs(
        original.y,
        recovered.y,
        0.001,
    );
}

test "rect bounds reject invalid and outside points" {
    const rect = Rect{ .x = 10, .y = 20, .width = 100, .height = 50 };
    try std.testing.expect(rect.isValid());
    try std.testing.expect(rect.contains(.{ .x = 10, .y = 20 }));
    try std.testing.expect(!rect.contains(.{ .x = 110, .y = 20 }));
}

test "camera calculates the visible world rectangle" {
    const camera = Camera2D{
        .position = .{ .x = 100, .y = 50 },
        .zoom = 2,
        .viewport = .{
            .width = 800,
            .height = 600,
        },
    };

    const rect = camera.visibleWorldRect();

    try std.testing.expectEqual(@as(f32, -100), rect.x);
    try std.testing.expectEqual(@as(f32, -100), rect.y);
    try std.testing.expectEqual(@as(f32, 400), rect.width);
    try std.testing.expectEqual(@as(f32, 300), rect.height);
}

test "renderer records and clears draw commands" {
    var renderer = Renderer2D.init(std.testing.allocator);
    defer renderer.deinit();

    try renderer.drawRect(
        .{ .x = 10, .y = 20, .width = 50, .height = 30 },
        .{ .r = 255, .g = 0, .b = 0 },
    );

    try renderer.drawLine(
        .{ .x = 0, .y = 0 },
        .{ .x = 100, .y = 100 },
        .{ .r = 255, .g = 255, .b = 255 },
        1,
    );

    try std.testing.expectEqual(@as(usize, 2), renderer.getCommands().len);

    renderer.clear();

    try std.testing.expectEqual(@as(usize, 0), renderer.getCommands().len);
}
