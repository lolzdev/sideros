const std = @import("std");
const vk = @import("vulkan.zig");
const Mesh = @import("Mesh.zig");
const Camera = @import("Camera.zig");
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

pub const Hit = struct {
    position: @Vector(3, f32),
};

heightmap: []f64,
width: usize,
height: usize,
world_width: usize,
world_height: usize,
seed: u64,

texture: vk.Texture,
vertex_buffer: vk.Buffer,
index_buffer: vk.Buffer,

const layers: [5][3]u32 = .{
    .{ 0, 94, 255 },
    .{ 222, 208, 20 },
    .{ 14, 122, 41 },
    .{ 64, 20, 20 },
    .{ 253, 253, 253 },
};

pub fn init(allocator: std.mem.Allocator, device: vk.Device, generator: Generator) !Self {
    const perlin: math.PerlinNoise = .{ .seed = generator.seed };
    const heightmap = try allocator.alloc(f64, generator.width * generator.resolution * generator.height * generator.resolution);
    const heightmap_data = try allocator.alloc(u32, generator.width * generator.resolution * generator.height * generator.resolution);
    defer allocator.free(heightmap_data);

    var max_noise_height = std.math.floatMin(f64);
    var min_noise_height = std.math.floatMax(f64);

    const columns = generator.width * generator.resolution;
    const rows = generator.height * generator.resolution;

    for (0..rows) |z| {
        for (0..columns) |x| {
            const u = @as(f64, @floatFromInt(x)) / @as(f64, @floatFromInt(columns - 1));
            const v = @as(f64, @floatFromInt(z)) / @as(f64, @floatFromInt(rows - 1));

            const h_x = u * @as(f64, @floatFromInt(generator.width));
            const h_y = v * @as(f64, @floatFromInt(generator.height));

            var pixel = perlin.fbm(h_x / generator.scale, h_y / generator.scale, generator.octaves, generator.lacunarity, generator.gain) * generator.multiplier;
            pixel = std.math.pow(f64, pixel, generator.exponent);

            if (pixel > max_noise_height) {
                max_noise_height = pixel;
            }
            if (pixel < min_noise_height) {
                min_noise_height = pixel;
            }
            heightmap[z * columns + x] = pixel;
        }
    }

    for (0..rows) |z| {
        for (0..columns) |x| {
            const index = z * columns + x;
            const pixel = math.inverseLerp(min_noise_height, max_noise_height, heightmap[index]);
            heightmap[index] = pixel;

            const gray: u32 = @intFromFloat(pixel * 255);
            const grayscale: u32 = (255 << 24) | (gray << 16) | (gray << 8) | gray;
            heightmap_data[index] = grayscale;
        }
    }

    const vertex_buffer, const index_buffer = try Mesh.terrain(allocator, device, generator.width, generator.height, generator.resolution);
    const heightmap_texture = try vk.Texture.fromBytes(@ptrCast(@alignCast(heightmap_data)), device, generator.width * generator.resolution, generator.height * generator.resolution);

    return .{
        .heightmap = heightmap,
        .width = columns,
        .height = rows,
        .world_width = generator.width,
        .world_height = generator.height,
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

pub fn getHeight(self: Self, x: usize, z: usize) f64 {
    return self.heightmap[z * self.width + x];
}

pub fn cursorHit(self: Self, camera: *Camera, cursor_x: f64, cursor_y: f64, viewport_width: u32, viewport_height: u32) ?Hit {
    const ray = camera.screenRay(cursor_x, cursor_y, viewport_width, viewport_height) orelse return null;
    return self.raycast(camera.position, ray);
}

pub fn raycast(self: Self, origin: @Vector(3, f32), ray: @Vector(3, f32)) ?Hit {
    const max_distance: f32 = 1000.0;
    const step: f32 = 1.0;
    var t: f32 = 0.0;

    while (t <= max_distance) : (t += step) {
        const point = origin + ray * @as(@Vector(3, f32), @splat(t));
        if (!self.containsWorldPoint(point)) {
            continue;
        }

        const height = self.worldHeight(point[0], point[2]);
        if (point[1] <= height) {
            var low = @max(0.0, t - step);
            var high = t;
            for (0..12) |_| {
                const mid = (low + high) * 0.5;
                const mid_point = origin + ray * @as(@Vector(3, f32), @splat(mid));
                if (!self.containsWorldPoint(mid_point) or mid_point[1] > self.worldHeight(mid_point[0], mid_point[2])) {
                    low = mid;
                } else {
                    high = mid;
                }
            }

            const hit_point = origin + ray * @as(@Vector(3, f32), @splat(high));
            return .{ .position = .{ hit_point[0], self.worldHeight(hit_point[0], hit_point[2]), hit_point[2] } };
        }
    }

    return null;
}

pub fn containsWorldPoint(self: Self, point: @Vector(3, f32)) bool {
    return point[0] >= 0.0 and point[2] >= 0.0 and point[0] <= self.worldWidth() and point[2] <= self.worldDepth();
}

pub fn worldHeight(self: Self, world_x: f32, world_z: f32) f32 {
    const x = clampFloat(world_x, 0.0, self.worldWidth());
    const z = clampFloat(world_z, 0.0, self.worldDepth());
    const max_x = @as(f32, @floatFromInt(self.width - 1));
    const max_z = @as(f32, @floatFromInt(self.height - 1));
    const sample_x = if (self.width > 1) x / self.worldWidth() * max_x else 0.0;
    const sample_z = if (self.height > 1) z / self.worldDepth() * max_z else 0.0;

    const x0: usize = @intFromFloat(@floor(sample_x));
    const z0: usize = @intFromFloat(@floor(sample_z));
    const x1 = @min(x0 + 1, self.width - 1);
    const z1 = @min(z0 + 1, self.height - 1);
    const tx = sample_x - @as(f32, @floatFromInt(x0));
    const tz = sample_z - @as(f32, @floatFromInt(z0));

    const h00 = self.normalizedHeight(x0, z0);
    const h10 = self.normalizedHeight(x1, z0);
    const h01 = self.normalizedHeight(x0, z1);
    const h11 = self.normalizedHeight(x1, z1);

    const hx0 = lerp(h00, h10, tx);
    const hx1 = lerp(h01, h11, tx);
    const h = lerp(hx0, hx1, tz);
    return h * std.math.pow(f32, 2.0, h * 5.0);
}

pub fn worldWidth(self: Self) f32 {
    return @floatFromInt(self.world_width);
}

pub fn worldDepth(self: Self) f32 {
    return @floatFromInt(self.world_height);
}

fn normalizedHeight(self: Self, x: usize, z: usize) f32 {
    const height = clampFloat(@floatCast(self.getHeight(x, z)), 0.0, 1.0);
    const quantized = @as(f32, @floatFromInt(@as(u32, @intFromFloat(height * 255.0)))) / 255.0;
    return srgbToLinear(quantized);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn clampFloat(value: f32, min: f32, max: f32) f32 {
    return @min(@max(value, min), max);
}

fn srgbToLinear(value: f32) f32 {
    if (value <= 0.04045) {
        return value / 12.92;
    }
    return std.math.pow(f32, (value + 0.055) / 1.055, 2.4);
}

fn pixelToNoise(x: usize, y: usize, width: usize, height: usize, world_min: @Vector(2, f64), world_max: @Vector(2, f64), scale: f64) struct { f64, f64 } {
    const u = (@as(f64, @floatFromInt(x)) + 0.5) / @as(f64, @floatFromInt(width));
    const v = (@as(f64, @floatFromInt(y)) + 0.5) / @as(f64, @floatFromInt(height));

    const world_x = world_min[0] + u * (world_max[0] - world_min[0]);
    const world_y = world_min[1] + v * (world_max[1] - world_min[1]);

    return .{ world_x / scale, world_y / scale };
}
