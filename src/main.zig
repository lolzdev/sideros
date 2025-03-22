const std = @import("std");
const c = @import("c.zig");
const window = @import("rendering/window.zig");

const config = @import("config");
const Renderer = @import("rendering/renderer_vulkan.zig");
const math = @import("math.zig");
const Parser = @import("mods/parse.zig");
const vm = @import("mods/vm.zig");
const wasm = @import("mods/wasm.zig");
const components = @import("ecs/components.zig");
const entities = @import("ecs/entities.zig");

fn testSystem2(pool: *entities.Pool) void {
    var i = @as(usize, 0);
    //std.debug.print("test: {d}\n", .{pool.position.components.items.len});
    for (pool.position.components.items) |position| {
        const entity = pool.position.dense.items[i];
        if (pool.speed.dense.items[pool.speed.sparse.items[entity]] == entity) {
            const speed = pool.speed.components.items[pool.speed.sparse.items[entity]];
            std.debug.print("entity{d}: {any},{any},{any} {any}\n", .{ i, position.x, position.y, position.z, speed.speed });
        }

        i += 1;
    }
}

fn testSystem(pool: *entities.Pool) void {
    _ = pool;
    std.debug.print("test\n", .{});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    {
        //var global_runtime = wasm.GlobalRuntime.init(allocator);
        //defer global_runtime.deinit();
        //try global_runtime.addFunction("debug", wasm.debug);

        //const file = try std.fs.cwd().openFile("assets/core.wasm", .{});
        //const module = try Parser.parseWasm(allocator, file.reader());
        //var runtime = try vm.Runtime.init(allocator, module, &global_runtime);
        //defer runtime.deinit(allocator);

        //var parameters = [_]usize{};
        //try runtime.callExternal(allocator, "preinit", &parameters);
        const w = try window.Window.create(800, 600, "sideros");
        defer w.destroy();

        var pool = try entities.Pool.init(allocator);
        defer pool.deinit(allocator);

        //try pool.addSystemGroup(&[_]entities.System{
        //    testSystem,
        //});
        try pool.addSystemGroup(&[_]entities.System{
            testSystem2,
        });

        const entity = try pool.createEntity();
        try pool.addComponent(entity, components.Position{ .x = 1.0, .y = 0.5, .z = 3.0 });
        try pool.addComponent(entity, components.Speed{ .speed = 5.0 });

        // TODO(luccie-cmd): Renderer.create shouldn't return an error
        var r = try Renderer.create(allocator, w);
        defer r.destroy();

        while (!w.shouldClose()) {
            c.glfwPollEvents();
            try r.tick();
            pool.tick();
        }
    }

    if (gpa.detectLeaks()) {
        return error.leaked_memory;
    }
}
