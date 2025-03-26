const std = @import("std");
const vm = @import("vm.zig");
const IR = @import("ir.zig");
const Allocator = std.mem.Allocator;

bytes: []const u8,
byte_idx: usize,
allocator: Allocator,

// TODO: We don't really need ArrayLists
types: std.ArrayListUnmanaged(Functype) = .{},
imports: std.ArrayListUnmanaged(Import) = .{},
exports: std.StringHashMapUnmanaged(u32) = .{},
functions: std.ArrayListUnmanaged(u32) = .{},
memory: ?Memtype = null,
code: std.ArrayListUnmanaged(Func) = .{},
funcs: std.ArrayListUnmanaged(vm.Func) = .{},

pub const FunctionType = struct {
    parameters: []u8,
    results: []u8,

    pub fn deinit(self: FunctionType, allocator: Allocator) void {
        allocator.free(self.parameters);
        allocator.free(self.results);
    }
};

pub const FunctionBody = struct {
    locals: []Local,
    code: []u8,
};

pub const FunctionScope = enum {
    external,
    internal,
};

const Parser = @This();

pub const Error = error{
    invalid_instruction,
    invalid_magic,
    invalid_version,
    invalid_section,
    invalid_functype,
    invalid_vectype,
    invalid_numtype,
    invalid_reftype,
    invalid_valtype,
    invalid_string,
    invalid_limits,
    invalid_globaltype,
    invalid_importdesc,
    invalid_exportdesc,
    unterminated_wasm,
};

// TODO: This function should not exists
fn warn(self: Parser, s: []const u8) void {
    std.debug.print("[WARN]: Parsing of {s} unimplemented at byte index {d}\n", .{ s, self.byte_idx });
}

// TODO: remove peek
fn peek(self: Parser) ?u8 {
    return if (self.byte_idx < self.bytes.len) self.bytes[self.byte_idx] else null;
}

fn read(self: *Parser, n: usize) ![]const u8 {
    if (self.byte_idx + n > self.bytes.len) return Error.unterminated_wasm;
    defer self.byte_idx += n;
    return self.bytes[self.byte_idx .. self.byte_idx + n];
}

// ==========
// = VALUES =
// ==========

pub fn readByte(self: *Parser) !u8 {
    return (try self.read(1))[0];
}

pub fn readU32(self: *Parser) !u32 {
    return std.leb.readUleb128(u32, self);
}

pub fn readI32(self: *Parser) !i32 {
    return std.leb.readIleb128(i32, self);
}

pub fn readI64(self: *Parser) !i64 {
    return std.leb.readIleb128(i64, self);
}

pub fn readF32(self: *Parser) !f32 {
    const bytes = try self.read(@sizeOf(f32));
    return std.mem.bytesAsValue(f32, bytes).*;
}

pub fn readF64(self: *Parser) !f64 {
    const bytes = try self.read(@sizeOf(f64));
    return std.mem.bytesAsValue(f64, bytes).*;
}

fn readName(self: *Parser) ![]const u8 {
    // NOTE: This should be the only vector not parsed through parseVector
    const size = try self.readU32();
    const str = try self.allocator.alloc(u8, size);
    @memcpy(str, try self.read(size));
    if (!std.unicode.utf8ValidateSlice(str)) return Error.invalid_string;
    return str;
}

// =========
// = TYPES =
// =========
// NOTE: This should return a value

fn VectorFnResult(parse_fn: anytype) type {
    const type_info = @typeInfo(@TypeOf(parse_fn));
    if (type_info != .@"fn") {
        @compileError("cannot determine return type of " ++ @typeName(@TypeOf(parse_fn)));
    }
    const ret_type = type_info.@"fn".return_type.?;
    const ret_type_info = @typeInfo(ret_type);
    return switch (ret_type_info) {
        .error_union => ret_type_info.error_union.payload,
        else => ret_type,
    };
}
fn parseVector(self: *Parser, parse_fn: anytype) ![]VectorFnResult(parse_fn) {
    const n = try self.readU32();
    const ret = try self.allocator.alloc(VectorFnResult(parse_fn), n);
    for (ret) |*i| {
        i.* = try parse_fn(self);
    }
    return ret;
}

fn parseNumtype(self: *Parser) !std.wasm.Valtype {
    return switch (try self.readByte()) {
        0x7F => .i32,
        0x7E => .i64,
        0x7D => .f32,
        0x7C => .f64,
        else => Error.invalid_numtype,
    };
}

fn parseVectype(self: *Parser) !std.wasm.Valtype {
    return switch (try self.readByte()) {
        0x7B => .v128,
        else => Error.invalid_vectype,
    };
}

fn parseReftype(self: *Parser) !std.wasm.RefType {
    return switch (try self.readByte()) {
        0x70 => .funcref,
        0x6F => .externref,
        else => Error.invalid_reftype,
    };
}

