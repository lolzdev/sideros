const std = @import("std");
const wasm = @import("wasm.zig");
const Parser = @import("Parser.zig");
const IR = @import("ir.zig");
const External = @import("external.zig");
const Allocator = std.mem.Allocator;
const AllocationError = error{OutOfMemory};

pub const Memory = struct {
    min: u32,
    max: ?u32,
};

pub const Valtype = union(enum) {
    val: std.wasm.Valtype,
    ref: std.wasm.RefType,
};

pub const Functype = struct {
    parameters: []Valtype,
    returns: []Valtype,

    pub fn deinit(self: Functype, allocator: Allocator) void {
        allocator.free(self.parameters);
        allocator.free(self.returns);
    }
};
pub const Function = struct { func_type: Functype, typ: union(enum) {
    internal: struct {
        locals: []Valtype,
        ir: IR,
    },
    external: u32
} };

pub const ExportFunction = enum {
    init,
    deinit,
    logErr,
    logWarn,
    logInfo,
    logDebug,
};
pub const Exports = struct {
    init: ?u32 = null,
    deinit: ?u32 = null,
    logErr: ?u32 = null,
    logWarn: ?u32 = null,
    logInfo: ?u32 = null,
    logDebug: ?u32 = null,
};
comptime {
    std.debug.assert(@typeInfo(ExportFunction).@"enum".fields.len == @typeInfo(Exports).@"struct".fields.len);
}

pub const Module = struct {
    memory: Memory,
    functions: []Function,
    exports: Exports,
    exported_memory: u32,
    data: []const u8,
    tables: []Parser.Tabletype,
    elems: [][]u32,

    pub fn deinit(self: Module, allocator: Allocator) void {
        for (self.functions) |f| {
            switch (f.typ) {
                .internal => {
                    allocator.free(f.typ.internal.ir.opcodes);
                    allocator.free(f.typ.internal.ir.indices);
                    allocator.free(f.typ.internal.ir.select_valtypes);
                    allocator.free(f.typ.internal.locals);
                },
                .external => {}
            }
            f.func_type.deinit(allocator);
        }
        allocator.free(self.functions);
        allocator.free(self.data);
        allocator.free(self.tables);
        for (self.elems) |elem| {
            allocator.free(elem);
        }
        allocator.free(self.elems);
    }
};

pub const CallFrame = struct {
    program_counter: usize,
    code: IR,
    locals: []Value,
};

pub const Value = union(enum) {
    i32: i32,
    i64: i64,
    f32: f32,
    f64: f64,
    ref: struct {
        type: ?std.wasm.RefType,
        val: u32,
    }

};

