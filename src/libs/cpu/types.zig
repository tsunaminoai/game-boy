pub const RegisterName = enum(u16) {
    // zig fmt: off
    A, F, B, C, D, E, H, L, //"8 bit" registers
    AF, BC, DE, HL,         //16 bit registers
    SP,                     //Special 16 bit registers
    // zig fmt: on
};

pub const Flag = enum(u4) {
    Zero,
    Subtraction,
    HalfCarry,
    Carry,
};
