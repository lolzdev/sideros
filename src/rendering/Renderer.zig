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
allocator: Allocator,
previous_time: std.Io.Timestamp,
current_image: usize,
pending_resize: ?c.VkExtent2D,

pub fn init(allocator: Allocator, io: std.Io, instance_handle: vk.c.VkInstance, surface_handle: vk.c.VkSurfaceKHR) !Self {
    const instance: vk.Instance = .{ .handle = instance_handle };
    const surface: vk.Surface = .{ .handle = surface_handle };
    var physical_device = try vk.PhysicalDevice.pick(allocator, instance);
    const device = try physical_device.create_device(surface, allocator, 2);

    const vertex_shader = try device.initShader("shader_vert");
    defer device.deinitShader(vertex_shader);
    const fragment_shader = try device.initShader("shader_frag");
    defer device.deinitShader(fragment_shader);

    const initial_extent = try vk.Swapchain.pickExtent(surface, physical_device, null);
    const render_pass = try vk.RenderPass.init(allocator, device, surface, physical_device, initial_extent);

    const swapchain = try vk.Swapchain.init(allocator, surface, device, physical_device, render_pass, null, null);

    var pipeline_builder = vk.GraphicsPipeline.Builder.init(allocator, device);

    const texture = try Texture.init("assets/textures/container.png", device);
    const diffuse = try Texture.init("assets/textures/container_specular.png", device);

    _ = try pipeline_builder.addTexture(texture, diffuse);
    _ = try pipeline_builder.addTexture(texture, diffuse);
    _ = try pipeline_builder.addTexture(texture, diffuse);
    _ = try pipeline_builder.addTexture(texture, diffuse);

    const mesh = try pipeline_builder.addMesh(io, "assets/models/cube.glb");
    var graphics_pipeline = try pipeline_builder.build(swapchain, render_pass, vertex_shader, fragment_shader);

    const terrain_vertex_shader = try device.initShader("terrain_vert");
    defer device.deinitShader(terrain_vertex_shader);
    const terrain_fragment_shader = try device.initShader("terrain_frag");
    defer device.deinitShader(terrain_fragment_shader);

    const terrain_pipeline = try vk.TerrainPipeline.init(graphics_pipeline, terrain_vertex_shader, terrain_fragment_shader);

    graphics_pipeline.directional_light.direction = .{ -0.2, -1.0, -0.3 };
    graphics_pipeline.directional_light.ambient = .{ 0.5, 0.5, 0.5 };
    graphics_pipeline.directional_light.diffuse = .{ 0.5, 0.5, 0.5 };
    graphics_pipeline.directional_light.specular = .{ 0.5, 0.5, 0.5 };

    graphics_pipeline.point_lights[0].position = .{ 0.0, 0.0, 0.0 };
    graphics_pipeline.point_lights[0].data[0] = 1.0;
    graphics_pipeline.point_lights[0].data[1] = 0.9;
    graphics_pipeline.point_lights[0].data[2] = 0.8;
    graphics_pipeline.point_lights[0].ambient = .{ 0.2, 0.2, 0.2 };
    graphics_pipeline.point_lights[0].diffuse = .{ 0.5, 0.5, 0.5 };
    graphics_pipeline.point_lights[0].specular = .{ 1.0, 1.0, 1.0 };

    graphics_pipeline.point_lights[1].position = .{ 0.0, 2.0, 0.5 };
    graphics_pipeline.point_lights[1].data[0] = 1.0;
    graphics_pipeline.point_lights[1].data[1] = 0.9;
    graphics_pipeline.point_lights[1].data[2] = 0.8;
    graphics_pipeline.point_lights[1].ambient = .{ 0.2, 0.2, 0.2 };
    graphics_pipeline.point_lights[1].diffuse = .{ 0.5, 0.5, 0.5 };
    graphics_pipeline.point_lights[1].specular = .{ 1.0, 1.0, 1.0 };

    var transforms = std.ArrayList(math.Transform).empty;

    try transforms.append(allocator, math.Transform.init(.{ 0.0, 0.0, 0.0 }, .{ 0.5, 0.5, 0.5 }, .{ 0.0, 0.0, 0.0 }));
    try transforms.append(allocator, math.Transform.init(.{ 0.0, 0.5, 1.0 }, .{ 0.5, 0.5, 0.5 }, .{ 0.0, 0.0, 0.0 }));

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
        .allocator = allocator,
        .previous_time = std.Io.Timestamp.now(std.Io.Threaded.global_single_threaded.io(), .awake),
        .mesh = mesh,
        .current_image = undefined,
        .pending_resize = null,
    };
}

