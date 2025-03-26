const std = @import("std");
const c = @import("c.zig");
const window = @import("rendering/window.zig");

const config = @import("config");
const Renderer = @import("rendering/renderer_vulkan.zig");
const math = @import("math.zig");
const mods = @import("mods");
const ecs = @import("ecs");
const gltf = @import("rendering/gltf.zig");

fn testSystem2(pool: *ecs.Pool) void {
    for (pool.getQuery(ecs.components.Position), 0..) |position, i| {
        const entity = pool.getEntity(i, ecs.components.Position);
        if (pool.getComponent(entity, ecs.components.Speed)) |speed| {
            std.debug.print("entity{d}: {any},{any},{any} {any}\n", .{ i, position.x, position.y, position.z, speed.speed });
        }
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() != .ok) @panic("Leaked memory");

    var global_runtime = mods.GlobalRuntime.init(allocator);
    defer global_runtime.deinit();
    try global_runtime.addFunction("debug", mods.Wasm.debug);

    const file = try std.fs.cwd().openFile("assets/core.wasm", .{});
    const all = try file.readToEndAlloc(allocator, 1_000_000); // 1 MB
    var parser = mods.Parser{
        .bytes = all,
        .byte_idx = 0,
        .allocator = allocator,
    };
    const module = parser.parseModule() catch |err| {
        std.debug.print("[ERROR]: error at byte {x}(0x{x})\n", .{ parser.byte_idx, parser.bytes[parser.byte_idx] });
        return err;
    };
    var runtime = try mods.Runtime.init(allocator, module, &global_runtime);
    defer runtime.deinit(allocator);

    var parameters = [_]usize{17};
    try runtime.callExternal(allocator, "preinit", &parameters);
    const result = runtime.stack.pop().?;
    std.debug.print("Result of preinit: {any}\n", .{result});

    const w = try window.Window.create(800, 600, "sideros");
    defer w.destroy();

    // var pool = try ecs.Pool.init(allocator);
    // defer pool.deinit(allocator);

    //try pool.addSystemGroup(&[_]entities.System{
    //    testSystem,
    //});
    // try pool.addSystemGroup(&[_]ecs.System{
    // testSystem2,
    // });

    // for (0..1000) |_| {
    //     const entity = try pool.createEntity();
    //     try pool.addComponent(entity, ecs.components.Position{ .x = 1.0, .y = 0.5, .z = 3.0 });
    //     try pool.addComponent(entity, ecs.components.Speed{ .speed = 5.0 });
    // }

    // var r = try Renderer.create(allocator, w);
    // defer r.destroy();

    // while (!w.shouldClose()) {
    //     c.glfwPollEvents();
    //     try r.tick();
    //     pool.tick();
    // }
}
