const std = @import("std");
const vk = @import("vulkan.zig");
const gltf = @import("gltf.zig");
const Allocator = std.mem.Allocator;
const c = vk.c;
const math = @import("math");

const Mesh = @This();

vertex_buffer: i32,
index_buffer: u32,
index_count: u32,

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

pub const TerrainVertex = struct {
    position: [2]f32,
    uv: [2]f32,
    texture: [2]f32,

    pub fn bindingDescription() vk.c.VkVertexInputBindingDescription {
        const binding_description: vk.c.VkVertexInputBindingDescription = .{
            .binding = 0,
            .stride = @sizeOf(TerrainVertex),
            .inputRate = vk.c.VK_VERTEX_INPUT_RATE_VERTEX,
        };

        return binding_description;
    }

    pub fn attributeDescriptions() []const c.VkVertexInputAttributeDescription {
        const attributes: []const c.VkVertexInputAttributeDescription = &.{
            .{
                .location = 0,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = 0,
            },
            .{
                .location = 1,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = 8,
            },
            .{
                .location = 2,
                .binding = 0,
                .format = c.VK_FORMAT_R32G32_SFLOAT,
                .offset = 16,
            },
        };

        return attributes;
    }
};


fn createVertexBuffer(device: vk.Device, vertices: std.ArrayList([6]f32)) !vk.Buffer {
    var data: [*c]?*anyopaque = null;

    const buffer = try device.initBuffer(vk.BufferUsage{ .transfer_src = true }, vk.BufferFlags{ .host_visible = true, .host_coherent = true }, @sizeOf([6]f32) * vertices.items.len);

    try vk.mapError(vk.c.vkMapMemory(
        device.handle,
        buffer.memory,
        0,
        buffer.size,
        0,
        @ptrCast(&data),
    ));

    if (data) |ptr| {
        const gpu_vertices: [*]Mesh.TerrainVertex = @ptrCast(@alignCast(ptr));

        @memcpy(gpu_vertices, @as([]Mesh.TerrainVertex, @ptrCast(vertices.items[0..])));
    }

    vk.c.vkUnmapMemory(device.handle, buffer.memory);

    const vertex_buffer = try device.initBuffer(vk.BufferUsage{ .vertex_buffer = true, .transfer_dst = true, .transfer_src = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(Mesh.TerrainVertex) * vertices.items.len);

    try buffer.copyTo(device, vertex_buffer, 0);
    buffer.deinit(device.handle);

    return vertex_buffer;
}

fn createIndexBuffer(device: vk.Device, indices: std.ArrayList(u32)) !vk.Buffer {
    var data: [*c]?*anyopaque = null;

    const buffer = try device.initBuffer(vk.BufferUsage{ .transfer_src = true }, vk.BufferFlags{ .host_visible = true, .host_coherent = true }, @sizeOf(u32) * indices.items.len);

    try vk.mapError(vk.c.vkMapMemory(
        device.handle,
        buffer.memory,
        0,
        buffer.size,
        0,
        @ptrCast(&data),
    ));

    if (data) |ptr| {
        const gpu_indices: [*]u32 = @ptrCast(@alignCast(ptr));

        @memcpy(gpu_indices, indices.items[0..]);
    }

    vk.c.vkUnmapMemory(device.handle, buffer.memory);

    const index_buffer = try device.initBuffer(vk.BufferUsage{ .index_buffer = true, .transfer_dst = true, .transfer_src = true }, vk.BufferFlags{ .device_local = true }, @sizeOf(u32) * indices.items.len);

    try buffer.copyTo(device, index_buffer, 0);
    buffer.deinit(device.handle);

    return index_buffer;
}

pub fn terrain(allocator: std.mem.Allocator, device: vk.Device, width: usize, height: usize, resolution: usize) !struct { vk.Buffer, vk.Buffer } {
    var vertices = std.ArrayList([6]f32).init(allocator);
    defer vertices.deinit();
    var indices = std.ArrayList(u32).init(allocator);
    defer indices.deinit();

    for (0..width*resolution) |x| {
        for (0..height*resolution) |z| {
            const offset_x = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width*resolution - 1)) * @as(f32, @floatFromInt(width));
            const offset_z = @as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(height*resolution - 1)) * @as(f32, @floatFromInt(height));
            const u = @as(f32, @floatFromInt(x)) / @as(f32, @floatFromInt(width*resolution - 1));
            const v = @as(f32, @floatFromInt(z)) / @as(f32, @floatFromInt(width*resolution - 1));

            const vertex: [6]f32 = .{offset_x, offset_z, u, v, offset_x, offset_z };
            try vertices.append(vertex);
        }
    }


    for (0..width*resolution-1) |x| {
        for (0..height*resolution-1) |z| {
            const top_left = @as(u32, @intCast(z * width*resolution + x));
            const top_right = @as(u32, @intCast(z * width*resolution + (x+1)));
            const bottom_left = @as(u32, @intCast((z+1) * width*resolution + x));
            const bottom_right = @as(u32, @intCast((z+1) * width*resolution + (x + 1)));

            try indices.append(top_left);
            try indices.append(top_right);
            try indices.append(bottom_left);

            try indices.append(top_right);
            try indices.append(bottom_right);
            try indices.append(bottom_left);
        }
    }
    
    const vertex_buffer = try createVertexBuffer(device, vertices);
    const index_buffer = try createIndexBuffer(device, indices);

    return .{ vertex_buffer, index_buffer };
}
