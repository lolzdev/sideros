pub const Parser = @import("Parser.zig");
pub const VM = @import("vm.zig");
// TODO: is this really needed?
pub const Wasm = @import("wasm.zig");
pub const IR = @import("ir.zig");

pub const GlobalRuntime = Wasm.GlobalRuntime;
pub const Runtime = VM.Runtime;

// const std = @import("std");

// test "Fibonacci" {
//     // var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     // const allocator = gpa.allocator();
//     const allocator = std.testing.allocator;
//     var global_runtime = GlobalRuntime.init(allocator);
//     defer global_runtime.deinit();

//     const file = try std.fs.cwd().openFile("assets/core.wasm", .{});
//     const all = try file.readToEndAlloc(allocator, 1_000_000); // 1 MB
//     var parser = Parser{
//         .bytes = all,
//         .byte_idx = 0,
//         .allocator = allocator,
//     };
//     const module = parser.parseModule() catch |err| {
//         std.debug.print("[ERROR]: error at byte {x}(0x{x})\n", .{ parser.byte_idx, parser.bytes[parser.byte_idx] });
//         return err;
//     };
//     var runtime = try Runtime.init(allocator, module, &global_runtime);
//     defer runtime.deinit(allocator);

//     var parameters = [_]usize{17};
//     try runtime.callExternal(allocator, "preinit", &parameters);
//     const result = runtime.stack.pop().?;
//     try std.testing.expect(result.i64 == 1597);

//     var parameters2 = [_]usize{1};
//     try runtime.callExternal(allocator, "preinit", &parameters2);
//     const result2 = runtime.stack.pop().?;
//     try std.testing.expect(result2.i64 == 1);

//     var parameters3 = [_]usize{5};
//     try runtime.callExternal(allocator, "preinit", &parameters3);
//     const result3 = runtime.stack.pop().?;
//     try std.testing.expect(result3.i64 == 5);
// }
