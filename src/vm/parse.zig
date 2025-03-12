const std = @import("std");
const wasm = @import("wasm.zig");
const Allocator = std.mem.Allocator;

pub const Error = error{
    malformed_wasm,
    invalid_utf8,
};

pub const Module = struct {
    types: []FunctionType,
    imports: std.ArrayList(Import),
    exports: std.StringHashMap(u32),
    functions: []u32,
    memory: Memory,
    code: []FunctionBody,
    funcs: std.ArrayList(Function),

    pub fn deinit(self: *Module, allocator: Allocator) void {
        for (self.types) |t| {
            t.deinit(allocator);
        }
        allocator.free(self.types);

        for (self.imports.items) |i| {
            i.deinit(allocator);
        }
        self.imports.deinit();

        var iter = self.exports.iterator();
        while (iter.next()) |entry| {
            allocator.free(entry.key_ptr.*);
        }
        self.exports.deinit();

        allocator.free(self.functions);

        for (self.code) |f| {
            for (f.locals) |l| {
                allocator.free(l.types);
            }
            allocator.free(f.code);
        }
        allocator.free(self.code);

        self.funcs.deinit();
    }
};

pub const FunctionScope = enum {
    external,
    internal,
};

pub const Function = union(FunctionScope) {
    external: u8,
    internal: u8,
};

// TODO: refactor locals
pub const Local = struct {
    types: []u8,
};

pub const FunctionBody = struct {
    locals: []Local,
    code: []u8,
};

pub const Memory = struct {
    initial: u32,
    max: u32,
};

pub const FunctionType = struct {
    parameters: []u8,
    results: []u8,

    pub fn deinit(self: FunctionType, allocator: Allocator) void {
        allocator.free(self.parameters);
        allocator.free(self.results);
    }
};

pub const Import = struct {
    name: []u8,
    module: []u8,
    signature: u32,

    pub fn deinit(self: Import, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.module);
    }
};

pub fn parseType(t: u8) wasm.Type {
    return @enumFromInt(t);
}

pub fn parseName(allocator: Allocator, stream: anytype) ![]u8 {
    const size = try std.leb.readULEB128(u32, stream);
    const str = try allocator.alloc(u8, size);
    if (try stream.read(str) != size) {
        // TODO: better error
        return Error.malformed_wasm;
    }

    if (!std.unicode.utf8ValidateSlice(str)) return Error.invalid_utf8;

    return str;
}

