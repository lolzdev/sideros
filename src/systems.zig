const ecs = @import("ecs");
const math = @import("math");
const rendering = @import("rendering");
const std = @import("std");
const Input = ecs.Input;

const TerrainHit = struct {
    position: @Vector(3, f32),
};

pub fn render(pool: *ecs.Pool) anyerror!void {
    var renderer = pool.resources.renderer;
    const camera = pool.resources.camera;
    const terrain = pool.resources.terrain;
    const placement = pool.resources.placement;

    const now = std.Io.Timestamp.now(pool.threaded_io.io(), .awake);
    const delta_time: f32 = @as(f32, @floatFromInt(renderer.previous_time.durationTo(now).toNanoseconds())) / @as(f32, 1_000_000_000.0);
    pool.resources.delta_time = delta_time;
    renderer.previous_time = now;

    renderer.setCamera(camera);

    const preview_count: usize = if (placement.preview_valid) 1 else 0;
    try renderer.graphics_pipeline.transform_buffer.ensureCapacity(renderer.transforms.items.len + preview_count);
    const transform_memory = renderer.graphics_pipeline.transform_buffer.mapped_memory;

    try renderer.begin();

    renderer.setLightCount(2);

    try renderer.beginTerrain();
    renderer.device.drawTerrain(@as(u32, @intCast(terrain.index_buffer.size / @sizeOf(u32))), renderer.current_frame, terrain.vertex_buffer, terrain.index_buffer);

    try renderer.beginGraphics();
    for (renderer.transforms.items, 0..) |transform, i| {
        transform_memory[i] = transform;
        renderer.setTransform(@intCast(i));
        renderer.device.draw(renderer.mesh.index_count, renderer.current_frame, renderer.mesh);
    }

    if (placement.preview_valid) {
        const i = renderer.transforms.items.len;
        const scale = placement.preview_scale;
        const position = placementModelPosition(placement.preview_position, scale);
        transform_memory[i] = math.Transform.init(
            .{ position[0], position[1], position[2] },
            .{ scale[0], scale[1], scale[2] },
            .{ 0.0, 0.0, 0.0 },
        );
        renderer.setTransform(@intCast(i));
        renderer.device.draw(renderer.mesh.index_count, renderer.current_frame, renderer.mesh);
    }

    try renderer.end();
}

pub fn updatePlacement(pool: *ecs.Pool) !void {
    const input = pool.resources.input;
    const camera = pool.resources.camera;
    const terrain = &pool.resources.terrain;
    var renderer = pool.resources.renderer;
    var placement = pool.resources.placement;

    if (input.wasKeyPressed(.b)) {
        placement.active = !placement.active;
        placement.preview_valid = false;
    }
    if (input.wasKeyPressed(.escape)) {
        placement.active = false;
        placement.preview_valid = false;
    }
    if (!placement.active) {
        input.discardMousePresses(.left);
        return;
    }

    const cursor = input.getCursorPosition();
    const extent = renderer.swapchain.extent;
    const place_requested = input.hasMousePress(.left);
    if (cursorToTerrain(camera, terrain, cursor[0], cursor[1], extent.width, extent.height)) |hit| {
        placement.preview_valid = true;
        placement.preview_position = hit.position;
    } else if (!place_requested) {
        placement.preview_valid = false;
    }

    if (place_requested and placement.preview_valid) {
        _ = input.consumeMousePress(.left);
        const scale = placement.preview_scale;
        const position = placementModelPosition(placement.preview_position, scale);
        try renderer.transforms.append(
            pool.allocator,
            math.Transform.init(
                .{ position[0], position[1], position[2] },
                .{ scale[0], scale[1], scale[2] },
                .{ 0.0, 0.0, 0.0 },
            ),
        );
    }
}

pub fn endInputFrame(pool: *ecs.Pool) !void {
    pool.resources.input.endFrame();
}

pub fn moveCamera(pool: *ecs.Pool) !void {
    const input = pool.resources.input;
    var camera = pool.resources.camera;
    const mul = @as(@Vector(3, f32), @splat(camera.speed * pool.resources.delta_time));
    var forward = camera.getDirection();
    forward[0] = -forward[0];
    forward[1] = 0.0;
    const left = math.cross(forward, camera.up);

    if (input.isKeyDown(.w)) {
        camera.position += forward * mul;
    }
    if (input.isKeyDown(.s)) {
        camera.position -= forward * mul;
    }
    if (input.isKeyDown(.a)) {
        camera.position += left * mul;
    }
    if (input.isKeyDown(.d)) {
        camera.position -= left * mul;
    }
    if (input.isKeyDown(.q)) {
        camera.rotateAround(camera.getTarget(), math.rad(100.0 * pool.resources.delta_time));
    }
    if (input.isKeyDown(.e)) {
        camera.rotateAround(camera.getTarget(), math.rad(-100.0 * pool.resources.delta_time));
    }
}

fn cursorToTerrain(camera: *rendering.Camera, terrain: *const rendering.Terrain, cursor_x: f64, cursor_y: f64, viewport_width: u32, viewport_height: u32) ?TerrainHit {
    if (viewport_width == 0 or viewport_height == 0) {
        return null;
    }

    const ray = cursorRay(camera, cursor_x, cursor_y, viewport_width, viewport_height);
    return raycastTerrain(camera.position, ray, terrain);
}

fn placementModelPosition(ground_position: @Vector(3, f32), scale: @Vector(3, f32)) @Vector(3, f32) {
    return .{ ground_position[0], ground_position[1] + scale[1] * 0.5, ground_position[2] };
}

