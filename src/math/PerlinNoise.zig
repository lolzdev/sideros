const std = @import("std");

const Self = @This();

seed: u64,

fn hash(self: Self, x: i32, y: i32) u64 {
    var hasher = std.hash.Wyhash.init(self.seed);
    hasher.update(std.mem.asBytes(&x));
    hasher.update(std.mem.asBytes(&y));
    return hasher.final();
}

fn random(self: Self, x: i32, y: i32) @Vector(2, f64) {
    const h = self.hash(x, y);
    var rng = std.Random.DefaultPrng.init(h);
    const angle = rng.random().float(f64) * std.math.tau;

    return .{ std.math.cos(angle), std.math.sin(angle) };
}

fn dot(a: @Vector(2, f64), b: @Vector(2, f64)) f64 {
    return @reduce(.Add, a*b);
}

fn fade(t: f64) f64 {
    return t * t * t * (t * (t * 6 - 15) + 10);
}

fn lerp(a: f64, b: f64, t: f64) f64 {
    return a + t * (b - a);
}

fn noise(self: Self, x: f64, y: f64) f64 {
     const x0 = @as(i32, @intFromFloat(std.math.floor(x)));
    const y0 = @as(i32, @intFromFloat(std.math.floor(y)));
    const x1 = x0 + 1;
    const y1 = y0 + 1;

    const sx = fade(x - @as(f64, @floatFromInt(x0)));
    const sy = fade(y - @as(f64, @floatFromInt(y0)));

    const grad00 = self.random(x0, y0);
    const grad10 = self.random(x1, y0);
    const grad01 = self.random(x0, y1);
    const grad11 = self.random(x1, y1);

    const dx = x - @as(f64, @floatFromInt(x0));
    const dy = y - @as(f64, @floatFromInt(y0));

    const dot00 = dot(grad00, .{ dx, dy });
    const dot10 = dot(grad10, .{ dx - 1, dy });
    const dot01 = dot(grad01, .{ dx, dy - 1 });
    const dot11 = dot(grad11, .{ dx - 1, dy - 1 });

    const ix0 = lerp(dot00, dot10, sx);
    const ix1 = lerp(dot01, dot11, sx);

    const value = lerp(ix0, ix1, sy);

    return value;
}

pub fn fbm(self: Self, x: f64, y: f64, octaves: u32, lacunarity: f64, gain: f64) f64 {
    var amplitude: f64 = 1.0;
    var frequency: f64 = 1.0;
    var maxAmplitude: f64 = 0.0;

    for(0..octaves) |_| {
        const value = (self.noise(x * frequency, y * frequency) * 2) - 1;
        maxAmplitude += amplitude * value;
        amplitude *= gain;
        frequency *= lacunarity;
    }

    return maxAmplitude;
}
