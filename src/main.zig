const std = @import("std");
const config = @import("config");
const math = @import("sideros").math;
const Input = @import("sideros").Input;
const mods = @import("mods");
const ecs = @import("ecs");
pub const Renderer = @import("renderer");

fn testSystem2(pool: *ecs.Pool) void {
    std.debug.print("{any}\n", .{pool.resources.input.isKeyDown(.a)});
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() != .ok) @panic("Leaked memory");

    //var global_runtime = mods.GlobalRuntime.init(allocator);
    //defer global_runtime.deinit();
    //try global_runtime.addFunction("debug", mods.Wasm.debug);

    //const file = try std.fs.cwd().openFile("assets/core.wasm", .{});
    //const all = try file.readToEndAlloc(allocator, 1_000_000); // 1 MB
    //var parser = mods.Parser{
    //    .bytes = all,
    //    .byte_idx = 0,
    //    .allocator = allocator,
    //};
    //const module = parser.parseModule() catch |err| {
    //    std.debug.print("[ERROR]: error at byte {x}(0x{x})\n", .{ parser.byte_idx, parser.bytes[parser.byte_idx] });
    //    return err;
    //};
    //var runtime = try mods.Runtime.init(allocator, module, &global_runtime);
    //defer runtime.deinit(allocator);

    //var parameters = [_]usize{17};
    //try runtime.callExternal(allocator, "preinit", &parameters);
    var w = try Renderer.Window.create(800, 600, "sideros");
    defer w.destroy();

    var r = try Renderer.create(allocator, w);
    defer r.destroy();

    const resources = ecs.Resources{
        .window = w,
        .renderer = r,
        .input = .{ .key_pressed = .{false} ** @intFromEnum(Input.KeyCode.menu) },
    };

    var pool = try ecs.Pool.init(allocator, resources);
    defer pool.deinit();
    w.setResources(&pool.resources);
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

    while (!w.shouldClose()) {
        Renderer.Window.pollEvents();
        try r.tick();
        pool.tick();
    }
}
