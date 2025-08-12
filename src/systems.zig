const ecs = @import("ecs");
const math = @import("math");
const std = @import("std");

pub fn render(pool: *ecs.Pool) anyerror!void {
    var renderer = pool.resources.renderer;
    const camera = pool.resources.camera;

    const now = try std.time.Instant.now();
    const delta_time: f32 = @as(f32, @floatFromInt(now.since(renderer.previous_time))) / @as(f32, 1_000_000_000.0);
    pool.resources.delta_time = delta_time;
    renderer.previous_time = now;

    renderer.setCamera(camera);

    const transform_memory = renderer.graphics_pipeline.transform_buffer.mapped_memory;

    try renderer.begin();
    
    renderer.setLightCount(2);

    for (renderer.transforms.items, 0..) |transform, i| {
        transform_memory[i] = transform;
        renderer.setTransform(@intCast(i));
        renderer.device.draw(renderer.mesh.index_count, renderer.current_frame, renderer.mesh);
    }
    
    try renderer.end();
}

pub fn moveCamera(pool: *ecs.Pool) !void {
    const input = pool.resources.input;
    var camera = pool.resources.camera;
    const mul = @as(@Vector(3, f32), @splat(camera.speed * pool.resources.delta_time));

    if (input.isKeyDown(.w)) {
        camera.position += @as(@Vector(3, f32), .{0.0, 0.0, 1.0}) * mul;
    }
    if (input.isKeyDown(.s)) {
        camera.position += @as(@Vector(3, f32), .{0.0, 0.0, -1.0}) * mul;
    }
    if (input.isKeyDown(.a)) {
        camera.position -= @as(@Vector(3, f32), .{1.0, 0.0, 0.0}) * mul;
    }
    if (input.isKeyDown(.d)) {
        camera.position += @as(@Vector(3, f32), .{1.0, 0.0, 0.0}) * mul;
    }
}
