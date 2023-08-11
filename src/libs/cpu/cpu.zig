const std = @import("std");

const MemorySize = 8000;

const Register = enum(u8) {
    // zig fmt: off
    AF, BC, DE, HL,         //16bit "combined" registers
    A, F, B, C, D, E, H, L, //"8bit" registers
    SP                  //16bit special registers
    // zig fmt: on
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
    flags: [4]bool = [_]bool{false} ** 4,
    programCounter: u16 = 0,

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
            Register.SP => {},
        }
    }
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

    fn FlagSet(self: *Self, flag: Flag) void {
        self.flags[@intFromEnum(flag)] = true;
    }

    fn FlagUnSet(self: *Self, flag: Flag) void {
        self.flags[@intFromEnum(flag)] = false;
    }
    pub fn FlagRead(self: *Self, flag: Flag) bool {
        return self.flags[@intFromEnum(flag)];
    }
    test "Test that flags can be set and unset" {
        var cpu = CPU{};
        cpu.FlagSet(Flag.Zero);
        try std.testing.expect(cpu.FlagRead(Flag.Zero) == true);
        cpu.FlagUnSet(Flag.Zero);
        try std.testing.expect(cpu.FlagRead(Flag.Zero) == false);
    }

    fn LoadRegister(self: *Self, register: Register) void {
        self.RegisterWrite(register, self.memory[self.programCounter]);
    }
    fn LoadRegisterImmediate(self: *Self, register: Register, value: u16) void {
        self.RegisterWrite(register, value);
    }
    fn Tick(self: *Self) void {
        const opcode = self.memory[self.programCounter];
        self.programCounter += 1;
        switch (opcode) {
            // zig fmt: off

            //LD n,nn
            0x06 => { self.LoadRegister(Register.B); },
            0x0E => { self.LoadRegister(Register.C); },
            0x16 => { self.LoadRegister(Register.D); },
            0x1E => { self.LoadRegister(Register.E); },
            0x26 => { self.LoadRegister(Register.H); },
            0x2E => { self.LoadRegister(Register.L); },

            // zig fmt: on
            else => undefined,
        }
    }
    test "Test ticking increments PC" {
        var cpu = CPU{};
        const pc = cpu.programCounter;
        cpu.Tick();
        try std.testing.expect(cpu.programCounter == pc + 1);
    }
    test "Test LD B,n" {
        var cpu = CPU{};
        cpu.memory[0] = 0x06;
        cpu.memory[1] = 0xFE;
        cpu.Tick();
        try std.testing.expect(cpu.RegisterRead(Register.B) == 0xFE);
    }
};
