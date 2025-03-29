const std = @import("std");
const ecs = @import("ecs");
const sideros = @import("sideros");
const math = sideros.math;

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
front: @Vector(3, f32),
up: @Vector(3, f32),
speed: f32 = 2.5,

pub fn getProjection(width: usize, height: usize) math.Matrix {
    return math.Matrix.perspective(math.rad(45.0), (@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height))), 0.1, 10.0);
}

pub fn getView(self: Camera) math.Matrix {
    math.lookAt(self.position, self.position + self.front, self.up);
}

pub fn moveCamera(pool: *ecs.Pool) void {
    const input = pool.resources.input;
    const camera = pool.resources.camera;
    if (input.isKeyDown(.w)) {
        camera.position += (camera.front * (camera.speed * pool.resources.delta_time));
    }
    if (input.isKeyDown(.s)) {
        camera.position -= (camera.front * (camera.speed * pool.resources.delta_time));
    }
    if (input.isKeyDown(.a)) {
        camera.position -= math.normalize(math.cross(camera.front, camera.up)) * (camera.speed * pool.resources.delta_time);
    }
    if (input.isKeyDown(.d)) {
        camera.position += math.normalize(math.cross(camera.front, camera.up)) * (camera.speed * pool.resources.delta_time);
    }
}
