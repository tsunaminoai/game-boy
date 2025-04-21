const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;

const Z80 = @This();

getAddress: *const fn (*anyopaque, u16) u8,
putAddress: *const fn (*anyopaque, u16, u8) void,
checkForInterupts: *const fn (*anyopaque) void,

PC: u16 = 0,
Registers: struct {
    A: u8 = 0x01,
    B: u8 = 0,
    C: u8 = 0x13,
    D: u8 = 0,
    E: u8 = 0xD8,
    HL: u16 = 0x014D,
    SP: u16 = 0xFFFE,
} = .{},
Flags: struct {
    Z: u1 = 0,
    N: u1 = 0,
    H: u1 = 0,
    C: u1 = 0,
} = .{},

IME: u8 = 0,
interuptCall: u16 = 0,
stopped: bool = false,

timerDivider: f32 = 0.0,
timerCounter: f32 = 0.0,
timerCounterFreq: f32 = 0.0,

pub fn stop(self: *Z80) void {
    self.stopped = true;
    self.timerDivider = 0.0;
}

pub fn cont(self: *Z80) void {
    self.stopped = false;
}

pub fn interupt(self: *Z80, address: u16) void {
    self.cont();
    if (self.IME > 0)
        self.interuptCall = address;
}

pub fn getAddress16(self: *Z80, address: u16) u16 {
    return (self.getAddress(self, address + 1) << 8) + self.getAddress(self, address);
}
pub fn putAddress16(self: *Z80, address: u16, value: u16) void {
    self.putAddress(self, (address + 1), @as(u8, @intCast(value >> 8)));
    self.putAddress(self, (address), @as(u8, @intCast((value & 0x00FF) >> 8)));
}
pub fn immediate16(self: *Z80) u16 {
    return (@as(u16, self.getAddress(self, self.PC + 1)) << 8) + self.getAddress(self, self.PC);
}
pub fn immediate8(self: *Z80) u8 {
    return self.getAddress(self, self.PC);
}
pub fn signImmediate8(self: *Z80) i8 {
    return @as(i8, self.getAddress(self, self.PC));
}
pub fn increment8(self: *Z80, value: u8) u8 {
    self.Flags.N = 0;
    self.Flags.H = 0;
    if (value >= 0xFF) {
        self.Flags.Z = 1;
        self.Flags.H = 1;
        return 0;
    }
    self.Flags.Z = 0;
    if (@mod(value, 16) == 15) self.Flags.H = 1;

    return @mod(value + 1, 256);
}
pub fn decrement8(self: *Z80, value: u8) u8 {
    self.Flags.N = 1;
    self.Flags.H = 0;
    if (value == 0) {
        self.Flags.Z = 0;
        self.Flags.H = 1;
        return 0xFF;
    } else if (value == 1) {
        self.Flags.Z = 1;
        return 0;
    }
    self.Flags.Z = 0;
    if (@mod(value, 16) == 0) self.Flags.H = 1;

    return value -| 1;
}
pub fn add8(self: *Z80, a: u8, b: u8) u8 {
    self.Flags.N = 0;

    self.Flags.C = if (a + b >= 0x100) 1 else 0;
    self.Flags.Z = if (@mod(a + b, 0x100) == 0) 1 else 0;
    self.Flags.H = if (@mod(a, 0x10) + @mod(b, 0x10) >= 0x10) 1 else 0;
    return @mod(a + b, 0x100);
}
pub fn adc8(self: *Z80, a: u8, b: u8) u8 {
    var c: u8 = 0;

    c = self.Flags.C;
    self.Flags.N = 0;

    self.Flags.C = if (a + b + c >= 0x100) 1 else 0;
    self.Flags.Z = if (@mod(a + b + c, 0x100) == 0) 1 else 0;
    self.Flags.H = if (@mod(a, 0x10) + @mod(b, 0x10) + c >= 0x10) 1 else 0;
    return @mod(a + b + c, 0x100);
}

