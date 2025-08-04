const std = @import("std");
const config = @import("sideros").config;
const math = @import("sideros").math;
const Input = @import("sideros").Input;
const mods = @import("sideros").mods;
const ecs = @import("sideros").ecs;
const builtin = @import("builtin");
const Renderer = @import("sideros").Renderer;

const platform = if (builtin.target.os.tag == .linux) (if (config.wayland) @import("wayland.zig") else @import("xorg.zig")) else @import("xorg.zig");

//fn testSystem2(pool: *ecs.Pool) void {
//    std.debug.print("{any}\n", .{pool.resources.input.isKeyDown(.a)});
//}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer if (gpa.deinit() != .ok) @panic("Leaked memory");

    // var global_runtime = mods.GlobalRuntime.init(allocator);
    // defer global_runtime.deinit();
    // try global_runtime.addFunction("debug", mods.Wasm.debug);

    // //const file = try std.fs.cwd().openFile("assets/core.wasm", .{});
    // const file = try std.fs.cwd().openFile("./test.wasm", .{});
    // const all = try file.readToEndAlloc(allocator, 1_000_000); // 1 MB
    // defer allocator.free(all);
    // var parser = try mods.Parser.init(allocator, all);
    // defer parser.deinit();
    // parser.parseModule() catch |err| {
    //    std.debug.print("[ERROR]: error at byte {x}(0x{x})\n", .{ parser.byte_idx, parser.bytes[parser.byte_idx] });
    //    return err;
    // };
    // const module = parser.module();
    // defer module.deinit(allocator);

    // for (0..parser.globalTypes.len) |i| {
    //     try global_runtime.addGlobal(@intCast(i), parser.globalTypes[i], parser.globalValues[i]);
    // }

    // var runtime = try mods.Runtime.init(allocator, module, &global_runtime);
    // defer runtime.deinit(allocator);

    // var parameters = [_]mods.VM.Value{.{ .i32 = 17 }};
    // try runtime.callExternal(allocator, .preinit, &parameters);
    // const result = runtime.stack.pop().?;
    // std.debug.print("Result of preinit: {any}\n", .{result});

    //var w = try Renderer.Window.create(800, 600, "sideros");
    //defer w.destroy();

    const resources = ecs.Resources{
        .camera = .{
            .position = .{0.0, 0.0, 100},
            .target = .{0.0, 0.0, 0.0},
        },
        .renderer = undefined,
        .input = .{ .key_pressed = .{false} ** @intFromEnum(Input.KeyCode.menu) },
    };
    var pool = try ecs.Pool.init(allocator, resources);
    defer pool.deinit();
    try pool.addSystemGroup(&[_]ecs.System{
        Renderer.render,
    }, true);

    try platform.init(allocator, &pool);
}
