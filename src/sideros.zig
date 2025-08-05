pub const ecs = @import("ecs");
pub const Renderer = @import("renderer");

const api = @cImport({
    @cInclude("sideros_api.h");
});

const std = @import("std");

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var pool: ecs.Pool = undefined;
var renderer: Renderer = undefined;

export fn sideros_init(init: api.GameInit) callconv(.C) void {
    pool = ecs.Pool.init(allocator, .{
        .camera = .{
            .position = .{ 0.0, 0.0, 1.0 },
            .target = .{ 0.0, 0.0, 0.0 },
        },
        .renderer = undefined,
        .input = .{ .key_pressed = .{false} ** @intFromEnum(ecs.Input.KeyCode.menu) },
    }) catch @panic("TODO: Gracefully handle error");
    // TODO(ernesto): I think this @ptrCast are unavoidable but maybe not?
    renderer = Renderer.init(allocator, @ptrCast(init.instance), @ptrCast(init.surface)) catch @panic("TODO: Gracefully handle error");
    pool.addSystemGroup(&[_]ecs.System{Renderer.render}, true) catch @panic("TODO: Gracefuly handle error");
    pool.resources.renderer = renderer;
    pool.tick();
}

export fn sideros_update(gameUpdate: api.GameUpdate) callconv(.C) void {
    _ = gameUpdate;
    pool.tick();
}

export fn sideros_cleanup() callconv(.C) void {
    renderer.deinit();
    pool.deinit();
    if (gpa.deinit() != .ok) @panic("Memory leaked");
}
