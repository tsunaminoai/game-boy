const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;

const Z80 = @This();

getAddress: *const fn (*anyopaque, u16) u8,
putAddress: *const fn (*anyopaque, u16, u8) void,
checkForInterupts: *const fn (*anyopaque) void,

system: *anyopaque,

PC: u16 = 0,
registers: Registers = .{},
flags: Flags = .{},

IME: u8 = 0,
interuptCall: u16 = 0,
stopped: bool = false,

timerDivider: f32 = 0.0,
timerCounter: f32 = 0.0,
timerCounterFreq: f32 = 0.0,
const Registers = struct {
    A: u8 = 0x01,
    B: u8 = 0,
    C: u8 = 0x13,
    D: u8 = 0,
    E: u8 = 0xD8,
    HL: u16 = 0x014D,
    SP: u16 = 0xFFFE,
    F: u8 = 0x0,

    const Kind = enum { A, B, C, D, E, HL, SP, AF, BC, DE, H, L };
    pub fn get8(self: Registers, k: Kind) u8 {
        return switch (k) {
            .AF, .BC, .DE, .HL => unreachable,
            .H => @truncate(self.HL >> 8),
            .L => @truncate(self.HL & 0xFF),
            inline else => |key| @truncate(@field(self, @tagName(key))),
        };
    }
    pub fn get(self: Registers, k: Kind) u16 {
        return switch (k) {
            .AF => @as(u16, self.A) << 8,
            .BC => (@as(u16, self.B) << 8) | self.C,
            .DE => (@as(u16, self.D) << 8) | self.E,
            .HL => self.HL,
            inline else => self.get8(k),
        };
    }
    pub fn set(self: *Registers, k: Kind, value: u16) void {
        switch (k) {
            .AF => self.A = @truncate(value >> 8),
            .BC => {
                self.B = @truncate(value >> 8);
                self.C = @truncate(value);
            },
            .DE => {
                self.D = @truncate(value >> 8);
                self.E = @truncate(value);
            },
            .HL => self.HL = value,
            .SP => self.SP = value,
            else => |half| {
                switch (half) {
                    .A => self.A = @truncate(value),
                    .B => self.B = @truncate(value),
                    .C => self.C = @truncate(value),
                    .D => self.D = @truncate(value),
                    .E => self.E = @truncate(value),
                    .H => self.HL |= value << 8,
                    .L => self.HL |= value & 0xFF,
                    else => unreachable,
                }
            },
        }
    }
};
test {
    var reg = Registers{};

    reg.set(.D, 0xBE);
    reg.set(.H, 0xFF);
    try tst.expectEqual(0x13, reg.get8(.C));
    try tst.expectEqual(0xBE, reg.get8(.D));
    try tst.expectEqual(0xFF, reg.get8(.H));
    try tst.expectEqual(0xFF4D, reg.get(.HL));
}
const Flags = packed struct(u8) {
    Z: u1 = 0,
    N: u1 = 0,
    H: u1 = 0,
    C: u1 = 0,
    _: u4 = 0,
    pub fn check(self: Flags, cc: enum { nz, nc, z }) u1 {
        const t: u8 = if (cc == .nz or cc == .nz) 0 else 1;
        const mask: u8 = if (cc == .nz or cc == .z) 0x80 else 0x10;

        return @intFromBool(0 < (t & @as(u8, @bitCast(self)) & mask) | (~t & ~(@as(u8, @bitCast(self)) & mask)));
    }
};
test {
    var f = Flags{};
    f.Z = 1;
    try tst.expectEqual(1, f.check(.z));
}

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
    return (self.getAddress(self.system, address + 1) << 8) + self.getAddress(self.system, address);
}
pub fn putAddress16(self: *Z80, address: u16, value: u16) void {
    self.putAddress(self.system, (address + 1), @as(u8, @intCast(value >> 8)));
    self.putAddress(self.system, (address), @as(u8, @intCast((value & 0x00FF) >> 8)));
}
pub fn immediate16(self: *Z80) u16 {
    return (@as(u16, self.getAddress(self.system, self.PC + 1)) << 8) + self.getAddress(self.system, self.PC);
}
pub fn immediate8(self: *Z80) u8 {
    return self.getAddress(self.system, self.PC);
}
pub fn signImmediate8(self: *Z80) i8 {
    return @as(i8, self.getAddress(self.system, self.PC));
}
pub fn increment8(self: *Z80, value: u8) u8 {
    self.flags.N = 0;
    self.flags.H = 0;
    if (value >= 0xFF) {
        self.flags.Z = 1;
        self.flags.H = 1;
        return 0;
    }
    self.flags.Z = 0;
    if (@mod(value, 16) == 15) self.flags.H = 1;

    return @mod(value + 1, 256);
}
pub fn decrement8(self: *Z80, value: u8) u8 {
    self.flags.N = 1;
    self.flags.H = 0;
    if (value == 0) {
        self.flags.Z = 0;
        self.flags.H = 1;
        return 0xFF;
    } else if (value == 1) {
        self.flags.Z = 1;
        return 0;
    }
    self.flags.Z = 0;
    if (@mod(value, 16) == 0) self.flags.H = 1;

    return value -| 1;
}
pub fn add8(self: *Z80, a: u8, b: u8) u8 {
    self.flags.N = 0;

    self.flags.C = if (a + b >= 0x100) 1 else 0;
    self.flags.Z = if (@mod(a + b, 0x100) == 0) 1 else 0;
    self.flags.H = if (@mod(a, 0x10) + @mod(b, 0x10) >= 0x10) 1 else 0;
    return @mod(a + b, 0x100);
}
pub fn adc8(self: *Z80, a: u8, b: u8) u8 {
    var c: u8 = 0;

    c = self.flags.C;
    self.flags.N = 0;

    self.flags.C = if (a + b + c >= 0x100) 1 else 0;
    self.flags.Z = if (@mod(a + b + c, 0x100) == 0) 1 else 0;
    self.flags.H = if (@mod(a, 0x10) + @mod(b, 0x10) + c >= 0x10) 1 else 0;
    return @mod(a + b + c, 0x100);
}

