const std = @import("std");
const Parser = @import("Parser.zig");

const Allocator = std.mem.Allocator;

const DIndex = packed struct {
	first: u32,
	second: u32,
};
comptime {
	// TODO: is this too big? we could do with 32 bits and a bit more indirection
	std.debug.assert(@sizeOf(Index) == 8);
}
/// packed union has no tag
const Index = packed union {
	u32: u32,
	i32: i32,
	u64: u64,
	i64: i64,
	f32: f32,
	f64: f64,
	di: DIndex,
};


opcodes: []Opcode,
/// Indices means something different depending on the Opcode.
/// Read the docs of each opcode to know what the index means.
indices: []Index,

select_valtypes: []Parser.Valtype,

/// Opcodes
pub const Opcode = enum(u8) {
	// CONTROL INSTRUCTIONS
	// The rest of instructions should be implemented in terms of these ones
	@"unreachable" = 0x00,
	nop = 0x01,
	/// Index: `u64`. Meaning: the next instruction pointer
	br = 0x0C,
	/// Index: `u64`. Meaning: the next instruction pointer
	br_if = 0x0D,
	/// TODO: this instruction (could be also implemented in terms of br and br_if)
	br_table = 0x0E,
	@"return" = 0x0F,
	/// Index: `u64`. Meaning: The function index to call
	call = 0x10,
	/// TODO: index (is it enough with using a double index here? if we consider it enough then the other indices should use u32)
	call_indirect = 0x11,

	// REFERENCE INSTRUCTIONS
	// This should be resolved at parse time and therefore not part of IR

	// PARAMETRIC INSTRUCTIONS
	// Select with no valtypes should be resolved at parse time
	drop = 0x1A,
	/// Index: `DIndex`. Meaning:
	/// `first` is the index into `select_valtypes` array and
	/// `second` is the number of valtypes
	select = 0x1C,

	// VARIABLE INSTRUCTIONS
	/// Index: `u32`. Meaing: index into local variables
	localget = 0x20,
	/// Index: `u32`. Meaing: index into local variables
	localset = 0x21,
	/// Index: `u32`. Meaing: index into local variables
	localtee = 0x22,
	/// Index: `u32`. Meaing: index into global variables
	globalget = 0x23,
	/// Index: `u32`. Meaing: index into global variables
	globalset = 0x24,

	// TABLE INSTRUCTIONS
	/// Index: `u32`. Meaning: index into table index
	tableget = 0x25,
	/// Index: `u32`. Meaning: index into table index
	tableset = 0x26,
	/// TODO: table operation. Value in wasm: 0xFC. Note wher is 0x27?
	tableop = 0xF0,

	// MEMORY INSTRUCTIONS
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i32load = 0x28,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64load = 0x29,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	f32load = 0x2A,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	f64load = 0x2B,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i32load8_s = 0x2C,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i32load8_u = 0x2D,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i32load16_s = 0x2E,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i32load16_u = 0x2F,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64load8_s = 0x30,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64load8_u = 0x31,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64load16_s = 0x32,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64load16_u = 0x33,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64load32_s = 0x34,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64load32_u = 0x35,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i32store = 0x36,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64store = 0x37,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	f32store = 0x38,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	f64store = 0x39,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i32store8 = 0x3A,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i32store16 = 0x3B,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64store8 = 0x3C,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64store16 = 0x3D,
	/// Index: `DIndex`. Meaning: `firts` is alignment, `second` is offset
	i64store32 = 0x3E,
	memorysize = 0x3F,
	memorygrow = 0x40,
	/// TODO: memory operation. Value in wasm: 0xFC
	memoryop = 0xF1,

	// NUMERIC INSTRUCTION
	/// Index: `i32`. Meaning: constant
	i32const = 0x41,
	/// Index: `i64`. Meaning: constant
	i64const = 0x42,
	/// Index: `f32`. Meaning: constant
	f32const = 0x43,
	/// Index: `f64`. Meaning: constant
	f64const = 0x44,
	i32eqz = 0x45,
	i32eq = 0x46,
	i32ne = 0x47,
	i32lt_s = 0x48,
	i32lt_u = 0x49,
	i32gt_s = 0x4A,
	i32gt_u = 0x4B,
	i32le_s = 0x4C,
	i32le_u = 0x4D,
	i32ge_s = 0x4E,
	i32ge_u = 0x4F,
	i64eqz = 0x50,
	i64eq = 0x51,
	i64ne = 0x52,
	i64lt_s = 0x53,
	i64lt_u = 0x54,
	i64gt_s = 0x55,
	i64gt_u = 0x56,
	i64le_s = 0x57,
	i64le_u = 0x58,
	i64ge_s = 0x59,
	i64ge_u = 0x5A,
	f32eq = 0x5B,
	f32ne = 0x5C,
	f32lt = 0x5D,
	f32gt = 0x5E,
	f32le = 0x5F,
	f32ge = 0x60,
	f64eq = 0x61,
	f64ne = 0x62,
	f64lt = 0x63,
	f64gt = 0x64,
	f64le = 0x65,
	f64ge = 0x66,
	i32clz = 0x67,
	i32ctz = 0x68,
	i32popcnt = 0x69,
	i32add = 0x6A,
	i32sub = 0x6B,
	i32mul = 0x6C,
	i32div_s = 0x6D,
	i32div_u = 0x6E,
	i32rem_s = 0x6F,
	i32rem_u = 0x70,
	i32and = 0x71,
	i32or = 0x72,
	i32xor = 0x73,
	i32shl = 0x74,
	i32shr_s = 0x75,
	i32shr_u = 0x76,
	i32rotl = 0x77,
	i32rotr = 0x78,
	i64clz = 0x79,
	i64ctz = 0x7A,
	i64popcnt = 0x7B,
	i64add = 0x7C,
	i64sub = 0x7D,
	i64mul = 0x7E,
	i64div_s = 0x7F,
	i64div_u = 0x80,
	i64rem_s = 0x81,
	i64rem_u = 0x82,
	i64and = 0x83,
	i64or = 0x84,
	i64xor = 0x85,
	i64shl = 0x86,
	i64shr_s = 0x87,
	i64shr_u = 0x88,
	i64rotl = 0x89,
	i64rotr = 0x8A,
	f32abs = 0x8B,
	f32neg = 0x8C,
	f32ceil = 0x8D,
	f32floor = 0x8E,
	f32trunc = 0x8F,
	f32nearest = 0x90,
	f32sqrt = 0x91,
	f32add = 0x92,
	f32sub = 0x93,
	f32mul = 0x94,
	f32div = 0x95,
	f32min = 0x96,
	f32max = 0x97,
	f32copysign = 0x98,
	f64abs = 0x99,
	f64neg = 0x9A,
	f64ceil = 0x9B,
	f64floor = 0x9C,
	f64trunc = 0x9D,
	f64nearest = 0x9E,
	f64sqrt = 0x9F,
	f64add = 0xA0,
	f64sub = 0xA1,
	f64mul = 0xA2,
	f64div = 0xA3,
	f64min = 0xA4,
	f64max = 0xA5,
	f64copysign = 0xA6,
	i32wrap_i64 = 0xA7,
	i32trunc_f32_s = 0xA8,
	i32trunc_f32_u = 0xA9,
	i32trunc_f64_s = 0xAA,
	i32trunc_f64_u = 0xAB,
	i64extend_i32_s = 0xAC,
	i64extend_i32_u = 0xAD,
	i64trunc_f32_s = 0xAE,
	i64trunc_f32_u = 0xAF,
	i64trunc_f64_s = 0xB0,
	i64trunc_f64_u = 0xB1,
	f32convert_i32_s = 0xB2,
	f32convert_i32_u = 0xB3,
	f32convert_i64_s = 0xB4,
	f32convert_i64_u = 0xB5,
	f32demote_f64 = 0xB6,
	f64convert_i32_s = 0xB7,
	f64convert_i32_u = 0xB8,
	f64convert_i64_s = 0xB9,
	f64convert_i64_u = 0xBA,
	f64promote_f32 = 0xBB,
	i32reinterpret_f32 = 0xBC,
	i64reinterpret_f64 = 0xBD,
	f32reinterpret_i32 = 0xBE,
	f64reinterpret_i64 = 0xBF,
	i32extend8_s = 0xC0,
	i32extend16_s = 0xC1,
	i64extend8_s = 0xC2,
	i64extend16_s = 0xC3,
	i64extend32_s = 0xC4,
	/// TODO: saturation truncation instructions. Value in wasm: 0xFC
	sattrunc = 0xF2,

	// VECTOR INSTRUCTIONS
	/// TODO: vector instructions. Value in wasm: 0xFC. Note: there are opcodes available lol
	vecinst = 0xF3,

};

