const c = @import("c.zig");
const std = @import("std");
const vk = @import("vulkan.zig");
pub const Window = @import("Window.zig");
pub const Mesh = @import("Mesh.zig");
const Allocator = std.mem.Allocator;

const Renderer = @This();

instance: vk.Instance,
surface: vk.Surface,
physical_device: vk.PhysicalDevice,
device: vk.Device(2),
render_pass: vk.RenderPass(2),
swapchain: vk.Swapchain(2),
graphics_pipeline: vk.GraphicsPipeline(2),
current_frame: u32,
vertex_buffer: vk.Buffer,
index_buffer: vk.Buffer,

pub fn create(allocator: Allocator, w: Window) !Renderer {
    const instance = try vk.Instance.create(allocator);

    const surface = try vk.Surface.create(instance, w);

    var physical_device = try vk.PhysicalDevice.pick(allocator, instance);
    const device = try physical_device.create_device(surface, allocator, 2);

    const vertex_shader = try device.createShader("shader_vert");
    defer device.destroyShader(vertex_shader);
    const fragment_shader = try device.createShader("shader_frag");
    defer device.destroyShader(fragment_shader);

    const render_pass = try vk.RenderPass(2).create(allocator, device, surface, physical_device);

    const swapchain = try vk.Swapchain(2).create(allocator, surface, device, physical_device, w, render_pass);

    const graphics_pipeline = try vk.GraphicsPipeline(2).create(device, swapchain, render_pass, vertex_shader, fragment_shader);

    // TODO: I think the renderer shouldn't have to interact with buffers. I think the API should change to
    // something along the lines of
    //    renderer.begin()
    //    renderer.render(triangle);
    //    renderer.render(some_other_thing);
    //    ...
    //    renderer.submit()
    const triangle = try Mesh.create(allocator, device);

    return Renderer{
        .instance = instance,
        .surface = surface,
        .physical_device = physical_device,
        .device = device,
        .render_pass = render_pass,
        .swapchain = swapchain,
        .graphics_pipeline = graphics_pipeline,
        .current_frame = 0,
        // TODO: Why are we storing the buffer and not the Mesh?
        .vertex_buffer = triangle.vertex_buffer,
        .index_buffer = triangle.index_buffer,
    };
}

pub fn destroy(self: Renderer) void {
    self.device.waitIdle();
    self.index_buffer.destroy(self.device.handle);
    self.vertex_buffer.destroy(self.device.handle);
    self.graphics_pipeline.destroy(self.device);
    self.swapchain.destroy(self.device);
    self.render_pass.destroy(self.device);
    self.device.destroy();
    self.surface.destroy(self.instance);
    self.instance.destroy();
}

// TODO: tick is maybe a bad name? something like present() or submit() is better?
pub fn tick(self: *Renderer) !void {
    try self.device.waitFence(self.current_frame);
    const image = try self.swapchain.nextImage(self.device, self.current_frame);
    try self.device.resetCommand(self.current_frame);
    try self.device.beginCommand(self.current_frame);
    self.render_pass.begin(self.swapchain, self.device, image, self.current_frame);
    self.graphics_pipeline.bind(self.device, self.current_frame);
    self.device.bindVertexBuffer(self.vertex_buffer, self.current_frame);
    self.device.bindIndexBuffer(self.index_buffer, self.current_frame);
    self.device.bindDescriptorSets(self.graphics_pipeline, self.current_frame);
    self.device.draw(@intCast(self.index_buffer.size / @sizeOf(u16)), self.current_frame);
    self.render_pass.end(self.device, self.current_frame);
    try self.device.endCommand(self.current_frame);

    try self.device.submit(self.swapchain, image, self.current_frame);

    self.current_frame = (self.current_frame + 1) % 2;
}
