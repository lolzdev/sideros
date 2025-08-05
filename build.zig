const std = @import("std");

const ShaderStage = enum { fragment, vertex };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const math = b.createModule(.{
        .root_source_file = b.path("src/math.zig"),
        .target = target,
        .optimize = optimize,
    });

    const mods = b.createModule(.{
        .root_source_file = b.path("src/mods/mods.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ecs = b.createModule(.{
        .root_source_file = b.path("src/ecs/ecs.zig"),
        .target = target,
        .optimize = optimize,
    });

    const renderer = b.createModule(.{
        .root_source_file = b.path("src/renderer/Renderer.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    renderer.addIncludePath(b.path("ext"));
    renderer.addCSourceFile(.{ .file = b.path("ext/stb_image.c") });
    //renderer.addImport("sideros", sideros);
    renderer.addImport("math", math);
    renderer.addImport("ecs", ecs);
    // TODO(ernesto): ecs and renderer should be decoupled
    ecs.addImport("renderer", renderer);

    compileAllShaders(b, renderer);

    const sideros = b.addLibrary(.{
        .name = "sideros",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sideros.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sideros.addIncludePath(b.path("ext"));
    sideros.addIncludePath(b.path("src"));

    sideros.root_module.addImport("mods", mods);
    sideros.root_module.addImport("ecs", ecs);
    sideros.root_module.addImport("renderer", renderer);

    b.installArtifact(sideros);

    const options = b.addOptions();

    switch (target.result.os.tag) {
        .linux => {
            const wayland = b.option(bool, "wayland", "Use Wayland to create the main window") orelse false;
            options.addOption(bool, "wayland", wayland);

            const exe = b.addExecutable(.{
                .name = if (wayland) "sideros-wayland" else "sideros-xorg",
                .root_module = b.createModule(.{
                    .root_source_file = b.path(if (wayland) "src/wayland.zig" else "src/xorg.zig"),
                    .target = target,
                    .optimize = optimize,
                }),
            });
            exe.root_module.addIncludePath(b.path("src"));
            exe.linkLibrary(sideros);
            exe.linkLibC();
            exe.linkSystemLibrary("vulkan");
            if (wayland) {
                exe.root_module.addIncludePath(b.path("ext"));
                exe.linkSystemLibrary("wayland-client");
                exe.root_module.addCSourceFile(.{ .file = b.path("ext/xdg-shell.c") });
            } else {
                exe.linkSystemLibrary("xcb");
                exe.linkSystemLibrary("xcb-icccm");
            }
            b.installArtifact(exe);
        },
        else => {
            std.debug.panic("Compilation not implemented for OS: {any}\n", .{target.result.os.tag});
        },
    }

    const install_docs = b.addInstallDirectory(.{
        .source_dir = sideros.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs/sideros",
    });
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);

    //const run_cmd = b.addRunArtifact(exe);
    //run_cmd.step.dependOn(b.getInstallStep());

    //if (b.args) |args| {
    //run_cmd.addArgs(args);
    //}

    //const run_step = b.step("run", "Run the app");
    //run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn compileAllShaders(b: *std.Build, module: *std.Build.Module) void {
    const shaders_dir = if (@hasDecl(@TypeOf(b.build_root.handle), "openIterableDir"))
        b.build_root.handle.openIterableDir("assets/shaders", .{}) catch @panic("Failed to open shaders directory")
    else
        b.build_root.handle.openDir("assets/shaders", .{ .iterate = true }) catch @panic("Failed to open shaders directory");

    var file_it = shaders_dir.iterate();
    while (file_it.next() catch @panic("Failed to iterate shader directory")) |entry| {
        if (entry.kind == .file) {
            const ext = std.fs.path.extension(entry.name);
            const basename = std.fs.path.basename(entry.name);
            const name = basename[0 .. basename.len - ext.len];
            if (std.mem.eql(u8, ext, ".vert")) {
                addShader(b, module, name, .vertex);
            } else if (std.mem.eql(u8, ext, ".frag")) {
                addShader(b, module, name, .fragment);
            }
        }
    }
}

fn addShader(b: *std.Build, module: *std.Build.Module, name: []const u8, stage: ShaderStage) void {
    const mod_name = std.fmt.allocPrint(b.allocator, "{s}_{s}", .{ name, if (stage == .vertex) "vert" else "frag" }) catch @panic("");
    const source = std.fmt.allocPrint(b.allocator, "assets/shaders/{s}.{s}", .{ name, if (stage == .vertex) "vert" else "frag" }) catch @panic("");
    const outpath = std.fmt.allocPrint(b.allocator, "assets/shaders/{s}_{s}.spv", .{ name, if (stage == .vertex) "vert" else "frag" }) catch @panic("");

    const shader_compilation = b.addSystemCommand(&.{"glslc"});
    shader_compilation.addArg("-o");
    const output = shader_compilation.addOutputFileArg(outpath);
    shader_compilation.addFileArg(b.path(source));

    module.addAnonymousImport(mod_name, .{ .root_source_file = output });
}
