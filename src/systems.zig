const ecs = @import("ecs");
const math = @import("math");
const std = @import("std");
const Input = ecs.Input;

pub fn updateUi(pool: *ecs.Pool) !void {
    var context = pool.resources.ui;
    var input = pool.resources.input;
    var commands = pool.resources.commands;
    const renderer = pool.resources.renderer;
    const placement = pool.resources.placement;

    const cursor = input.getCursorPosition();
    context.beginFrame(
        .{ @floatCast(cursor[0]), @floatCast(cursor[1]) },
        input.isMouseDown(.left),
    );

    const extent = renderer.swapchain.extent;
    const panel_height: f32 = 96.0;
    try context.panel(.{
        .x = 0.0,
        .y = @as(f32, @floatFromInt(extent.height)) - panel_height,
        .width = @floatFromInt(extent.width),
        .height = panel_height,
    });

    const click_available = input.hasMouseClick(.left);
    const build_rect: @import("ui").Rect = .{
        .x = 16.0,
        .y = @as(f32, @floatFromInt(extent.height)) - panel_height + 20.0,
        .width = 72.0,
        .height = 56.0,
    };
    if (try context.button(.{ .id = context.id("build.cube"), .rect = build_rect }, click_available)) {
        _ = input.consumeMouseClick(.left);
        try commands.push(pool.allocator, .start_placement);
    }
    try context.rect(.{
        .x = build_rect.x + 18.0,
        .y = build_rect.y + 14.0,
        .width = 36.0,
        .height = 28.0,
    }, .{ .r = 0.25, .g = 0.76, .b = 0.38, .a = 1.0 });

    if (placement.active) {
        const cancel_rect: @import("ui").Rect = .{
            .x = 104.0,
            .y = @as(f32, @floatFromInt(extent.height)) - panel_height + 20.0,
            .width = 72.0,
            .height = 56.0,
        };
        if (try context.button(.{ .id = context.id("placement.cancel"), .rect = cancel_rect }, input.hasMouseClick(.left))) {
            _ = input.consumeMouseClick(.left);
            try commands.push(pool.allocator, .cancel_placement);
        }
        try context.rect(.{
            .x = cancel_rect.x + 18.0,
            .y = cancel_rect.y + 14.0,
            .width = 36.0,
            .height = 28.0,
        }, .{ .r = 0.80, .g = 0.18, .b = 0.16, .a = 1.0 });
    }

    if (context.wants_mouse) {
        input.discardMouseClicks(.left);
    }

    context.endFrame();
}

pub fn applyCommands(pool: *ecs.Pool) !void {
    var commands = pool.resources.commands;
    var placement = pool.resources.placement;

    for (commands.items.items) |command| {
        switch (command) {
            .start_placement => {
                placement.active = true;
                placement.preview_valid = false;
            },
            .cancel_placement => {
                placement.active = false;
                placement.preview_valid = false;
            },
        }
    }

    commands.clear();
}

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
        const position = placement.modelPosition();
        transform_memory[i] = math.Transform.init(
            .{ position[0], position[1], position[2] },
            .{ scale[0], scale[1], scale[2] },
            .{ 0.0, 0.0, 0.0 },
        );
        renderer.setTransform(@intCast(i));
        renderer.device.draw(renderer.mesh.index_count, renderer.current_frame, renderer.mesh);
    }

    renderer.drawUi(pool.resources.ui);

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
        input.discardMouseClicks(.left);
        return;
    }
    if (pool.resources.ui.wants_mouse) {
        return;
    }

    const cursor = input.getCursorPosition();
    const extent = renderer.swapchain.extent;
    const place_requested = input.hasMouseClick(.left);
    if (terrain.cursorHit(camera, cursor[0], cursor[1], extent.width, extent.height)) |hit| {
        placement.preview_valid = true;
        placement.preview_position = hit.position;
    } else if (!place_requested) {
        placement.preview_valid = false;
    }

    if (place_requested and placement.preview_valid) {
        _ = input.consumeMouseClick(.left);
        const scale = placement.preview_scale;
        const position = placement.modelPosition();
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
