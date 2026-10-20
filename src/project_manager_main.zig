const sdl3 = @import("sdl3");
const pm = @import("project-manager-ui");
const ui = @import("ui-components");
const render = @import("ui/render_sdl.zig");

const WIDTH: usize = 1100;
const HEIGHT: usize = 720;

pub fn main() !void {
    const flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(flags);
    defer sdl3.quit(flags);

    const window = try sdl3.video.Window.init(
        "Zigine - Project Manager",
        WIDTH,
        HEIGHT,
        .{ .resizable = true },
    );
    defer window.deinit();

    var manager = pm.ProjectManager.init();
    manager.setTheme(.catppuccin_mocha);

    var running = true;

    while (running) {
        while (sdl3.events.poll()) |event| {
            switch (event) {
                .quit, .terminating => running = false,
                else => {},
            }
        }

        if (!running) break;

        const surface = try window.getSurface();

        const viewport_width: f32 = @floatFromInt(surface.getWidth());
        const viewport_height: f32 = @floatFromInt(surface.getHeight());

        const commands = try manager.build(viewport_width, viewport_height);

        try surface.fillRect(
            null,
            surface.mapRgb(30, 30, 46),
        );

        for (commands) |command| {
            if (command.color.a == 0) continue;

            const bounds = ui.intersectRects(
                command.bounds,
                command.clip_bounds,
            );

            const left: i32 = @intFromFloat(@ceil(bounds.x));
            const top: i32 = @intFromFloat(@ceil(bounds.y));
            const right: i32 = @intFromFloat(@floor(bounds.x + bounds.width));
            const bottom: i32 = @intFromFloat(@floor(bounds.y + bounds.height));

            if (right <= left or bottom <= top) continue;

            switch (command.kind) {
                .container, .rectangle => {
                    try surface.fillRect(.{
                        .x = left,
                        .y = top,
                        .w = right - left,
                        .h = bottom - top,
                    }, surface.mapRgb(
                        command.color.r,
                        command.color.g,
                        command.color.b,
                    ));
                },
                .text => {
                    try render.drawText(
                        surface,
                        command.bounds,
                        command.text,
                        command.color,
                        command.clip_bounds,
                        .{ .scale = 2, .wrap = true },
                    );
                },
            }
        }

        try window.updateSurface();
    }
}