// NOTE: Parsing of Valtype can be improved but it makes it less close to spec so...
// TODO: Do we really need Valtype?
pub const Valtype = union(enum) {
    val: std.wasm.Valtype,
    ref: std.wasm.RefType,
};
fn parseValtype(self: *Parser) !Valtype {
    const pb = self.peek() orelse return Error.unterminated_wasm;
    return switch (pb) {
        0x7F, 0x7E, 0x7D, 0x7C => .{ .val = try self.parseNumtype() },
        0x7B => .{ .val = try self.parseVectype() },
        0x70, 0x6F => .{ .ref = try self.parseReftype() },
        else => Error.invalid_valtype,
    };
}

fn parseResultType(self: *Parser) ![]Valtype {
    return try self.parseVector(Parser.parseValtype);
}

pub const Functype = struct {
    parameters: []Valtype,
    rt2: []Valtype,

    pub fn deinit(self: Functype, allocator: Allocator) void {
        allocator.free(self.parameters);
        allocator.free(self.rt2);
    }
};
fn parseFunctype(self: *Parser) !Functype {
    if (try self.readByte() != 0x60) return Error.invalid_functype;
    return .{
        .parameters = try self.parseResultType(),
        .rt2 = try self.parseResultType(),
    };
}

const Limits = struct {
    min: u32,
    max: ?u32,
};

fn parseLimits(self: *Parser) !Limits {
    return switch (try self.readByte()) {
        0x00 => .{
            .min = try self.readU32(),
            .max = null,
        },
        0x01 => .{
            .min = try self.readU32(),
            .max = try self.readU32(),
        },
        else => Error.invalid_limits,
    };
}

const Memtype = struct {
    lim: Limits,
};
fn parseMemtype(self: *Parser) !Memtype {
    return .{ .lim = try self.parseLimits() };
}

const Tabletype = struct {
    et: std.wasm.RefType,
    lim: Limits,
};
fn parseTabletype(self: *Parser) !Tabletype {
    return .{
        .et = try self.parseReftype(),
        .lim = try self.parseLimits(),
    };
}

const Globaltype = struct {
    t: Valtype,
    m: enum {
        @"const",
        @"var",
    },
};
fn parseGlobaltype(self: *Parser) !Globaltype {
    return .{
        .t = try self.parseValtype(),
        .m = switch (try self.readByte()) {
            0x00 => .@"const",
            0x01 => .@"var",
            else => return Error.invalid_globaltype,
        },
    };
}

// ===========
// = MODULES =
// ===========
// NOTE: This should not return anything but modify IR

pub fn parseModule(self: *Parser) !vm.Module {
    if (!std.mem.eql(u8, try self.read(4), &.{ 0x00, 0x61, 0x73, 0x6d })) return Error.invalid_magic;
    if (!std.mem.eql(u8, try self.read(4), &.{ 0x01, 0x00, 0x00, 0x00 })) return Error.invalid_version;
    // TODO: Ensure only one section of each type (except for custom section), some code depends on it
    while (self.byte_idx < self.bytes.len) {
        try switch (try self.readByte()) {
            0 => self.parseCustomsec(),
            1 => self.parseTypesec(),
            2 => self.parseImportsec(),
            3 => self.parseFuncsec(),
            4 => self.parseTablesec(),
            5 => self.parseMemsec(),
            6 => self.parseGlobalsec(),
            7 => self.parseExportsec(),
            8 => self.parseStartsec(),
            9 => self.parseElemsec(),
            10 => self.parseCodesec(),
            11 => self.parseDatasec(),
            12 => self.parseDatacountsec(),
            else => return Error.invalid_section,
        };
    }

    return .{
        .memory = .{
            .min = self.memory.?.lim.min,
            .max = self.memory.?.lim.max,
        },
        .exports = self.exports,
        .funcs = try self.funcs.toOwnedSlice(self.allocator),
        .types = try self.types.toOwnedSlice(self.allocator),
        .functions = try self.functions.toOwnedSlice(self.allocator),
        .imports = try self.imports.toOwnedSlice(self.allocator),
        .code = try self.code.toOwnedSlice(self.allocator),
    };
}

fn parseCustomsec(self: *Parser) !void {
    self.warn("customsec");
    const size = try self.readU32();
    _ = try self.read(size);
}

fn parseTypesec(self: *Parser) !void {
    const size = try self.readU32();
    const end_idx = self.byte_idx + size;

    const ft = try self.parseVector(Parser.parseFunctype);
    // TODO: Maybe the interface should be better?
    try self.types.appendSlice(self.allocator, ft);

    // TODO: run this check not only on debug
    std.debug.assert(self.byte_idx == end_idx);
}

pub const Import = struct {
    name: []const u8,
    module: []const u8,
    importdesc: union { func: u32, table: Tabletype, mem: Memtype, global: Globaltype },
    pub fn deinit(self: Import, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.module);
    }
};
fn parseImport(self: *Parser) !Import {
    return .{
        .name = try self.readName(),
        .module = try self.readName(),
        .importdesc = switch (try self.readByte()) {
            0x00 => .{ .func = try self.readU32() },
            0x01 => .{ .table = try self.parseTabletype() },
            0x02 => .{ .mem = try self.parseMemtype() },
            0x03 => .{ .global = try self.parseGlobaltype() },
            else => return Error.invalid_importdesc,
        },
    };
}