pub const Runtime = struct {
    module: Module,
    stack: std.ArrayList(Value),
    memory: []u8,
    global_runtime: *wasm.GlobalRuntime,
    externalFuncs: std.AutoHashMapUnmanaged(u32, ExternalFuncWrapper),
    const ExternalFuncWrapper = struct {
        func: *const fn (self: *Runtime, params: []Value) ?Value,
    };


    pub fn init(allocator: Allocator, module: Module, global_runtime: *wasm.GlobalRuntime) !Runtime {
        // if memory max is not set the memory is allowed to grow but it is not supported at the moment
        const max = module.memory.max orelse module.memory.min;
        const memory = try allocator.alloc(u8, max);
        @memset(memory, 0);
        @memcpy(memory[0..module.data.len], module.data);
        var externalFuncs: std.AutoHashMapUnmanaged(u32, ExternalFuncWrapper) = .{};
        if (module.exports.logDebug != null){
            try externalFuncs.put(allocator, module.exports.logDebug.?, .{.func = External.logDebug});
        }
        if (module.exports.logInfo != null){
            try externalFuncs.put(allocator, module.exports.logInfo.?, .{.func = External.logInfo});
        }
        if (module.exports.logWarn != null){
            try externalFuncs.put(allocator, module.exports.logWarn.?, .{.func = External.logWarn});
        }
        if (module.exports.logErr != null){
            try externalFuncs.put(allocator, module.exports.logErr.?, .{.func = External.logErr});
        }
        return Runtime{
            .externalFuncs = externalFuncs,
            .module = module,
            .stack = try std.ArrayList(Value).initCapacity(allocator, 10),
            .memory = memory,
            .global_runtime = global_runtime,
        };
    }

    pub fn deinit(self: *Runtime, allocator: Allocator) void {
        self.stack.deinit();
        self.global_runtime.deinit();
        self.module.deinit(allocator);
        self.externalFuncs.deinit(allocator);
        allocator.free(self.memory);
    }

    pub fn executeFrame(self: *Runtime, allocator: Allocator, frame: *CallFrame) !void {
        loop: while (frame.program_counter < frame.code.opcodes.len) {
            const opcode: IR.Opcode = frame.code.opcodes[frame.program_counter];
            const index = frame.code.indices[frame.program_counter];
            // std.debug.print("Executing at {X} {any} {X}\n", .{frame.program_counter, opcode, if (opcode == IR.Opcode.br_if) @as(i64, @intCast(index.u32)) else -1});
            switch (opcode) {
                .@"unreachable" => {
                    std.debug.panic("Reached unreachable statement at IR counter {any}\n", .{frame.program_counter});
                },
                .nop => {},
                .br => {
                    frame.program_counter = index.u32;
                    continue;
                },
                .br_if => {
                    if (self.stack.pop().?.i32 != 0) {
                        frame.program_counter = index.u32;
                        continue;
                    }
                },
                .br_table => {
                    const idx = self.stack.pop().?.i32;
                    if (idx < index.indirect.y){
                        frame.program_counter = frame.code.br_table_vectors[index.indirect.x + @as(u32, @intCast(idx))];
                    } else {
                        frame.program_counter = frame.code.br_table_vectors[index.indirect.y];
                    }
                    continue;
                },
                .@"return" => break :loop,
                .call => {
                    var parameters = std.ArrayList(Value).init(allocator);
                    defer parameters.deinit();
                    for (self.module.functions[index.u32].func_type.parameters) |_| {
                        try parameters.append(self.stack.pop().?);
                    }
                    try self.call(allocator, index.u32, parameters.items);
                },
                .call_indirect => {
                    if (self.module.tables[index.indirect.x].et != std.wasm.RefType.funcref) {
                        std.debug.panic("Table at index {any} is not a `funcref` table\n", .{index.indirect.x});
                    }
                    const j: u32 = @intCast(self.stack.pop().?.i32);
                    const funcIdx = self.module.elems[index.indirect.x][j];
                    var parameters = std.ArrayList(Value).init(allocator);
                    defer parameters.deinit();
                    for (self.module.functions[funcIdx].func_type.parameters) |_| {
                        try parameters.append(self.stack.pop().?);
                    }
                    try self.call(allocator, funcIdx, parameters.items);
                },

                .refnull => {
                    try self.stack.append(.{.ref = .{.type = null, .val = 0}});
                },
                .refisnull => {
                    try self.stack.append(.{ .i32 = @intCast(@as(i1, @bitCast(self.stack.pop().?.ref.type == null))) });
                },
                .reffunc => {
                    try self.stack.append(.{.ref = .{.type = std.wasm.RefType.funcref, .val = index.u32}});
                },

                .drop => {
                    _ = self.stack.pop();
                },
                .select => {
                    const c = self.stack.pop().?.i32;
                    const val2 = self.stack.pop().?;
                    const val1 = self.stack.pop().?;
                    if (c != 0) {
                        try self.stack.append(val1);
                    } else {
                        try self.stack.append(val2);
                    }
                },
                .select_with_values => @panic("UNIMPLEMENTED"),

                .localget => try self.stack.append(frame.locals[index.u32]),
                .localset => frame.locals[index.u32] = self.stack.pop().?,
                .localtee => frame.locals[index.u32] = self.stack.items[self.stack.items.len - 1],
                .globalget => try self.stack.append(self.global_runtime.getGlobal(index.u32)),
                .globalset => try self.global_runtime.updateGlobal(index.u32, self.stack.pop().?),

                .tableget => @panic("UNIMPLEMENTED"),
                .tableset => @panic("UNIMPLEMENTED"),
                .tableinit => @panic("UNIMPLEMENTED"),
                .elemdrop => @panic("UNIMPLEMENTED"),
                .tablecopy => @panic("UNIMPLEMENTED"),
                .tablegrow => @panic("UNIMPLEMENTED"),
                .tablesize => @panic("UNIMPLEMENTED"),
                .tablefill => @panic("UNIMPLEMENTED"),

                // TODO(ernesto): This code is repeated...
                .i32_load => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(i32);
                    try self.stack.append(.{ .i32 = std.mem.littleToNative(i32, std.mem.bytesAsValue(i32, self.memory[start..end]).*) });
                },
                .i64_load => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(i64);
                    try self.stack.append(.{ .i64 = std.mem.littleToNative(i64, std.mem.bytesAsValue(i64, self.memory[start..end]).*) });
                },
                .f32_load => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(f32);
                    try self.stack.append(.{ .f32 = std.mem.littleToNative(f32, std.mem.bytesAsValue(f32, self.memory[start..end]).*) });
                },
                .f64_load => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(f64);
                    try self.stack.append(.{ .f64 = std.mem.littleToNative(f64, std.mem.bytesAsValue(f64, self.memory[start..end]).*) });
                },
                .i32_load8_s => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(i8);
                    const raw_value = std.mem.readInt(i8, @as(*const [1]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i32 = @intCast(@as(i32, raw_value)) });
                },
                .i32_load8_u => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(u8);
                    const raw_value = std.mem.readInt(u8, @as(*const [1]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i32 = @intCast(@as(u32, raw_value)) });
                },
                .i32_load16_s => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(i16);
                    const raw_value = std.mem.readInt(i16, @as(*const [2]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i32 = @intCast(@as(i32, raw_value)) });
                },
                .i32_load16_u => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(u16);
                    const raw_value = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i32 = @intCast(@as(u32, raw_value)) });
                },
                .i64_load8_s => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(i8);
                    const raw_value = std.mem.readInt(i8, @as(*const [1]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i64 = @intCast(@as(i64, raw_value)) });
                },
                .i64_load8_u => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(u8);
                    const raw_value = std.mem.readInt(u8, @as(*const [1]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i64 = @intCast(@as(u64, raw_value)) });
                },
                .i64_load16_s => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(i16);
                    const raw_value = std.mem.readInt(i16, @as(*const [2]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i64 = @intCast(@as(i64, raw_value)) });
                },
                .i64_load16_u => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(u16);
                    const raw_value = std.mem.readInt(u16, @as(*const [2]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i64 = @intCast(@as(u64, raw_value)) });
                },
                .i64_load32_s => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(i32);
                    const raw_value = std.mem.readInt(i32, @as(*const [4]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i64 = @intCast(@as(i64, raw_value)) });
                },
                .i64_load32_u => {
                    const start = index.memarg.offset + @as(u32, @intCast(self.stack.pop().?.i32));
                    const end = start + @sizeOf(u32);
                    const raw_value = std.mem.readInt(u32, @as(*const [4]u8, @ptrCast(self.memory[start..end])), std.builtin.Endian.little);
                    try self.stack.append(.{ .i64 = @intCast(@as(u64, raw_value)) });
                },
                .i32_store => {
                    const val = std.mem.nativeToLittle(i32, self.stack.pop().?.i32);
                    const offsetVal = self.stack.pop().?.i32;
                    if (offsetVal < 0) {
                        std.debug.panic("offsetVal is negative (val: {any})\n", .{offsetVal});
                    }
                    const offset: u64 = @intCast(offsetVal);
                    const start: usize = @intCast(@as(u64, index.memarg.offset) + offset);
                    const end = start + @sizeOf(u32);
                    @memcpy(self.memory[start..end], std.mem.asBytes(&val));
                },
                .i64_store => {
                    const val = std.mem.nativeToLittle(i64, self.stack.pop().?.i64);
                    const offsetVal = self.stack.pop().?.i32;
                    if (offsetVal < 0) {
                        std.debug.panic("offsetVal is negative (val: {any})\n", .{offsetVal});
                    }
                    const offset: u64 = @intCast(offsetVal);
                    const start: usize = @intCast(@as(u64, index.memarg.offset) + offset);
                    const end = start + @sizeOf(u64);
                    @memcpy(self.memory[start..end], std.mem.asBytes(&val));
                },
                .f32_store => @panic("UNIMPLEMENTED"),
                .f64_store => @panic("UNIMPLEMENTED"),
                .i32_store8 => {
                    const val = std.mem.nativeToLittle(i8, @as(i8, @truncate(self.stack.pop().?.i32)));
                    const offsetVal = self.stack.pop().?.i32;
                    if (offsetVal < 0) {
                        std.debug.panic("offsetVal is negative (val: {any})\n", .{offsetVal});
                    }
                    const offset: u64 = @intCast(offsetVal);
                    const start: usize = @intCast(@as(u64, index.memarg.offset) + offset);
                    const end = start + @sizeOf(u8);
                    @memcpy(self.memory[start..end], std.mem.asBytes(&val));
                },
                .i32_store16 => {
                    const val = std.mem.nativeToLittle(i16, @as(i16, @truncate(self.stack.pop().?.i32)));
                    const offsetVal = self.stack.pop().?.i32;
                    if (offsetVal < 0) {
                        std.debug.panic("offsetVal is negative (val: {any})\n", .{offsetVal});
                    }
                    const offset: u64 = @intCast(offsetVal);
                    const start: usize = @intCast(@as(u64, index.memarg.offset) + offset);
                    const end = start + @sizeOf(u16);
                    @memcpy(self.memory[start..end], std.mem.asBytes(&val));
                },
                .i64_store8 => {
                    const val = std.mem.nativeToLittle(i8, @as(i8, @truncate(self.stack.pop().?.i64)));
                    const offsetVal = self.stack.pop().?.i32;
                    if (offsetVal < 0) {
                        std.debug.panic("offsetVal is negative (val: {any})\n", .{offsetVal});
                    }
                    const offset: u64 = @intCast(offsetVal);
                    const start: usize = @intCast(@as(u64, index.memarg.offset) + offset);
                    const end = start + @sizeOf(u8);
                    @memcpy(self.memory[start..end], std.mem.asBytes(&val));
                },
                .i64_store16 => {
                    const val = std.mem.nativeToLittle(i16, @as(i16, @truncate(self.stack.pop().?.i64)));
                    const offsetVal = self.stack.pop().?.i32;
                    if (offsetVal < 0) {
                        std.debug.panic("offsetVal is negative (val: {any})\n", .{offsetVal});
                    }
                    const offset: u64 = @intCast(offsetVal);
                    const start: usize = @intCast(@as(u64, index.memarg.offset) + offset);
                    const end = start + @sizeOf(u16);
                    @memcpy(self.memory[start..end], std.mem.asBytes(&val));
                },
                .i64_store32 => {
                    const val = std.mem.nativeToLittle(i32, @as(i32, @truncate(self.stack.pop().?.i64)));
                    const offsetVal = self.stack.pop().?.i32;
                    if (offsetVal < 0) {
                        std.debug.panic("offsetVal is negative (val: {any})\n", .{offsetVal});
                    }
                    const offset: u64 = @intCast(offsetVal);
                    const start: usize = @intCast(@as(u64, index.memarg.offset) + offset);
                    const end = start + @sizeOf(u32);
                    @memcpy(self.memory[start..end], std.mem.asBytes(&val));
                },

                .memorysize => {
                    try self.stack.append(.{ .i32 = @intCast(self.memory.len / Parser.PAGE_SIZE) });
                },
                .memorygrow => {
                    const newPages = self.stack.pop().?.i32;
                    const newSize = (self.memory.len / Parser.PAGE_SIZE) + @as(usize, @intCast(newPages));
                    if (self.module.memory.max != null and newSize > self.module.memory.max.?){
                        std.debug.panic("Mod failed to stay within memory range\n", .{});
                    }
                    const oldPages: i32 = @intCast(self.memory.len / Parser.PAGE_SIZE);
                    self.memory = try allocator.realloc(self.memory, newSize * Parser.PAGE_SIZE);
                    try self.stack.append(.{ .i32 = oldPages });
                },
                // TODO(luccie): We need passive memory for this
                .memoryinit => @panic("UNIMPLEMENTED"),
                .datadrop => @panic("UNIMPLEMENTED"),
                .memorycopy => {
                    const bytes: usize = @intCast(self.stack.pop().?.i32);
                    const source: usize = @intCast(self.stack.pop().?.i32);
                    const dest: usize = @intCast(self.stack.pop().?.i32);
                    @memcpy(self.memory[dest .. dest + bytes], self.memory[source .. source + bytes]);
                },
                .memoryfill => {
                    const bytes: usize = @intCast(self.stack.pop().?.i32);
                    const val: u8 = @as(u8, @intCast(self.stack.pop().?.i32));
                    const dest: usize = @intCast(self.stack.pop().?.i32);
                    @memset(self.memory[dest .. dest + bytes], val);
                },

                .i32_const => {
                    try self.stack.append(Value{ .i32 = frame.code.indices[frame.program_counter].i32 });
                },
                .i64_const => {
                    try self.stack.append(Value{ .i64 = frame.code.indices[frame.program_counter].i64 });
                },
                .f32_const => @panic("UNIMPLEMENTED"),
                .f64_const => @panic("UNIMPLEMENTED"),

                .i32_eqz => {
                    const val = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = @intFromBool(val == 0) });
                },
                .i32_eq => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = @intFromBool(a == b) });
                },
                .i32_ne => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = @intFromBool(a != b) });
                },
                .i32_lt_s => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = @intFromBool(b < a) });
                },
                .i32_lt_u => {
                    const a = @as(u32, @bitCast(self.stack.pop().?.i32));
                    const b = @as(u32, @bitCast(self.stack.pop().?.i32));
                    try self.stack.append(Value{ .i32 = @intFromBool(b < a) });
                },
                .i32_gt_s => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = @intFromBool(b > a) });
                },
                .i32_gt_u => {
                    const a = @as(u32, @bitCast(self.stack.pop().?.i32));
                    const b = @as(u32, @bitCast(self.stack.pop().?.i32));
                    try self.stack.append(Value{ .i32 = @intFromBool(b > a) });
                },
                .i32_le_s => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = @intFromBool(b <= a) });
                },
                .i32_le_u => {
                    const a = @as(u32, @bitCast(self.stack.pop().?.i32));
                    const b = @as(u32, @bitCast(self.stack.pop().?.i32));
                    try self.stack.append(Value{ .i32 = @intFromBool(b <= a) });
                },
                .i32_ge_s => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = @intFromBool(b >= a) });
                },
                .i32_ge_u => {
                    const a = @as(u32, @bitCast(self.stack.pop().?.i32));
                    const b = @as(u32, @bitCast(self.stack.pop().?.i32));
                    try self.stack.append(Value{ .i32 = @intFromBool(b >= a) });
                },

                .i64_eqz => {
                    const val = self.stack.pop().?.i64;
                    try self.stack.append(Value{ .i32 = @intFromBool(val == 0) });
                },
                .i64_eq => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(Value{ .i32 = @intFromBool(a == b) });
                },
                .i64_ne => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(Value{ .i32 = @intFromBool(a != b) });
                },
                .i64_lt_s => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(Value{ .i32 = @intFromBool(b < a) });
                },
                .i64_lt_u => {
                    const a = @as(u64, @bitCast(self.stack.pop().?.i64));
                    const b = @as(u64, @bitCast(self.stack.pop().?.i64));
                    try self.stack.append(Value{ .i32 = @intFromBool(b < a) });
                },
                .i64_gt_s => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(Value{ .i32 = @intFromBool(b > a) });
                },
                .i64_gt_u => {
                    const a = @as(u64, @bitCast(self.stack.pop().?.i64));
                    const b = @as(u64, @bitCast(self.stack.pop().?.i64));
                    try self.stack.append(Value{ .i32 = @intFromBool(b > a) });
                },
                .i64_le_s => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(Value{ .i32 = @intFromBool(b <= a) });
                },
                .i64_le_u => {
                    const a = @as(u64, @bitCast(self.stack.pop().?.i64));
                    const b = @as(u64, @bitCast(self.stack.pop().?.i64));
                    try self.stack.append(Value{ .i32 = @intFromBool(b <= a) });
                },
                .i64_ge_s => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(Value{ .i32 = @intFromBool(b >= a) });
                },
                .i64_ge_u => {
                    const a = @as(u64, @bitCast(self.stack.pop().?.i64));
                    const b = @as(u64, @bitCast(self.stack.pop().?.i64));
                    try self.stack.append(Value{ .i32 = @intFromBool(b >= a) });
                },

                .f32_eq => @panic("UNIMPLEMENTED"),
                .f32_ne => @panic("UNIMPLEMENTED"),
                .f32_lt => @panic("UNIMPLEMENTED"),
                .f32_gt => @panic("UNIMPLEMENTED"),
                .f32_le => @panic("UNIMPLEMENTED"),
                .f32_ge => @panic("UNIMPLEMENTED"),

                .f64_eq => @panic("UNIMPLEMENTED"),
                .f64_ne => @panic("UNIMPLEMENTED"),
                .f64_lt => @panic("UNIMPLEMENTED"),
                .f64_gt => @panic("UNIMPLEMENTED"),
                .f64_le => @panic("UNIMPLEMENTED"),
                .f64_ge => @panic("UNIMPLEMENTED"),

                .i32_clz => {
                    try self.stack.append(.{ .i32 = @clz(self.stack.pop().?.i32) });
                },
                .i32_ctz => {
                    try self.stack.append(.{ .i32 = @ctz(self.stack.pop().?.i32) });
                },
                .i32_popcnt => {
                    try self.stack.append(.{ .i32 = @popCount(self.stack.pop().?.i32) });
                },
                .i32_add => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = a + b });
                },
                .i32_sub => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = b - a });
                },
                .i32_and => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = a & b });
                },
                .i32_mul => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = a * b });
                },
                .i32_div_s => {
                    const a_signed = self.stack.pop().?.i32;
                    const b_signed = self.stack.pop().?.i32;
                    if (b_signed == 0){
                        std.debug.panic("Division by 0 error!\n", .{});
                    }
                    try self.stack.append(.{ .i32 = @divTrunc(b_signed, a_signed) });
                },
                .i32_div_u => {
                    const a_unsigned = @as(u32, @bitCast(self.stack.pop().?.i32));
                    const b_unsigned = @as(u32, @bitCast(self.stack.pop().?.i32));
                    if (b_unsigned == 0){
                        std.debug.panic("Division by 0 error!\n", .{});
                    }
                    try self.stack.append(.{ .i32 = @bitCast(b_unsigned / a_unsigned) });
                },
                .i32_rem_s => {
                    const divisor = self.stack.pop().?.i32;
                    const dividend = self.stack.pop().?.i32;
                    if (divisor == 0) {
                        std.debug.panic("Divide by 0\n", .{});
                    }
                    try self.stack.append(.{ .i32 = @intCast(dividend - divisor * @divTrunc(dividend, divisor)) });
                },
                .i32_rem_u => {
                    const divisor = @as(u32, @intCast(self.stack.pop().?.i32));
                    const dividend = @as(u32, @intCast(self.stack.pop().?.i32));
                    if (divisor == 0) {
                        std.debug.panic("Divide by 0\n", .{});
                    }
                    try self.stack.append(.{ .i32 = @intCast(dividend - divisor * @divTrunc(dividend, divisor)) });
                },
                .i32_or => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = a | b });
                },
                .i32_xor => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = a ^ b });
                },
                .i32_shl => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = (b << @as(u5, @intCast(a))) });
                },
                .i32_shr_s => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = (b >> @as(u5, @intCast(a))) });
                },
                .i32_shr_u => {
                    const a = @as(u32, @intCast(self.stack.pop().?.i32));
                    const b = @as(u32, @intCast(self.stack.pop().?.i32));
                    try self.stack.append(.{ .i32 = @intCast(b >> @as(u5, @intCast(a))) });
                },
                .i32_rotl => {
                    const a = @as(u32, @bitCast(self.stack.pop().?.i32));
                    const b = @as(u32, @bitCast(self.stack.pop().?.i32));
                    try self.stack.append(.{ .i32 = @intCast(std.math.rotl(u32, b, a)) });
                },
                .i32_rotr => {
                    const a = @as(u32, @bitCast(self.stack.pop().?.i32));
                    const b = @as(u32, @bitCast(self.stack.pop().?.i32));
                    try self.stack.append(.{ .i32 = @intCast(std.math.rotr(u32, b, a)) });
                },

                .i64_clz => {
                    try self.stack.append(.{ .i64 = @clz(self.stack.pop().?.i64) });
                },
                .i64_ctz => {
                    try self.stack.append(.{ .i64 = @ctz(self.stack.pop().?.i64) });
                },
                .i64_popcnt => {
                    try self.stack.append(.{ .i64 = @popCount(self.stack.pop().?.i64) });
                },
                .i64_add => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = a + b });
                },
                .i64_sub => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = b - a });
                },
                .i64_mul => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = a * b });
                },
                .i64_div_s => {
                    const a_signed = self.stack.pop().?.i64;
                    const b_signed = self.stack.pop().?.i64;
                    if (b_signed == 0){
                        std.debug.panic("Division by 0 error!\n", .{});
                    }
                    try self.stack.append(.{ .i64 = @divTrunc(b_signed, a_signed) });
                },
                .i64_div_u => {
                    const a_unsigned = @as(u64, @bitCast(self.stack.pop().?.i64));
                    const b_unsigned = @as(u64, @bitCast(self.stack.pop().?.i64));
                    if (b_unsigned == 0){
                        std.debug.panic("Division by 0 error!\n", .{});
                    }
                    try self.stack.append(.{ .i64 = @bitCast(b_unsigned / a_unsigned) });
                },
                .i64_rem_s => {
                    const divisor = self.stack.pop().?.i64;
                    const dividend = self.stack.pop().?.i64;
                    if (divisor == 0) {
                        std.debug.panic("Divide by 0\n", .{});
                    }
                    try self.stack.append(.{ .i64 = @intCast(dividend - divisor * @divTrunc(dividend, divisor)) });
                },
                .i64_rem_u => {
                    const divisor = @as(u64, @intCast(self.stack.pop().?.i64));
                    const dividend = @as(u64, @intCast(self.stack.pop().?.i64));
                    if (divisor == 0) {
                        std.debug.panic("Divide by 0\n", .{});
                    }
                    try self.stack.append(.{ .i64 = @intCast(dividend - divisor * @divTrunc(dividend, divisor)) });
                },
                .i64_and => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = a & b });
                },
                .i64_or => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = a | b });
                },
                .i64_xor => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = a ^ b });
                },
                .i64_shl => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = @intCast(b << @as(u6, @intCast(a))) });
                },
                .i64_shr_s => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = @intCast(b >> @as(u6, @intCast(a))) });
                },
                .i64_shr_u => {
                    const a = @as(u64, @intCast(self.stack.pop().?.i64));
                    const b = @as(u64, @intCast(self.stack.pop().?.i64));
                    try self.stack.append(.{ .i64 = @intCast(b >> @as(u6, @intCast(a))) });
                },
                .i64_rotl => {
                    const a = @as(u64, @bitCast(self.stack.pop().?.i64));
                    const b = @as(u64, @bitCast(self.stack.pop().?.i64));
                    try self.stack.append(.{ .i64 = @intCast(std.math.rotl(u64, b, a)) });
                },
                .i64_rotr => {
                    const a = @as(u64, @bitCast(self.stack.pop().?.i64));
                    const b = @as(u64, @bitCast(self.stack.pop().?.i64));
                    try self.stack.append(.{ .i64 = @intCast(std.math.rotr(u64, b, a)) });
                },

                .f32_abs => @panic("UNIMPLEMENTED"),
                .f32_neg => @panic("UNIMPLEMENTED"),
                .f32_ceil => @panic("UNIMPLEMENTED"),
                .f32_floor => @panic("UNIMPLEMENTED"),
                .f32_trunc => @panic("UNIMPLEMENTED"),
                .f32_nearest => @panic("UNIMPLEMENTED"),
                .f32_sqrt => @panic("UNIMPLEMENTED"),
                .f32_add => @panic("UNIMPLEMENTED"),
                .f32_sub => @panic("UNIMPLEMENTED"),
                .f32_mul => @panic("UNIMPLEMENTED"),
                .f32_div => @panic("UNIMPLEMENTED"),
                .f32_min => @panic("UNIMPLEMENTED"),
                .f32_max => @panic("UNIMPLEMENTED"),
                .f32_copysign => @panic("UNIMPLEMENTED"),

                .f64_abs => @panic("UNIMPLEMENTED"),
                .f64_neg => @panic("UNIMPLEMENTED"),
                .f64_ceil => @panic("UNIMPLEMENTED"),
                .f64_floor => @panic("UNIMPLEMENTED"),
                .f64_trunc => @panic("UNIMPLEMENTED"),
                .f64_nearest => @panic("UNIMPLEMENTED"),
                .f64_sqrt => @panic("UNIMPLEMENTED"),
                .f64_add => @panic("UNIMPLEMENTED"),
                .f64_sub => @panic("UNIMPLEMENTED"),
                .f64_mul => @panic("UNIMPLEMENTED"),
                .f64_div => @panic("UNIMPLEMENTED"),
                .f64_min => @panic("UNIMPLEMENTED"),
                .f64_max => @panic("UNIMPLEMENTED"),
                .f64_copysign => @panic("UNIMPLEMENTED"),

                .i32_wrap_i64 => {
                    try self.stack.append(.{ .i32 = @truncate(self.stack.pop().?.i64) });
                },
                .i32_trunc_f32_s => @panic("UNIMPLEMENTED"),
                .i32_trunc_f32_u => @panic("UNIMPLEMENTED"),
                .i32_trunc_f64_s => @panic("UNIMPLEMENTED"),
                .i32_trunc_f64_u => @panic("UNIMPLEMENTED"),
                .i64_extend_i32_s => {
                    try self.stack.append(.{ .i64 = @as(i64, self.stack.pop().?.i32) });
                },
                .i64_extend_i32_u => {
                    try self.stack.append(.{ .i64 = @as(i64, @as(u32, @bitCast(self.stack.pop().?.i32))) });
                },
                .i64_trunc_f32_s => @panic("UNIMPLEMENTED"),
                .i64_trunc_f32_u => @panic("UNIMPLEMENTED"),
                .i64_trunc_f64_s => @panic("UNIMPLEMENTED"),
                .i64_trunc_f64_u => @panic("UNIMPLEMENTED"),
                .f32_convert_i32_s => @panic("UNIMPLEMENTED"),
                .f32_convert_i32_u => @panic("UNIMPLEMENTED"),
                .f32_convert_i64_s => @panic("UNIMPLEMENTED"),
                .f32_convert_i64_u => @panic("UNIMPLEMENTED"),
                .f32_demote_f64 => @panic("UNIMPLEMENTED"),
                .f64_convert_i32_s => @panic("UNIMPLEMENTED"),
                .f64_convert_i32_u => @panic("UNIMPLEMENTED"),
                .f64_convert_i64_s => @panic("UNIMPLEMENTED"),
                .f64_convert_i64_u => @panic("UNIMPLEMENTED"),
                .f64_promote_f32 => @panic("UNIMPLEMENTED"),
                .i32_reinterpret_f32 => @panic("UNIMPLEMENTED"),
                .i64_reinterpret_f64 => @panic("UNIMPLEMENTED"),
                .f32_reinterpret_i32 => @panic("UNIMPLEMENTED"),
                .f64_reinterpret_i64 => @panic("UNIMPLEMENTED"),

                .i32_extend8_s => {
                    const val = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = @as(i32, @as(i8, @truncate(val))) });
                },
                .i32_extend16_s => {
                    const val = self.stack.pop().?.i32;
                    try self.stack.append(.{ .i32 = @as(i32, @as(i16, @truncate(val))) });
                },
                .i64_extend8_s => {
                    const val = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = @as(i64, @as(i8, @truncate(val))) });
                },
                .i64_extend16_s => {
                    const val = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = @as(i64, @as(i16, @truncate(val))) });
                },
                .i64_extend32_s => {
                    const val = self.stack.pop().?.i64;
                    try self.stack.append(.{ .i64 = @as(i64, @as(i32, @truncate(val))) });
                },

                .i32_trunc_sat_f32_s => @panic("UNIMPLEMENTED"),
                .i32_trunc_sat_f32_u => @panic("UNIMPLEMENTED"),
                .i32_trunc_sat_f64_s => @panic("UNIMPLEMENTED"),
                .i32_trunc_sat_f64_u => @panic("UNIMPLEMENTED"),
                .i64_trunc_sat_f32_s => @panic("UNIMPLEMENTED"),
                .i64_trunc_sat_f32_u => @panic("UNIMPLEMENTED"),
                .i64_trunc_sat_f64_s => @panic("UNIMPLEMENTED"),
                .i64_trunc_sat_f64_u => @panic("UNIMPLEMENTED"),

                .vecinst => @panic("UNIMPLEMENTED"),
            }
            frame.program_counter += 1;
        }
    }

    // TODO: Do name resolution at parseTime
    pub fn externalCall(self: *Runtime, allocator: Allocator, name: ExportFunction, parameters: []Value) !void {
        switch (name) {
            .init => {
                if (self.module.exports.init) |func| {
                    try self.call(allocator, func, parameters);
                } else {
                    std.debug.panic("Function init unavailable\n", .{});
                }
            },
            .deinit => {
                if (self.module.exports.deinit) |func| {
                    try self.call(allocator, func, parameters);
                } else {
                    std.debug.panic("Function deinit unavailable\n", .{});
                }
            },
            else => {
                std.debug.panic("Function {any} not handled\n", .{name});
            },
        }
    }

    fn reverseSlice(slice: []Value) void {
        var i: usize = 0;
        var j = slice.len - 1;
        while (i < j) {
            std.mem.swap(Value, &slice[i], &slice[j]);
            i += 1;
            j -= 1;
        }
    }

    pub fn call(self: *Runtime, allocator: Allocator, function: usize, parameters: []Value) AllocationError!void {
        const f = self.module.functions[function];
        if (parameters.len > 1){
            reverseSlice(parameters);
        }
        switch (f.typ) {
            .internal => {
                // std.debug.print("Calling {d}\n", .{function});
                const ir: IR = f.typ.internal.ir;
                const function_type = f.func_type;
                var frame = CallFrame{
                    .code = ir,
                    .program_counter = 0x0,
                    .locals = try allocator.alloc(Value, f.typ.internal.locals.len + function_type.parameters.len),
                };

                @memcpy(frame.locals[0..parameters.len], parameters);

                for (f.typ.internal.locals, function_type.parameters.len..) |local, i| {
                    switch (local) {
                        .val => |v| switch (v) {
                            .i32 => {
                                frame.locals[i] = .{ .i32 = 0 };
                            },
                            .i64 => {
                                frame.locals[i] = .{ .i64 = 0 };
                            },
                            else => unreachable,
                        },
                        .ref => unreachable,
                    }
                }

                try self.executeFrame(allocator, &frame);
                // std.debug.print("Returning from {d}\n", .{function});

                allocator.free(frame.locals);
            },
            .external => {
                const func = self.externalFuncs.get(@intCast(function));
                if (func == null){
                    std.debug.panic("ERROR: WASM tried calling out of bounds external function\n", .{});
                }
                const ret = func.?.func(self, parameters);
                if (ret != null){
                    try self.stack.append(ret.?);
                }
            },
        }
    }
};

pub fn handleGlobalInit(allocator: Allocator, ir: IR) !Value {
    var instruction_pointer: usize = 0;
    var stack = try std.ArrayList(Value).initCapacity(allocator, 10);
    defer stack.deinit();
    while (instruction_pointer < ir.opcodes.len) {
        const opcode: IR.Opcode = ir.opcodes[instruction_pointer];
        const index = ir.indices[instruction_pointer];
        switch (opcode) {
            .i32_const => try stack.append(Value{ .i32 = index.i32 }),
            else => {
                std.debug.panic("TODO: Handle opcode {any}\n", .{opcode});
            },
        }
        instruction_pointer += 1;
    }
    if (stack.items.len != 1) {
        std.debug.panic("Improper amount of variables at end\n", .{});
    }
    return stack.pop().?;
}
