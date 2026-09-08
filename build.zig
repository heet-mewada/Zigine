const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zigine", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const project_creation = b.addModule("project_creation", .{
        .root_source_file = b.path("src/project-creation.zig"),
        .target = target,
    });

    const ui_components = b.addModule("UI_components", .{
        .root_source_file = b.path("src/ui_components.zig"),
        .target = target,
    });

    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,

        // Lib options.
        .ext_image = true,
        .ext_mixer = true,
        .ext_net = false,
        .ext_shadercross = false,
        .ext_shadercross_dxc = false,
        .ext_ttf = true,
        .log_message_stack_size = 1024,
        .main = true,
        .renderer_debug_text_stack_size = 1024,

        // Options passed directly to https://github.com/castholm/SDL (SDL3 C Bindings):
        // .c_sdl_preferred_linkage = .static,
        // .c_sdl_strip = false,
        // .c_sdl_sanitize_c = .off,
        // .c_sdl_lto = .none,
        // .c_sdl_emscripten_pthreads = false,
        // .c_sdl_install_build_config_h = false,

        // Options if `ext_image` is enabled:
        // .image_enable_bmp = true,
        // .image_enable_gif = true,
        // .image_enable_jpg = true,
        // .image_enable_lbm = true,
        // .image_enable_pcx = true,
        // .image_enable_png = true,
        // .image_enable_pnm = true,
        // .image_enable_qoi = true,
        // .image_enable_svg = true,
        // .image_enable_tga = true,
        // .image_enable_xcf = true,
        // .image_enable_xpm = true,
        // .image_enable_xv = true,
        //
        // Options if `ext_mixer` is enabled:
        // .mixer_shared = false,
        //
        // Options if `ext_net` is enabled:
        // .net_shared = false,
    });

    const exe = b.addExecutable(.{
        .name = "zigine",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "zigine", .module = mod },
            },
        }),
    });

    const sdl_testing = b.addExecutable(.{
        .name = "sdl-test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sdl-testing.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdl-test", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);
    b.installArtifact(sdl_testing);

    exe.root_module.addImport("sdl3", sdl3.module("sdl3"));
    exe.root_module.addImport("project_creation", project_creation);
    exe.root_module.addImport("ui_components", ui_components);
    sdl_testing.root_module.addImport("sdl3", sdl3.module("sdl3"));

    const run_step = b.step("run", "Run the app");
    const sdl_step = b.step("sdl", "Test sdl");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    const sdl_cmd = b.addRunArtifact(sdl_testing);
    sdl_step.dependOn(&sdl_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());
    sdl_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
        sdl_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
