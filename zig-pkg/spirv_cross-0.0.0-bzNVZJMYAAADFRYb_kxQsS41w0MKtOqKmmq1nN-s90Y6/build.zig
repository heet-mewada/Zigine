const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const build_shared = b.option(bool, "spv_cross_build_shared", "Whether to build a shared lib") orelse false;

    const glsl = b.option(bool, "spv_cross_glsl", "Build GLSL support into SPIRV-Cross") orelse true;
    const hlsl = b.option(bool, "spv_cross_hlsl", "Build HLSL support into SPIRV-Cross") orelse true;
    const msl = b.option(bool, "spv_cross_msl", "Build MSL support into SPIRV-Cross") orelse true;
    const cpp = b.option(bool, "spv_cross_cpp", "Build C++ support into SPIRV-Cross") orelse true;
    const reflect = b.option(bool, "spv_cross_reflect", "Build JSON Reflection support into SPIRV-Cross") orelse true;
    const c_api = b.option(bool, "spv_cross_c_api", "Build C-API support into SPIRV-Cross") orelse true;
    const util = b.option(bool, "spv_cross_util", "Build SPIRV-Cross util support") orelse true;

    const pic = b.option(bool, "pic", "Whether to use PIC when building the library");

    const options: SpirvCrossOptions = .{
        .glsl = glsl,
        .hlsl = hlsl,
        .msl = msl,
        .cpp = cpp,
        .reflect = reflect,
        .c_api = c_api,
        .util = util,
        .pic = pic,
    };

    const lib = try createSpirvCross(b, build_shared, target, optimize, options);
    b.installArtifact(lib);
}

pub const SpirvCrossOptions = struct {
    glsl: bool = true,
    hlsl: bool = true,
    msl: bool = true,
    cpp: bool = true,
    reflect: bool = true,
    c_api: bool = true,
    util: bool = true,
    pic: ?bool = null,
};

pub fn createSpirvCross(
    b: *std.Build,
    shared: bool,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: SpirvCrossOptions,
) !*std.Build.Step.Compile {
    const c_flags = blk: {
        const flags = &.{"-std=c++11"};

        break :blk flags;
    };

    const core_sources = &.{
        "spirv_cross.cpp",
        "spirv_parser.cpp",
        "spirv_cross_parsed_ir.cpp",
        "spirv_cfg.cpp",
    };

    const c_sources = &.{"spirv_cross_c.cpp"};
    const glsl_sources = &.{"spirv_glsl.cpp"};
    const cpp_sources = &.{"spirv_cpp.cpp"};
    const msl_sources = &.{"spirv_msl.cpp"};
    const hlsl_sources = &.{"spirv_hlsl.cpp"};
    const reflect_sources = &.{"spirv_reflect.cpp"};
    const util_sources = &.{"spirv_cross_util.cpp"};

    const spirv_cross_version = "0.64.0";
    _ = spirv_cross_version; // autofix

    const spirv_cross = b.addLibrary(.{
        .name = "spirv-cross-c",
        .linkage = if (shared) .dynamic else .static,
        .root_module = b.addModule("spirv-cross-c", .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .link_libcpp = true,
        }),
    });

    spirv_cross.root_module.pic = options.pic;

    if (shared)
        spirv_cross.root_module.addCMacro("SPVC_EXPORT_SYMBOLS", "1");

    if (b.lazyDependency("SPIRV-Cross", .{})) |upstream| {
        spirv_cross.root_module.addCSourceFiles(.{
            .files = core_sources,
            .flags = c_flags,
            .root = upstream.path("."),
        });

        if (options.glsl) {
            spirv_cross.root_module.addCSourceFiles(.{
                .files = glsl_sources,
                .flags = c_flags,
                .root = upstream.path("."),
            });
        }

        if (options.cpp) {
            if (!options.glsl)
                @panic("GLSL must be enabled to enable C++ support");

            spirv_cross.root_module.addCSourceFiles(.{
                .files = cpp_sources,
                .flags = c_flags,
                .root = upstream.path("."),
            });
        }

        if (options.reflect) {
            if (!options.glsl)
                @panic("GLSL must be enabled to enable JSON reflection support");

            spirv_cross.root_module.addCSourceFiles(.{
                .files = reflect_sources,
                .flags = c_flags,
                .root = upstream.path("."),
            });
        }

        if (options.msl) {
            if (!options.glsl)
                @panic("GLSL must be enabled to enable MSL support");

            spirv_cross.root_module.addCSourceFiles(.{
                .files = msl_sources,
                .flags = c_flags,
                .root = upstream.path("."),
            });
        }

        if (options.hlsl) {
            if (!options.glsl)
                @panic("GLSL must be enabled to enable HLSL support");

            spirv_cross.root_module.addCSourceFiles(.{
                .files = hlsl_sources,
                .flags = c_flags,
                .root = upstream.path("."),
            });
        }

        if (options.util) {
            spirv_cross.root_module.addCSourceFiles(.{
                .files = util_sources,
                .flags = c_flags,
                .root = upstream.path("."),
            });
        }

        if (options.c_api) {
            spirv_cross.root_module.addCSourceFiles(.{
                .files = c_sources,
                .flags = c_flags,
                .root = upstream.path("."),
            });

            if (options.glsl) spirv_cross.root_module.addCMacro("SPIRV_CROSS_C_API_GLSL", "1");
            if (options.hlsl) spirv_cross.root_module.addCMacro("SPIRV_CROSS_C_API_HLSL", "1");
            if (options.msl) spirv_cross.root_module.addCMacro("SPIRV_CROSS_C_API_MSL", "1");
            if (options.cpp) spirv_cross.root_module.addCMacro("SPIRV_CROSS_C_API_CPP", "1");
            if (options.reflect) spirv_cross.root_module.addCMacro("SPIRV_CROSS_C_API_REFLECT", "1");
        }

        spirv_cross.installHeader(upstream.path("spirv_cross_c.h"), "spirv_cross_c.h");
    }

    return spirv_cross;
}
