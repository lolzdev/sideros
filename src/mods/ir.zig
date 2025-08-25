const std = @import("std");
const Parser = @import("Parser.zig");
const vm = @import("vm.zig");

const Allocator = std.mem.Allocator;

const IR = @This();

const VectorIndex = packed struct {
    opcode: VectorOpcode,
    laneidx: u8,
    memarg: Memarg,
};
const Memarg = packed struct {
    offset: u32,
    /// Accordng to spec this should be a `u32` but who the fuck needs that big of an alignment? Moreover
    /// if we make this value bigger, then VectorIndex does not fit anymore :(
    alignment: u16,
};
const DIndex = packed struct {
    x: u32,
    y: u32,
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
    indirect: DIndex,
    reftype: std.wasm.RefType,
    valtype: std.wasm.Valtype,
    memarg: Memarg,
    vector: VectorIndex,
};

opcodes: []Opcode,
/// Indices means something different depending on the Opcode.
/// Read the docs of each opcode to know what the index means.
indices: []Index,

// TODO: this could be a byte array and v128.const and i8x16.shuffle could live here too
select_valtypes: []vm.Valtype,

br_table_vectors: []u32,

pub fn print(self: IR, writer: anytype) !void {
    for (self.opcodes, 0..) |op, i| {
        try writer.print("{x:3} {s}", .{ i, @tagName(op) });
        if (op == .br or op == .br_if) {
            try writer.print(" {x:3}", .{self.indices[i].u32});
        }
        _ = try writer.write("\n");
    }
}

