const std = @import("std");
const wasm = @import("wasm.zig");
const Parser = @import("parse.zig");
const Allocator = std.mem.Allocator;
const AllocationError = error{OutOfMemory};

pub fn leb128Decode(comptime T: type, bytes: []u8) struct { len: usize, val: T } {
    switch (@typeInfo(T)) {
        .int => {},
        else => @compileError("LEB128 integer decoding only support integers, but got " ++ @typeName(T)),
    }
    if (@typeInfo(T).int.bits != 32 and @typeInfo(T).int.bits != 64) {
        @compileError("LEB128 integer decoding only supports 32 or 64 bits integers but got " ++ std.fmt.comptimePrint("{d} bits", .{@typeInfo(T).int.bits}));
    }

    var result: T = 0;
    // TODO: is the type of shift important. Reading Wikipedia (not very much tho) it seems like we can use u32 and call it a day...
    var shift: if (@typeInfo(T).int.bits == 32) u5 else u6 = 0;
    var byte: u8 = undefined;
    var len: usize = 0;
    for (bytes) |b| {
        len += 1;
        result |= @as(T, @intCast((b & 0x7f))) << shift;
        if ((b & (0x1 << 7)) == 0) {
            byte = b;
            break;
        }
        shift += 7;
    }
    if (@typeInfo(T).int.signedness == .signed) {
        const size = @sizeOf(T) * 8;
        if (shift < size and (byte & 0x40) != 0) {
            result |= (~@as(T, 0) << shift);
        }
    }

    return .{ .len = len, .val = result };
}

pub fn decodeLittleEndian(comptime T: type, bytes: []u8) T {
    if (T != i32 and T != i64) {
        return @as(T, 0);
    } else {
        var value = @as(T, 0);
        for (0..@sizeOf(T)) |b| {
            value |= ((bytes[b]) << @intCast((@sizeOf(T) - b - 1)));
        }
        return value;
    }
}

pub fn encodeLittleEndian(comptime T: type, bytes: *[]u8, value: T) void {
    for (0..@sizeOf(T)) |b| {
        bytes.*[b] = @intCast(((value >> @intCast((@sizeOf(T) - b - 1))) & 0xff));
    }
}

pub const CallFrame = struct {
    program_counter: usize,
    code: []u8,
    locals: []Value,
};

const ValueType = enum {
    i32,
    i64,
};

pub const Value = union(ValueType) {
    i32: i32,
    i64: i64,
};

