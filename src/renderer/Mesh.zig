const c = @import("sideros").c;
const std = @import("std");
const vk = @import("vulkan.zig");
const gltf = @import("gltf.zig");
const Allocator = std.mem.Allocator;

const Mesh = @This();

pub const Vertex = struct {
    position: [3]f32,

    pub fn create(x: f32, y: f32, z: f32) Vertex {
        return Vertex{
            .position = .{ x, y, z },
        };
    }

    pub fn bindingDescription() c.VkVertexInputBindingDescription {
        const binding_description: c.VkVertexInputBindingDescription = .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return binding_description;
    }

    pub fn attributeDescription() c.VkVertexInputAttributeDescription {
        const attribute_description: c.VkVertexInputAttributeDescription = .{
            .location = 0,
            .binding = 0,
            .format = c.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = 0,
        };

        return attribute_description;
    }
};

vertex_buffer: vk.Buffer,
index_buffer: vk.Buffer,

pub fn createVertexBuffer(allocator: Allocator, device: anytype) !vk.Buffer {
    const gltf_data = try gltf.parseFile(allocator, "assets/models/block.glb");

    const vertices = gltf_data.vertices;
    defer allocator.free(vertices);
    defer allocator.free(gltf_data.indices);

    var data: [*c]?*anyopaque = null;

    const buffer = try device.createBuffer(vk.BufferUsage{ .transfer_src = true }, vk.BufferFlags{ .host_visible = true, .host_coherent = true }, @sizeOf(Vertex) * vertices.len);

    try vk.mapError(c.vkMapMemory(
        device.handle,
        buffer.memory,
        0,
        buffer.size,
        0,
        @ptrCast(&data),
    ));

    if (data) |ptr| {
        const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(ptr));

        @memcpy(gpu_vertices, @as([]Vertex, @ptrCast(vertices[0..])));
    }

    c.vkUnmapMemory(device.handle, buffer.memory);

    const vertex_buffer = try device.createBuffer(vk.BufferUsage{ .vertex_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(Vertex) * vertices.len);

    try buffer.copyTo(device, vertex_buffer);
    buffer.destroy(device.handle);

    return vertex_buffer;
}

pub fn createIndexBuffer(allocator: Allocator, device: anytype) !vk.Buffer {
    const gltf_data = try gltf.parseFile(allocator, "assets/models/block.glb");
    const indices = gltf_data.indices;
    defer allocator.free(indices);
    defer allocator.free(gltf_data.vertices);
    //const indices = [_]u16{ 0, 1, 2, 3, 0, 2 };

    var data: [*c]?*anyopaque = null;

    const buffer = try device.createBuffer(vk.BufferUsage{ .transfer_src = true }, vk.BufferFlags{ .host_visible = true, .host_coherent = true }, @sizeOf(u16) * indices.len);

    try vk.mapError(c.vkMapMemory(
        device.handle,
        buffer.memory,
        0,
        buffer.size,
        0,
        @ptrCast(&data),
    ));

    if (data) |ptr| {
        const gpu_indices: [*]u16 = @ptrCast(@alignCast(ptr));

        @memcpy(gpu_indices, indices[0..]);
    }

    c.vkUnmapMemory(device.handle, buffer.memory);

    const index_buffer = try device.createBuffer(vk.BufferUsage{ .index_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(u16) * indices.len);

    try buffer.copyTo(device, index_buffer);
    buffer.destroy(device.handle);

    return index_buffer;
}

pub fn create(allocator: Allocator, device: anytype) !Mesh {
    const vertex_buffer = try Mesh.createVertexBuffer(allocator, device);
    const index_buffer = try Mesh.createIndexBuffer(allocator, device);

    return Mesh{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
    };
}
