pub const ecs = @import("ecs");
pub const rendering = @import("rendering");
pub const mods = @import("mods");

const Renderer = rendering.Renderer;

const api = @cImport({
    @cInclude("sideros_api.h");
});

const std = @import("std");

const systems = @import("systems.zig");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var pool: ecs.Pool = undefined;
var renderer: Renderer = undefined;
var camera: rendering.Camera = .{
    .position = .{ 0.0, 0.0, 5.0 },
};
var input: ecs.Input = .{ .key_pressed = .{false} ** @intFromEnum(ecs.Input.KeyCode.menu) };
var resources: ecs.Resources = undefined;
const ModInfo = struct {
    name: []const u8,
    runtime: mods.Runtime,
    modIdx: u32,
};
var loadedMods: std.ArrayListUnmanaged(ModInfo) = .{};

fn openOrCreateDir(fs: std.fs.Dir, path: []const u8) !std.fs.Dir {
    var dir: std.fs.Dir = undefined;
    dir = fs.openDir(path, .{.iterate = true}) catch |err| {
        if (err == std.fs.Dir.OpenError.FileNotFound) {
            try fs.makeDir(path);
            dir = try fs.openDir(path, .{.iterate = true});
            return dir;
        } else {
            return err;
        }
    };
    return dir;
}

fn untarToDirAndGetFile(fs: std.fs.Dir, name: []const u8) !std.fs.File {
    var modDir = try openOrCreateDir(fs,name);
    defer modDir.close();
    var buffer: [1024]u8 = undefined;
    var tarFile = try fs.openFile(try std.fmt.bufPrint(&buffer, "{s}.tar", .{name}), .{});
    defer tarFile.close();
    const tarData = try tarFile.readToEndAlloc(allocator, 1_000_000);
    var tarReader = std.io.Reader.fixed(tarData);
    try std.tar.pipeToFileSystem(modDir, &tarReader, .{});
    return try fs.openFile(try std.fmt.bufPrint(&buffer, "{s}/main.wasm", .{name}), .{});
}

fn init_mods() void {

    var modsDir = std.fs.cwd().openDir("./assets/mods", .{.iterate = true}) catch @panic("Failed to open assets/mods");
    defer modsDir.close();

    var modsDirIter = modsDir.iterate();
    while (modsDirIter.next() catch @panic("Failed to get next iteration of mods directory")) |entry| {
        if (entry.kind != std.fs.File.Kind.file){
            std.debug.panic("TODO: Search recursively for mods\n", .{});
        }
        const extension = entry.name.ptr[entry.name.len - 4..entry.name.len];
        if (!std.mem.eql(u8, extension, ".tar")){
            std.debug.print("[WARNING]: Found non tar extension in mods directory\n", .{});
            continue;
        }
        const fullDir = std.fmt.allocPrint(allocator, "assets/mods/{s}", .{entry.name.ptr[0..entry.name.len - 4]}) catch @panic("Failed to allocate for fullDir");
        var global_runtime = mods.GlobalRuntime.init(allocator);

        var file = untarToDirAndGetFile(std.fs.cwd(), fullDir) catch @panic("Failed to load mod");
        defer file.close();
        const all = file.readToEndAlloc(allocator, 1_000_000) catch @panic("Unable to read main file");
        defer allocator.free(all);
        var parser = mods.Parser.init(allocator, all) catch @panic("Failed to init parser");
        defer parser.deinit();
        parser.parseModule() catch |err| {
           std.debug.panic("[ERROR]: error {any} at byte {x}(0x{x})\n", .{ err, parser.byte_idx, parser.bytes[parser.byte_idx] });
        };
        const module = parser.module();

        for (0..parser.globalTypes.len) |i| {
            global_runtime.addGlobal(@intCast(i), parser.globalTypes[i], parser.globalValues[i]) catch @panic("Failed to add runtime global");
        }

        var runtime = mods.Runtime.init(allocator, module, &global_runtime) catch @panic("Failed to init runtime");

        const modIdx: u32 = @intCast(loadedMods.items.len);
        var parameters = [_]mods.VM.Value{.{ .i32 = @intCast(modIdx) }};
        runtime.externalCall(allocator, .init, &parameters) catch @panic("Failed to call to init");
        const result = runtime.stack.pop().?;
        std.debug.print("Result of {s} init: {any}\n", .{fullDir, result});
        loadedMods.append(allocator, .{.name = fullDir, .runtime = runtime, .modIdx = modIdx}) catch @panic("Failed to append to loadedMods");
        std.fs.cwd().deleteTree(fullDir) catch std.debug.panic("Failed to delete {s}", .{fullDir});
    }
}

export fn sideros_init(init: api.GameInit) callconv(.c) void {
    resources = .{
        .camera = &camera,
        .renderer = undefined,
        .input = &input,
    };

    pool = ecs.Pool.init(allocator, &resources) catch @panic("TODO: Gracefully handle error");
    // TODO(ernesto): I think this @ptrCast are unavoidable but maybe not?
    renderer = Renderer.init(allocator, @ptrCast(init.instance), @ptrCast(init.surface)) catch @panic("TODO: Gracefully handle error");
    pool.addSystemGroup(&[_]ecs.System{systems.render, systems.moveCamera}, true) catch @panic("TODO: Gracefuly handle error");
    pool.resources.renderer = &renderer;
    pool.tick();
    init_mods();
}

export fn sideros_update(gameUpdate: api.GameUpdate) callconv(.c) void {
    _ = gameUpdate;
    pool.tick();
}

export fn sideros_cleanup() callconv(.c) void {
    for (loadedMods.items) |info| {
        var runtime = info.runtime;
        // runtime.externalCall(allocator, .deinit, &.{});
        // const result = runtime.stack.pop().?;
        // std.debug.print("Result of {s} init: {any}\n", .{info.name, result});
        runtime.deinit(allocator);
    }
    loadedMods.deinit(allocator);
    renderer.deinit();
    pool.deinit();
    if (gpa.deinit() != .ok) @panic("Memory leaked");
}

export fn sideros_key_callback(key: u32, release: bool) callconv(.c) void {
    if (key <= @intFromEnum(ecs.Input.KeyCode.menu) and key >= @intFromEnum(ecs.Input.KeyCode.space)) {
        if (release) {
            input.key_pressed[key] = false;
        } else {
            input.key_pressed[key] = true;
        }
    }
}
