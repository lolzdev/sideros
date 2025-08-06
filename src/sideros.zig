pub const ecs = @import("ecs");
pub const Renderer = @import("renderer");
pub const mods = @import("mods");

const api = @cImport({
    @cInclude("sideros_api.h");
});

const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var pool: ecs.Pool = undefined;
var renderer: Renderer = undefined;

fn init_mods() void {
    var global_runtime = mods.GlobalRuntime.init(allocator);
    defer global_runtime.deinit();

    // const file = std.fs.cwd().openFile("assets/mods/core.wasm", .{}) catch @panic("Couldn't open assets/mods/core.wasm");
    const file = std.fs.cwd().openFile("./test.wasm", .{}) catch @panic("Couldn't open test.wasm");
    const all = file.readToEndAlloc(allocator, 1_000_000) catch @panic("Unable to read the file"); // 1 MB
    defer allocator.free(all);
    var parser = mods.Parser.init(allocator, all) catch @panic("Failed to init parser");
    defer parser.deinit();
    parser.parseModule() catch |err| {
       std.debug.panic("[ERROR]: error {any} at byte {x}(0x{x})\n", .{ err, parser.byte_idx, parser.bytes[parser.byte_idx] });
    };
    const module = parser.module();
    defer module.deinit(allocator);

    for (0..parser.globalTypes.len) |i| {
        global_runtime.addGlobal(@intCast(i), parser.globalTypes[i], parser.globalValues[i]) catch @panic("Failed to add runtime global");
    }

    var runtime = mods.Runtime.init(allocator, module, &global_runtime) catch @panic("Failed to init runtime");
    defer runtime.deinit(allocator);

    var parameters = [_]mods.VM.Value{.{ .i32 = 17 }};
    runtime.callExternal(allocator, .preinit, &parameters) catch @panic("Failed to call to preinit");
    const result = runtime.stack.pop().?;
    std.debug.print("Result of preinit: {any}\n", .{result});
}

export fn sideros_init(init: api.GameInit) callconv(.c) void {
    pool = ecs.Pool.init(allocator, .{
        .camera = .{
            .position = .{ 5.0, 5.0, 5.0 },
            .target = .{ 0.0, 0.0, 0.0 },
        },
        .renderer = undefined,
        .input = .{ .key_pressed = .{false} ** @intFromEnum(ecs.Input.KeyCode.menu) },
    }) catch @panic("TODO: Gracefully handle error");
    // TODO(ernesto): I think this @ptrCast are unavoidable but maybe not?
    renderer = Renderer.init(allocator, @ptrCast(init.instance), @ptrCast(init.surface)) catch @panic("TODO: Gracefully handle error");
    pool.addSystemGroup(&[_]ecs.System{Renderer.render}, true) catch @panic("TODO: Gracefuly handle error");
    pool.resources.renderer = &renderer;
    pool.tick();
    // init_mods();
}

export fn sideros_update(gameUpdate: api.GameUpdate) callconv(.c) void {
    _ = gameUpdate;
    pool.tick();
}

export fn sideros_cleanup() callconv(.c) void {
    renderer.deinit();
    pool.deinit();
    if (gpa.deinit() != .ok) @panic("Memory leaked");
}
