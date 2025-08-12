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
pitch: f32 = -45,
yaw: f32 = 0,
distance: f32 = 5.0,

pub fn getProjection(width: usize, height: usize) math.Matrix {
    return math.Matrix.perspective(math.rad(45.0), (@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height))), 0.1, 100.0);
}

pub fn getView(self: *Camera) math.Matrix {
    return math.Matrix.lookAt(self.position, math.rad(self.yaw), math.rad(self.pitch));
}

pub fn getTarget(self: *Camera) @Vector(3, f32) {
    const direction: @Vector(3, f32) = .{
        math.sin(math.rad(self.yaw)) * math.cos(math.rad(self.pitch)),
        math.sin(math.rad(self.pitch)),
        math.cos(math.rad(self.yaw)) * math.cos(math.rad(self.pitch)),
    };

    const t = (self.position[1] - (self.position[1] - self.distance)) / direction[1];
    const target: @Vector(3, f32) = .{
        self.position[0] + (t*direction[0]),
        (self.position[1] - self.distance),
        self.position[2] + (t*direction[2]),
    };

    //target[2] = 0.0;

    std.debug.print("{} {} {}\n", .{direction, t, target});

    return target;
}


