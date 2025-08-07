const std = @import("std");
const vk = @import("vulkan.zig");
const gltf = @import("gltf.zig");
const Allocator = std.mem.Allocator;
const c = vk.c;

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

pub fn init(allocator: Allocator, device: anytype) !Mesh {
    const vertex_buffer = try Mesh.createVertexBuffer(allocator, device);
    const index_buffer = try Mesh.createIndexBuffer(allocator, device);

    return Mesh{
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
    };
}
