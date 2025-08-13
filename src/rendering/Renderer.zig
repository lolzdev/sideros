const math = @import("math");
const std = @import("std");
const vk = @import("vulkan.zig");
const c = vk.c;
const Mesh = @import("Mesh.zig");
const Texture = vk.Texture;
const Camera = @import("Camera.zig");
const Allocator = std.mem.Allocator;

const Self = @This();

instance: vk.Instance,
surface: vk.Surface,
physical_device: vk.PhysicalDevice,
device: vk.Device,
render_pass: vk.RenderPass,
swapchain: vk.Swapchain,
graphics_pipeline: vk.GraphicsPipeline,
terrain_pipeline: vk.TerrainPipeline,
current_frame: u32,
mesh: Mesh,
transforms: std.ArrayList(math.Transform),
previous_time: std.time.Instant,
current_image: usize,
terrain_vertex: vk.Buffer,
terrain_index: vk.Buffer,

pub fn init(allocator: Allocator, instance_handle: vk.c.VkInstance, surface_handle: vk.c.VkSurfaceKHR) !Self {
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

    const terrain_vertex_shader = try device.initShader("terrain_vert");
    defer device.deinitShader(terrain_vertex_shader);
    const terrain_fragment_shader = try device.initShader("terrain_frag");
    defer device.deinitShader(terrain_fragment_shader);

    var terrain_pipeline = try vk.TerrainPipeline.init(graphics_pipeline, terrain_vertex_shader, terrain_fragment_shader);

    const perlin: math.PerlinNoise = .{ .seed = 54321 };
    const heightmap = try allocator.alloc(u32, 700 * 700);
    defer allocator.free(heightmap);
    for (0..700) |x| {
        for (0..700) |y| {
            const scale = 0.01;
            var pixel = (perlin.fbm(@as(f64, @floatFromInt(x)) * scale, @as(f64, @floatFromInt(y)) * scale, 8, 3, 0.5) * 3);
            pixel = std.math.pow(f64, pixel, 1.2);
            const gray: u32 = @intFromFloat(pixel * 255);
            const color: u32 = (255 << 24) | (gray << 16) | (gray << 8) | gray;

            heightmap[x*700 + y] = color;
        }
    }

    const terrain_vertex, const terrain_index = try Mesh.terrain(allocator, device, 700, 700, 10);
    const heightmap_texture = try Texture.fromBytes(@alignCast(@ptrCast(heightmap)), device, 700, 700);
    //const heightmap_texture = try Texture.init("assets/textures/heightmap.png", device);
    try terrain_pipeline.setHeightmap(device, heightmap_texture);
    const texture = try Texture.init("assets/textures/container.png", device);
    const diffuse = try Texture.init("assets/textures/container_specular.png", device);

    _ = try graphics_pipeline.addTexture(device, texture, diffuse);

    graphics_pipeline.directional_light.direction = .{-0.2, -1.0, -0.3};
    graphics_pipeline.directional_light.ambient = .{0.5, 0.5, 0.5};
    graphics_pipeline.directional_light.diffuse = .{0.5, 0.5, 0.5};
    graphics_pipeline.directional_light.specular = .{0.5, 0.5, 0.5};

    graphics_pipeline.point_lights[0].position = .{0.0, 0.0, 0.0};
    graphics_pipeline.point_lights[0].data[0] = 1.0;
    graphics_pipeline.point_lights[0].data[1] = 0.9;
    graphics_pipeline.point_lights[0].data[2] = 0.8;
    graphics_pipeline.point_lights[0].ambient = .{0.2, 0.2, 0.2};
    graphics_pipeline.point_lights[0].diffuse = .{0.5, 0.5, 0.5};
    graphics_pipeline.point_lights[0].specular = .{1.0, 1.0, 1.0};

    graphics_pipeline.point_lights[1].position = .{0.0, 2.0, 0.5};
    graphics_pipeline.point_lights[1].data[0] = 1.0;
    graphics_pipeline.point_lights[1].data[1] = 0.9;
    graphics_pipeline.point_lights[1].data[2] = 0.8;
    graphics_pipeline.point_lights[1].ambient = .{0.2, 0.2, 0.2};
    graphics_pipeline.point_lights[1].diffuse = .{0.5, 0.5, 0.5};
    graphics_pipeline.point_lights[1].specular = .{1.0, 1.0, 1.0};

    var transforms = std.ArrayList(math.Transform).init(allocator);

    try transforms.append(math.Transform.init(.{0.0, 0.5, 1.0}, .{0.5, 0.5, 0.5}, .{0.0, 0.0, 0.0}));
    try transforms.append(math.Transform.init(.{0.0, 0.0, 0.0}, .{0.5, 0.5, 0.5}, .{0.0, 0.0, 0.0}));


    return .{
        .instance = instance,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .render_pass = render_pass,
        .swapchain = swapchain,
        .graphics_pipeline = graphics_pipeline,
        .terrain_pipeline = terrain_pipeline,
        .current_frame = 0,
        .transforms = transforms,
        .previous_time = try std.time.Instant.now(),
        .mesh = mesh,
        .current_image = undefined,
        .terrain_vertex = terrain_vertex,
        .terrain_index = terrain_index,
    };
}

