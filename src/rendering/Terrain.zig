const std = @import("std");
const vk = @import("vulkan.zig");
const Mesh = @import("Mesh.zig");
const math = @import("math");
const stb = vk.Texture.stb;
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
    resolution: usize = 1,
};

heightmap: []f64,
width: usize,
height: usize,
seed: u64,

texture: vk.Texture,
vertex_buffer: vk.Buffer,
index_buffer: vk.Buffer,

const layers: [5][3]u32 = .{
    .{0, 94, 255},
    .{222, 208, 20},
    .{14, 122, 41},
    .{64, 20, 20},
    .{253, 253, 253},
};

pub fn init(allocator: std.mem.Allocator, device: vk.Device, generator: Generator) !Self {
    const perlin: math.PerlinNoise = .{ .seed = generator.seed };
    const heightmap = try allocator.alloc(f64, generator.width*generator.resolution * generator.height*generator.resolution);
    const heightmap_data = try allocator.alloc(u32, generator.width*generator.resolution * generator.height*generator.resolution);
    defer allocator.free(heightmap_data);

    var max_noise_height = std.math.floatMin(f64);
    var min_noise_height = std.math.floatMax(f64);

    const columns = generator.width*generator.resolution;
    const rows = generator.height*generator.resolution;

    for (0..columns) |x| {
        for (0..rows) |y| {
            const u = @as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(columns - 1));
            const v = @as(f64, @floatFromInt(y)) / @as(f64, @floatFromInt(rows - 1));

            const h_x = u * @as(f64, @floatFromInt(generator.width));
            const h_y = v * @as(f64, @floatFromInt(generator.height));

            var pixel = (perlin.fbm(h_x / generator.scale, h_y / generator.scale, generator.octaves, generator.lacunarity, generator.gain) * generator.multiplier);

            if (pixel > max_noise_height) {
                max_noise_height = pixel;
            } else if (pixel < min_noise_height) {
                min_noise_height = pixel;
            }

            pixel = std.math.pow(f64, pixel, generator.exponent);
            pixel = math.inverseLerp(min_noise_height, max_noise_height, pixel);
            
            heightmap[x*columns + y] = pixel;

            const gray: u32 = @intFromFloat(pixel * 255);
            const grayscale: u32 = (255 << 24) | (gray << 16) | (gray << 8) | gray;

            heightmap_data[x*columns + y] = grayscale;
        }
    }

    const vertex_buffer, const index_buffer = try Mesh.terrain(allocator, device, generator.width, generator.height, generator.resolution);
    const heightmap_texture = try vk.Texture.fromBytes(@alignCast(@ptrCast(heightmap_data)), device, generator.width*generator.resolution, generator.height*generator.resolution);

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

fn pixelToNoise(
    x: usize,
    y: usize,
    width: usize,
    height: usize,
    world_min: @Vector(2, f64),
    world_max: @Vector(2, f64),
    scale: f64
) struct { f64, f64 }{
    const u = (@as(f64, @floatFromInt(x)) + 0.5) / @as(f64, @floatFromInt(width));
    const v = (@as(f64, @floatFromInt(y)) + 0.5) / @as(f64, @floatFromInt(height));

    const world_x = world_min[0] + u * (world_max[0] - world_min[0]);
    const world_y = world_min[1] + v * (world_max[1] - world_min[1]);

    return .{ world_x / scale, world_y / scale };
}
