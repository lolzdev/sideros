const std = @import("std");
const c = @import("c.zig");
const window = @import("render/window.zig");

const config = @import("config");
const Renderer = @import("render/renderer_vulkan.zig");
const math = @import("math.zig");
const Parser = @import("vm/parse.zig");
const vm = @import("vm/vm.zig");
const wasm = @import("vm/wasm.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    {
        var global_runtime = wasm.GlobalRuntime.init(allocator);
        defer global_runtime.deinit();
        try global_runtime.addFunction("debug", wasm.debug);

        const file = try std.fs.cwd().openFile("assets/core.wasm", .{});
        const module = try Parser.parseWasm(allocator, file.reader());
        var runtime = try vm.Runtime.init(allocator, module, &global_runtime);
        defer runtime.deinit(allocator);

        var parameters = [_]usize{};
        try runtime.callExternal(allocator, "fibonacci", &parameters);

        const w = try window.Window.create(800, 600, "sideros");
        defer w.destroy();

        // TODO: Renderer.destroy should not return an error?
        var r = try Renderer.create(allocator, w);
        defer r.destroy() catch {};

        while (!w.shouldClose()) {
            c.glfwPollEvents();
            try r.tick();
        }
        try r.device.waitIdle();
    }

    if (gpa.detectLeaks()) {
        return error.leaked_memory;
    }
}
