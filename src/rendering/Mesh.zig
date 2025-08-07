const std = @import("std");
const vk = @import("vulkan.zig");
const gltf = @import("gltf.zig");
const Allocator = std.mem.Allocator;
const c = vk.c;

const Mesh = @This();

pub const Vertex = struct {
    position: [3]f32,
    normal: [3]f32,
    uv: [2]f32,

    pub fn init(x: f32, y: f32, z: f32, normal_x: f32, normal_y: f32, normal_z: f32, u: f32, v: f32) Vertex {
        return Vertex{
            .position = .{ x, y, z },
            .normal = .{ normal_x, normal_y, normal_z },
            .uv = .{u, v},
        };
    }

    pub fn bindingDescription() vk.c.VkVertexInputBindingDescription {
        const binding_description: vk.c.VkVertexInputBindingDescription = .{
            .binding = 0,
            .stride = @sizeOf(Vertex),
            .inputRate = vk.c.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return binding_description;
    }

    pub fn attributeDescriptions() []const c.VkVertexInputAttributeDescription {
        const attributes: []const c.VkVertexInputAttributeDescription = &.{
            .{
                .location = 0,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = 0,
            },
            .{
                .location = 1,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32B32_SFLOAT,
                .offset = 12,
            },
            .{
                .location = 2,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = 24,
            },
        };

        return attributes;
    }
};

vertex_buffer: vk.Buffer,
index_buffer: vk.Buffer,

pub fn createVertexBuffer(allocator: Allocator, device: anytype) !vk.Buffer {
    const gltf_data = try gltf.parseFile(allocator, "assets/models/cube.glb");

    const vertices = gltf_data.vertices;
    const normals = gltf_data.normals;
    const uvs = gltf_data.uvs;
    defer allocator.free(uvs);
    defer allocator.free(normals);
    defer allocator.free(vertices);
    defer allocator.free(gltf_data.indices);

    const final_array = try allocator.alloc([8]f32, vertices.len);
    defer allocator.free(final_array);

    for (vertices, normals, uvs, final_array) |vertex, normal, uv, *final| {
        final[0] = vertex[0];
        final[1] = vertex[1];
        final[2] = vertex[2];

        final[3] = normal[0];
        final[4] = normal[1];
        final[5] = normal[2];

        final[6] = uv[0];
        final[7] = uv[1];
    }

    var data: [*c]?*anyopaque = null;

    const buffer = try device.initBuffer(vk.BufferUsage{ .transfer_src = true }, vk.BufferFlags{ .host_visible = true, .host_coherent = true }, @sizeOf([8]f32) * vertices.len);

    try vk.mapError(vk.c.vkMapMemory(
        device.handle,
        buffer.memory,
        0,
        buffer.size,
        0,
        @ptrCast(&data),
    ));

    if (data) |ptr| {
        const gpu_vertices: [*]Vertex = @ptrCast(@alignCast(ptr));

        @memcpy(gpu_vertices, @as([]Vertex, @ptrCast(final_array[0..])));
    }

    vk.c.vkUnmapMemory(device.handle, buffer.memory);

    const vertex_buffer = try device.initBuffer(vk.BufferUsage{ .vertex_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(Vertex) * vertices.len);

    try buffer.copyTo(device, vertex_buffer);
    buffer.deinit(device.handle);

    return vertex_buffer;
}

pub fn createIndexBuffer(allocator: Allocator, device: anytype) !vk.Buffer {
    const gltf_data = try gltf.parseFile(allocator, "assets/models/cube.glb");
    const indices = gltf_data.indices;
    defer allocator.free(indices);
    defer allocator.free(gltf_data.vertices);
    defer allocator.free(gltf_data.normals);
    defer allocator.free(gltf_data.uvs);

    var data: [*c]?*anyopaque = null;

    const buffer = try device.initBuffer(vk.BufferUsage{ .transfer_src = true }, vk.BufferFlags{ .host_visible = true, .host_coherent = true }, @sizeOf(u16) * indices.len);

    try vk.mapError(vk.c.vkMapMemory(
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

    vk.c.vkUnmapMemory(device.handle, buffer.memory);

    const index_buffer = try device.initBuffer(vk.BufferUsage{ .index_buffer = true, .transfer_dst = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(u16) * indices.len);

    try buffer.copyTo(device, index_buffer);
    buffer.deinit(device.handle);

    return index_buffer;
}

pub fn init(allocator: Allocator, device: anytype) !Mesh {
    const vertex_buffer = try Mesh.createVertexBuffer(allocator, device);
    const index_buffer = try Mesh.createIndexBuffer(allocator, device);

    return Mesh{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
    };
}
