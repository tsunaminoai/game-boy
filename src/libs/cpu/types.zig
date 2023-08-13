const std = @import("std");

pub const RegisterName = enum(u16) {
    // zig fmt: off
    A, F, B, C, D, E, H, L, //"8 bit" registers
    AF, BC, DE, HL,         //16 bit registers
    SP,                     //Special 16 bit registers
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
