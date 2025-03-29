const std = @import("std");
const wasm = @import("wasm.zig");
const Parser = @import("Parser.zig");
const IR = @import("ir.zig");
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
    external: void,
} };

pub const Module = struct {
    memory: Memory,
    functions: []Function,
    exports: std.StringHashMapUnmanaged(u32),

    fn deinit(self: *Module, allocator: Allocator) void {
        self.exports.deinit(allocator);
        for (self.functions) |f| {
            allocator.free(f.func_type.parameters);
            allocator.free(f.func_type.returns);
            switch (f.typ) {
                .internal => {
                    allocator.free(f.typ.internal.ir.opcodes);
                    allocator.free(f.typ.internal.ir.indices);
                    allocator.free(f.typ.internal.ir.select_valtypes);
                    allocator.free(f.typ.internal.locals);
                },
                .external => {},
            }
        }
        allocator.free(self.functions);
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
};

pub const Runtime = struct {
    module: Module,
    stack: std.ArrayList(Value),
    memory: []u8,
    global_runtime: *wasm.GlobalRuntime,

    pub fn init(allocator: Allocator, module: Module, global_runtime: *wasm.GlobalRuntime) !Runtime {
        // if memory max is not set the memory is allowed to grow but it is not supported at the moment
        const max = module.memory.max orelse 1_000;
        if (module.memory.max == null) {
            std.log.warn("Growing memory is not yet supported, usign a default value of 1Kb\n", .{});
        }
        const memory = try allocator.alloc(u8, max);
        return Runtime{
            .module = module,
            .stack = try std.ArrayList(Value).initCapacity(allocator, 10),
            .memory = memory,
            .global_runtime = global_runtime,
        };
    }

    pub fn deinit(self: *Runtime, allocator: Allocator) void {
        self.module.deinit(allocator);
        self.stack.deinit();
        allocator.free(self.memory);
    }

    pub fn executeFrame(self: *Runtime, allocator: Allocator, frame: *CallFrame) !void {
        loop: while (frame.program_counter < frame.code.opcodes.len) {
            const opcode: IR.Opcode = frame.code.opcodes[frame.program_counter];
            const index = frame.code.indices[frame.program_counter];
            switch (opcode) {
                // TODO(ernesto): How should we handle unreachable?
                .@"unreachable" => {},
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
                .br_table => @panic("UNIMPLEMENTED"),
                .@"return" => break :loop,
                .call => {
                    // TODO: figure out how many parameters to push
                    try self.call(allocator, index.u32, &[_]Value{});
                },
                .call_indirect => @panic("UNIMPLEMENTED"),

                .refnull => @panic("UNIMPLEMENTED"),
                .refisnull => @panic("UNIMPLEMENTED"),
                .reffunc => @panic("UNIMPLEMENTED"),

                .drop => @panic("UNIMPLEMENTED"),
                .select => @panic("UNIMPLEMENTED"),
                .select_with_values => @panic("UNIMPLEMENTED"),

                .localget => try self.stack.append(frame.locals[index.u32]),
                .localset => frame.locals[index.u32] = self.stack.pop().?,
                .localtee => frame.locals[index.u32] = self.stack.items[self.stack.items.len - 1],
                .globalget => @panic("UNIMPLEMENTED"),
                .globalset => @panic("UNIMPLEMENTED"),

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
                    const start = index.memarg.alignment + index.memarg.offset;
                    const end = start + @sizeOf(i32);
                    try self.stack.append(.{ .i32 = std.mem.littleToNative(i32, std.mem.bytesAsValue(i32, self.memory[start..end]).*) });
                },
                .i64_load => {
                    const start = index.memarg.alignment + index.memarg.offset;
                    const end = start + @sizeOf(i64);
                    try self.stack.append(.{ .i64 = std.mem.littleToNative(i64, std.mem.bytesAsValue(i64, self.memory[start..end]).*) });
                },
                .f32_load => {
                    const start = index.memarg.alignment + index.memarg.offset;
                    const end = start + @sizeOf(f32);
                    try self.stack.append(.{ .f32 = std.mem.littleToNative(f32, std.mem.bytesAsValue(f32, self.memory[start..end]).*) });
                },
                .f64_load => {
                    const start = index.memarg.alignment + index.memarg.offset;
                    const end = start + @sizeOf(f64);
                    try self.stack.append(.{ .f64 = std.mem.littleToNative(f64, std.mem.bytesAsValue(f64, self.memory[start..end]).*) });
                },
                .i32_load8_s => @panic("UNIMPLEMENTED"),
                .i32_load8_u => @panic("UNIMPLEMENTED"),
                .i32_load16_s => @panic("UNIMPLEMENTED"),
                .i32_load16_u => @panic("UNIMPLEMENTED"),
                .i64_load8_s => @panic("UNIMPLEMENTED"),
                .i64_load8_u => @panic("UNIMPLEMENTED"),
                .i64_load16_s => @panic("UNIMPLEMENTED"),
                .i64_load16_u => @panic("UNIMPLEMENTED"),
                .i64_load32_s => @panic("UNIMPLEMENTED"),
                .i64_load32_u => @panic("UNIMPLEMENTED"),
                .i32_store => {
                    // TODO(ernesto): I'm pretty sure this is wrong
                    const start = index.memarg.offset + index.memarg.alignment;
                    const end = start + @sizeOf(u32);
                    const val = std.mem.nativeToLittle(i32, self.stack.pop().?.i32);
                    @memcpy(self.memory[start..end], std.mem.asBytes(&val));
                },

                //         0x36 => {
                //             const address = leb128Decode(u32, frame.code[frame.program_counter..]);
                //             frame.program_counter += address.len;
                //             const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
                //             frame.program_counter += offset.len;
                //             const start = (address.val + offset.val);
                //             const end = start + @sizeOf(u32);
                //             try self.stack.append(Value{ .i32 = decodeLittleEndian(i32, self.memory[start..end]) });
                //         },
                //         0x37 => {
                //             const address = leb128Decode(u32, frame.code[frame.program_counter..]);
                //             frame.program_counter += address.len;
                //             const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
                //             frame.program_counter += offset.len;
                //             const start = (address.val + offset.val);
                //             const end = start + @sizeOf(u32);
                //             encodeLittleEndian(i32, @constCast(&self.memory[start..end]), self.stack.pop().?.i32);
                //         },
                //         0x38 => {
                //             const address = leb128Decode(u32, frame.code[frame.program_counter..]);
                //             frame.program_counter += address.len;
                //             const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
                //             frame.program_counter += offset.len;
                //             const start = (address.val + offset.val);
                //             const end = start + @sizeOf(u64);
                //             encodeLittleEndian(i64, @constCast(&self.memory[start..end]), self.stack.pop().?.i64);
                //         },

                .i32_const => {
                    try self.stack.append(Value{ .i32 = frame.code.indices[frame.program_counter].i32 });
                },
                .i32_lt_u => {
                    const b = self.stack.pop().?.i32;
                    const a = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(a < b))) });
                },
                .i32_ge_u => {
                    const b = self.stack.pop().?.i32;
                    const a = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(a >= b))) });
                },
                .i32_eqz => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 == 0))) });
                },
                .i32_add => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = a + b });
                },
                .i32_and => {
                    const a = self.stack.pop().?.i32;
                    const b = self.stack.pop().?.i32;
                    try self.stack.append(Value{ .i32 = a & b });
                },
                .i64_const => {
                    try self.stack.append(Value{ .i64 = frame.code.indices[frame.program_counter].i64 });
                },
                .i64_add => {
                    const a = self.stack.pop().?.i64;
                    const b = self.stack.pop().?.i64;
                    try self.stack.append(Value{ .i64 = a + b });
                },
                .i64_extend_i32_u => {
                    try self.stack.append(.{ .i64 = self.stack.pop().?.i32 });
                },
                else => {
                    std.log.err("instruction {any} not implemented\n", .{opcode});
                    std.process.exit(1);
                },
            }
            //     switch (byte) {
            //         0x02 => {
            //             var depth: usize = 1;
            //             var pc = frame.program_counter;
            //             while (depth > 0) {
            //                 const opcode = frame.code[pc];
            //                 const operand = frame.code[pc + 1];
            //                 if ((opcode == 0x02 and operand == 0x40) or (opcode == 0x03 and operand == 0x40) or (opcode == 0x04 and operand == 0x40)) {
            //                     depth += 1;
            //                     pc += 1;
            //                 } else if (opcode == 0x0B) {
            //                     depth -= 1;
            //                 }
            //                 pc += 1;
            //             }
            //             try self.labels.append(pc);
            //             frame.program_counter += 1;
            //         },
            //         0x03 => {
            //             try self.labels.append(frame.program_counter - 1);
            //             frame.program_counter += 1;
            //             for_loop = true;
            //         },
            //         0x0c => {
            //             const label = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             var address = @as(usize, 0);
            //             for (0..(label.val + (if (label.val == 0) @as(u32, 1) else @as(u32, 0)))) |_| {
            //                 address = self.labels.pop().?;
            //             }
            //             frame.program_counter = address;
            //         },
            //         0x0d => {
            //             if (self.stack.pop().?.i32 != 0) {
            //                 const label = leb128Decode(u32, frame.code[frame.program_counter..]);
            //                 var address = @as(usize, 0);
            //                 for (0..(label.val + (if (label.val == 0) @as(u32, 1) else @as(u32, 0)))) |_| {
            //                     address = self.labels.pop().?;
            //                 }
            //                 frame.program_counter = address;
            //             } else {
            //                 frame.program_counter += 1;
            //             }
            //         },

            //         0x20 => {
            //             const integer = leb128Decode(u32, frame.code[frame.program_counter..]);

            //             frame.program_counter += integer.len;
            //             try self.stack.append(frame.locals[integer.val]);
            //         },
            //         0x21 => {
            //             const integer = leb128Decode(u32, frame.code[frame.program_counter..]);

            //             frame.program_counter += integer.len;
            //             frame.locals[integer.val] = self.stack.pop().?;
            //         },
            //         0x22 => {
            //             const integer = leb128Decode(u32, frame.code[frame.program_counter..]);

            //             frame.program_counter += integer.len;
            //             const a = self.stack.pop().?;
            //             frame.locals[integer.val] = a;
            //             try self.stack.append(a);
            //         },
            //         0x28 => {
            //             const address = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += address.len;
            //             const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += offset.len;
            //             const start = (address.val + offset.val);
            //             const end = start + @sizeOf(u32);
            //             try self.stack.append(Value{ .i32 = decodeLittleEndian(i32, self.memory[start..end]) });
            //         },
            //         0x29 => {
            //             const address = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += address.len;
            //             const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += offset.len;
            //             const start = (address.val + offset.val);
            //             const end = start + @sizeOf(u64);
            //             try self.stack.append(Value{ .i64 = decodeLittleEndian(i64, self.memory[start..end]) });
            //         },
            //         0x36 => {
            //             const address = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += address.len;
            //             const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += offset.len;
            //             const start = (address.val + offset.val);
            //             const end = start + @sizeOf(u32);
            //             try self.stack.append(Value{ .i32 = decodeLittleEndian(i32, self.memory[start..end]) });
            //         },
            //         0x37 => {
            //             const address = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += address.len;
            //             const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += offset.len;
            //             const start = (address.val + offset.val);
            //             const end = start + @sizeOf(u32);
            //             encodeLittleEndian(i32, @constCast(&self.memory[start..end]), self.stack.pop().?.i32);
            //         },
            //         0x38 => {
            //             const address = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += address.len;
            //             const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += offset.len;
            //             const start = (address.val + offset.val);
            //             const end = start + @sizeOf(u64);
            //             encodeLittleEndian(i64, @constCast(&self.memory[start..end]), self.stack.pop().?.i64);
            //         },
            //         0x41 => {
            //             const integer = leb128Decode(i32, frame.code[frame.program_counter..]);

            //             frame.program_counter += integer.len;
            //             try self.stack.append(Value{ .i32 = integer.val });
            //         },
            //         0x42 => {
            //             const integer = leb128Decode(i64, frame.code[frame.program_counter..]);

            //             frame.program_counter += integer.len;
            //             try self.stack.append(Value{ .i64 = integer.val });
            //         },
            //         0x45 => {
            //             try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 == 0))) });
            //         },
            //         0x46 => {
            //             try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 == self.stack.pop().?.i32))) });
            //         },
            //         0x47 => {
            //             try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 != self.stack.pop().?.i32))) });
            //         },
            //         // 0x48 => {
            //         //     const a = self.stack.pop().?.i32;
            //         //     const b = self.stack.pop().?.i32;
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(b < a))) });
            //         // },
            //         0x49 => {
            //             const a = self.stack.pop().?.i32;
            //             const b = self.stack.pop().?.i32;
            //             try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(b < a))) });
            //         },
            //         // 0x4b => {
            //         //     const b = self.stack.pop().?.i32;
            //         //     const a = self.stack.pop().?.i32;
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(a > b))) });
            //         // },
            //         // 0x4d => {
            //         //     const b = self.stack.pop().?.i32;
            //         //     const a = self.stack.pop().?.i32;
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(b <= a))) });
            //         // },
            //         // 0x4a => {
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 > self.stack.pop().?.i32))) });
            //         // },
            //         // 0x4b => {
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(@as(u32, @bitCast(self.stack.pop().?.i32)) > @as(u32, @bitCast(self.stack.pop().?.i32))))) });
            //         // },
            //         // 0x4c => {
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 <= self.stack.pop().?.i32))) });
            //         // },
            //         // 0x4d => {
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(@as(u32, @bitCast(self.stack.pop().?.i32)) <= @as(u32, @bitCast(self.stack.pop().?.i32))))) });
            //         // },
            //         // 0x4e => {
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 >= self.stack.pop().?.i32))) });
            //         // },
            //         0x4f => {
            //             const a = self.stack.pop().?.i32;
            //             const b = self.stack.pop().?.i32;
            //             try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(a >= b))) });
            //         },

            //         0x50 => {
            //             try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 == 0))) });
            //         },
            //         0x51 => {
            //             try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 == self.stack.pop().?.i64))) });
            //         },
            //         0x52 => {
            //             try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 != self.stack.pop().?.i64))) });
            //         },
            //         // 0x53 => {
            //         //     try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 < self.stack.pop().?.i64))) });
            //         // },
            //         // 0x54 => {
            //         //     try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(@as(u64, @bitCast(self.stack.pop().?.i64)) < @as(u64, @bitCast(self.stack.pop().?.i64))))) });
            //         // },
            //         // 0x55 => {
            //         //     try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 > self.stack.pop().?.i64))) });
            //         // },
            //         // 0x56 => {
            //         //     try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(@as(u64, @bitCast(self.stack.pop().?.i64)) > @as(u64, @bitCast(self.stack.pop().?.i64))))) });
            //         // },
            //         // 0x57 => {
            //         //     try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 <= self.stack.pop().?.i64))) });
            //         // },
            //         // 0x58 => {
            //         //     try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(@as(u64, @bitCast(self.stack.pop().?.i64)) <= @as(u64, @bitCast(self.stack.pop().?.i64))))) });
            //         // },
            //         // 0x59 => {
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 >= self.stack.pop().?.i64))) });
            //         // },
            //         // 0x5a => {
            //         //     try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(@as(u64, @bitCast(self.stack.pop().?.i64)) >= @as(u64, @bitCast(self.stack.pop().?.i64))))) });
            //         // },

            //         // 0x67 => {
            //         //     var i = @as(i32, 0);
            //         //     const number = self.stack.pop().?.i32;
            //         //     for (0..@sizeOf(i32)) |b| {
            //         //         if (number & (@as(i32, 0x1) << @intCast((@sizeOf(i32) - b - 1))) == 1) {
            //         //             break;
            //         //         }
            //         //         i += 1;
            //         //     }
            //         //     try self.stack.append(Value{ .i32 = i });
            //         // },
            //         // 0x68 => {
            //         //     var i = @as(i32, 0);
            //         //     const number = self.stack.pop().?.i32;
            //         //     for (0..@sizeOf(i32)) |b| {
            //         //         if (number & (@as(i32, 0x1) << @intCast(b)) == 1) {
            //         //             break;
            //         //         }
            //         //         i += 1;
            //         //     }
            //         //     try self.stack.append(Value{ .i32 = i });
            //         // },
            //         // 0x69 => {
            //         //     var i = @as(i32, 0);
            //         //     const number = self.stack.pop().?.i32;
            //         //     for (0..@sizeOf(i32)) |b| {
            //         //         if (number & (@as(i32, 0x1) << @intCast(b)) == 1) {
            //         //             i += 1;
            //         //         }
            //         //     }
            //         //     try self.stack.append(Value{ .i32 = i });
            //         // },
            //         0x6a => {
            //             const a = self.stack.pop().?;
            //             const b = self.stack.pop().?;
            //             try self.stack.append(.{ .i32 = a.i32 + b.i32 });
            //         },
            //         // 0x6b => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = a.i32 - b.i32 });
            //         // },
            //         // 0x6c => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = a.i32 * b.i32 });
            //         // },
            //         // 0x6d => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = @divTrunc(a.i32, b.i32) });
            //         // },
            //         // 0x6e => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = @as(i32, @bitCast(@as(u32, @bitCast(a.i32)) / @as(u32, @bitCast(b.i32)))) });
            //         // },
            //         // 0x6f => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = @rem(a.i32, b.i32) });
            //         // },
            //         // 0x70 => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = @as(i32, @bitCast(@as(u32, @bitCast(a.i32)) % @as(u32, @bitCast(b.i32)))) });
            //         // },
            //         0x71 => {
            //             const a = self.stack.pop().?;
            //             const b = self.stack.pop().?;
            //             try self.stack.append(.{ .i32 = a.i32 & b.i32 });
            //         },
            //         // 0x72 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = a.i32 | b.i32 });
            //         // },
            //         // 0x73 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = a.i32 ^ b.i32 });
            //         // },
            //         // 0x74 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = a.i32 << @intCast(b.i32) });
            //         // },
            //         // 0x75 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = a.i32 >> @intCast(b.i32) });
            //         // },
            //         // 0x76 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = @as(i32, @bitCast(@as(u32, @bitCast(a.i32)) >> @intCast(@as(u32, @bitCast(b.i32))))) });
            //         // },
            //         // 0x77 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = (a.i32 << @intCast(@as(u32, @bitCast(b.i32)))) | (a.i32 >> @intCast((@sizeOf(u32) * 8 - b.i32))) });
            //         // },
            //         // 0x78 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i32 = (a.i32 >> @intCast(@as(u32, @bitCast(b.i32)))) | (a.i32 << @intCast((@sizeOf(u32) * 8 - b.i32))) });
            //         // },

            //         // 0x79 => {
            //         //     var i = @as(i64, 0);
            //         //     const number = self.stack.pop().?.i64;
            //         //     for (0..@sizeOf(i64)) |b| {
            //         //         if (number & (@as(i64, 0x1) << @intCast((@sizeOf(i64) - b - 1))) == 1) {
            //         //             break;
            //         //         }
            //         //         i += 1;
            //         //     }
            //         //     try self.stack.append(Value{ .i64 = i });
            //         // },
            //         // 0x7a => {
            //         //     var i = @as(i64, 0);
            //         //     const number = self.stack.pop().?.i64;
            //         //     for (0..@sizeOf(i64)) |b| {
            //         //         if (number & (@as(i64, 0x1) << @intCast(b)) == 1) {
            //         //             break;
            //         //         }
            //         //         i += 1;
            //         //     }
            //         //     try self.stack.append(Value{ .i64 = i });
            //         // },
            //         // 0x7b => {
            //         //     var i = @as(i64, 0);
            //         //     const number = self.stack.pop().?.i64;
            //         //     for (0..@sizeOf(i64)) |b| {
            //         //         if (number & (@as(i64, 0x1) << @intCast(b)) == 1) {
            //         //             i += 1;
            //         //         }
            //         //     }
            //         //     try self.stack.append(Value{ .i64 = i });
            //         // },
            //         0x7c => {
            //             const a = self.stack.pop().?;
            //             const b = self.stack.pop().?;
            //             try self.stack.append(.{ .i64 = a.i64 + b.i64 });
            //         },
            //         // 0x7d => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = a.i64 - b.i64 });
            //         // },
            //         // 0x7e => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = a.i64 * b.i64 });
            //         // },
            //         // 0x7f => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = @divTrunc(a.i64, b.i64) });
            //         // },
            //         // 0x80 => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = @as(i64, @bitCast(@as(u64, @bitCast(a.i64)) / @as(u64, @bitCast(b.i64)))) });
            //         // },
            //         // 0x81 => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = @rem(a.i64, b.i64) });
            //         // },
            //         // 0x82 => {
            //         //     const b = self.stack.pop().?;
            //         //     const a = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = @as(i64, @bitCast(@as(u64, @bitCast(a.i64)) % @as(u64, @bitCast(b.i64)))) });
            //         // },
            //         // 0x83 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = a.i64 & b.i64 });
            //         // },
            //         // 0x84 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = a.i64 | b.i64 });
            //         // },
            //         // 0x85 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = a.i64 ^ b.i64 });
            //         // },
            //         // 0x86 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = a.i64 << @intCast(b.i64) });
            //         // },
            //         // 0x87 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = a.i64 >> @intCast(b.i64) });
            //         // },
            //         // 0x88 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = @as(i64, @bitCast(@as(u64, @bitCast(a.i64)) >> @intCast(@as(u64, @bitCast(b.i64))))) });
            //         // },
            //         // 0x89 => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = (a.i64 << @intCast(@as(u64, @bitCast(b.i64)))) | (a.i64 >> @intCast((@sizeOf(u64) * 8 - b.i64))) });
            //         // },
            //         // 0x8a => {
            //         //     const a = self.stack.pop().?;
            //         //     const b = self.stack.pop().?;
            //         //     try self.stack.append(.{ .i64 = (a.i64 >> @intCast(@as(u64, @bitCast(b.i64)))) | (a.i64 << @intCast((@sizeOf(u64) * 8 - b.i64))) });
            //         // },

            //         0xad => {
            //             try self.stack.append(.{ .i64 = self.stack.pop().?.i32 });
            //         },

            //         0x0f => {
            //             break :loop;
            //         },
            //         0x10 => {
            //             const integer = leb128Decode(u32, frame.code[frame.program_counter..]);
            //             frame.program_counter += integer.len;

            //             self.call(allocator, integer.val, &[_]usize{}) catch {};
            //         },
            //         0xb => {
            //             _ = self.labels.pop();
            //             if (for_loop) {
            //                 for_loop = false;
            //             }
            //         },
            //         else => std.log.err("instruction {} not implemented\n", .{byte}),
            //     }
            frame.program_counter += 1;
        }
    }

    // TODO: Do name resolution at parseTime
    pub fn callExternal(self: *Runtime, allocator: Allocator, name: []const u8, parameters: []Value) !void {
        if (self.module.exports.get(name)) |function| {
            try self.call(allocator, function, parameters);
        } else {
            std.debug.panic("Function `{s}` not avaliable", .{name});
        }
    }

    pub fn call(self: *Runtime, allocator: Allocator, function: usize, parameters: []Value) AllocationError!void {
        const f = self.module.functions[function];
        switch (f.typ) {
            .internal => {
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
                                std.debug.print("Local with type i32\n", .{});
                                frame.locals[i] = .{ .i32 = 0 };
                            },
                            .i64 => {
                                std.debug.print("Local with type i64\n", .{});
                                frame.locals[i] = .{ .i64 = 0 };
                            },
                            else => unreachable,
                        },
                        .ref => unreachable,
                    }
                }

                try self.executeFrame(allocator, &frame);

                allocator.free(frame.locals);
            },
            .external => {
                // TODO(ernesto): handle external functions
                // const name = self.module.imports[f.external].name;
                // if (self.global_runtime.functions.get(name)) |external| {
                //     external(&self.stack);
                // }
            },
        }
    }
};
