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
speed: f32 = 10,
pitch: f32 = -45,
yaw: f32 = 0,

pub fn getProjection(width: usize, height: usize) math.Matrix {
    return math.Matrix.perspective(math.rad(45.0), (@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height))), 0.1, 100.0);
}

pub fn getView(self: *Camera) math.Matrix {
    _ = self.getTarget();
    return math.Matrix.lookAt(self.position, math.rad(self.yaw), math.rad(self.pitch));
}

pub inline fn getDirection(self: *Camera) @Vector(3, f32) {
    return .{
        math.sin(math.rad(self.yaw)) * math.cos(math.rad(self.pitch)),
        math.sin(math.rad(self.pitch)),
        math.cos(math.rad(self.yaw)) * math.cos(math.rad(self.pitch)),
    };
}

pub fn getTarget(self: *Camera) @Vector(3, f32) {
    const direction = self.getDirection();

    const t = self.position[1] / direction[1];
    const target: @Vector(3, f32) = .{
        self.position[0] + (t*direction[0]),
        0.0,
        self.position[2] - (t*direction[2]),
    };

    return target;
}

pub fn rotateAround(self: *Camera, pivot: @Vector(3, f32), angle: f32) void {
    self.yaw -= math.deg(angle);
    var rotation = math.Quaternion.fromAxisAngle(.{0.0, 1.0, 0.0}, angle);
    self.position = rotation.rotateVector(self.position - pivot) + pivot;
}