// TODO: parse Global Section
// TODO: Consider Arena allocator
pub fn parseWasm(allocator: Allocator, stream: anytype) !Module {
    var types: []FunctionType = undefined;
    var imports = std.ArrayList(Import).init(allocator);
    var exports = std.StringHashMap(u32).init(allocator);
    var funcs = std.ArrayList(Function).init(allocator);
    var functions: []u32 = undefined;
    var memory: Memory = undefined;
    var code: []FunctionBody = undefined;

    // Parse magic
    if (!(try stream.isBytes(&[_]u8{ 0x00, 0x61, 0x73, 0x6d }))) return Error.malformed_wasm;
    // Parse version
    if (!(try stream.isBytes(&[_]u8{ 0x01, 0x00, 0x00, 0x00 }))) return Error.malformed_wasm;

    // NOTE: This ensures that (in this block) illegal behavior is safety-checked.
    //     This slows down the code but since this function is only called at the start
    //     I believe it is better to take the ``hit'' in performance (should only be @enumFromInt)
    //     rather than  having undefined behavior when user provides an invalid wasm file.
    @setRuntimeSafety(true);
    loop: while (stream.readByte()) |byte| {
        const section_size = try std.leb.readULEB128(u32, stream);
        switch (@as(std.wasm.Section, @enumFromInt(byte))) {
            std.wasm.Section.custom => {
                // TODO: unimplemented
                break :loop;
            },
            std.wasm.Section.type => {
                const type_count = try std.leb.readULEB128(u32, stream);
                types = try allocator.alloc(FunctionType, type_count);
                for (types) |*t| {
                    if (!(try stream.isBytes(&.{0x60}))) return Error.malformed_wasm;
                    const params_count = try std.leb.readULEB128(u32, stream);
                    t.parameters = try allocator.alloc(u8, params_count);
                    if (try stream.read(t.parameters) != params_count) {
                        // TODO: better errors
                        return Error.malformed_wasm;
                    }
                    const results = try std.leb.readULEB128(u32, stream);
                    t.results = try allocator.alloc(u8, results);
                    if (try stream.read(t.results) != results) {
                        // TODO: better errors
                        return Error.malformed_wasm;
                    }
                }
            },
            std.wasm.Section.import => {
                // Can there be more than one import section?
                const import_count = try std.leb.readULEB128(u32, stream);
                for (0..import_count) |i| {
                    const mod = try parseName(allocator, stream);
                    const nm = try parseName(allocator, stream);

                    const b = try stream.readByte();
                    switch (@as(std.wasm.ExternalKind, @enumFromInt(b))) {
                        std.wasm.ExternalKind.function => try funcs.append(.{ .external = @intCast(i) }),
                        // TODO: not implemented
                        std.wasm.ExternalKind.table => {},
                        std.wasm.ExternalKind.memory => {},
                        std.wasm.ExternalKind.global => {},
                    }
                    const idx = try std.leb.readULEB128(u32, stream);
                    try imports.append(.{
                        .module = mod,
                        .name = nm,
                        .signature = idx,
                    });
                }
            },
            std.wasm.Section.function => {
                const function_count = try std.leb.readULEB128(u32, stream);
                functions = try allocator.alloc(u32, function_count);
                for (functions) |*f| {
                    f.* = try std.leb.readULEB128(u32, stream);
                }
            },
            std.wasm.Section.table => {
                // TODO: not implemented
                try stream.skipBytes(section_size, .{});
            },
            std.wasm.Section.memory => {
                const memory_count = try std.leb.readULEB128(u32, stream);
                for (0..memory_count) |_| {
                    const b = try stream.readByte();
                    const n = try std.leb.readULEB128(u32, stream);
                    var m: u32 = 0;
                    switch (b) {
                        0x00 => {},
                        0x01 => m = try std.leb.readULEB128(u32, stream),
                        else => return Error.malformed_wasm,
                    }
                    // TODO: support multiple memories
                    memory = .{
                        .initial = n,
                        .max = m,
                    };
                }
            },
            std.wasm.Section.global => {
                // TODO: unimplemented
                try stream.skipBytes(section_size, .{});
            },
            // TODO: Can there be more than one export section? Otherwise we can optimize allocations
            std.wasm.Section.@"export" => {
                const export_count = try std.leb.readULEB128(u32, stream);
                for (0..export_count) |_| {
                    const nm = try parseName(allocator, stream);
                    const b = try stream.readByte();
                    const idx = try std.leb.readULEB128(u32, stream);
                    switch (@as(std.wasm.ExternalKind, @enumFromInt(b))) {
                        std.wasm.ExternalKind.function => try exports.put(nm, idx),
                        // TODO: unimplemented,
                        std.wasm.ExternalKind.table => allocator.free(nm),
                        std.wasm.ExternalKind.memory => allocator.free(nm),
                        std.wasm.ExternalKind.global => allocator.free(nm),
                    }
                }
            },
            std.wasm.Section.start => {
                // TODO: unimplemented
                try stream.skipBytes(section_size, .{});
            },
            std.wasm.Section.element => {
                // TODO: unimplemented
                try stream.skipBytes(section_size, .{});
            },
            std.wasm.Section.code => {
                const code_count = try std.leb.readULEB128(u32, stream);
                code = try allocator.alloc(FunctionBody, code_count);
                for (0..code_count) |i| {
                    const code_size = try std.leb.readULEB128(u32, stream);
                    const local_count = try std.leb.readULEB128(u32, stream);
                    const locals = try allocator.alloc(Local, local_count);
                    for (locals) |*l| {
                        const n = try std.leb.readULEB128(u32, stream);
                        l.types = try allocator.alloc(u8, n);
                        @memset(l.types, try stream.readByte());
                    }
                    code[i].locals = locals;

                    // TODO: maybe is better to parse code into ast here and not do it every frame?
                    // FIXME: This calculation is plain wrong. Resolving above TODO should help
                    code[i].code = try allocator.alloc(u8, code_size - local_count - 1);
                    // TODO: better error reporting
                    if (try stream.read(code[i].code) != code_size - local_count - 1) return Error.malformed_wasm;

                    const f = Function{ .internal = @intCast(i) };
                    try funcs.append(f);
                }
            },
            std.wasm.Section.data => {
                // TODO: unimplemented
                try stream.skipBytes(section_size, .{});
            },
            std.wasm.Section.data_count => {
                // TODO: unimplemented
                try stream.skipBytes(section_size, .{});
            },
            else => return Error.malformed_wasm,
        }
    } else |err| switch (err) {
        error.EndOfStream => {},
        else => return err,
    }

    return Module{
        .types = types,
        .imports = imports,
        .functions = functions,
        .memory = memory,
        .exports = exports,
        .code = code,
        .funcs = funcs,
    };
}
