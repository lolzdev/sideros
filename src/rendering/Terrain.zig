const std = @import("std");
const vk = @import("vulkan.zig");
const Mesh = @import("Mesh.zig");
const math = @import("math");
const Self = @This();

pub const Generator = struct {
    octaves: u32,
    lacunarity: f64,
    gain: f64,
    scale: f64 = 0.01,
    multiplier: f64,
    exponent: f64 = 1.0,

    width: usize,
    height: usize,
    seed: u64,
    resolution: f32 = 1.0,
};

heightmap: []f64,
width: usize,
height: usize,
seed: u64,

texture: vk.Texture,
vertex_buffer: vk.Buffer,
index_buffer: vk.Buffer,

pub fn init(allocator: std.mem.Allocator, device: vk.Device, generator: Generator) !Self {
    const perlin: math.PerlinNoise = .{ .seed = generator.seed };
    const heightmap = try allocator.alloc(f64, generator.width * generator.height);
    const heightmap_data = try allocator.alloc(u32, generator.width * generator.height);
    defer allocator.free(heightmap_data);
    for (0..generator.width) |x| {
        for (0..generator.height) |y| {
            var pixel = (perlin.fbm(@as(f64, @floatFromInt(x)) * generator.scale, @as(f64, @floatFromInt(y)) * generator.scale, generator.octaves, generator.lacunarity, generator.gain) * generator.multiplier);
            pixel = std.math.pow(f64, pixel, generator.exponent);
            const gray: u32 = @intFromFloat(pixel * 255);
            const color: u32 = (255 << 24) | (gray << 16) | (gray << 8) | gray;

            heightmap[x*generator.width + y] = pixel;
            heightmap_data[x*generator.width + y] = color;
        }
    }

    const vertex_buffer, const index_buffer = try Mesh.terrain(allocator, device, generator.width, generator.height, generator.resolution);
    const heightmap_texture = try vk.Texture.fromBytes(@alignCast(@ptrCast(heightmap_data)), device, generator.width, generator.height);

    return .{
        .heightmap = heightmap,
        .width = generator.width,
        .height = generator.height,
        .seed = generator.seed,
        .vertex_buffer = vertex_buffer,
        .index_buffer = index_buffer,
        .texture = heightmap_texture,
    };
}

pub fn deinit(self: *Self, allocator: std.mem.Allocator, device: vk.Device) !void {
    allocator.free(self.heightmap);
    self.vertex_buffer.deinit(device.handle);
    self.index_buffer.deinit(device.handle);
    self.texture.deinit(device);
}

pub fn getHeight(self: Self, x: usize, y: usize) f64 {
    return self.heightmap[x*self.width + y];
}
