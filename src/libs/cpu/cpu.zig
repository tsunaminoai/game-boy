const std = @import("std");

const MemorySize = 8000;

const Register = enum(u8) {
    AF,
    BC,
    DE,
    HL,
    A,
    F,
    B,
    C,
    D,
    E,
    H,
    L,
    PC,
    SP,
};

const Flag = enum(u4) {
    Zero,
    Subtraction,
    HalfCarry,
    Carry,
};

pub const CPU = struct {
    memory: [MemorySize]u8 = [_]u8{0} ** MemorySize,
    registers: [14]u16 = [_]u16{0} ** 14,

    const Self = @This();
    const Address = u16;

    pub fn RegisterRead(self: *Self, register: Register) u16 {
        return self.registers[@intFromEnum(register)];
    }

    fn internalRegisterWrite(self: *Self, register: Register, value: u16) void {
        self.registers[@intFromEnum(register)] = value;
    }

    pub fn RegisterWrite(self: *Self, register: Register, value: u16) void {
        // std.debug.print("RegisterWrite({},{}: {X})\n", .{ register, @TypeOf(value), value });
        self.internalRegisterWrite(register, value);
        switch (register) {
            Register.AF => {
                self.internalRegisterWrite(Register.A, value >> 8);
                self.internalRegisterWrite(Register.F, value & 0x0F);
            },
            Register.BC => {
                self.internalRegisterWrite(Register.B, value >> 8);
                self.internalRegisterWrite(Register.C, value & 0x0F);
            },
            Register.DE => {
                self.internalRegisterWrite(Register.D, value >> 8);
                self.internalRegisterWrite(Register.E, value & 0x0F);
            },
            Register.HL => {
                self.internalRegisterWrite(Register.H, value >> 8);
                self.internalRegisterWrite(Register.L, value & 0x0F);
            },
            Register.A => {
                const currentValue = self.RegisterRead(Register.AF);
                self.internalRegisterWrite(Register.AF, (value << 8) | currentValue);
            },
            Register.F => {
                const currentValue = self.RegisterRead(Register.AF);
                self.internalRegisterWrite(Register.AF, (value & 0x0F) | currentValue);
            },
            Register.B => {
                const currentValue = self.RegisterRead(Register.BC);
                self.internalRegisterWrite(Register.BC, (value << 8) | currentValue);
            },
            Register.C => {
                const currentValue = self.RegisterRead(Register.BC);
                self.internalRegisterWrite(Register.BC, (value & 0x0F) | currentValue);
            },
            Register.D => {
                const currentValue = self.RegisterRead(Register.DE);
                self.internalRegisterWrite(Register.DE, (value << 8) | currentValue);
            },
            Register.E => {
                const currentValue = self.RegisterRead(Register.DE);
                self.internalRegisterWrite(Register.DE, (value & 0x0F) | currentValue);
            },
            Register.H => {
                const currentValue = self.RegisterRead(Register.HL);
                self.internalRegisterWrite(Register.HL, (value << 8) | currentValue);
            },
            Register.L => {
                const currentValue = self.RegisterRead(Register.HL);
                self.internalRegisterWrite(Register.HL, (value & 0x0F) | currentValue);
            },
            else => unreachable,
        }
    }
};

test "Test a register can be written to" {
    var cpu = CPU{};
    cpu.RegisterWrite(Register.AF, @as(u16, 0x0A0B));
    try std.testing.expect(cpu.registers[@intFromEnum(Register.AF)] == 0x0A0B);
}
test "Test that writing to a sub-register writes to the parent and vice versa" {
    var cpu = CPU{};
    cpu.RegisterWrite(Register.AF, @as(u16, 0x0A0B));
    try std.testing.expect(cpu.registers[@intFromEnum(Register.A)] == 0x0A);
    try std.testing.expect(cpu.registers[@intFromEnum(Register.F)] == 0x0B);

    cpu.RegisterWrite(Register.C, @as(u16, 0x0B));
    cpu.RegisterWrite(Register.B, @as(u16, 0x0A));
    try std.testing.expect(cpu.registers[@intFromEnum(Register.BC)] == 0x0A0B);
}