/// Opcodes.
/// This is a mix of wasm opcodes mixed with a few of our own.
/// Mainly for `0xFC` opcodes we use `0xD3` to `0xE4`.
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
    /// Index: `u32`. Meaning: The function index to call
    call = 0x10,
    /// Index: `DIndex`. Meaning: `DIndex.x` is the table index and `DIndex.y` is the typeindex
    call_indirect = 0x11,

    // REFERENCE INSTRUCTIONS
    /// Index: `Parser.Reftype`. Meaning: reftype
    refnull = 0xD0,
    refisnull = 0xD1,
    /// Index: `u32`. Meaning: funcidx
    reffunc = 0xD2,

    // PARAMETRIC INSTRUCTIONS
    drop = 0x1A,
    select = 0x1B,
    /// Index: `DIndex`. Meaning:
    /// `DIndex.x` is the index into `select_valtypes` array and
    /// `DIndex.y` is the number of valtypes
    select_with_values = 0x1C,

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
    /// Index: `DIndex`. Meaning: TODO
    tableinit = 0xDF,
    /// Index: `u32`. Meaning: TODO
    elemdrop = 0xE0,
    /// Index: `DIndex`. Meaning: `DIndex.x` is destination `DIndex.y` is source
    tablecopy = 0xE1,
    /// Index: `u32`. Meaning: tableidx
    tablegrow = 0xE2,
    /// Index: `u32`. Meaning: tableidx
    tablesize = 0xE3,
    /// Index: `u32`. Meaning: tableidx
    tablefill = 0xE4,

    // MEMORY INSTRUCTIONS
    /// Index: `Memarg`. Meaning: memarg
    i32_load = 0x28,
    /// Index: `Memarg`. Meaning: memarg
    i64_load = 0x29,
    /// Index: `Memarg`. Meaning: memarg
    f32_load = 0x2A,
    /// Index: `Memarg`. Meaning: memarg
    f64_load = 0x2B,
    /// Index: `Memarg`. Meaning: memarg
    i32_load8_s = 0x2C,
    /// Index: `Memarg`. Meaning: memarg
    i32_load8_u = 0x2D,
    /// Index: `Memarg`. Meaning: memarg
    i32_load16_s = 0x2E,
    /// Index: `Memarg`. Meaning: memarg
    i32_load16_u = 0x2F,
    /// Index: `Memarg`. Meaning: memarg
    i64_load8_s = 0x30,
    /// Index: `Memarg`. Meaning: memarg
    i64_load8_u = 0x31,
    /// Index: `Memarg`. Meaning: memarg
    i64_load16_s = 0x32,
    /// Index: `Memarg`. Meaning: memarg
    i64_load16_u = 0x33,
    /// Index: `Memarg`. Meaning: memarg
    i64_load32_s = 0x34,
    /// Index: `Memarg`. Meaning: memarg
    i64_load32_u = 0x35,
    /// Index: `Memarg`. Meaning: memarg
    i32_store = 0x36,
    /// Index: `Memarg`. Meaning: memarg
    i64_store = 0x37,
    /// Index: `Memarg`. Meaning: memarg
    f32_store = 0x38,
    /// Index: `Memarg`. Meaning: memarg
    f64_store = 0x39,
    /// Index: `Memarg`. Meaning: memarg
    i32_store8 = 0x3A,
    /// Index: `Memarg`. Meaning: memarg
    i32_store16 = 0x3B,
    /// Index: `Memarg`. Meaning: memarg
    i64_store8 = 0x3C,
    /// Index: `Memarg`. Meaning: memarg
    i64_store16 = 0x3D,
    /// Index: `Memarg`. Meaning: memarg
    i64_store32 = 0x3E,
    memorysize = 0x3F,
    memorygrow = 0x40,
    /// Index: `u32`. Meaning: dataidx
    memoryinit = 0xDB,
    /// Index: `u32`. Meaning: dataidx
    datadrop = 0xDC,
    memorycopy = 0xDD,
    memoryfill = 0xDE,

    // NUMERIC INSTRUCTION
    /// Index: `i32`. Meaning: constant
    i32_const = 0x41,
    /// Index: `i64`. Meaning: constant
    i64_const = 0x42,
    /// Index: `f32`. Meaning: constant
    f32_const = 0x43,
    /// Index: `f64`. Meaning: constant
    f64_const = 0x44,

    i32_eqz = 0x45,
    i32_eq = 0x46,
    i32_ne = 0x47,
    i32_lt_s = 0x48,
    i32_lt_u = 0x49,
    i32_gt_s = 0x4A,
    i32_gt_u = 0x4B,
    i32_le_s = 0x4C,
    i32_le_u = 0x4D,
    i32_ge_s = 0x4E,
    i32_ge_u = 0x4F,

    i64_eqz = 0x50,
    i64_eq = 0x51,
    i64_ne = 0x52,
    i64_lt_s = 0x53,
    i64_lt_u = 0x54,
    i64_gt_s = 0x55,
    i64_gt_u = 0x56,
    i64_le_s = 0x57,
    i64_le_u = 0x58,
    i64_ge_s = 0x59,
    i64_ge_u = 0x5A,

    f32_eq = 0x5B,
    f32_ne = 0x5C,
    f32_lt = 0x5D,
    f32_gt = 0x5E,
    f32_le = 0x5F,
    f32_ge = 0x60,

    f64_eq = 0x61,
    f64_ne = 0x62,
    f64_lt = 0x63,
    f64_gt = 0x64,
    f64_le = 0x65,
    f64_ge = 0x66,

    i32_clz = 0x67,
    i32_ctz = 0x68,
    i32_popcnt = 0x69,
    i32_add = 0x6A,
    i32_sub = 0x6B,
    i32_mul = 0x6C,
    i32_div_s = 0x6D,
    i32_div_u = 0x6E,
    i32_rem_s = 0x6F,
    i32_rem_u = 0x70,
    i32_and = 0x71,
    i32_or = 0x72,
    i32_xor = 0x73,
    i32_shl = 0x74,
    i32_shr_s = 0x75,
    i32_shr_u = 0x76,
    i32_rotl = 0x77,
    i32_rotr = 0x78,

    i64_clz = 0x79,
    i64_ctz = 0x7A,
    i64_popcnt = 0x7B,
    i64_add = 0x7C,
    i64_sub = 0x7D,
    i64_mul = 0x7E,
    i64_div_s = 0x7F,
    i64_div_u = 0x80,
    i64_rem_s = 0x81,
    i64_rem_u = 0x82,
    i64_and = 0x83,
    i64_or = 0x84,
    i64_xor = 0x85,
    i64_shl = 0x86,
    i64_shr_s = 0x87,
    i64_shr_u = 0x88,
    i64_rotl = 0x89,
    i64_rotr = 0x8A,

    f32_abs = 0x8B,
    f32_neg = 0x8C,
    f32_ceil = 0x8D,
    f32_floor = 0x8E,
    f32_trunc = 0x8F,
    f32_nearest = 0x90,
    f32_sqrt = 0x91,
    f32_add = 0x92,
    f32_sub = 0x93,
    f32_mul = 0x94,
    f32_div = 0x95,
    f32_min = 0x96,
    f32_max = 0x97,
    f32_copysign = 0x98,

    f64_abs = 0x99,
    f64_neg = 0x9A,
    f64_ceil = 0x9B,
    f64_floor = 0x9C,
    f64_trunc = 0x9D,
    f64_nearest = 0x9E,
    f64_sqrt = 0x9F,
    f64_add = 0xA0,
    f64_sub = 0xA1,
    f64_mul = 0xA2,
    f64_div = 0xA3,
    f64_min = 0xA4,
    f64_max = 0xA5,
    f64_copysign = 0xA6,

    i32_wrap_i64 = 0xA7,
    i32_trunc_f32_s = 0xA8,
    i32_trunc_f32_u = 0xA9,
    i32_trunc_f64_s = 0xAA,
    i32_trunc_f64_u = 0xAB,
    i64_extend_i32_s = 0xAC,
    i64_extend_i32_u = 0xAD,
    i64_trunc_f32_s = 0xAE,
    i64_trunc_f32_u = 0xAF,
    i64_trunc_f64_s = 0xB0,
    i64_trunc_f64_u = 0xB1,
    f32_convert_i32_s = 0xB2,
    f32_convert_i32_u = 0xB3,
    f32_convert_i64_s = 0xB4,
    f32_convert_i64_u = 0xB5,
    f32_demote_f64 = 0xB6,
    f64_convert_i32_s = 0xB7,
    f64_convert_i32_u = 0xB8,
    f64_convert_i64_s = 0xB9,
    f64_convert_i64_u = 0xBA,
    f64_promote_f32 = 0xBB,
    i32_reinterpret_f32 = 0xBC,
    i64_reinterpret_f64 = 0xBD,
    f32_reinterpret_i32 = 0xBE,
    f64_reinterpret_i64 = 0xBF,

    i32_extend8_s = 0xC0,
    i32_extend16_s = 0xC1,
    i64_extend8_s = 0xC2,
    i64_extend16_s = 0xC3,
    i64_extend32_s = 0xC4,

    i32_trunc_sat_f32_s = 0xD3,
    i32_trunc_sat_f32_u = 0xD4,
    i32_trunc_sat_f64_s = 0xD5,
    i32_trunc_sat_f64_u = 0xD6,
    i64_trunc_sat_f32_s = 0xD7,
    i64_trunc_sat_f32_u = 0xD8,
    i64_trunc_sat_f64_s = 0xD9,
    i64_trunc_sat_f64_u = 0xDA,

    // VECTOR INSTRUCTIONS
    /// Index: `VectorIndex`. Meaning: See `VectorOpcode`
    vecinst = 0xFD,
};