fn parseImportsec(self: *Parser) !void {
    const size = try self.readU32();
    const end_idx = self.byte_idx + size;

    const imports = try self.parseVector(Parser.parseImport);
    try self.imports.appendSlice(self.allocator, imports);

    // TODO: run this check not only on debug
    std.debug.assert(self.byte_idx == end_idx);
}

fn parseFuncsec(self: *Parser) !void {
    const size = try self.readU32();
    const end_idx = self.byte_idx + size;

    const types = try self.parseVector(Parser.readU32);
    try self.functions.appendSlice(self.allocator, types);

    // TODO: run this check not only on debug
    std.debug.assert(self.byte_idx == end_idx);
}

fn parseTablesec(self: *Parser) !void {
    self.warn("tablesec");
    const size = try self.readU32();
    _ = try self.read(size);
}

fn parseMemsec(self: *Parser) !void {
    const size = try self.readU32();
    const end_idx = self.byte_idx + size;

    const mems = try self.parseVector(Parser.parseMemtype);
    if (mems.len == 0) {
        // WTF?
    } else if (mems.len == 1) {
        self.memory = mems[0];
    } else {
        std.debug.print("[WARN]: Parsing more than one memory is not yet supported\n", .{});
    }

    // TODO: run this check not only on debug
    std.debug.assert(self.byte_idx == end_idx);
}

fn parseGlobalsec(self: *Parser) !void {
    self.warn("globalsec");
    const size = try self.readU32();
    _ = try self.read(size);
}

pub const Export = struct {
    name: []const u8,
    exportdesc: union(enum) { func: u32, table: u32, mem: u32, global: u32 },
    pub fn deinit(self: Import, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

fn parseExport(self: *Parser) !Export {
    return .{
        .name = try self.readName(),
        .exportdesc = switch (try self.readByte()) {
            0x00 => .{ .func = try self.readU32() },
            0x01 => .{ .table = try self.readU32() },
            0x02 => .{ .mem = try self.readU32() },
            0x03 => .{ .global = try self.readU32() },
            else => return Error.invalid_exportdesc,
        },
    };
}

fn parseExportsec(self: *Parser) !void {
    const size = try self.readU32();
    const end_idx = self.byte_idx + size;

    const exports = try self.parseVector(Parser.parseExport);
    for (exports) |e| {
        switch (e.exportdesc) {
            .func => try self.exports.put(self.allocator, e.name, e.exportdesc.func),
            else => std.debug.print("[WARN]: export ignored\n", .{}),
        }
    }

    // TODO: run this check not only on debug
    std.debug.assert(self.byte_idx == end_idx);
}

fn parseStartsec(self: *Parser) !void {
    self.warn("startsec");
    const size = try self.readU32();
    _ = try self.read(size);
}

fn parseElemsec(self: *Parser) !void {
    self.warn("elemsec");
    const size = try self.readU32();
    _ = try self.read(size);
}

pub const Func = struct {
    locals: []Valtype,
    code: []const u8,
};
const Local = struct {
    n: u32,
    t: Valtype,
};
fn parseLocal(self: *Parser) !Local {
    return .{
        .n = try self.readU32(),
        .t = try self.parseValtype(),
    };
}

fn parseCode(self: *Parser) !Func {
    const size = try self.readU32();
    const end_idx = self.byte_idx + size;

    const locals = try self.parseVector(Parser.parseLocal);
    var local_count: usize = 0;
    for (locals) |l| {
        local_count += l.n;
    }

    // _ = try IR.parse(self);

    const func = Func{
        .locals = try self.allocator.alloc(Valtype, local_count),
        .code = try self.read(end_idx - self.byte_idx),
    };

    var li: usize = 0;
    for (locals) |l| {
        @memset(func.locals[li .. li + l.n], l.t);
        li += l.n;
    }

    // TODO: run this check not only on debug
    std.debug.assert(self.byte_idx == end_idx);

    return func;
}

fn parseCodesec(self: *Parser) !void {
    const size = try self.readU32();
    const end_idx = self.byte_idx + size;

    const codes = try self.parseVector(Parser.parseCode);
    for (codes, 0..) |_, i| {
        try self.funcs.append(self.allocator, .{ .internal = @intCast(i) });
    }
    try self.code.appendSlice(self.allocator, codes);

    // TODO: run this check not only on debug
    std.debug.assert(self.byte_idx == end_idx);
}

fn parseDatasec(self: *Parser) !void {
    self.warn("datasec");
    const size = try self.readU32();
    _ = try self.read(size);
}

fn parseDatacountsec(self: *Parser) !void {
    self.warn("datacountsec");
    const size = try self.readU32();
    _ = try self.read(size);
}
