const std = @import("std");
const config = @import("config");
const math = @import("sideros").math;
const Input = @import("sideros").Input;
const mods = @import("sideros").mods;
const ecs = @import("sideros").ecs;
const Renderer = @import("sideros").Renderer;

fn testSystem2(pool: *ecs.Pool) void {
    std.debug.print("{any}\n", .{pool.resources.input.isKeyDown(.a)});
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
    defer allocator.free(all);
    var parser = try mods.Parser.init(allocator, all);
    defer parser.deinit();
    parser.parseModule() catch |err| {
        std.debug.print("[ERROR]: error at byte {x}(0x{x})\n", .{ parser.byte_idx, parser.bytes[parser.byte_idx] });
        return err;
    };
    const module = parser.module();
    // defer module.deinit(allocator);

    var runtime = try mods.Runtime.init(allocator, module, &global_runtime);
    defer runtime.deinit(allocator);

    var parameters = [_]mods.VM.Value{.{ .i32 = 17 }};
    try runtime.callExternal(allocator, .preinit, &parameters);
    const result = runtime.stack.pop().?;
    std.debug.print("Result of preinit: {any}\n", .{result});
    var w = try Renderer.Window.create(800, 600, "sideros");
    defer w.destroy();

    var r = try Renderer.init(allocator, w);
    defer r.deinit();

    const resources = ecs.Resources{
        .window = w,
        .renderer = r,
        .input = .{ .key_pressed = .{false} ** @intFromEnum(Input.KeyCode.menu) },
    };

    var pool = try ecs.Pool.init(allocator, resources);
    defer pool.deinit();
    w.setResources(&pool.resources);
    try pool.addSystemGroup(&[_]ecs.System{
        Renderer.render,
    }, true);
    // try pool.addSystemGroup(&[_]ecs.System{
    // testSystem2,
    // });

    // for (0..1000) |_| {
    //     const entity = try pool.createEntity();
    //     try pool.addComponent(entity, ecs.components.Position{ .x = 1.0, .y = 0.5, .z = 3.0 });
    //     try pool.addComponent(entity, ecs.components.Speed{ .speed = 5.0 });
    // }
    var last_time: f64 = 0.0;
    while (!w.shouldClose()) {
        const current_time = Renderer.Window.getTime();
        pool.resources.delta_time = current_time - last_time;
        last_time = current_time;
        Renderer.Window.pollEvents();
        pool.tick();
    }
}