const VectorOpcode = enum(u8) {
    v128_load = 0,
    v128_load8x8_s = 1,
    v128_load8x8_u = 2,
    v128_load16x4_s = 3,
    v128_load16x4_u = 4,
    v128_load32x2_s = 5,
    v128_load32x2_u = 6,
    v128_load8_splat = 7,
    v128_load16_splat = 8,
    v128_load32_splat = 9,
    v128_load64_splat = 10,
    v128_load32_zero = 92,
    v128_load64_zero = 93,
    v128_store = 11,
    v128_load8_lane = 84,
    v128_load16_lane = 85,
    v128_load32_lane = 86,
    v128_load64_lane = 87,
    v128_store8_lane = 88,
    v128_store16_lane = 89,
    v128_store32_lane = 90,
    v128_store64_lane = 91,

    /// TODO
    v128_const = 12,
    /// TODO
    i8x16_shuffle = 13,

    i8x16_extract_lane_s = 21,
    i8x16_extract_lane_u = 22,
    i8x16_replace_lane = 23,
    i16x8_extract_lane_s = 24,
    i16x8_extract_lane_u = 25,
    i16x8_replace_lane = 26,
    i32x4_extract_lane = 27,
    i32x4_replace_lane = 28,
    i64x2_extract_lane = 29,
    i64x2_replace_lane = 30,
    f32x4_extract_lane = 31,
    f32x4_replace_lane = 32,
    f64x2_extract_lane = 33,
    f64x2_replace_lane = 34,

    i8x16_swizzle = 14,
    i8x16_splat = 15,
    i16x8_splat = 16,
    i32x4_splat = 17,
    i64x2_splat = 18,
    f32x4_splat = 19,
    f64x2_splat = 20,

    i8x16_eq = 35,
    i8x16_ne = 36,
    i8x16_lt_s = 37,
    i8x16_lt_u = 38,
    i8x16_gt_s = 39,
    i8x16_gt_u = 40,
    i8x16_le_s = 41,
    i8x16_le_u = 42,
    i8x16_ge_s = 43,
    i8x16_ge_u = 44,

    i16x8_eq = 45,
    i16x8_ne = 46,
    i16x8_lt_s = 47,
    i16x8_lt_u = 48,
    i16x8_gt_s = 49,
    i16x8_gt_u = 50,
    i16x8_le_s = 51,
    i16x8_le_u = 52,
    i16x8_ge_s = 53,
    i16x8_ge_u = 54,

    i32x4_eq = 55,
    i32x4_ne = 56,
    i32x4_lt_s = 57,
    i32x4_lt_u = 58,
    i32x4_gt_s = 59,
    i32x4_gt_u = 60,
    i32x4_le_s = 61,
    i32x4_le_u = 62,
    i32x4_ge_s = 63,
    i32x4_ge_u = 64,

    i64x2_eq = 214,
    i64x2_ne = 215,
    i64x2_lt_s = 216,
    i64x2_gt_s = 217,
    i64x2_le_s = 218,
    i64x2_ge_s = 219,

    f32x4_eq = 65,
    f32x4_ne = 66,
    f32x4_lt = 67,
    f32x4_gt = 68,
    f32x4_le = 69,
    f32x4_ge = 70,

    f64x2_eq = 71,
    f64x2_ne = 72,
    f64x2_lt = 73,
    f64x2_gt = 74,
    f64x2_le = 75,
    f64x2_ge = 76,

    v128_not = 77,
    v128_and = 78,
    v128_andnot = 79,
    v128_or = 80,
    v128x_or = 81,
    v128_bitselect = 82,
    v128_any_true = 83,

    i8x16_abs = 96,
    i8x16_neg = 97,
    i8x16_popcnt = 98,
    i8x16_all_true = 99,
    i8x16_bitmask = 100,
    i8x16_narrow_i16x8_s = 101,
    i8x16_narrow_i16x8_u = 102,
    i8x16_shl = 107,
    i8x16_shr_s = 108,
    i8x16_shr_u = 109,
    i8x16_add = 110,
    i8x16_add_sat_s = 111,
    i8x16_add_sat_u = 112,
    i8x16_sub = 113,
    i8x16_sub_sat_s = 114,
    i8x16_sub_sat_u = 115,
    i8x16_min_s = 118,
    i8x16_min_u = 119,
    i8x16_max_s = 120,
    i8x16_max_u = 121,
    i8x16_avgr_u = 123,

    i16x8_extadd_pairwise_i8x16_s = 124,
    i16x8_extadd_pairwise_i8x16_u = 125,
    i16x8_abs = 128,
    i16x8_neg = 129,
    i16x8_q15mulr_sat_s = 130,
    i16x8_all_true = 131,
    i16x8_bitmask = 132,
    i16x8_narrow_i32x4_s = 133,
    i16x8_narrow_i32x4_u = 134,
    i16x8_extend_low_i8x16_s = 135,
    i16x8_extend_high_i8x16_s = 136,
    i16x8_extend_low_i8x16_u = 137,
    i16x8_extend_high_i8x16_u = 138,
    i16x8_shl = 139,
    i16x8_shr_s = 140,
    i16x8_shr_u = 141,
    i16x8_add = 142,
    i16x8_add_sat_s = 143,
    i16x8_add_sat_u = 144,
    i16x8_sub = 145,
    i16x8_sub_sat_s = 146,
    i16x8_sub_sat_u = 147,
    i16x8_mul = 149,
    i16x8_min_s = 150,
    i16x8_min_u = 151,
    i16x8_max_s = 152,
    i16x8_max_u = 153,
    i16x8_avgr_u = 155,
    i16x8_extmul_low_i8x16_s = 156,
    i16x8_extmul_high_i8x16_s = 157,
    i16x8_extmul_low_i8x16_u = 158,
    i16x8_extmul_high_u8x16_u = 159,

    i32x4_extadd_pairwise_i16x8_s = 126,
    i32x4_extadd_pairwise_i16x8_u = 127,
    i32x4_abs = 160,
    i32x4_neg = 161,
    i32x4_all_true = 163,
    i32x4_bitmask = 164,
    i32x4_extend_low_i16x8_s = 167,
    i32x4_extend_high_i16x8_s = 168,
    i32x4_extend_low_i16x8_u = 169,
    i32x4_extend_high_i16x8_u = 170,
    i32x4_shl = 171,
    i32x4_shr_s = 172,
    i32x4_shr_u = 173,
    i32x4_add = 174,
    i32x4_sib = 177,
    i32x4_mul = 181,
    i32x4_min_s = 182,
    i32x4_min_u = 183,
    i32x4_max_s = 184,
    i32x4_max_u = 185,
    i32x4_dot_i16x8_s = 186,
    i32x4_extmul_low_i16x8_s = 188,
    i32x4_extmul_high_i16x8_s = 189,
    i32x4_extmul_los_i16x8_u = 190,
    i32x4_extmul_high_i16x8_u = 191,

    i64x2_abs = 192,
    i64x2_neg = 193,
    i64x2_all_true = 195,
    i64x2_bitmask = 196,
    i64x2_extend_low_i32x4_s = 199,
    i64x2_extend_high_i32x4_s = 200,
    i64x2_extend_low_i32x4_u = 201,
    i64x2_extend_high_i32x4_u = 202,
    i64x2_shl = 203,
    i64x2_shr_s = 204,
    i64x2_shr_u = 205,
    i64x2_add = 206,
    i64x2_sub = 209,
    i64x2_mul = 213,
    i64x2_extmul_low_i32x4_s = 220,
    i64x2_extmul_high_i32x4_s = 221,
    i64x2_extmul_low_i32x4_u = 222,
    i64x2_extmul_high_i32x4_u = 223,

    f32x4_ceil = 103,
    f32x4_floor = 104,
    f32x4_trunc = 105,
    f32x4_nearest = 106,
    f32x4_abs = 224,
    f32x4_neg = 225,
    f32x4_sqrt = 227,
    f32x4_add = 228,
    f32x4_sub = 229,
    f32x4_mul = 230,
    f32x4_div = 231,
    f32x4_min = 232,
    f32x4_max = 233,
    f32x4_pmin = 234,
    f32x4_pmax = 235,

    f64x2_ceil = 116,
    f64x2_floor = 117,
    f64x2_trunc = 122,
    f64x2_nearest = 148,
    f64x2_abs = 236,
    f64x2_neg = 237,
    f64x2_sqrt = 239,
    f64x2_add = 240,
    f64x2_sub = 241,
    f64x2_mul = 242,
    f64x2_div = 243,
    f64x2_min = 244,
    f64x2_max = 245,
    f64x2_pmin = 246,
    f64x2_pmax = 247,

    i32x4_trunc_sat_f32x4_s = 248,
    i32x4_trunc_sat_f32x4_u = 249,
    f32x4_convert_i32x4_s = 250,
    f32x4_convert_i32x4_u = 251,
    i32x4_trunc_sat_f64x2_s_zero = 252,
    i32x4_trunc_sat_f64x2_u_zero = 253,
    f64x2_convert_low_i32x4_s = 254,
    f64x2_convert_low_i32x4_u = 255,
    f32x4_demote_f64x2_zero = 94,
    f64x2_promote_low_f32x4 = 95,
};

