pub const RegisterName = enum(u8) {
    // zig fmt: off
    AF, BC, DE, HL,         //16bit "combined" registers
    A, F, B, C, D, E, H, L, //"8bit" registers
    SP                  //16bit special registers
    // zig fmt: on
};

pub const Flag = enum(u4) {
    Zero,
    Subtraction,
    HalfCarry,
    Carry,
};
