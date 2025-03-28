const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Position = packed struct {
    x: f32,
    y: f32,
    z: f32,

    pub const id: usize = 0;
};

pub const Speed = packed struct {
    speed: f32,
};