const IRParserState = struct {
    parser: *Parser,
    allocator: Allocator,

    // branches: std.AutoHashMapUnmanaged(u32, u32),
    branches: std.ArrayListUnmanaged( struct { pc: u32, index: u32, table: bool } ),
    br_table_vectors: std.ArrayListUnmanaged(u32),

    opcodes: std.ArrayListUnmanaged(Opcode),
    indices: std.ArrayListUnmanaged(Index),

    fn parseFunction(self: *IRParserState) !void {
        while (true) {
            const op = self.parser.peek() orelse return Parser.Error.unterminated_wasm;
            if (op == 0x0B) {
                _ = try self.parser.readByte();
                break;
            } else {
                try self.parseExpression();
            }
        }
    }

    fn parseExpression(self: *IRParserState) Parser.Error!void {
        const b = try self.parser.readByte();
        try switch (b) {
            0x00 => self.push(@enumFromInt(b), .{ .u64 = 0 }),
            0x01 => self.push(@enumFromInt(b), .{ .u64 = 0 }),
            0x02...0x03 => self.parseBlock(b),
            0x04 => self.parseIf(),
            0x0C...0x0D => self.parseBranch(b),
            0x0E => self.parseBrTable(b),
            0x0F => self.push(@enumFromInt(b), .{ .u64 = 0 }),
            0x10 => self.push(@enumFromInt(b), .{ .u32 = try self.parser.readU32() }),
            0x11 => self.push(@enumFromInt(b), .{ .indirect = .{ .y = try self.parser.readU32(), .x = try self.parser.readU32() } }),
            0xD0 => self.push(@enumFromInt(b), .{ .reftype = try self.parser.parseReftype() }),
            0xD1 => self.push(@enumFromInt(b), .{ .u64 = 0 }),
            0xD2 => self.push(@enumFromInt(b), .{ .u32 = try self.parser.readU32() }),
            0x1A...0x1C => self.parseParametric(b),
            0x20...0x24 => self.push(@enumFromInt(b), .{ .u32 = try self.parser.readU32() }),
            0x25...0x26 => self.push(@enumFromInt(b), .{ .u32 = try self.parser.readU32() }),
            0x28...0x3E => self.push(@enumFromInt(b), .{ .memarg = try self.parseMemarg() }),
            0x3F...0x40 => self.parseMemsizeorgrow(b),
            0x41...0x44 => self.parseConst(b),
            0x45...0xC4 => self.push(@enumFromInt(b), .{ .u64 = 0 }),
            0xFD => self.parseVector(),
            0xFC => self.parseMisc(),
            else => {
                std.log.err("Invalid instruction {x} at position {d}\n", .{ b, self.parser.reader.seek });
                return Parser.Error.invalid_instruction;
            },
        };
    }

    fn push(self: *IRParserState, opcode: Opcode, index: Index) !void {
        try self.opcodes.append(self.allocator, opcode);
        try self.indices.append(self.allocator, index);
    }

    fn parseMemarg(self: *IRParserState) !Memarg {
        return .{
            // TODO: assert this intCast does not fail
            .alignment = @intCast(try self.parser.readU32()),
            .offset = try self.parser.readU32(),
        };
    }

    fn parseMemsizeorgrow(self: *IRParserState, b: u8) !void {
        if (try self.parser.readByte() != 0x00) return Parser.Error.invalid_instruction;
        try self.push(@enumFromInt(b), .{ .u64 = 0 });
    }

    fn parseConst(self: *IRParserState, b: u8) !void {
        try switch (b) {
            0x41 => self.push(.i32_const, .{ .i32 = try self.parser.readI32() }),
            0x42 => self.push(.i64_const, .{ .i64 = try self.parser.readI64() }),
            0x43 => self.push(.f32_const, .{ .f32 = try self.parser.readF32() }),
            0x44 => self.push(.f64_const, .{ .f64 = try self.parser.readF64() }),
            else => unreachable,
        };
    }

    fn parseMisc(self: *IRParserState) !void {
        const n = try self.parser.readU32();
        try switch (n) {
            0...7 => self.push(@enumFromInt(0xD3 + @as(u8, @intCast(n))), .{ .u64 = 0 }),
            8...9 => @panic("UNIMPLEMENTED"),
            10...11 => {
                try self.push(@enumFromInt(0xD3 + @as(u8, @intCast(n))), .{ .u64 = 0 });
                _ = try self.parser.readByte();
                if (n == 10) {
                    _ = try self.parser.readByte();
                }
            },
            12...17 => @panic("UNIMPLEMENTED"),
            else => {
                std.log.err("Invalid misc instruction {d} at position {d}\n", .{ n, self.parser.reader.seek });
                return Parser.Error.invalid_instruction;
            },
        };
    }

    fn parseBlockType(self: *IRParserState) !void {
        const b = self.parser.peek() orelse return Parser.Error.unterminated_wasm;
        switch (b) {
            0x40 => _ = try self.parser.readByte(),
            0x6F...0x70, 0x7B...0x7F => _ = try self.parser.readByte(),
            else => _ = try self.parser.readI33(),
        }
    }

    fn parseBlock(self: *IRParserState, b: u8) !void {
        // TODO: Should we do something with this?
        _ = try self.parseBlockType();
        const start: u32 = @intCast(self.opcodes.items.len);
        while (true) {
            const op = self.parser.peek() orelse return Parser.Error.unterminated_wasm;
            if (op == 0x0B) {
                _ = try self.parser.readByte();
                break;
            } else {
                try self.parseExpression();
            }
        }
        const end: u32 = @intCast(self.opcodes.items.len);
        const jump_addr: u32 = switch (b) {
            0x02 => end,
            0x03 => start,
            else => unreachable,
        };
        try self.fix_branches_for_block(start, end, jump_addr);
    }

    fn parseGlobal(self: *IRParserState) !void {
        while (true) {
            const op = self.parser.peek() orelse return Parser.Error.unterminated_wasm;
            if (op == 0x0B) {
                _ = try self.parser.readByte();
                break;
            } else {
                try self.parseExpression();
            }
        }
    }

    fn parseIf(self: *IRParserState) !void {
        // TODO: Should we do something with this?
        _ = try self.parseBlockType();

        try self.push(.br_if, .{ .u32 = @intCast(self.opcodes.items.len + 2) });
        const start: u32 = @intCast(self.opcodes.items.len);
        try self.push(.br, .{ .u32 = 0 });

        var else_addr: u32 = 0;
        while (true) {
            const op = self.parser.peek() orelse return Parser.Error.unterminated_wasm;

            if (op == 0x05) {
                if (else_addr != 0) return Parser.Error.double_else;
                _ = try self.parser.readByte();
                else_addr = @intCast(self.opcodes.items.len);
                try self.push(.br, .{ .u32 = 0 });
            } else if (op == 0x0B) {
                _ = try self.parser.readByte();
                break;
            } else {
                try self.parseExpression();
            }
        }
        const end: u32 = @intCast(self.opcodes.items.len);

        if (else_addr > 0) {
            self.indices.items[start].u32 = else_addr + 1;
            self.indices.items[else_addr].u32 = end;
        } else {
            self.indices.items[start].u32 = end;
        }

        try self.fix_branches_for_block(start, end, end);
    }

    fn parseParametric(self: *IRParserState, b: u8) !void {
        try switch (b) {
            0x1A...0x1B => self.push(@enumFromInt(b), .{ .u64 = 0 }),
            0x1C => @panic("UNIMPLEMENTED"),
            else => return Parser.Error.invalid_instruction,
        };
    }

    fn fix_branches_for_block(self: *IRParserState, start: u32, end: u32, jump_addr: u32) !void {
        var todel: std.ArrayListUnmanaged(u32) = .{};
        defer todel.deinit(self.allocator);

        for (self.branches.items, 0..) |branch, idx| {
            if (start <= branch.pc and branch.pc < end) {
                const ptr = if (branch.table) &self.br_table_vectors.items[branch.index] else &self.indices.items[branch.index].u32;
                if (ptr.* == 0) {
                    ptr.* = jump_addr;
                    try todel.append(self.allocator, @intCast(idx));
                } else {
                    ptr.* -= 1;
                }
            }
        }

        // TODO(ernesto): need better way of deleting from the array (this looks ugly)
        std.mem.sort(u32, todel.items, {}, comptime std.sort.desc(u32));
        for (todel.items) |d| {
            // TODO: Do we need to assert this is true?
            _ = self.branches.swapRemove(d);
        }
    }

    fn parseBranch(self: *IRParserState, b: u8) !void {
        const idx = try self.parser.readU32();
        try self.branches.append(self.allocator, .{ .pc = @intCast(self.opcodes.items.len), .index = @intCast(self.indices.items.len), .table = false });
        try self.push(@enumFromInt(b), .{ .u32 = idx });
    }

    fn parseBrTable(self: *IRParserState, b: u8) !void {
        const idxs = try self.parser.parseVectorU32();
        const idxN = try self.parser.readU32();
        const table_vectors_len = self.br_table_vectors.items.len;
        try self.br_table_vectors.appendSlice(self.allocator, idxs);
        try self.br_table_vectors.append(self.allocator, idxN);
        for (0..idxs.len+1) |i| {
            try self.branches.append(self.allocator, .{ .pc = @intCast(self.opcodes.items.len), .index = @intCast(table_vectors_len + i), .table = true });
        }
        try self.push(@enumFromInt(b), .{ .indirect = .{ .x = @intCast(table_vectors_len), .y = @intCast(idxs.len) }});
    }

    fn parseVector(self: *IRParserState) !void {
        const n = try self.parser.readU32();
        try switch (n) {
            0...10, 92...93, 11 => self.push(.vecinst, .{ .vector = .{ .opcode = @enumFromInt(n), .memarg = try self.parseMemarg(), .laneidx = 0 } }),
            84...91 => self.push(.vecinst, .{ .vector = .{ .opcode = @enumFromInt(n), .memarg = try self.parseMemarg(), .laneidx = try self.parser.readByte() } }),
            12 => {},
            13 => {},
            21...34 => self.push(.vecinst, .{ .vector = .{ .opcode = @enumFromInt(n), .memarg = .{ .alignment = 0, .offset = 0 }, .laneidx = try self.parser.readByte() } }),
            // Yes, there are this random gaps in wasm vector instructions don't ask me how I know...
            14...20, 35...83, 94...153, 155...161, 163...164, 167...174, 177, 181...186, 188...193, 195...196, 199...206, 209, 213...225, 227...237, 239...255 => {
                try self.push(.vecinst, .{ .vector = .{ .opcode = @enumFromInt(n), .memarg = .{ .alignment = 0, .offset = 0 }, .laneidx = 0 } });
            },
            else => {
                std.log.err("Invalid vector instruction {d} at position {d}\n", .{ n, self.parser.reader.seek });
                return Parser.Error.invalid_instruction;
            },
        };
    }
};

