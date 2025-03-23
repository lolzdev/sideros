const std = @import("std");
const mesh = @import("mesh.zig");
const Allocator = std.mem.Allocator;

pub const Model = packed struct {
    const Chunk = packed struct {
        length: u32,
        ty: u32,

    },
    header: packed struct {
        magic: u32,
        version: u32,
        length: u32,
    },
};
