const vmValue = @import("vm.zig").Value;
const vmRuntime = @import("vm.zig").Runtime;
const std = @import("std");

pub fn logDebug(self: *vmRuntime, params: []vmValue) ?vmValue {
    const offset: usize = @intCast(params[0].i32);
    const size: usize = @intCast(params[1].i64);
    const ptr: []u8 = self.memory[offset .. offset + size];
    const extra: u8 = if (ptr.len > 0 and ptr[ptr.len - 1] != '\n') 0x0a else 0;
    std.debug.print("[DEBUG]: {s}{c}", .{ptr, extra});
    return null;
}
pub fn logInfo(self: *vmRuntime, params: []vmValue) ?vmValue {
    const offset: usize = @intCast(params[0].i32);
    const size: usize = @intCast(params[1].i64);
    const ptr: []u8 = self.memory[offset .. offset + size];
    const extra: u8 = if (ptr.len > 0 and ptr[ptr.len - 1] != '\n') 0x0a else 0;
    std.debug.print("[INFO]: {s}{c}", .{ptr, extra});
    return null;
}
pub fn logWarn(self: *vmRuntime, params: []vmValue) ?vmValue {
    const offset: usize = @intCast(params[0].i32);
    const size: usize = @intCast(params[1].i64);
    const ptr: []u8 = self.memory[offset .. offset + size];
    const extra: u8 = if (ptr.len > 0 and ptr[ptr.len - 1] != '\n') 0x0a else 0;
    std.debug.print("[WARN]: {s}{c}", .{ptr, extra});
    return null;
}
pub fn logErr(self: *vmRuntime, params: []vmValue) ?vmValue {
    const offset: usize = @intCast(params[0].i32);
    const size: usize = @intCast(params[1].i64);
    const ptr: []u8 = self.memory[offset .. offset + size];
    const extra: u8 = if (ptr.len > 0 and ptr[ptr.len - 1] != '\n') 0x0a else 0;
    std.debug.print("[ERROR]: {s}{c}", .{ptr, extra});
    return null;
}