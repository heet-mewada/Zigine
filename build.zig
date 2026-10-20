const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ------------------------------------------------------------
    // SDL3 dependency
    // ------------------------------------------------------------

    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .ext_image = true,
        .ext_mixer = true,
        .ext_net = false,
        .ext_shadercross = false,
        .ext_shadercross_dxc = false,
        .ext_ttf = true,
        .log_message_stack_size = 1024,
        .main = true,
        .renderer_debug_text_stack_size = 1024,
    });

    const sdl3_module = sdl3.module("sdl3");

    // ------------------------------------------------------------
    // Core modules
    // ------------------------------------------------------------

    const zigine_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const project_creation_module = b.createModule(.{
        .root_source_file = b.path("src/project-creation.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ui_components_module = b.createModule(.{
        .root_source_file = b.path("src/ui_components.zig"),
        .target = target,
        .optimize = optimize,
    });

    const project_registry_module = b.createModule(.{
        .root_source_file = b.path("src/project_registry.zig"),
        .target = target,
        .optimize = optimize,
    });

    const settings_module = b.createModule(.{
        .root_source_file = b.path("src/settings.zig"),
        .target = target,
        .optimize = optimize,
    });

    settings_module.addImport(
        "project-registry",
        project_registry_module,
    );

    const directory_picker_module = b.createModule(.{
        .root_source_file = b.path("src/directory_picker.zig"),
        .target = target,
        .optimize = optimize,
    });

    directory_picker_module.addImport(
        "ui-components",
        ui_components_module,
    );

    // ------------------------------------------------------------
    // SDL UI renderer
    // ------------------------------------------------------------

    const render_sdl_module = b.createModule(.{
        .root_source_file = b.path("src/ui/render_sdl.zig"),
        .target = target,
        .optimize = optimize,
    });

    render_sdl_module.addImport("sdl3", sdl3_module);
    render_sdl_module.addImport(
        "ui-components",
        ui_components_module,
    );

    // ------------------------------------------------------------
    // Project manager UI
    // ------------------------------------------------------------

    const project_manager_module = b.createModule(.{
        .root_source_file = b.path("src/project_manager.zig"),
        .target = target,
        .optimize = optimize,
    });

    project_manager_module.addImport(
        "ui-components",
        ui_components_module,
    );

    project_manager_module.addImport(
        "project_creation",
        project_creation_module,
    );

    project_manager_module.addImport(
        "project-registry",
        project_registry_module,
    );

    project_manager_module.addImport(
        "app-settings",
        settings_module,
    );

    // ------------------------------------------------------------
    // Renderer
    // ------------------------------------------------------------

    const renderer_module = b.createModule(.{
        .root_source_file = b.path("src/render/renderer.zig"),
        .target = target,
        .optimize = optimize,
    });

    renderer_module.addImport("sdl3", sdl3_module);
    renderer_module.addImport(
        "ui-components",
        ui_components_module,
    );

    // ------------------------------------------------------------
    // Scene modules
    // ------------------------------------------------------------

    const scene_module = b.createModule(.{
        .root_source_file = b.path("src/scene/scene.zig"),
        .target = target,
        .optimize = optimize,
    });

    const scene_tree_module = b.createModule(.{
        .root_source_file = b.path("src/scene/scene_tree.zig"),
        .target = target,
        .optimize = optimize,
    });

    scene_tree_module.addImport("scene", scene_module);

    const scene_renderer_module = b.createModule(.{
        .root_source_file = b.path("src/scene/scene_renderer.zig"),
        .target = target,
        .optimize = optimize,
    });

    scene_renderer_module.addImport("sdl3", sdl3_module);
    scene_renderer_module.addImport("scene", scene_module);
    scene_renderer_module.addImport("scene-tree", scene_tree_module);
    scene_renderer_module.addImport("renderer", renderer_module);

    // ------------------------------------------------------------
    // Editor
    // ------------------------------------------------------------

    const editor_module = b.createModule(.{
        .root_source_file = b.path("src/editor.zig"),
        .target = target,
        .optimize = optimize,
    });

    editor_module.addImport("ui-components", ui_components_module);
    editor_module.addImport("sdl3", sdl3_module);
    editor_module.addImport("render-sdl", render_sdl_module);
    editor_module.addImport("scene", scene_module);
    editor_module.addImport("scene-tree", scene_tree_module);
    editor_module.addImport("renderer", renderer_module);
    editor_module.addImport("scene-renderer", scene_renderer_module);

    // ------------------------------------------------------------
    // Main Zigine application
    // ------------------------------------------------------------

    const main_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    main_module.addImport("sdl3", sdl3_module);
    main_module.addImport("zigine", zigine_module);
    main_module.addImport("project_creation", project_creation_module);
    main_module.addImport("directory-picker", directory_picker_module);
    main_module.addImport("ui-components", ui_components_module);
    main_module.addImport("project-manager-ui", project_manager_module);
    main_module.addImport("project-registry", project_registry_module);
    main_module.addImport("app-settings", settings_module);
    main_module.addImport("editor", editor_module);
    main_module.addImport("render-sdl", render_sdl_module);
    main_module.addImport("renderer", renderer_module);
    main_module.addImport("scene", scene_module);
    main_module.addImport("scene-tree", scene_tree_module);
    main_module.addImport("scene-renderer", scene_renderer_module);

    const exe = b.addExecutable(.{
        .name = "zigine",
        .root_module = main_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Build and run Zigine");
    run_step.dependOn(&run_cmd.step);

    // ------------------------------------------------------------
    // UI demo
    // ------------------------------------------------------------

    const ui_demo_module = b.createModule(.{
        .root_source_file = b.path("src/ui_demo.zig"),
        .target = target,
        .optimize = optimize,
    });

    ui_demo_module.addImport("sdl3", sdl3_module);
    ui_demo_module.addImport("ui-components", ui_components_module);
    ui_demo_module.addImport("render-sdl", render_sdl_module);

    const ui_demo_exe = b.addExecutable(.{
        .name = "ui-demo",
        .root_module = ui_demo_module,
    });

    const ui_demo_run = b.addRunArtifact(ui_demo_exe);

    if (b.args) |args| {
        ui_demo_run.addArgs(args);
    }

    const ui_demo_step = b.step("ui-demo", "Run the UI demo");
    ui_demo_step.dependOn(&ui_demo_run.step);

    // ------------------------------------------------------------
    // SDL test
    // ------------------------------------------------------------

    const sdl_test_module = b.createModule(.{
        .root_source_file = b.path("src/sdl-testing.zig"),
        .target = target,
        .optimize = optimize,
    });

    sdl_test_module.addImport("sdl3", sdl3_module);

    const sdl_test_exe = b.addExecutable(.{
        .name = "sdl-test",
        .root_module = sdl_test_module,
    });

    const sdl_test_run = b.addRunArtifact(sdl_test_exe);
    const sdl_test_step = b.step("sdl-test", "Run the SDL3 test");
    sdl_test_step.dependOn(&sdl_test_run.step);

    // ------------------------------------------------------------
    // Core tests
    // ------------------------------------------------------------

    const core_tests_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const core_tests = b.addTest(.{
        .root_module = core_tests_module,
    });

    const run_core_tests = b.addRunArtifact(core_tests);
    const test_step = b.step("test", "Run Zigine tests");
    test_step.dependOn(&run_core_tests.step);
}
