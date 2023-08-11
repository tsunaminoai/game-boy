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

const CPU = struct {
    memory: [MemorySize]u8 = [_]u8{0} ** MemorySize,
    registers: [14]u16 = [_]u16{0} ** 14,

    const Self = @This();
    const Address = u16;

    pub fn RegisterRead(self: *Self, register: Register) u16 {
        return self.registers[@intFromEnum(register)];
    }

    pub fn RegisterWrite(self: *Self, register: Register, value: anytype) void {
        std.debug.print("RegisterWrite({},{}: {X})\n", .{ register, @TypeOf(value), value });
        self.registers[@intFromEnum(register)] = value;

        switch (register) {
            Register.AF => {
                self.RegisterWrite(Register.A, value >> 8);
                self.RegisterWrite(Register.F, value & 0x0F);
            },
            Register.BC => {
                self.RegisterWrite(Register.B, value >> 8);
                self.RegisterWrite(Register.C, value & 0x0F);
            },
            Register.DE => {
                self.RegisterWrite(Register.D, value >> 8);
                self.RegisterWrite(Register.E, value & 0x0F);
            },
            Register.HL => {
                self.RegisterWrite(Register.H, value >> 8);
                self.RegisterWrite(Register.L, value & 0x0F);
            },
            Register.A => {
                const currentValue = self.RegisterRead(Register.AF);
                self.RegisterWrite(Register.AF, (value << 8) & currentValue);
            },
            Register.F => {
                const currentValue = self.RegisterRead(Register.AF);
                self.RegisterWrite(Register.AF, (value & 0x0F) & currentValue);
            },
            Register.B => {
                const currentValue = self.RegisterRead(Register.BC);
                self.RegisterWrite(Register.BC, (value << 8) & currentValue);
            },
            Register.C => {
                const currentValue = self.RegisterRead(Register.BC);
                self.RegisterWrite(Register.BC, (value & 0x0F) & currentValue);
            },
            Register.D => {
                const currentValue = self.RegisterRead(Register.DE);
                self.RegisterWrite(Register.DE, (value << 8) & currentValue);
            },
            Register.E => {
                const currentValue = self.RegisterRead(Register.DE);
                self.RegisterWrite(Register.DE, (value & 0x0F) & currentValue);
            },
            Register.H => {
                const currentValue = self.RegisterRead(Register.HL);
                self.RegisterWrite(Register.HL, (value << 8) & currentValue);
            },
            Register.L => {
                const currentValue = self.RegisterRead(Register.HL);
                self.RegisterWrite(Register.HL, (value & 0x0F) & currentValue);
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

    cpu.RegisterWrite(Register.C, @as(u8, 0x0B));
    cpu.RegisterWrite(Register.B, @as(u8, 0x0A));
    try std.testing.expect(cpu.registers[@intFromEnum(Register.BC)] == 0x0A0B);
}
