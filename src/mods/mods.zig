pub const Parser = @import("Parser.zig");
pub const VM = @import("vm.zig");
// TODO: is this really needed?
pub const Wasm = @import("wasm.zig");
pub const IR = @import("ir.zig");

pub const GlobalRuntime = Wasm.GlobalRuntime;
pub const Runtime = VM.Runtime;