fn cursorRay(camera: *rendering.Camera, cursor_x: f64, cursor_y: f64, viewport_width: u32, viewport_height: u32) @Vector(3, f32) {
    const ndc_x = (2.0 * @as(f32, @floatCast(cursor_x)) / @as(f32, @floatFromInt(viewport_width))) - 1.0;
    const ndc_y = 1.0 - (2.0 * @as(f32, @floatCast(cursor_y)) / @as(f32, @floatFromInt(viewport_height)));
    const aspect = @as(f32, @floatFromInt(viewport_width)) / @as(f32, @floatFromInt(viewport_height));
    const half_fov = math.tan(math.rad(45.0) / 2.0);

    const forward = math.normalize(camera.getTarget() - camera.position);
    const world_up = @Vector(3, f32){ 0.0, 1.0, 0.0 };
    const right = math.normalize(math.cross(world_up, forward));
    const up = math.normalize(math.cross(forward, right));

    return math.normalize(forward + right * @as(@Vector(3, f32), @splat(ndc_x * aspect * half_fov)) + up * @as(@Vector(3, f32), @splat(ndc_y * half_fov)));
}

fn raycastTerrain(origin: @Vector(3, f32), ray: @Vector(3, f32), terrain: *const rendering.Terrain) ?TerrainHit {
    const max_distance: f32 = 1000.0;
    const step: f32 = 1.0;
    var t: f32 = 0.0;

    while (t <= max_distance) : (t += step) {
        const point = origin + ray * @as(@Vector(3, f32), @splat(t));
        if (!isInsideTerrain(point, terrain)) {
            continue;
        }

        const height = terrainWorldHeight(terrain, point[0], point[2]);
        if (point[1] <= height) {
            var low = @max(0.0, t - step);
            var high = t;
            for (0..12) |_| {
                const mid = (low + high) * 0.5;
                const mid_point = origin + ray * @as(@Vector(3, f32), @splat(mid));
                if (!isInsideTerrain(mid_point, terrain) or mid_point[1] > terrainWorldHeight(terrain, mid_point[0], mid_point[2])) {
                    low = mid;
                } else {
                    high = mid;
                }
            }

            const hit_point = origin + ray * @as(@Vector(3, f32), @splat(high));
            return .{ .position = .{ hit_point[0], terrainWorldHeight(terrain, hit_point[0], hit_point[2]), hit_point[2] } };
        }
    }

    return null;
}

fn isInsideTerrain(point: @Vector(3, f32), terrain: *const rendering.Terrain) bool {
    return point[0] >= 0.0 and point[2] >= 0.0 and point[0] <= terrainWorldWidth(terrain) and point[2] <= terrainWorldDepth(terrain);
}

fn terrainWorldHeight(terrain: *const rendering.Terrain, world_x: f32, world_z: f32) f32 {
    const x = clampFloat(world_x, 0.0, terrainWorldWidth(terrain));
    const z = clampFloat(world_z, 0.0, terrainWorldDepth(terrain));
    const max_x = @as(f32, @floatFromInt(terrain.width - 1));
    const max_z = @as(f32, @floatFromInt(terrain.height - 1));
    const sample_x = if (terrain.width > 1) x / terrainWorldWidth(terrain) * max_x else 0.0;
    const sample_z = if (terrain.height > 1) z / terrainWorldDepth(terrain) * max_z else 0.0;

    const x0: usize = @intFromFloat(@floor(sample_x));
    const z0: usize = @intFromFloat(@floor(sample_z));
    const x1 = @min(x0 + 1, terrain.width - 1);
    const z1 = @min(z0 + 1, terrain.height - 1);
    const tx = sample_x - @as(f32, @floatFromInt(x0));
    const tz = sample_z - @as(f32, @floatFromInt(z0));

    const h00 = normalizedTerrainHeight(terrain, x0, z0);
    const h10 = normalizedTerrainHeight(terrain, x1, z0);
    const h01 = normalizedTerrainHeight(terrain, x0, z1);
    const h11 = normalizedTerrainHeight(terrain, x1, z1);

    const hx0 = lerp(h00, h10, tx);
    const hx1 = lerp(h01, h11, tx);
    const h = lerp(hx0, hx1, tz);
    return h * std.math.pow(f32, 2.0, h * 5.0);
}

fn normalizedTerrainHeight(terrain: *const rendering.Terrain, x: usize, z: usize) f32 {
    const height = clampFloat(@floatCast(terrain.getHeight(x, z)), 0.0, 1.0);
    const quantized = @as(f32, @floatFromInt(@as(u32, @intFromFloat(height * 255.0)))) / 255.0;
    return srgbToLinear(quantized);
}

fn terrainWorldWidth(terrain: *const rendering.Terrain) f32 {
    return @floatFromInt(terrain.world_width);
}

fn terrainWorldDepth(terrain: *const rendering.Terrain) f32 {
    return @floatFromInt(terrain.world_height);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn clampFloat(value: f32, min: f32, max: f32) f32 {
    return @min(@max(value, min), max);
}

fn srgbToLinear(value: f32) f32 {
    if (value <= 0.04045) {
        return value / 12.92;
    }
    return std.math.pow(f32, (value + 0.055) / 1.055, 2.4);
}

pub fn zoomCamera(pool: *ecs.Pool, direction: Input.ScrollDirection) !void {
    var camera = pool.resources.camera;
    var camera_direction = camera.getDirection();
    camera_direction[0] = -camera_direction[0];
    if (direction == .up) {
        camera.position += camera_direction;
    } else {
        camera.position -= camera_direction;
    }
}
