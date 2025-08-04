const c = @import("sideros").c;
const math = @import("sideros").math;
const ecs = @import("ecs");
const std = @import("std");
const vk = @import("vulkan.zig");
pub const Mesh = @import("Mesh.zig");
pub const Camera = @import("Camera.zig");
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

pub fn init(comptime C: type, comptime S: type, allocator: Allocator, display: C, s: S) !Renderer {
    const instance = try vk.Instance.create(allocator);

    const surface = try vk.Surface.create(C, S, instance, display, s);

    var physical_device = try vk.PhysicalDevice.pick(allocator, instance);
    const device = try physical_device.create_device(surface, allocator, 2);

    const vertex_shader = try device.createShader("shader_vert");
    defer device.destroyShader(vertex_shader);
    const fragment_shader = try device.createShader("shader_frag");
    defer device.destroyShader(fragment_shader);

    const render_pass = try vk.RenderPass(2).create(allocator, device, surface, physical_device);

    const swapchain = try vk.Swapchain(2).create(allocator, surface, device, physical_device, render_pass);

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

pub fn deinit(self: Renderer) void {
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

// TODO: render is maybe a bad name? something like present() or submit() is better?
pub fn render(pool: *ecs.Pool) anyerror!void {
    var renderer = pool.resources.renderer;
    var camera = pool.resources.camera;

    const view_memory = renderer.graphics_pipeline.view_memory;
    @memcpy(view_memory[0..@sizeOf(math.Matrix)], std.mem.asBytes(&camera.getView()));

    try renderer.device.waitFence(renderer.current_frame);
    const image = try renderer.swapchain.nextImage(renderer.device, renderer.current_frame);
    try renderer.device.resetCommand(renderer.current_frame);
    try renderer.device.beginCommand(renderer.current_frame);
    renderer.render_pass.begin(renderer.swapchain, renderer.device, image, renderer.current_frame);
    renderer.graphics_pipeline.bind(renderer.device, renderer.current_frame);
    renderer.device.bindVertexBuffer(renderer.vertex_buffer, renderer.current_frame);
    renderer.device.bindIndexBuffer(renderer.index_buffer, renderer.current_frame);
    renderer.device.bindDescriptorSets(renderer.graphics_pipeline, renderer.current_frame);
    renderer.device.draw(@intCast(renderer.index_buffer.size / @sizeOf(u16)), renderer.current_frame);
    renderer.render_pass.end(renderer.device, renderer.current_frame);
    try renderer.device.endCommand(renderer.current_frame);

    try renderer.device.submit(renderer.swapchain, image, renderer.current_frame);

    renderer.current_frame = (renderer.current_frame + 1) % 2;

    renderer.device.waitIdle();
}
