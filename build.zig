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

    const ui = b.createModule(.{
        .root_source_file = b.path("src/ui/ui.zig"),
        .target = target,
        .optimize = optimize,
    });

    const vulkandeps = b.dependency("vulkan_headers", .{});

    const vulkan_c = b.addTranslateC(.{
        .root_source_file = b.addWriteFiles().add("vulkan.h",
            \\#include <vulkan/vulkan.h>
            \\#include <vulkan/vulkan_metal.h>
            \\#include <sideros_api.h>
        ),
        .target = target,
        .optimize = optimize,
    });
    vulkan_c.addIncludePath(vulkandeps.path("include/"));
    vulkan_c.addIncludePath(b.path("src"));

    const vulkan = vulkan_c.createModule();
    vulkan.link_libc = true;

    const rendering = b.createModule(.{
        .root_source_file = b.path("src/rendering/rendering.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    rendering.addIncludePath(b.path("ext"));
    if (target.result.os.tag == .macos) {
        rendering.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });
        rendering.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    }
    rendering.addCSourceFile(.{ .file = b.path("ext/stb_image.c") });
    rendering.addImport("math", math);
    rendering.addImport("vulkan", vulkan);
    rendering.addImport("ui", ui);

    const ecs = b.createModule(.{
        .root_source_file = b.path("src/ecs/ecs.zig"),
        .target = target,
        .optimize = optimize,
    });
    ecs.addImport("rendering", rendering);
    ecs.addImport("ui", ui);

    compileAllShaders(b, rendering);

    const sideros = b.addLibrary(.{
        .name = "sideros",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/sideros.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sideros.root_module.addIncludePath(b.path("ext"));
    sideros.root_module.addIncludePath(b.path("src"));
    if (target.result.os.tag == .macos) {
        sideros.root_module.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });
        sideros.root_module.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
    }

    sideros.root_module.addImport("mods", mods);
    sideros.root_module.addImport("ecs", ecs);
    sideros.root_module.addImport("rendering", rendering);
    sideros.root_module.addImport("math", math);
    sideros.root_module.addImport("vulkan", vulkan);
    sideros.root_module.addImport("ui", ui);

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
            exe.root_module.linkLibrary(sideros);
            exe.root_module.link_libc = true;
            exe.root_module.linkSystemLibrary("vulkan", .{ .needed = true });
            if (wayland) {
                exe.root_module.addIncludePath(b.path("ext"));
                exe.root_module.linkSystemLibrary("wayland-client", .{});
                exe.root_module.linkSystemLibrary("xkbcommon", .{});
                exe.root_module.addCSourceFile(.{ .file = b.path("ext/xdg-shell.c") });
            } else {
                exe.root_module.linkSystemLibrary("xcb", .{});
                exe.root_module.linkSystemLibrary("xcb-keysyms", .{});
                exe.root_module.linkSystemLibrary("xcb-icccm", .{});
            }
            exe.root_module.addImport("vulkan", vulkan);
            b.installArtifact(exe);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());

            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step("run", "Run Sideros");
            run_step.dependOn(&run_cmd.step);
        },
        .macos => {
            const exe = b.addExecutable(.{
                .name = "sideros",
                .root_module = b.createModule(.{
                    .root_source_file = b.path("src/macos.zig"),
                    .target = target,
                    .optimize = optimize,
                }),
            });
            exe.root_module.addIncludePath(b.path("src"));
            exe.root_module.linkSystemLibrary("vulkan", .{});
            exe.root_module.addSystemIncludePath(.{ .cwd_relative = "/usr/local/include" });
            exe.root_module.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });
            exe.root_module.addCSourceFile(.{ .file = b.path("src/window.m") });
            exe.root_module.linkFramework("Cocoa", .{});
            exe.root_module.linkFramework("Metal", .{});
            exe.root_module.linkFramework("QuartzCore", .{});
            exe.root_module.linkLibrary(sideros);
            exe.root_module.addImport("vulkan", vulkan);
            exe.root_module.addImport("sideros", sideros.root_module);
            b.installArtifact(exe);

            const run_cmd = b.addRunArtifact(exe);
            run_cmd.step.dependOn(b.getInstallStep());

            if (b.args) |args| {
                run_cmd.addArgs(args);
            }

            const run_step = b.step("run", "Run Sideros");
            run_step.dependOn(&run_cmd.step);
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
    const shaders_dir = b.build_root.handle.openDir(b.graph.io, "assets/shaders", .{ .iterate = true }) catch @panic("Failed to open shaders directory");

    var file_it = shaders_dir.iterate();
    while (file_it.next(b.graph.io) catch @panic("Failed to iterate shader directory")) |entry| {
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