pub fn add16(self: *Z80, a: u16, b: u16) u16 {
    const A = a & 0xFFFF;
    const B = b & 0xFFFF;

    self.Flags.N = 0;

    self.Flags.C = if (A + B > 0xFFFF) 1 else 0;
    self.Flags.Z = if (@mod(A + B, 0xFFFF) == 0) 1 else 0;
    self.Flags.H = if (@mod(A, 0xFFFF) + @mod(B, 0xFFFF) > 0xFFFF) 1 else 0;
    return @mod(A + B, 0xFFFF);
}
pub fn add16_8(self: *Z80, a: u16, b: u8) u16 {
    const A = a & 0xFFFF;
    const B = b & 0xFFFF;

    self.Flags.N = 0;

    self.Flags.C = if ((A & 0xFF) + (B & 0xFF) > 0xFF) 1 else 0;
    self.Flags.H = if ((A & 0x0F) + (B & 0x0F) > 0x0F) 1 else 0;

    return (A + B) & 0xFFFF;
}
pub fn sub8(self: *Z80, a: u8, b: u8) u8 {
    self.Flags.N = 1;

    self.Flags.C = if (a - b < 0) 1 else 0;
    self.Flags.Z = if (a - b == 0) 1 else 0;
    self.Flags.H = if (@mod(a, 0x10) - @mod(b, 0x10) < 0) 1 else 0;

    return @mod(a - b, 0x100);
}
pub fn sbc8(self: *Z80, a: u8, b: u8) u8 {
    var c: u8 = 0;

    c = self.Flags.C;
    self.Flags.N = 1;

    self.Flags.C = if (a - b - c < 0) 1 else 0;
    self.Flags.Z = if (a - b - c == 0) 1 else 0;
    self.Flags.H = if (@mod(a, 0x10) - @mod(b, 0x10) - c < 0) 1 else 0;

    return @mod(a - b - c, 0x100);
}
pub fn and8(self: *Z80, a: u8, b: u8) u8 {
    self.Flags.N = 0;
    self.Flags.H = 1;
    self.Flags.C = 0;
    self.Flags.Z = if (a & b == 0) 1 else 0;

    return a & b;
}
pub fn xor8(self: *Z80, a: u8, b: u8) u8 {
    self.Flags.N = 0;
    self.Flags.H = 0;
    self.Flags.C = 0;
    self.Flags.Z = if (a ^ b == 0) 1 else 0;

    return a ^ b;
}
pub fn or8(self: *Z80, a: u8, b: u8) u8 {
    self.Flags.N = 0;
    self.Flags.H = 0;
    self.Flags.C = 0;
    self.Flags.Z = if (a | b == 0) 1 else 0;

    return a | b;
}
pub fn call(self: *Z80, address: u16) void {
    self.Registers.SP -|= 2;
    self.putAddress16(self.Registers.SP, self.PC);
    self.PC = address;
    // self.Registers.SP = @mod((self.Registers.SP + 0x10000), 0x10000);
}
pub fn ret(self: *Z80) void {
    self.PC = self.getAddress16(self.Registers.SP);
    self.Registers.SP += 2;
    self.Registers.SP = @mod(self.Registers.SP, 0x10000);
}
pub fn setH(self: *Z80, value: u8) void {
    self.Registers.HL = (self.Registers.HL & 0xFF) | (value << 8);
}
pub fn setL(self: *Z80, value: u8) void {
    self.Registers.HL = (self.Registers.HL & 0xFF00) | value;
}

const Instruction = *const fn (*Z80) usize;
const Instructions = &[_]Instruction{
    struct {
        fn inst00(self: *Z80) usize {
            // NOP
            self.PC += 1;
            return 4;
        }
    }.inst00,
    struct {
        fn inst01(self: *Z80) usize {
            // LD BC, d16
            self.PC += 1;
            const data = self.immediate16();
            self.Registers.B = @as(u8, @intCast(data >> 8));
            self.Registers.C = @as(u8, @intCast(data & 0xFF));
            self.PC += 2;
            return 12;
        }
    }.inst01,
    struct {
        fn inst02(self: *Z80) usize {
            // LD (BC), A
            self.putAddress16(
                (@as(u16, @intCast(self.Registers.B)) << 8) | self.Registers.C,
                self.Registers.A,
            );
            self.PC += 1;
            return 8;
        }
    }.inst02,
    struct {
        fn inst03(self: *Z80) usize {
            // INC BC
            self.Registers.C +%= 1;
            if (self.Registers.C == 0) {
                self.Registers.B +%= 1;
            }
            self.PC += 1;
            return 8;
        }
    }.inst03,
    // inst03,
    // inst04,
    // inst05,
    // inst06,
    // inst07,
    // inst08,
    // inst09,
    // inst0A,
    // inst0B,
    // inst0C,
    // inst0D,
    // inst0E,
    // inst0F,

    // CB instructions
};

