const std = @import("std");

pub const RegisterName = enum(u16) {
    // zig fmt: off
    B, C, D, E, H, L, HL, A,
    AF, BC, DE,
    SP, F
    // zig fmt: on
};

pub const Flags = packed struct(u8) {
    zero: bool = false,
    subtraction: bool = false,
    halfCarry: bool = false,
    carry: bool = false,
    _padding: u4 = 0,

    comptime {
        std.debug.assert(@sizeOf(@This()) == @sizeOf(u8));
        std.debug.assert(@bitSizeOf(@This()) == @bitSizeOf(u8));
    }
};

pub const MathOperations = enum {
    add,
    subtract,
    logicalAnd,
    logicalOr,
    logicalXor,
    cmp,
};