pub const Runtime = struct {
    module: Parser.Module,
    stack: std.ArrayList(Value),
    call_stack: std.ArrayList(CallFrame),
    memory: []u8,
    global_runtime: *wasm.GlobalRuntime,
    labels: std.ArrayList(usize),

    pub fn init(allocator: Allocator, module: Parser.Module, global_runtime: *wasm.GlobalRuntime) !Runtime {
        const memory = try allocator.alloc(u8, module.memory.max);
        return Runtime{
            .module = module,
            .stack = try std.ArrayList(Value).initCapacity(allocator, 10),
            .call_stack = try std.ArrayList(CallFrame).initCapacity(allocator, 5),
            .labels = try std.ArrayList(usize).initCapacity(allocator, 2),
            .memory = memory,
            .global_runtime = global_runtime,
        };
    }

    pub fn deinit(self: *Runtime, allocator: Allocator) void {
        self.module.deinit(allocator);
        self.stack.deinit();
        self.labels.deinit();
        self.call_stack.deinit();
        allocator.free(self.memory);
    }

    pub fn executeFrame(self: *Runtime, allocator: Allocator, frame: *CallFrame) !void {
        var for_loop = false;
        loop: while (true) {
            const byte: u8 = frame.code[frame.program_counter];
            frame.program_counter += 1;
            std.debug.print("b: {x}\n", .{byte});
            switch (byte) {
                0x03 => {
                    try self.labels.append(frame.program_counter);
                    frame.program_counter += 1;
                    //const a = frame.code[frame.program_counter];
                    for_loop = true;
                },
                0x0d => {
                    const label = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += label.len;
                    var address = @as(usize, 0);
                    for (0..(label.val)) |_| {
                        address = self.labels.pop().?;
                    }

                    if (self.stack.pop().?.i32 != 0) {
                        frame.program_counter = address;
                    }
                },

                0x20 => {
                    const integer = leb128Decode(u32, frame.code[frame.program_counter..]);

                    frame.program_counter += integer.len;
                    try self.stack.append(frame.locals[integer.val]);
                },
                0x21 => {
                    const integer = leb128Decode(u32, frame.code[frame.program_counter..]);

                    frame.program_counter += integer.len;
                    frame.locals[integer.val] = self.stack.pop().?;
                },
                0x22 => {
                    const integer = leb128Decode(u32, frame.code[frame.program_counter..]);

                    frame.program_counter += integer.len;
                    frame.locals[integer.val] = self.stack.pop().?;
                    try self.stack.append(Value{ .i32 = @intCast(integer.val) });
                },
                0x28 => {
                    const address = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += address.len;
                    const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += offset.len;
                    const start = (address.val + offset.val);
                    const end = start + @sizeOf(u32);
                    try self.stack.append(Value{ .i32 = decodeLittleEndian(i32, self.memory[start..end]) });
                },
                0x29 => {
                    const address = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += address.len;
                    const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += offset.len;
                    const start = (address.val + offset.val);
                    const end = start + @sizeOf(u64);
                    try self.stack.append(Value{ .i64 = decodeLittleEndian(i64, self.memory[start..end]) });
                },
                0x36 => {
                    const address = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += address.len;
                    const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += offset.len;
                    const start = (address.val + offset.val);
                    const end = start + @sizeOf(u32);
                    try self.stack.append(Value{ .i32 = decodeLittleEndian(i32, self.memory[start..end]) });
                },
                0x37 => {
                    const address = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += address.len;
                    const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += offset.len;
                    const start = (address.val + offset.val);
                    const end = start + @sizeOf(u32);
                    encodeLittleEndian(i32, @constCast(&self.memory[start..end]), self.stack.pop().?.i32);
                },
                0x38 => {
                    const address = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += address.len;
                    const offset = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += offset.len;
                    const start = (address.val + offset.val);
                    const end = start + @sizeOf(u64);
                    encodeLittleEndian(i64, @constCast(&self.memory[start..end]), self.stack.pop().?.i64);
                },
                0x41 => {
                    const integer = leb128Decode(i32, frame.code[frame.program_counter..]);

                    frame.program_counter += integer.len;
                    try self.stack.append(Value{ .i32 = integer.val });
                },
                0x42 => {
                    const integer = leb128Decode(i64, frame.code[frame.program_counter..]);

                    frame.program_counter += integer.len;
                    try self.stack.append(Value{ .i64 = integer.val });
                },
                0x45 => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 == 0))) });
                },
                0x46 => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 == self.stack.pop().?.i32))) });
                },
                0x47 => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 != self.stack.pop().?.i32))) });
                },
                0x48 => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 < self.stack.pop().?.i32))) });
                },
                0x49 => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(@as(u32, @bitCast(self.stack.pop().?.i32)) < @as(u32, @bitCast(self.stack.pop().?.i32))))) });
                },
                0x4a => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 > self.stack.pop().?.i32))) });
                },
                0x4b => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(@as(u32, @bitCast(self.stack.pop().?.i32)) > @as(u32, @bitCast(self.stack.pop().?.i32))))) });
                },
                0x4c => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 <= self.stack.pop().?.i32))) });
                },
                0x4d => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(@as(u32, @bitCast(self.stack.pop().?.i32)) <= @as(u32, @bitCast(self.stack.pop().?.i32))))) });
                },
                0x4e => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i32 >= self.stack.pop().?.i32))) });
                },
                0x4f => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(@as(u32, @bitCast(self.stack.pop().?.i32)) >= @as(u32, @bitCast(self.stack.pop().?.i32))))) });
                },

                0x50 => {
                    try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 == 0))) });
                },
                0x51 => {
                    try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 == self.stack.pop().?.i64))) });
                },
                0x52 => {
                    try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 != self.stack.pop().?.i64))) });
                },
                0x53 => {
                    try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 < self.stack.pop().?.i64))) });
                },
                0x54 => {
                    try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(@as(u64, @bitCast(self.stack.pop().?.i64)) < @as(u64, @bitCast(self.stack.pop().?.i64))))) });
                },
                0x55 => {
                    try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 > self.stack.pop().?.i64))) });
                },
                0x56 => {
                    try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(@as(u64, @bitCast(self.stack.pop().?.i64)) > @as(u64, @bitCast(self.stack.pop().?.i64))))) });
                },
                0x57 => {
                    try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 <= self.stack.pop().?.i64))) });
                },
                0x58 => {
                    try self.stack.append(Value{ .i64 = @intCast(@as(u1, @bitCast(@as(u64, @bitCast(self.stack.pop().?.i64)) <= @as(u64, @bitCast(self.stack.pop().?.i64))))) });
                },
                0x59 => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(self.stack.pop().?.i64 >= self.stack.pop().?.i64))) });
                },
                0x5a => {
                    try self.stack.append(Value{ .i32 = @intCast(@as(u1, @bitCast(@as(u64, @bitCast(self.stack.pop().?.i64)) >= @as(u64, @bitCast(self.stack.pop().?.i64))))) });
                },

                0x67 => {
                    var i = @as(i32, 0);
                    const number = self.stack.pop().?.i32;
                    for (0..@sizeOf(i32)) |b| {
                        if (number & (@as(i32, 0x1) << @intCast((@sizeOf(i32) - b - 1))) == 1) {
                            break;
                        }
                        i += 1;
                    }
                    try self.stack.append(Value{ .i32 = i });
                },
                0x68 => {
                    var i = @as(i32, 0);
                    const number = self.stack.pop().?.i32;
                    for (0..@sizeOf(i32)) |b| {
                        if (number & (@as(i32, 0x1) << @intCast(b)) == 1) {
                            break;
                        }
                        i += 1;
                    }
                    try self.stack.append(Value{ .i32 = i });
                },
                0x69 => {
                    var i = @as(i32, 0);
                    const number = self.stack.pop().?.i32;
                    for (0..@sizeOf(i32)) |b| {
                        if (number & (@as(i32, 0x1) << @intCast(b)) == 1) {
                            i += 1;
                        }
                    }
                    try self.stack.append(Value{ .i32 = i });
                },
                0x6a => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = a.i32 + b.i32 });
                },
                0x6b => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = a.i32 - b.i32 });
                },
                0x6c => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = a.i32 * b.i32 });
                },
                0x6d => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = @divTrunc(a.i32, b.i32) });
                },
                0x6e => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = @as(i32, @bitCast(@as(u32, @bitCast(a.i32)) / @as(u32, @bitCast(b.i32)))) });
                },
                0x6f => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = @rem(a.i32, b.i32) });
                },
                0x70 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = @as(i32, @bitCast(@as(u32, @bitCast(a.i32)) % @as(u32, @bitCast(b.i32)))) });
                },
                0x71 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = a.i32 & b.i32 });
                },
                0x72 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = a.i32 | b.i32 });
                },
                0x73 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = a.i32 ^ b.i32 });
                },
                0x74 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = a.i32 << @intCast(b.i32) });
                },
                0x75 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = a.i32 >> @intCast(b.i32) });
                },
                0x76 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = @as(i32, @bitCast(@as(u32, @bitCast(a.i32)) >> @intCast(@as(u32, @bitCast(b.i32))))) });
                },
                0x77 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = (a.i32 << @intCast(@as(u32, @bitCast(b.i32)))) | (a.i32 >> @intCast((@sizeOf(u32) * 8 - b.i32))) });
                },
                0x78 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i32 = (a.i32 >> @intCast(@as(u32, @bitCast(b.i32)))) | (a.i32 << @intCast((@sizeOf(u32) * 8 - b.i32))) });
                },

                0x79 => {
                    var i = @as(i64, 0);
                    const number = self.stack.pop().?.i64;
                    for (0..@sizeOf(i64)) |b| {
                        if (number & (@as(i64, 0x1) << @intCast((@sizeOf(i64) - b - 1))) == 1) {
                            break;
                        }
                        i += 1;
                    }
                    try self.stack.append(Value{ .i64 = i });
                },
                0x7a => {
                    var i = @as(i64, 0);
                    const number = self.stack.pop().?.i64;
                    for (0..@sizeOf(i64)) |b| {
                        if (number & (@as(i64, 0x1) << @intCast(b)) == 1) {
                            break;
                        }
                        i += 1;
                    }
                    try self.stack.append(Value{ .i64 = i });
                },
                0x7b => {
                    var i = @as(i64, 0);
                    const number = self.stack.pop().?.i64;
                    for (0..@sizeOf(i64)) |b| {
                        if (number & (@as(i64, 0x1) << @intCast(b)) == 1) {
                            i += 1;
                        }
                    }
                    try self.stack.append(Value{ .i64 = i });
                },
                0x7c => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = a.i64 + b.i64 });
                },
                0x7d => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = a.i64 - b.i64 });
                },
                0x7e => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = a.i64 * b.i64 });
                },
                0x7f => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = @divTrunc(a.i64, b.i64) });
                },
                0x80 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = @as(i64, @bitCast(@as(u64, @bitCast(a.i64)) / @as(u64, @bitCast(b.i64)))) });
                },
                0x81 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = @rem(a.i64, b.i64) });
                },
                0x82 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = @as(i64, @bitCast(@as(u64, @bitCast(a.i64)) % @as(u64, @bitCast(b.i64)))) });
                },
                0x83 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = a.i64 & b.i64 });
                },
                0x84 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = a.i64 | b.i64 });
                },
                0x85 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = a.i64 ^ b.i64 });
                },
                0x86 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = a.i64 << @intCast(b.i64) });
                },
                0x87 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = a.i64 >> @intCast(b.i64) });
                },
                0x88 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = @as(i64, @bitCast(@as(u64, @bitCast(a.i64)) >> @intCast(@as(u64, @bitCast(b.i64))))) });
                },
                0x89 => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = (a.i64 << @intCast(@as(u64, @bitCast(b.i64)))) | (a.i64 >> @intCast((@sizeOf(u64) * 8 - b.i64))) });
                },
                0x8a => {
                    const a = self.stack.pop().?;
                    const b = self.stack.pop().?;
                    try self.stack.append(.{ .i64 = (a.i64 >> @intCast(@as(u64, @bitCast(b.i64)))) | (a.i64 << @intCast((@sizeOf(u64) * 8 - b.i64))) });
                },

                0x10 => {
                    const integer = leb128Decode(u32, frame.code[frame.program_counter..]);
                    frame.program_counter += integer.len;

                    self.call(allocator, integer.val, &[_]usize{}) catch {};
                },
                0xb => {
                    if (for_loop) {
                        frame.program_counter += 1;
                    } else {
                        break :loop;
                    }
                },
                else => std.debug.print("instruction {} not implemented\n", .{byte}),
            }
        }
    }

    pub fn callExternal(self: *Runtime, allocator: Allocator, name: []const u8, parameters: []usize) !void {
        if (self.module.exports.get(name)) |function| {
            try self.call(allocator, function, parameters);
        }
    }

    pub fn call(self: *Runtime, allocator: Allocator, function: usize, parameters: []usize) AllocationError!void {
        const f = self.module.funcs.items[function];
        switch (f) {
            .internal => {
                const function_type = self.module.types[self.module.functions[f.internal]];
                var frame = CallFrame{
                    .code = self.module.code[f.internal].code,
                    .program_counter = 0x0,
                    .locals = try allocator.alloc(Value, self.module.code[f.internal].locals.len + function_type.parameters.len),
                };

                for (parameters, 0..) |p, i| {
                    switch (Parser.parseType(function_type.parameters[i])) {
                        .i32 => {
                            frame.locals[i] = .{ .i32 = @intCast(p) };
                        },
                        .i64 => {
                            frame.locals[i] = .{ .i64 = @intCast(p) };
                        },
                        else => unreachable,
                    }
                }

                for (self.module.code[f.internal].locals, function_type.parameters.len..) |local, i| {
                    switch (Parser.parseType(local.types[0])) {
                        .i32 => {
                            frame.locals[i] = .{ .i32 = 0 };
                        },
                        .i64 => {
                            frame.locals[i] = .{ .i64 = 0 };
                        },
                        else => unreachable,
                    }
                }

                try self.executeFrame(allocator, &frame);

                allocator.free(frame.locals);
            },
            .external => {
                const name = self.module.imports.items[f.external].name;
                if (self.global_runtime.functions.get(name)) |external| {
                    external(&self.stack);
                }
            },
        }
    }
};