fn cbInstuctions(self: *Z80, code: u8) void {
    var data: u16 = 0;
    var data_8: u8 = 0;
    var op: u8 = 0;

    data = switch (@mod(code, 8)) {
        0 => self.Registers.B,
        1 => self.Registers.C,
        2 => self.Registers.D,
        3 => self.Registers.E,
        4 => self.Registers.HL >> 8,
        5 => self.Registers.HL & 0xFF,
        6 => self.getAddress(self, self.Registers.HL),
        7 => self.Registers.A,
        else => unreachable,
    };
    data_8 = @as(u8, @intCast(data));
    op = @divExact(code, 8);
    switch (op) {
        0 => { // rotate left
            if (data >= 128) {
                data = @mod(data << 1, 256) + 1;
                self.Flags.C = 1;
            } else {
                data = @mod(data << 1, 256);
                self.Flags.C = 0;
            }
        },
        1 => { // rotate right
            if (data & 1 == 1) {
                data = @as(u8, @intCast(data >> 1)) + 128;
                self.Flags.C = 1;
            } else {
                data = data >> 1;
                self.Flags.C = 0;
            }
        },
        2 => { //rotate left through carry
            if (data >= 128) {
                data = @mod(data << 1, 256) + self.Flags.C;
                self.Flags.C = 1;
            } else {
                data = @mod(data << 1, 256) + self.Flags.C;
                self.Flags.C = 0;
            }
        },
        3 => { //rotate right through carry
            if (data & 1 == 1) {
                data = @as(u8, @intCast(data >> 1)) + 128 + @as(u8, @intCast(self.Flags.C)) * 128;
                self.Flags.C = 1;
            } else {
                data = @as(u8, @intCast(data >> 1)) + @as(u8, @intCast(self.Flags.C)) * 128;
                self.Flags.C = 0;
            }
        },
        4 => { //shift left arithmetic
            self.Flags.C = if (data >= 128) 1 else 0;
            data = @mod(data << 1, 256);
        },
        5 => { //shift right arithmetic
            self.Flags.C = if (data & 1 == 1) 1 else 0;
            data = @as(u8, @intCast(data >> 1)) + @as(u8, (if (data >= 128) 128 else 0));
        },
        6 => { // swap
            self.Flags.C = 0;
            data = @mod(data << 4, 256) + @mod(data >> 4, 256);
        },
        7 => { // shift right logical
            self.Flags.C = if (data & 1 == 1) 1 else 0;
            data = data >> 1;
        },
        8...15 => { // bit test
            self.Flags.N = 0;
            self.Flags.H = 1;
            const shifted: u8 = @as(u8, 1) << @as(u3, @truncate(op - 8));
            self.Flags.Z = if (@as(u8, @intCast(data)) & shifted == 0) 1 else 0;
        },
        16...23 => { // bit reset
            data = data & ~(@as(u8, 1) << @as(u3, @truncate(op - 16)));
        },
        24...31 => { // bit set
            data = data | (@as(u8, 1) << @as(u3, @truncate(op - 24)));
        },
        else => {},
    }
    if (data_8 != data) {
        switch (@mod(code, 8)) {
            0 => self.Registers.B = @as(u8, @truncate(data & 0xFF)),
            1 => self.Registers.C = @as(u8, @truncate(data >> 8)),
            2 => self.Registers.D = @as(u8, @truncate(data & 0xFF)),
            3 => self.Registers.E = @as(u8, @truncate(data >> 8)),
            4 => self.Registers.HL = self.Registers.HL | @as(u8, @truncate(data & 0xFF)),
            5 => self.Registers.HL = self.Registers.HL | @as(u8, @truncate(data >> 8)),
            6 => self.putAddress(self, self.Registers.HL, @as(u8, @truncate(data & 0xFF))),
            7 => self.Registers.A = @as(u8, @truncate(data & 0xFF)),
            else => unreachable,
        }
    }
}

pub fn execute(self: *Z80, n: usize) !void {
    var i = n;
    var inst: u8 = 0;
    var len: usize = 0;

    while (i > 0) {
        if (self.IME == 1) {
            if (self.interuptCall > 0) {
                self.IME = 0;
                self.call(self.interuptCall);
                self.interuptCall = 0;
            }
        }
        if (self.stopped) {
            len = 1;
            i -= 1;
        } else {
            inst = self.getAddress(self, self.PC);
            len = blk: switch (inst) {
                0x00...0xCA => {
                    std.debug.print("Running Instruction {X:0>2}\n", .{inst});
                    const instruction = Instructions[inst];
                    const l = instruction(self);
                    self.PC += 1;
                    break :blk l;
                },
                0xCB => {
                    inst = self.getAddress(self, self.PC + 1);
                    cbInstuctions(self, inst);
                    self.PC += 2;
                    return;
                },
                else => unreachable,
            };
        }
        i -|= len;
    }
}
test {
    var z80 = Z80{
        .getAddress = struct {
            pub fn fun(_: *anyopaque, address: u16) u8 {
                return @as(u8, @intCast(address & 0xFF));
            }
        }.fun,
        .putAddress = struct {
            pub fn fun(_: *anyopaque, _: u16, _: u8) void {}
        }.fun,
        .checkForInterupts = struct {
            pub fn fun(_: *anyopaque) void {}
        }.fun,
    };
    z80.Registers.B = 0x01;
    z80.Registers.C = 0x02;
    z80.putAddress16(0x0, 0x0003);
    try z80.execute(1);
    try tst.expectEqual( 0x01, z80.Registers.B);
    try tst.expectEqual( 0x03, z80.Registers.C);
}
