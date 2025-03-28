const std = @import("std");
const config = @import("config");
const math = @import("sideros").math;
const mods = @import("mods");
const ecs = @import("ecs/ecs.zig");
pub const Renderer = @import("renderer");

fn testSystem2(pool: *ecs.Pool) void {
    const slice = pool.humans.slice();

    for (slice.items(.position), slice.items(.speed)) |position, speed| {
        std.debug.print("entity: {any} {any} {any}: {any}\n", .{ position.x, position.y, position.z, speed.speed });
    }
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

    //var parameters = [_]usize{};
    //try runtime.callExternal(allocator, "preinit", &parameters);
    const w = try Renderer.Window.create(800, 600, "sideros");
    defer w.destroy();

    // TODO(luccie-cmd): Renderer.create shouldn't return an error
    var r = try Renderer.create(allocator, w);
    defer r.destroy();

    const resources = ecs.Resources{
        .window = w,
        .renderer = r,
    };

    var pool = try ecs.Pool.init(allocator, resources);
    defer pool.deinit();

    _ = try pool.createEntity(ecs.entities.Human{
        .position = .{ .x = 0.0, .y = 1.0, .z = 0.0 },
        .speed = .{ .speed = 5.0 },
    });

    try pool.addSystemGroup(&[_]ecs.System{
        testSystem2,
    });

    while (!w.shouldClose()) {
        try r.tick();
        pool.tick();
    }
}
