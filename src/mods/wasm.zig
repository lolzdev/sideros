const vm = @import("vm.zig");
const Parser = @import("Parser.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Type = enum(u8) {
    i32 = 0x7f,
    i64 = 0x7e,
    f32 = 0x7d,
    f64 = 0x7c,
    v128 = 0x7b,
};

pub const GlobalRuntime = struct {
    functions: std.StringHashMap(*const fn (stack: *std.ArrayList(vm.Value)) void),
    globals: std.AutoHashMap(u32, Parser.Globaltype),
    globalExprs: std.AutoHashMap(u32, vm.Value),

    pub fn init(allocator: Allocator) GlobalRuntime {
        return GlobalRuntime{
            .functions = std.StringHashMap(*const fn (stack: *std.ArrayList(vm.Value)) void).init(allocator),
            .globals = std.AutoHashMap(u32, Parser.Globaltype).init(allocator),
            .globalExprs = std.AutoHashMap(u32, vm.Value).init(allocator)
        };
    }

    pub fn deinit(self: *GlobalRuntime) void {
        self.functions.deinit();
        self.globals.deinit();
        self.globalExprs.deinit();
    }

    pub fn addFunction(self: *GlobalRuntime, name: []const u8, function: *const fn (stack: *std.ArrayList(vm.Value)) void) !void {
        try self.functions.put(name, function);
    }

    pub fn addGlobal(self: *GlobalRuntime, index: u32, @"type": Parser.Globaltype, initValue: vm.Value) !void {
        try self.globals.put(index, @"type");
        try self.globalExprs.put(index, initValue);
    }

    pub fn updateGlobal(self: *GlobalRuntime, index: u32, value: vm.Value) !void {
        const globType = self.globals.get(index) orelse std.debug.panic("Tried updating global {any} but couldn't find it.\n", .{index});
        if(globType.m == Parser.GlobalMutability.@"const"){
            std.debug.panic("Attempted write to immutable global\n", .{});
        }
        try self.globalExprs.put(index, value);
    }

    pub fn getGlobal(self: *GlobalRuntime, index: u32) vm.Value {
        return self.globalExprs.get(index) orelse std.debug.panic("Tried getting global {any} but couldn't find it.\n", .{index});
    }
};

pub fn debug(stack: *std.ArrayList(vm.Value)) void {
    const a = stack.pop().?;

    std.debug.print("{}\n", .{a.i32});
}
