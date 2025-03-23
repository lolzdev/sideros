const std = @import("std");

const ShaderStage = enum { fragment, vertex };

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const glfw = b.addStaticLibrary(.{
        .name = "glfw",
        .target = target,
        .optimize = optimize,
    });
    glfw.addCSourceFiles(.{ .files = &[_][]const u8{
        "ext/glfw/src/cocoa_init.m",
        "ext/glfw/src/cocoa_joystick.m",
        "ext/glfw/src/cocoa_monitor.m",
        "ext/glfw/src/cocoa_time.c",
        "ext/glfw/src/cocoa_window.m",
        "ext/glfw/src/context.c",
        "ext/glfw/src/egl_context.c",
        "ext/glfw/src/glx_context.c",
        "ext/glfw/src/init.c",
        "ext/glfw/src/input.c",
        "ext/glfw/src/linux_joystick.c",
        "ext/glfw/src/monitor.c",
        "ext/glfw/src/nsgl_context.m",
        "ext/glfw/src/null_init.c",
        "ext/glfw/src/null_joystick.c",
        "ext/glfw/src/null_monitor.c",
        "ext/glfw/src/null_window.c",
        "ext/glfw/src/osmesa_context.c",
        "ext/glfw/src/platform.c",
        "ext/glfw/src/posix_module.c",
        "ext/glfw/src/posix_poll.c",
        "ext/glfw/src/posix_thread.c",
        "ext/glfw/src/posix_time.c",
        "ext/glfw/src/vulkan.c",
        "ext/glfw/src/wgl_context.c",
        "ext/glfw/src/win32_init.c",
        "ext/glfw/src/win32_joystick.c",
        "ext/glfw/src/win32_module.c",
        "ext/glfw/src/win32_monitor.c",
        "ext/glfw/src/win32_thread.c",
        "ext/glfw/src/win32_time.c",
        "ext/glfw/src/win32_window.c",
        "ext/glfw/src/window.c",
        "ext/glfw/src/wl_init.c",
        "ext/glfw/src/wl_monitor.c",
        "ext/glfw/src/wl_window.c",
        "ext/glfw/src/x11_init.c",
        "ext/glfw/src/x11_monitor.c",
        "ext/glfw/src/x11_window.c",
        "ext/glfw/src/xkb_unicode.c",
    }, .flags = &[_][]const u8{ "-D_GLFW_X11", "-Wall", "-Wextra" } });
    glfw.linkLibC();

    const mods = b.addModule("mods", .{
        .root_source_file = b.path("src/mods/mods.zig"),
        .target = target,
        .optimize = optimize,
    });

    const ecs = b.addModule("ecs", .{
        .root_source_file = b.path("src/ecs/ecs.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .name = "sideros",
    });
    exe.root_module.addImport("mods", mods);
    exe.root_module.addImport("ecs", ecs);
    exe.addIncludePath(b.path("ext/glfw/include"));

    exe.linkSystemLibrary("vulkan");
    compileAllShaders(b, exe);
    exe.linkLibrary(glfw);
    exe.linkLibC();

    b.installArtifact(exe);

    // TODO: This does not generate documentation correctly?
    const install_docs = b.addInstallDirectory(.{
        .source_dir = exe.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Generate documentation");
    docs_step.dependOn(&install_docs.step);

    // NOTE: This is a hack to generate documentation
    const mods_lib = b.addStaticLibrary(.{
        .root_module = mods,
        .name = "mods",
    });
    const mods_docs = b.addInstallDirectory(.{
        .source_dir = mods_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs/mods",
    });
    docs_step.dependOn(&mods_docs.step);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}

fn compileAllShaders(b: *std.Build, exe: *std.Build.Step.Compile) void {
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
                addShader(b, exe, name, .vertex);
            } else if (std.mem.eql(u8, ext, ".frag")) {
                addShader(b, exe, name, .fragment);
            }
        }
    }
}

fn addShader(b: *std.Build, exe: *std.Build.Step.Compile, name: []const u8, stage: ShaderStage) void {
    const mod_name = std.fmt.allocPrint(b.allocator, "{s}_{s}", .{ name, if (stage == .vertex) "vert" else "frag" }) catch @panic("");
    const source = std.fmt.allocPrint(b.allocator, "assets/shaders/{s}.{s}", .{ name, if (stage == .vertex) "vert" else "frag" }) catch @panic("");
    const outpath = std.fmt.allocPrint(b.allocator, "assets/shaders/{s}_{s}.spv", .{ name, if (stage == .vertex) "vert" else "frag" }) catch @panic("");

    const shader_compilation = b.addSystemCommand(&.{"glslc"});
    shader_compilation.addArg("-o");
    const output = shader_compilation.addOutputFileArg(outpath);
    shader_compilation.addFileArg(b.path(source));

    exe.root_module.addAnonymousImport(mod_name, .{ .root_source_file = output });
}
