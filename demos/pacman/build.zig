const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const sdl = b.dependency("sdl3", .{ .target = target, .optimize = optimize, .main = true });
    const renderer = b.createModule(.{ .root_source_file = b.path("../../src/render/renderer.zig"), .target = target, .optimize = optimize });
    const game = b.createModule(.{ .root_source_file = b.path("src/main.zig"), .target = target, .optimize = optimize });
    game.addImport("renderer", renderer);
    game.addImport("sdl3", sdl.module("sdl3"));
    const ui_render = b.createModule(.{ .root_source_file = b.path("../../src/ui/render_sdl.zig"), .target = target, .optimize = optimize });
    ui_render.addImport("ui-components", b.createModule(.{ .root_source_file = b.path("../../src/ui_components.zig"), .target = target, .optimize = optimize }));
    game.addImport("ui-render", ui_render);
    const exe = b.addExecutable(.{ .name = "pacman", .root_module = game });
    b.installArtifact(exe);
    const run = b.addRunArtifact(exe);
    run.step.dependOn(b.getInstallStep());
    const step = b.step("run", "Run Pacman");
    step.dependOn(&run.step);
}
