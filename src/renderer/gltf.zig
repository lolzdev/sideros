const std = @import("std");
const Mesh = @import("Mesh.zig");
const Allocator = std.mem.Allocator;

pub const Model = struct {
    const Asset = struct {
        version: []u8,
        generator: ?[]u8 = null,
        copyright: ?[]u8 = null,
    };
    const Buffer = struct {
        byteLength: usize,
        uri: ?[]u8 = null,
    };
    const BufferView = struct {
        buffer: usize,
        byteLength: usize,
        byteOffset: usize,
        byteStride: ?usize = null,
        target: ?usize = null,
    };
    const Node = struct {
        name: []u8,
        mesh: ?usize = null,
        weights: ?[]f64 = null,
        children: ?[]usize = null,
        rotation: ?[4]f64 = null,
        scale: ?[3]f64 = null,
        translation: ?[3]f64 = null,
        camera: ?usize = null,
        matrix: ?[16]usize = null,
    };
    const Accessor = struct {
        bufferView: usize,
        byteOffset: ?usize = null,
        componentType: usize,
        count: usize,
        type: []u8,
        max: ?[]f64 = null,
        min: ?[]f64 = null,
    };
    const Primitive = struct {
        const Attributes = struct {
            NORMAL: ?usize = null,
            POSITION: ?usize = null,
            TANGENT: ?usize = null,
            TEXCOORD_0: ?usize = null,
            TEXCOORD_1: ?usize = null,
            COLOR_0: ?usize = null,
            JOINTS_0: ?usize = null,
            WEIGHTS_0: ?usize = null,
        };

        attributes: ?Attributes = null,
        indices: ?usize = null,
        material: ?usize = null,
        mode: ?usize = null,
    };
    const Mesh = struct {
        name: ?[]u8 = null,
        primitives: ?[]Primitive = null,
        weights: ?[]f64 = null,
    };
    const Skin = struct {
        inverseBindMatrices: usize,
        joints: []usize,
        skeleton: usize,
    };
    const Texture = struct {
        sampler: usize,
        source: usize,
    };
    const Image = struct {
        uri: ?[]u8 = null,
        bufferView: ?usize = null,
        mimeType: ?[]u8 = null,
    };
    const Material = struct {
        const Pbr = struct {
            baseColorFactor: ?[4]f64 = null,
            baseColorTexture: ?struct {
                index: usize,
                texCoord: usize,
            } = null,
            metallicFactor: ?f64 = null,
            roughnessFactor: ?f64 = null,
        };
        name: ?[]u8 = null,
        pbrMetallicRoughness: Pbr,
        doubleSided: bool,
    };
    const Scene = struct {
        nodes: ?[]usize = null,
        name: ?[]u8 = null,
    };

    const Chunk = packed struct {
        const offset = Header.offset + 8;
        length: u32,
        type: u32,
    };

    const JsonChunk = struct {
        asset: Asset,
        scene: usize,
        scenes: ?[]Scene = null,
        nodes: ?[]Node = null,
        materials: ?[]Material = null,
        meshes: ?[]Model.Mesh = null,
        accessors: ?[]Accessor = null,
        bufferViews: ?[]BufferView = null,
        buffers: ?[]Buffer = null,
    };

    const Header = packed struct {
        const offset = 12;
        magic: u32,
        version: u32,
        length: u32,
    };

    const Binary = struct {
        data: []u8,
        const Vec3 = [3]f32;

        pub fn readU16(self: Binary, allocator: Allocator, view: BufferView, count: usize) ![]u16 {
            const data = self.data[view.byteOffset .. view.byteOffset + view.byteLength];
            const scalars = try allocator.alloc(u16, count);

            var j: usize = 0;
            for (0..data.len / 2) |i| {
                scalars[i] = std.mem.bytesAsValue(u16, data[j .. j + 1]).*;
                j += 2;
            }

            return scalars;
        }

        pub fn readVec3(self: Binary, allocator: Allocator, view: BufferView, count: usize) ![]Vec3 {
            const data = self.data[view.byteOffset .. view.byteOffset + view.byteLength];
            const vectors = try allocator.alloc(Vec3, count);

            for (0..count) |i| {
                vectors[i] = std.mem.bytesAsValue(Vec3, data[(@sizeOf(Vec3) * i) .. (@sizeOf(Vec3) * i) + @sizeOf(Vec3)]).*;
            }

            return vectors;
        }
    };
};

pub fn parseFile(allocator: Allocator, name: []const u8) !struct { vertices: [][3]f32, indices: []u16 } {
    const file = try std.fs.cwd().openFile(name, .{});
    const all = try file.readToEndAlloc(allocator, 1_000_000);
    defer allocator.free(all);
    const json_chunk = std.mem.bytesAsValue(Model.Chunk, all[Model.Header.offset..]);

    const parsed = try std.json.parseFromSlice(Model.JsonChunk, allocator, @constCast(all[Model.Chunk.offset .. Model.Chunk.offset + json_chunk.length]), .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    const data = parsed.value;
    const binary = Model.Binary{ .data = all[Model.Chunk.offset + json_chunk.length + 8 ..] };

    const vertices = try binary.readVec3(allocator, data.bufferViews.?[data.meshes.?[0].primitives.?[0].attributes.?.POSITION.?], data.accessors.?[data.meshes.?[0].primitives.?[0].attributes.?.POSITION.?].count);
    const indices = try binary.readU16(allocator, data.bufferViews.?[data.meshes.?[0].primitives.?[0].indices.?], data.accessors.?[data.meshes.?[0].primitives.?[0].indices.?].count);

    return .{ .vertices = vertices, .indices = indices };
}
