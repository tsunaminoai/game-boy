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
    fn LoadRegisterFromRegister(self: *Self, source: Register, destination: Register) void {
        self.RegisterWrite(destination, self.RegisterRead(source));
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

            //LD r1,r2
            0x7F => { self.LoadRegisterFromRegister(Register.A,Register.A); },
            0x78 => { self.LoadRegisterFromRegister(Register.B,Register.A); },
            0x79 => { self.LoadRegisterFromRegister(Register.C,Register.A); },
            0x7A => { self.LoadRegisterFromRegister(Register.D,Register.A); },
            0x7B => { self.LoadRegisterFromRegister(Register.E,Register.A); },
            0x7C => { self.LoadRegisterFromRegister(Register.H,Register.A); },
            0x7D => { self.LoadRegisterFromRegister(Register.L,Register.A); },
            0x7E => { self.LoadRegisterFromRegister(Register.HL, Register.A); },

            0x40 => { self.LoadRegisterFromRegister(Register.B, Register.B); },
            0x41 => { self.LoadRegisterFromRegister(Register.C, Register.B); },
            0x42 => { self.LoadRegisterFromRegister(Register.D, Register.B); },
            0x43 => { self.LoadRegisterFromRegister(Register.E, Register.B); },
            0x44 => { self.LoadRegisterFromRegister(Register.H, Register.B); },
            0x45 => { self.LoadRegisterFromRegister(Register.L, Register.B); },
            0x46 => { self.LoadRegisterFromRegister(Register.HL, Register.B); },

            0x48 => { self.LoadRegisterFromRegister(Register.B, Register.C); },
            0x49 => { self.LoadRegisterFromRegister(Register.C, Register.C); },
            0x4A => { self.LoadRegisterFromRegister(Register.D, Register.C); },
            0x4B => { self.LoadRegisterFromRegister(Register.E, Register.C); },
            0x4C => { self.LoadRegisterFromRegister(Register.H, Register.C); },
            0x4D => { self.LoadRegisterFromRegister(Register.L, Register.C); },
            0x4E => { self.LoadRegisterFromRegister(Register.HL, Register.C); },

            0x50 => { self.LoadRegisterFromRegister(Register.B, Register.D); },
            0x51 => { self.LoadRegisterFromRegister(Register.C, Register.D); },
            0x52 => { self.LoadRegisterFromRegister(Register.D, Register.D); },
            0x53 => { self.LoadRegisterFromRegister(Register.E, Register.D); },
            0x54 => { self.LoadRegisterFromRegister(Register.H, Register.D); },
            0x55 => { self.LoadRegisterFromRegister(Register.L, Register.D); },
            0x56 => { self.LoadRegisterFromRegister(Register.HL, Register.D); },

            0x58 => { self.LoadRegisterFromRegister(Register.B, Register.E); },
            0x59 => { self.LoadRegisterFromRegister(Register.C, Register.E); },
            0x5A => { self.LoadRegisterFromRegister(Register.D, Register.E); },
            0x5B => { self.LoadRegisterFromRegister(Register.E, Register.E); },
            0x5C => { self.LoadRegisterFromRegister(Register.H, Register.E); },
            0x5D => { self.LoadRegisterFromRegister(Register.L, Register.E); },
            0x5E => { self.LoadRegisterFromRegister(Register.HL, Register.E); },

            0x60 => { self.LoadRegisterFromRegister(Register.B, Register.H); },
            0x61 => { self.LoadRegisterFromRegister(Register.C, Register.H); },
            0x62 => { self.LoadRegisterFromRegister(Register.D, Register.H); },
            0x63 => { self.LoadRegisterFromRegister(Register.E, Register.H); },
            0x64 => { self.LoadRegisterFromRegister(Register.H, Register.H); },
            0x65 => { self.LoadRegisterFromRegister(Register.L, Register.H); },
            0x66 => { self.LoadRegisterFromRegister(Register.HL, Register.H); },

            0x68 => { self.LoadRegisterFromRegister(Register.B, Register.L); },
            0x69 => { self.LoadRegisterFromRegister(Register.C, Register.L); },
            0x6A => { self.LoadRegisterFromRegister(Register.D, Register.L); },
            0x6B => { self.LoadRegisterFromRegister(Register.E, Register.L); },
            0x6C => { self.LoadRegisterFromRegister(Register.H, Register.L); },
            0x6D => { self.LoadRegisterFromRegister(Register.L, Register.L); },
            0x6E => { self.LoadRegisterFromRegister(Register.HL, Register.L); },

            0x70 => { self.LoadRegisterFromRegister(Register.B, Register.HL); },
            0x71 => { self.LoadRegisterFromRegister(Register.C, Register.HL); },
            0x72 => { self.LoadRegisterFromRegister(Register.D, Register.HL); },
            0x73 => { self.LoadRegisterFromRegister(Register.E, Register.HL); },
            0x74 => { self.LoadRegisterFromRegister(Register.H, Register.HL); },
            0x75 => { self.LoadRegisterFromRegister(Register.L, Register.HL); },
            0x36 => { self.LoadRegisterFromRegister(Register.L, Register.HL); },

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
    test "Test LD n,nn" {
        var cpu = CPU{};
        cpu.memory[0] = 0x06; // LDB,d8
        cpu.memory[1] = 0xFE;
        cpu.Tick();
        try std.testing.expect(cpu.RegisterRead(Register.B) == 0xFE);
    }
    test "Test LD r1,r2" {
        var cpu = CPU{};
        cpu.RegisterWrite(Register.A, 0x0);
        cpu.RegisterWrite(Register.H, 0xBC);
        cpu.memory[0] = 0x7C; //LDA,L
        cpu.Tick();
        try std.testing.expect(cpu.RegisterRead(Register.A) == 0xBC);
    }
};
