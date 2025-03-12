const vm = @import("vm.zig");
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

    pub fn init(allocator: Allocator) GlobalRuntime {
        return GlobalRuntime{
            .functions = std.StringHashMap(*const fn (stack: *std.ArrayList(vm.Value)) void).init(allocator),
        };
    }

    pub fn deinit(self: *GlobalRuntime) void {
        self.functions.deinit();
    }

    pub fn addFunction(self: *GlobalRuntime, name: []const u8, function: *const fn (stack: *std.ArrayList(vm.Value)) void) !void {
        try self.functions.put(name, function);
    }
};

pub fn debug(stack: *std.ArrayList(vm.Value)) void {
    const a = stack.pop().?;

    std.debug.print("{}\n", .{a.i32});
}