pub fn deinit(self: Self) void {
    self.device.waitIdle();
    self.graphics_pipeline.deinit(self.device);
    self.swapchain.deinit(self.device);
    self.render_pass.deinit(self.device);
    self.device.deinit();
}

pub fn setCamera(self: *Self, camera: *Camera) void {
    const view = camera.getView();
    const view_memory = self.graphics_pipeline.view_memory;
    @memcpy(view_memory[0..@sizeOf(math.Matrix)], std.mem.asBytes(&view));

    const view_pos_memory = self.graphics_pipeline.view_pos_memory;
    const view_pos: [*]f32 = @alignCast(@ptrCast(view_pos_memory));
    view_pos[0] = camera.position[0];
    view_pos[1] = camera.position[1];
    view_pos[2] = camera.position[2];
}

pub fn begin(self: *Self) !void {
    try self.device.waitFence(self.current_frame);
    const image = try self.swapchain.nextImage(self.device, self.current_frame);
    try self.device.resetCommand(self.current_frame);
    try self.device.beginCommand(self.current_frame);
    self.render_pass.begin(self.swapchain, self.device, image, self.current_frame);
    self.current_image = image;
}

pub fn beginGraphics(self: *Self) !void {
    self.graphics_pipeline.bind(self.device, self.current_frame);
    self.device.bindVertexBuffer(self.graphics_pipeline.vertex_buffer, self.current_frame);
    self.device.bindIndexBuffer(self.graphics_pipeline.index_buffer, self.current_frame);
    self.device.bindDescriptorSets(self.graphics_pipeline, self.current_frame, 0);
}

pub fn beginTerrain(self: *Self) !void {
    self.terrain_pipeline.bind(self.device, self.current_frame);
    self.device.bindTerrainSets(self.terrain_pipeline, self.current_frame);
}

pub fn setLightCount(self: *Self, count: u32) void {
    self.device.pushConstant(self.graphics_pipeline, c.VK_SHADER_STAGE_FRAGMENT_BIT, 0, 4, @constCast(@ptrCast(&count)), self.current_frame);
}

pub fn setTransform(self: *Self, transform: u32) void {
    self.device.pushConstant(self.graphics_pipeline, c.VK_SHADER_STAGE_VERTEX_BIT, 4, 4, @constCast(@ptrCast(&transform)), self.current_frame);
}

pub fn end(self: *Self) !void {
    self.render_pass.end(self.device, self.current_frame);
    try self.device.endCommand(self.current_frame);

    try self.device.submit(self.swapchain, self.current_image, self.current_frame);

    self.current_frame = (self.current_frame + 1) % 2;

        self.device.waitIdle();
    }
