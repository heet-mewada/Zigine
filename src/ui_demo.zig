const sdl3 = @import("sdl3");
const ui = @import("ui-components");

const WIDTH: usize = 800;
const HEIGHT: usize = 600;

pub fn main() !void {
    const flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(flags);
    defer sdl3.quit(flags);

    const window = try sdl3.video.Window.init(
        "zigine - UI Layout Demo",
        WIDTH,
        HEIGHT,
        .{ .resizable = true },
    );
    defer window.deinit();

    var context = ui.Context.init();
    var running = true;

    while (running) {
        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit, .terminating => running = false,
                else => {},
            }
        }

        if (!running) break;

        // Build the UI tree for this frame.
        context.beginFrame(.{
            .width = @floatFromInt(WIDTH),
            .height = @floatFromInt(HEIGHT),
        });

        // Root container fills the window.
        try context.begin(1, .{
            .direction = .top_to_bottom,
            .width = ui.Sizing.grow(),
            .height = ui.Sizing.grow(),
            .padding = ui.Padding.all(20),
            .gap = 16,
        }, .{ .r = 25, .g = 28, .b = 38, .a = 255 });

        // Three columns: fixed, grow, and grow.
        try context.begin(2, .{
            .direction = .left_to_right,
            .width = ui.Sizing.grow(),
            .height = ui.Sizing.fixed(260),
            .padding = ui.Padding.all(12),
            .gap = 12,
        }, .{ .r = 40, .g = 44, .b = 58, .a = 255 });

        // Fixed-width element: always 140 pixels wide.
        try context.rect(3, .{
            .width = ui.Sizing.fixed(140),
            .height = ui.Sizing.grow(),
        }, .{ .r = 220, .g = 90, .b = 90, .a = 255 });

        // Grow elements share the remaining width.
        try context.rect(4, .{
            .width = ui.Sizing.grow(),
            .height = ui.Sizing.grow(),
        }, .{ .r = 90, .g = 170, .b = 240, .a = 255 });

        try context.rect(5, .{
            .width = ui.Sizing.grow(),
            .height = ui.Sizing.grow(),
        }, .{ .r = 100, .g = 205, .b = 140, .a = 255 });

        context.end();

        // A second panel demonstrating horizontal gaps and fixed sizes.
        try context.begin(6, .{
            .direction = .left_to_right,
            .width = ui.Sizing.grow(),
            .height = ui.Sizing.fixed(180),
            .padding = ui.Padding.all(12),
            .gap = 16,
            .align_y = .center,
        }, .{ .r = 40, .g = 44, .b = 58, .a = 255 });

        try context.rect(7, .{
            .width = ui.Sizing.fixed(80),
            .height = ui.Sizing.fixed(80),
        }, .{ .r = 240, .g = 190, .b = 80, .a = 255 });

        try context.rect(8, .{
            .width = ui.Sizing.fixed(120),
            .height = ui.Sizing.fixed(110),
        }, .{ .r = 190, .g = 120, .b = 230, .a = 255 });

        try context.rect(9, .{
            .width = ui.Sizing.grow(),
            .height = ui.Sizing.fixed(60),
        }, .{ .r = 230, .g = 230, .b = 240, .a = 255 });

        context.end();
        context.end();

        // Resolve layout into flat draw commands.
        const commands = context.endFrame();

        // Render the resulting rectangles using the 7Games SDL3 surface API.
        const surface = try window.getSurface();

        try surface.fillRect(
            null,
            surface.mapRgb(25, 28, 38),
        );

        for (commands) |command| {
            if (command.color.a == 0) continue;

            const bounds = command.bounds;

            try surface.fillRect(.{
                .x = @intFromFloat(bounds.x),
                .y = @intFromFloat(bounds.y),
                .w = @intFromFloat(bounds.width),
                .h = @intFromFloat(bounds.height),
            }, surface.mapRgb(
                command.color.r,
                command.color.g,
                command.color.b,
            ));
        }

        try window.updateSurface();
    }
}