pub fn add16(self: *Z80, a: u16, b: u16) u16 {
    const A = a & 0xFFFF;
    const B = b & 0xFFFF;

    self.flags.N = 0;

    self.flags.C = if (A + B > 0xFFFF) 1 else 0;
    self.flags.Z = if (@mod(A + B, 0xFFFF) == 0) 1 else 0;
    self.flags.H = if (@mod(A, 0xFFFF) + @mod(B, 0xFFFF) > 0xFFFF) 1 else 0;
    return @mod(A + B, 0xFFFF);
}
pub fn add16_8(self: *Z80, a: u16, b: u8) u16 {
    const A = a & 0xFFFF;
    const B = b & 0xFFFF;

    self.flags.N = 0;

    self.flags.C = if ((A & 0xFF) + (B & 0xFF) > 0xFF) 1 else 0;
    self.flags.H = if ((A & 0x0F) + (B & 0x0F) > 0x0F) 1 else 0;

    return (A + B) & 0xFFFF;
}
pub fn sub8(self: *Z80, a: u8, b: u8) u8 {
    self.flags.N = 1;

    self.flags.C = if (a - b < 0) 1 else 0;
    self.flags.Z = if (a - b == 0) 1 else 0;
    self.flags.H = if (@mod(a, 0x10) - @mod(b, 0x10) < 0) 1 else 0;

    return @mod(a - b, 0x100);
}
pub fn sbc8(self: *Z80, a: u8, b: u8) u8 {
    var c: u8 = 0;

    c = self.flags.C;
    self.flags.N = 1;

    self.flags.C = if (a - b - c < 0) 1 else 0;
    self.flags.Z = if (a - b - c == 0) 1 else 0;
    self.flags.H = if (@mod(a, 0x10) - @mod(b, 0x10) - c < 0) 1 else 0;

    return @mod(a - b - c, 0x100);
}
pub fn and8(self: *Z80, a: u8, b: u8) u8 {
    self.flags.N = 0;
    self.flags.H = 1;
    self.flags.C = 0;
    self.flags.Z = if (a & b == 0) 1 else 0;

    return a & b;
}
pub fn xor8(self: *Z80, a: u8, b: u8) u8 {
    self.flags.N = 0;
    self.flags.H = 0;
    self.flags.C = 0;
    self.flags.Z = if (a ^ b == 0) 1 else 0;

    return a ^ b;
}
pub fn or8(self: *Z80, a: u8, b: u8) u8 {
    self.flags.N = 0;
    self.flags.H = 0;
    self.flags.C = 0;
    self.flags.Z = if (a | b == 0) 1 else 0;

    return a | b;
}
pub fn call(self: *Z80, address: u16) void {
    self.registers.SP -|= 2;
    self.putAddress16(self.registers.SP, self.PC);
    self.PC = address;
    // self.registers.SP = @mod((self.registers.SP + 0x10000), 0x10000);
}
pub fn ret(self: *Z80) void {
    self.PC = self.getAddress16(self.registers.SP);
    self.registers.SP += 2;
    self.registers.SP = @mod(self.registers.SP, 0x10000);
}
pub fn setH(self: *Z80, value: u8) void {
    self.registers.HL = (self.registers.HL & 0xFF) | (value << 8);
}
pub fn setL(self: *Z80, value: u8) void {
    self.registers.HL = (self.registers.HL & 0xFF00) | value;
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
            self.registers.B = @as(u8, @intCast(data >> 8));
            self.registers.C = @as(u8, @intCast(data & 0xFF));
            self.PC += 2;
            return 12;
        }
    }.inst01,
    struct {
        fn inst02(self: *Z80) usize {
            // LD (BC), A
            self.putAddress16(
                (@as(u16, @intCast(self.registers.B)) << 8) | self.registers.C,
                self.registers.A,
            );
            self.PC += 1;
            return 8;
        }
    }.inst02,
    struct {
        fn inst03(self: *Z80) usize {
            // INC BC
            self.registers.C +%= 1;
            if (self.registers.C == 0) {
                self.registers.B +%= 1;
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
        0 => self.registers.B,
        1 => self.registers.C,
        2 => self.registers.D,
        3 => self.registers.E,
        4 => self.registers.HL >> 8,
        5 => self.registers.HL & 0xFF,
        6 => self.getAddress(self, self.registers.HL),
        7 => self.registers.A,
        else => unreachable,
    };
    data_8 = @as(u8, @intCast(data));
    op = @divExact(code, 8);
    switch (op) {
        0 => { // rotate left
            if (data >= 128) {
                data = @mod(data << 1, 256) + 1;
                self.flags.C = 1;
            } else {
                data = @mod(data << 1, 256);
                self.flags.C = 0;
            }
        },
        1 => { // rotate right
            if (data & 1 == 1) {
                data = @as(u8, @intCast(data >> 1)) + 128;
                self.flags.C = 1;
            } else {
                data = data >> 1;
                self.flags.C = 0;
            }
        },
        2 => { //rotate left through carry
            if (data >= 128) {
                data = @mod(data << 1, 256) + self.flags.C;
                self.flags.C = 1;
            } else {
                data = @mod(data << 1, 256) + self.flags.C;
                self.flags.C = 0;
            }
        },
        3 => { //rotate right through carry
            if (data & 1 == 1) {
                data = @as(u8, @intCast(data >> 1)) + 128 + @as(u8, @intCast(self.flags.C)) * 128;
                self.flags.C = 1;
            } else {
                data = @as(u8, @intCast(data >> 1)) + @as(u8, @intCast(self.flags.C)) * 128;
                self.flags.C = 0;
            }
        },
        4 => { //shift left arithmetic
            self.flags.C = if (data >= 128) 1 else 0;
            data = @mod(data << 1, 256);
        },
        5 => { //shift right arithmetic
            self.flags.C = if (data & 1 == 1) 1 else 0;
            data = @as(u8, @intCast(data >> 1)) + @as(u8, (if (data >= 128) 128 else 0));
        },
        6 => { // swap
            self.flags.C = 0;
            data = @mod(data << 4, 256) + @mod(data >> 4, 256);
        },
        7 => { // shift right logical
            self.flags.C = if (data & 1 == 1) 1 else 0;
            data = data >> 1;
        },
        8...15 => { // bit test
            self.flags.N = 0;
            self.flags.H = 1;
            const shifted: u8 = @as(u8, 1) << @as(u3, @truncate(op - 8));
            self.flags.Z = if (@as(u8, @intCast(data)) & shifted == 0) 1 else 0;
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
            0 => self.registers.B = @as(u8, @truncate(data & 0xFF)),
            1 => self.registers.C = @as(u8, @truncate(data >> 8)),
            2 => self.registers.D = @as(u8, @truncate(data & 0xFF)),
            3 => self.registers.E = @as(u8, @truncate(data >> 8)),
            4 => self.registers.HL = self.registers.HL | @as(u8, @truncate(data & 0xFF)),
            5 => self.registers.HL = self.registers.HL | @as(u8, @truncate(data >> 8)),
            6 => self.putAddress(self, self.registers.HL, @as(u8, @truncate(data & 0xFF))),
            7 => self.registers.A = @as(u8, @truncate(data & 0xFF)),
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
            std.debug.print("Running Instruction 0x{X:0>2} {}\n", .{ inst, self.PC });
            len = switch (inst) {
                0x00...0xCA => blk: {
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

pub inline fn makeword(a: u8, b: u8) u16 {
    return (a << 8) + b;
}
pub fn getRegAddr(self: Z80, r1: Z80.Registers, r2: Z80.Registers) u16 {
    _ = r2; // autofix
    _ = r1; // autofix
    _ = self; // autofix

}
