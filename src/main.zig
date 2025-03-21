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
        _ = try pool.createEntity();
        //try pool.addComponent(entity, components.Speed{ .speed = 0.0 });

        // TODO(luccie-cmd): Renderer.create shouldn't return an error
        var r = try Renderer.create(allocator, w);
        defer r.destroy();

        while (!w.shouldClose()) {
            c.glfwPollEvents();
            try r.tick();
        }
    }

    if (gpa.detectLeaks()) {
        return error.leaked_memory;
    }
}
