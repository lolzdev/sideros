const math = @import("math");
const ecs = @import("ecs");
const std = @import("std");
const vk = @import("vulkan.zig");
const Mesh = @import("Mesh.zig");
const Texture = vk.Texture;
const Camera = @import("Camera.zig");
const Allocator = std.mem.Allocator;

const Renderer = @This();

instance: vk.Instance,
surface: vk.Surface,
physical_device: vk.PhysicalDevice,
device: vk.Device,
render_pass: vk.RenderPass,
swapchain: vk.Swapchain,
graphics_pipeline: vk.GraphicsPipeline,
current_frame: u32,
mesh: Mesh,
transform: math.Transform,
transform2: math.Transform,
previous_time: std.time.Instant,

pub fn init(allocator: Allocator, instance_handle: vk.c.VkInstance, surface_handle: vk.c.VkSurfaceKHR) !Renderer {
    const instance: vk.Instance = .{ .handle = instance_handle };
    const surface: vk.Surface = .{ .handle = surface_handle };
    var physical_device = try vk.PhysicalDevice.pick(allocator, instance);
    const device = try physical_device.create_device(surface, allocator, 2);

    const vertex_shader = try device.initShader("shader_vert");
    defer device.deinitShader(vertex_shader);
    const fragment_shader = try device.initShader("shader_frag");
    defer device.deinitShader(fragment_shader);

    const render_pass = try vk.RenderPass.init(allocator, device, surface, physical_device);

    const swapchain = try vk.Swapchain.init(allocator, surface, device, physical_device, render_pass);

    var pipeline_builder = vk.GraphicsPipeline.Builder.init(allocator, device);
    const mesh = try pipeline_builder.addMesh("assets/models/cube.glb");
    var graphics_pipeline = try pipeline_builder.build(swapchain, render_pass, vertex_shader, fragment_shader);

    // TODO: I think the renderer shouldn't have to interact with buffers. I think the API should change to
    // something along the lines of
    //    renderer.begin()
    //    renderer.render(triangle);
    //    renderer.render(some_other_thing);
    //    ...
    //    renderer.submit()
    const texture = try Texture.init("assets/textures/container.png", device);
    const diffuse = try Texture.init("assets/textures/container_specular.png", device);

    _ = try graphics_pipeline.addTexture(device, texture, diffuse);

    graphics_pipeline.directional_light.direction = .{-0.2, -1.0, -0.3};
    graphics_pipeline.directional_light.ambient = .{0.5, 0.5, 0.5};
    graphics_pipeline.directional_light.diffuse = .{0.5, 0.5, 0.5};
    graphics_pipeline.directional_light.specular = .{0.5, 0.5, 0.5};

    graphics_pipeline.point_lights[0].position = .{0.0, 3.0, 3.0};
    graphics_pipeline.point_lights[0].data[0] = 1.0;
    graphics_pipeline.point_lights[0].data[1] = 0.0014;
    graphics_pipeline.point_lights[0].data[2] = 0.000007;
    graphics_pipeline.point_lights[0].ambient = .{0.5, 0.5, 0.5};
    graphics_pipeline.point_lights[0].diffuse = .{0.5, 0.5, 0.5};
    graphics_pipeline.point_lights[0].specular = .{1.0, 1.0, 1.0};

    graphics_pipeline.point_lights[1].position = .{-1.0, 0.0, 0.0};
    graphics_pipeline.point_lights[1].data[0] = 1.0;
    graphics_pipeline.point_lights[1].data[1] = 0.09;
    graphics_pipeline.point_lights[1].data[2] = 0.032;
    graphics_pipeline.point_lights[1].ambient = .{0.5, 0.5, 0.5};
    graphics_pipeline.point_lights[1].diffuse = .{0.5, 0.5, 0.5};
    graphics_pipeline.point_lights[1].specular = .{1.0, 1.0, 1.0};

    return Renderer{
        .instance = instance,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .render_pass = render_pass,
        .swapchain = swapchain,
        .graphics_pipeline = graphics_pipeline,
        .current_frame = 0,
        .transform = math.Transform.init(.{0.0, 0.0, 0.0}, .{1.0, 1.0, 1.0}, .{0.0, 0.0, 0.0}),
        .transform2 = math.Transform.init(.{0.0, 3.0, 3.0}, .{0.5, 0.5, 0.5}, .{0.0, 0.0, 0.0}),
        .previous_time = try std.time.Instant.now(),
        .mesh = mesh,
    };
}

pub fn deinit(self: Renderer) void {
    self.device.waitIdle();
    self.graphics_pipeline.deinit(self.device);
    self.swapchain.deinit(self.device);
    self.render_pass.deinit(self.device);
    self.device.deinit();
}

// TODO: render is maybe a bad name? something like present() or submit() is better?
pub fn render(pool: *ecs.Pool) anyerror!void {
    var renderer = pool.resources.renderer;
    var camera = pool.resources.camera;

    const now = try std.time.Instant.now();
    const delta_time: f32 = @as(f32, @floatFromInt(now.since(renderer.previous_time))) / @as(f32, 1_000_000_000.0);
    renderer.previous_time = now;

    const view_memory = renderer.graphics_pipeline.view_memory;
    @memcpy(view_memory[0..@sizeOf(math.Matrix)], std.mem.asBytes(&camera.getView()));

    const view_pos_memory = renderer.graphics_pipeline.view_pos_memory;
    const view_pos: [*]f32 = @alignCast(@ptrCast(view_pos_memory));
    view_pos[0] = camera.position[0];
    view_pos[1] = camera.position[1];
    view_pos[2] = camera.position[2];

    renderer.transform.rotate(math.rad(15) * delta_time, .{0.0, 1.0, 0.0});

    const transform_memory = renderer.graphics_pipeline.transform_memory;
    @memcpy(transform_memory[0..(@sizeOf(math.Transform)-@sizeOf(math.Quaternion))], std.mem.asBytes(&renderer.transform)[0..(@sizeOf(math.Transform)-@sizeOf(math.Quaternion))]);

    try renderer.device.waitFence(renderer.current_frame);
    const image = try renderer.swapchain.nextImage(renderer.device, renderer.current_frame);
    try renderer.device.resetCommand(renderer.current_frame);
    try renderer.device.beginCommand(renderer.current_frame);
    renderer.render_pass.begin(renderer.swapchain, renderer.device, image, renderer.current_frame);
    renderer.graphics_pipeline.bind(renderer.device, renderer.current_frame);
    renderer.device.bindVertexBuffer(renderer.graphics_pipeline.vertex_buffer, renderer.current_frame);
    renderer.device.bindIndexBuffer(renderer.graphics_pipeline.index_buffer, renderer.current_frame);
    renderer.device.bindDescriptorSets(renderer.graphics_pipeline, renderer.current_frame, 0);
    var lights: u32 = 2;
    renderer.device.pushConstant(renderer.graphics_pipeline, 0, 0, 4, @ptrCast(&lights), renderer.current_frame);
    renderer.device.draw(renderer.mesh.index_count, renderer.current_frame, renderer.mesh);
    renderer.render_pass.end(renderer.device, renderer.current_frame);
    try renderer.device.endCommand(renderer.current_frame);

    try renderer.device.submit(renderer.swapchain, image, renderer.current_frame);

    renderer.current_frame = (renderer.current_frame + 1) % 2;

    renderer.device.waitIdle();
}