pub fn deinit(self: *Self) void {
    self.device.waitIdle();
    self.terrain_pipeline.deinit(self.device);
    self.graphics_pipeline.deinit(self.device);
    self.swapchain.deinit(self.device);
    self.render_pass.deinit(self.device);
    self.transforms.deinit(self.allocator);
    self.device.deinit();
}

pub fn setCamera(self: *Self, camera: *Camera) void {
    const view = camera.getView();
    const view_memory = self.graphics_pipeline.view_memory;
    @memcpy(view_memory[0..@sizeOf(math.Matrix)], std.mem.asBytes(&view));

    const view_pos_memory = self.graphics_pipeline.view_pos_memory;
    const view_pos: [*]f32 = @ptrCast(@alignCast(view_pos_memory));
    view_pos[0] = camera.position[0];
    view_pos[1] = camera.position[1];
    view_pos[2] = camera.position[2];
}

pub fn begin(self: *Self) !void {
    try self.applyPendingResize();
    try self.device.waitFence(self.current_frame);
    const image = self.swapchain.nextImage(self.device, self.current_frame) catch |err| switch (err) {
        error.OutOfDate => {
            try self.recreateSwapchain();
            return self.begin();
        },
        else => return err,
    };
    try self.device.resetCommand(self.current_frame);
    try self.device.beginCommand(self.current_frame);
    self.render_pass.begin(self.swapchain, self.device, image, self.current_frame);
    self.setViewport();
    self.current_image = image;
}

pub fn beginGraphics(self: *Self) !void {
    self.graphics_pipeline.bind(self.device, self.current_frame);
    self.device.bindVertexBuffer(self.graphics_pipeline.vertex_buffer, self.current_frame);
    self.device.bindIndexBuffer(self.graphics_pipeline.index_buffer, self.current_frame);
    self.device.bindDescriptorSets(self.graphics_pipeline, self.current_frame);
}

pub fn beginTerrain(self: *Self) !void {
    self.terrain_pipeline.bind(self.device, self.current_frame);
    self.device.bindTerrainSets(self.terrain_pipeline, self.current_frame);
}

pub fn setLightCount(self: *Self, count: u32) void {
    self.device.pushConstant(self.graphics_pipeline, c.VK_SHADER_STAGE_FRAGMENT_BIT, 0, 4, @ptrCast(@constCast(&count)), self.current_frame);
}

pub fn setTransform(self: *Self, transform: u32) void {
    self.device.pushConstant(self.graphics_pipeline, c.VK_SHADER_STAGE_VERTEX_BIT, 4, 4, @ptrCast(@constCast(&transform)), self.current_frame);
}

pub fn end(self: *Self) !void {
    self.render_pass.end(self.device, self.current_frame);
    try self.device.endCommand(self.current_frame);

    self.device.submit(self.swapchain, self.current_image, self.current_frame) catch |err| switch (err) {
        error.OutOfDate => {
            try self.recreateSwapchain();
        },
        else => return err,
    };

    self.current_frame = (self.current_frame + 1) % 2;

    self.device.waitIdle();
}

pub fn resize(self: *Self, width: u32, height: u32) void {
    if (width == 0 or height == 0) {
        return;
    }
    self.pending_resize = .{ .width = width, .height = height };
}

fn applyPendingResize(self: *Self) !void {
    if (self.pending_resize != null) {
        try self.recreateSwapchain();
    }
}

fn recreateSwapchain(self: *Self) !void {
    const preferred_extent = self.pending_resize orelse self.swapchain.extent;
    const extent = try vk.Swapchain.pickExtent(self.surface, self.physical_device, preferred_extent);
    self.pending_resize = null;

    self.device.waitIdle();
    try self.render_pass.resize(self.device, self.physical_device, extent);

    const old_swapchain = self.swapchain;
    const new_swapchain = try vk.Swapchain.init(self.allocator, self.surface, self.device, self.physical_device, self.render_pass, extent, old_swapchain.handle);
    self.swapchain = new_swapchain;
    self.graphics_pipeline.updateSwapchain(new_swapchain);
    old_swapchain.deinit(self.device);
}

fn setViewport(self: *Self) void {
    const viewport: c.VkViewport = .{
        .x = 0.0,
        .y = 0.0,
        .width = @floatFromInt(self.swapchain.extent.width),
        .height = @floatFromInt(self.swapchain.extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };
    const scissor: c.VkRect2D = .{
        .offset = .{ .x = 0, .y = 0 },
        .extent = self.swapchain.extent,
    };

    c.vkCmdSetViewport(self.device.command_buffers[self.current_frame], 0, 1, &viewport);
    c.vkCmdSetScissor(self.device.command_buffers[self.current_frame], 0, 1, &scissor);
}
