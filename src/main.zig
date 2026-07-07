const sdl3 = @import("sdl3");
const std = @import("std");

const fps = 60;
const screen_width = 640;
const screen_height = 480;


const Button = struct{
    x: i32,
    y: i32,
    w: i32,
    h: i32,
};

pub fn main() !void {
    defer sdl3.shutdown();

    // Initialize SDL with subsystems you need here.
    const init_flags = sdl3.InitFlags{ .video = true , .audio = true, .events=true};
    try sdl3.init(init_flags);
    defer sdl3.quit(init_flags);

    // Initial window setup.
    const window = try sdl3.video.Window.init("Hello SDL3", screen_width, screen_height, .{
        .resizable = true,
        .maximized = true,
    });
    defer window.deinit();

    // Useful for limiting the FPS and getting the delta time.
    var fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = fps } };

    const button = Button{
        .x = 40,
        .y = 40,
        .w = 200,
        .h = 50,
    };


    var quit = false;
    while (!quit) {

        // Delay to limit the FPS, returned delta time not needed.
        const dt = fps_capper.delay();
        _ = dt;

        // Update logic.
        const surface = try window.getSurface();
        try surface.fillRect(null, surface.mapRgb(255, 255, 255));
        try surface.fillRect(.{
            .x = button.x,
            .y = button.y,
            .h = button.h,
            .w = button.w,
        },   surface.mapRgb(0,0,0),
            );
        try window.updateSurface();




        // Event logic.
        while (sdl3.events.poll()) |event|
            switch (event) {
                .quit => quit = true,
                .terminating => quit = true,
    .key_down => {
    const e = event.key_down;

    if (e.key) |key| {
        switch (key) {
            .escape => quit = true,

            .w => std.debug.print("W\n", .{}),
            .a => std.debug.print("A\n", .{}),
            .s => std.debug.print("S\n", .{}),
            .d => std.debug.print("D\n", .{}),

            .space => std.debug.print("Jump\n", .{}),

            else => {},
        }
    }
},             else => {},
            };
    }
}
