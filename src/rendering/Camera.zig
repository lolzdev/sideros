const std = @import("std");
const ecs = @import("ecs");
const math = @import("math");

const Camera = @This();
const UP = @Vector(3, f32){ 0.0, 1.0, 0.0 };

pub const Uniform = struct {
    proj: math.Matrix,
    view: math.Matrix,
    model: math.Matrix,
};

position: @Vector(3, f32),
target: @Vector(3, f32) = .{ 0.0, 0.0, -1.0 },
up: @Vector(3, f32) = .{ 0.0, 1.0, 0.0 },
speed: f32 = 5,

pub fn getProjection(width: usize, height: usize) math.Matrix {
    return math.Matrix.perspective(math.rad(45.0), (@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height))), 0.1, 100.0);
}

pub fn getView(self: *Camera) math.Matrix {
    return math.Matrix.lookAt(self.position, self.position + self.target, self.up);
}


