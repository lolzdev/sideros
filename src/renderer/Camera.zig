const std = @import("std");
const ecs = @import("ecs");
const math = @import("../math.zig");
const Camera = @This();
const UP = @Vector(3, f32){ 0.0, 1.0, 0.0 };

pub const Uniform = struct {
    proj: math.Matrix,
    view: math.Matrix,
    model: math.Matrix,
};

uniform: Uniform,
position: @Vector(3, f32),
target: @Vector(3, f32),
direction: @Vector(3, f32),
right: @Vector(3, f32),
up: @Vector(3, f32),

fn input(pool: *ecs.Pool) void {
}
