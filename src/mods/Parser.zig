const std = @import("std");
const vm = @import("vm.zig");
const IR = @import("ir.zig");
const Allocator = std.mem.Allocator;

bytes: []const u8,
byte_idx: usize,
allocator: Allocator,

types: []vm.Functype,
functions: []vm.Function,
memory: Memtype,
exports: vm.Exports,

const Parser = @This();

pub const Error = error{
    OutOfMemory,
    Overflow,
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
    double_else,
    duplicated_funcsec,
    duplicated_typesec,
    unresolved_branch,
    unterminated_wasm,
};

pub fn init(allocator: Allocator, bytes: []const u8) !Parser {
	return .{
		.bytes = bytes,
		.byte_idx = 0,
		.allocator = allocator,
		.types = &.{},
		.functions = &.{},
		.memory = .{
			.lim = .{
				.min = 0,
				.max = 0,
			},
		},
		.exports = .{},
	};
}

pub fn deinit(self: Parser) void {
	for (self.types) |t| {
		self.allocator.free(t.parameters);
		self.allocator.free(t.returns);
	}
	self.allocator.free(self.types);
	self.allocator.free(self.functions);
}

pub fn module(self: *Parser) vm.Module {
	defer self.functions = &.{};
	return .{
		.memory = .{
			.min = self.memory.lim.min,
			.max = self.memory.lim.max,
		},
		.functions = self.functions,
		.exports = self.exports,
	};
}

// TODO: This function should not exists
fn warn(self: Parser, s: []const u8) void {
    std.debug.print("[WARN]: Parsing of {s} unimplemented at byte index {d}\n", .{ s, self.byte_idx });
}

// TODO: remove peek?
pub fn peek(self: Parser) ?u8 {
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

pub fn readI33(self: *Parser) !i33 {
    return std.leb.readIleb128(i33, self);
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

pub fn parseReftype(self: *Parser) !std.wasm.RefType {
    return switch (try self.readByte()) {
        0x70 => .funcref,
        0x6F => .externref,
        else => Error.invalid_reftype,
    };
}

// NOTE: Parsing of Valtype can be improved but it makes it less close to spec so...
// TODO: Do we really need Valtype?
fn parseValtype(self: *Parser) !vm.Valtype {
    const pb = self.peek() orelse return Error.unterminated_wasm;
    return switch (pb) {
        0x7F, 0x7E, 0x7D, 0x7C => .{ .val = try self.parseNumtype() },
        0x7B => .{ .val = try self.parseVectype() },
        0x70, 0x6F => .{ .ref = try self.parseReftype() },
        else => Error.invalid_valtype,
    };
}

fn parseResultType(self: *Parser) ![]vm.Valtype {
    return try self.parseVector(Parser.parseValtype);
}

fn parseFunctype(self: *Parser) !vm.Functype {
    if (try self.readByte() != 0x60) return Error.invalid_functype;
    return .{
        .parameters = try self.parseResultType(),
        .returns = try self.parseResultType(),
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
    t: vm.Valtype,
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

pub fn parseModule(self: *Parser) !void {
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

    if (self.types.len != 0) return Error.duplicated_typesec;
    self.types = ft;

    // TODO(ernesto): run this check not only on debug
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

    // TODO(ernesto): this should be used to do name resolution.
    const imports = try self.parseVector(Parser.parseImport);
    defer self.allocator.free(imports);

    // TODO: run this check not only on debug
    std.debug.assert(self.byte_idx == end_idx);
}

fn parseFuncsec(self: *Parser) !void {
    const size = try self.readU32();
    const end_idx = self.byte_idx + size;

    const types = try self.parseVector(Parser.readU32);
    defer self.allocator.free(types);

    if (self.functions.len != 0) return Error.duplicated_funcsec;
    self.functions = try self.allocator.alloc(vm.Function, types.len);

    for (types, 0..) |t, i| {
        self.functions[i].func_type = .{
	        .parameters = try self.allocator.alloc(vm.Valtype, self.types[t].parameters.len),
	        .returns = try self.allocator.alloc(vm.Valtype, self.types[t].returns.len),
        };
        @memcpy(self.functions[i].func_type.parameters, self.types[t].parameters);
        @memcpy(self.functions[i].func_type.returns, self.types[t].returns);
    }

    // TODO(ernesto): run this check not only in debug
    std.debug.assert(types.len == self.functions.len);

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
    defer self.allocator.free(mems);
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
    defer {
	    for (exports) |e| self.allocator.free(e.name);
	    self.allocator.free(exports);
    }
    for (exports) |e| {
        switch (e.exportdesc) {
            .func => {
	            if (std.mem.eql(u8, e.name, "preinit")) {
		            self.exports.preinit = e.exportdesc.func;
	            } else {
		            std.log.warn("exported function {s} not supported\n", .{e.name});
	            }
            },
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
    locals: []vm.Valtype,
    ir: IR,
};
const Local = struct {
    n: u32,
    t: vm.Valtype,
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
    defer self.allocator.free(locals);
    var local_count: usize = 0;
    for (locals) |l| {
        local_count += l.n;
    }

    const ir = try IR.parse(self);
    // const stdout = std.fs.File.stdout().writer();
    // try ir.print(stdout);

    const func = Func{
        .locals = try self.allocator.alloc(vm.Valtype, local_count),
        .ir = ir,
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
    defer self.allocator.free(codes);
    // TODO: run this check not only on debug
    std.debug.assert(codes.len == self.functions.len);

    for (codes, self.functions) |code, *f| {
        f.typ = .{ .internal = .{
            .locals = code.locals,
            .ir = code.ir,
        } };
    }

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