pub fn parse(parser: *Parser) !IR {
    var state = IRParserState{
        .br_table_vectors = .{},
        .opcodes = .{},
        .indices = .{},
        .branches = .{},
        .parser = parser,
        .allocator = parser.allocator,
    };
    try state.parseFunction();
    if (state.branches.items.len != 0) return Parser.Error.unresolved_branch;
    return .{
        .opcodes = try state.opcodes.toOwnedSlice(state.allocator),
        .indices = try state.indices.toOwnedSlice(state.allocator),
        .select_valtypes = &.{},
        .br_table_vectors = state.br_table_vectors.items
    };
}

pub fn parseGlobalExpr(parser: *Parser) !IR {
    var state = IRParserState{
        .br_table_vectors = .{},
        .opcodes = .{},
        .indices = .{},
        .branches = .{},
        .parser = parser,
        .allocator = parser.allocator,
    };
    try state.parseGlobal();
    return .{
        .opcodes = try state.opcodes.toOwnedSlice(state.allocator),
        .indices = try state.indices.toOwnedSlice(state.allocator),
        .select_valtypes = &.{},
        .br_table_vectors = state.br_table_vectors.items
    };
}

pub fn parseSingleExpr(parser: *Parser) !IR {
    var state = IRParserState{
        .br_table_vectors = .{},
        .opcodes = .{},
        .indices = .{},
        .branches = .{},
        .parser = parser,
        .allocator = parser.allocator,
    };
    try state.parseExpression();
    return .{
        .opcodes = try state.opcodes.toOwnedSlice(state.allocator),
        .indices = try state.indices.toOwnedSlice(state.allocator),
        .select_valtypes = &.{},
        .br_table_vectors = state.br_table_vectors.items
    };
}
