const sdl3 = @import("sdl3");

pub fn main() !void {
    const flags = sdl3.InitFlags{ .video = true };
    try sdl3.init(flags);
    defer sdl3.quit(flags);
    const window = try sdl3.video.Window.init("Zigine SDL3 Game", 960, 540, .{});
    defer window.deinit();
    var running = true;
    while (running) {
        while (sdl3.events.poll()) |event| switch (event) {
            .quit, .terminating => running = false,
            else => {},
        };
        const surface = try window.getSurface();
        try surface.fillRect(null, surface.mapRgb(24, 28, 40));
        try window.updateSurface();
    }
}
