const std = @import("std");
const RegisterName = @import("types.zig").RegisterName;
const Flags = @import("types.zig").Flags;
const MOps = @import("types.zig").MathOperations;

const MemorySize = 0x10000;
const MemoryOffset: u16 = 0xFF00;

fn getMSB(value: u16) u8 {
    return @as(u8, @truncate(value >> 8));
}
fn getLSB(value: u16) u8 {
    return @as(u8, @truncate(value & 0x00FF));
}
fn setLSB(val16: u16, val8: u16) u16 {
    return (val8 << 8) | (val16);
}
fn setMSB(val16: u16, val8: u16) u16 {
    return (val16) | (val8 & 0x00FF);
}

pub const CPU = struct {
    memory: [MemorySize]u16 = [_]u16{0} ** MemorySize,
    registers: [14]u16 = [_]u16{0} ** 14,
    flags: Flags = Flags{},
    programCounter: u16 = 0,
    currentIntruction: u16 = 0,
    ticks: u16 = 0,
    halt: bool = false,

    const Self = @This();
    const Address = u16;

    pub fn Run(self: *Self) void {
        while ((!self.halt) and (self.ticks < 5)) {
            self.Tick();
            std.debug.print("Tick {} Instruction {X}\n", .{self.ticks, self.currentIntruction});
        }
    }

    pub fn ReadRegister(self: *Self, register: RegisterName) u16 {
        return self.registers[@intFromEnum(register)];
    }

    // We're going to take advantage of the fact that there are 8 8bit registers and their
    // doubled up counterparts are esily mappable.
    pub fn WriteRegister(self: *Self, register: RegisterName, value: u16) void {
        const index: u16 = @intFromEnum(register);

        self.registers[index] = value;

        switch (index) {
            // the normal registers
            0...7 => {
                // set the register above
                const combinedIndex = 8 + index / 2;
                const currentValue = self.registers[combinedIndex];
                self.registers[combinedIndex] = if (index % 2 == 0) setLSB(currentValue, value) else setMSB(currentValue, value);
            },
            // for 16 bit "combined" registers
            8 => {
                // set the registers 8 and 7 spaces below
                self.registers[0] = getLSB(value);
                self.registers[1] = getMSB(value);
            },
            9 => {
                // set the registers 8 and 7 spaces below
                self.registers[2] = getLSB(value);
                self.registers[3] = getMSB(value);
            },
            10 => {
                // set the registers 8 and 7 spaces below
                self.registers[4] = getLSB(value);
                self.registers[5] = getMSB(value);
            },
            11 => {
                // set the registers 8 and 7 spaces below
                self.registers[6] = getLSB(value);
                self.registers[7] = getMSB(value);
            },
            12 => {},
            else => {
                std.debug.panic("index: {}, {}, {}\n\n\n", .{ index, register, @intFromEnum(register) });
                unreachable;
            },
        }
    }

    fn LoadRegister(self: *Self, register: RegisterName) void {
        self.WriteRegister(register, self.memory[self.programCounter]);
    }

    fn LoadRegisterFromRegister(self: *Self, source: RegisterName, destination: RegisterName) void {
        self.WriteRegister(destination, self.ReadRegister(source));
    }

    fn LoadRegisterFromAddressRegister(self: *Self, source: RegisterName, destination: RegisterName) void {
        self.WriteRegister(destination, self.ReadMemory(self.ReadRegister(source), 1));
    }

    pub fn WriteMemory(self: *Self, address: u16, value: u16, size: u2) void {
        // for each byte we're expecting
        var idx: usize = 0;
        while (idx < size) : (idx += 1) {
            // write to the address + offset
            // the value passed in shifted by i bytes and masked to u8
            self.memory[address + idx] = (value >> @intCast(8 * idx)) & 0x00FF;
        }
    }

    pub fn ReadMemory(self: *Self, address: u16, size: u2) u16 {
        switch (size) {
            1 => {
                return self.memory[address];
            },
            2 => {
                return (self.memory[address + 1] << 8) + self.memory[address];
            },
            else => unreachable,
        }
    }

    /// Writes a source register value to a memory address defined in the address register
    fn WriteMemoryByteFromRegister(self: *Self, sourceRegisterName: RegisterName, addressRegisterName: RegisterName) void {
        self.WriteMemory(self.ReadRegister(addressRegisterName), self.ReadRegister(sourceRegisterName), 1);
    }

    /// Writes to a memory address defined as the next <size> immediates
    fn WriteMemoryByteFromAddressNN(self: *Self, sourceRegisterName: RegisterName, size: u2) void {
        self.WriteMemory(self.ReadMemory(self.programCounter, size), self.ReadRegister(sourceRegisterName), size);
    }

    /// Pushes the source register onto the stack
    fn StackPush(self: *Self, sourceRegisterName: RegisterName) void {
        const SP = self.ReadRegister(RegisterName.SP);
        const LSB = getLSB(self.ReadRegister(sourceRegisterName));
        const MSB = getMSB(self.ReadRegister(sourceRegisterName));
        self.WriteMemory(SP + 1, MSB, 1);
        self.WriteMemory(SP, LSB, 1);
        self.RegisterDecrement(RegisterName.SP);
        self.RegisterDecrement(RegisterName.SP);
    }

    /// Pops the stack into the destination register
    fn StackPop(self: *Self, destinationRegisterName: RegisterName) void {
        var result: u16 = 0;
        self.RegisterIncrement(RegisterName.SP);
        self.RegisterIncrement(RegisterName.SP);

        const SP = self.ReadRegister(RegisterName.SP);
        result = setLSB(result, self.ReadMemory(SP + 1, 1));
        result = setMSB(result, self.ReadMemory(SP, 1));
        self.WriteRegister(destinationRegisterName, result);
    }

    pub fn adder(self: *Self, op1: u16, op2: u16, size: u2, useCarry: bool, subtraction: bool) u16 {
        var result: u32 = undefined;
        if (subtraction) {
            result = 1 + @as(u32, op1) + @as(u32, (~op2));
        } else {
            result = @as(u32, op1) + @as(u32, op2);
        }

        const halfCarryMask: u32 = if (size == 1) 0x10 else 0x1000;
        const fullCarryMask: u32 = if (size == 1) 0x100 else 0x10000;
        const byteMask: u32 = if (size == 1) 0xFF else 0xFFFF;

        if (useCarry) {
            result += @intFromBool(self.flags.carry);
        }

        self.flags = .{
            .zero = ((result & byteMask) == 0),
            .subtraction = subtraction,
            .halfCarry = ((op1 ^ op2 ^ result) & halfCarryMask) == halfCarryMask,
            .carry = (result & fullCarryMask) == fullCarryMask,
        };
        return @as(u16, @truncate(result & byteMask));
    }
    pub fn add(self: *Self, op1: u16, op2: u16, size: u2, useCarry: bool) u16 {
        return self.adder(op1, op2, size, useCarry, false);
    }
    pub fn subtract(self: *Self, op1: u16, op2: u16, size: u2, useCarry: bool) u16 {
        return self.adder(op1, op2, size, useCarry, true);
    }
    pub fn logicalAnd(self: *Self, op1: u16, op2: u16) u16 {
        const result = op1 & op2;
        self.flags = .{
            .zero = result == 0x0,
            .subtraction = false,
            .halfCarry = true,
            .carry = false,
        };
        return result;
    }
    pub fn logicalOr(self: *Self, op1: u16, op2: u16) u16 {
        const result = op1 | op2;
        self.flags = .{
            .zero = result == 0x0,
            .subtraction = false,
            .halfCarry = false,
            .carry = false,
        };
        return result;
    }
    pub fn logicalXor(self: *Self, op1: u16, op2: u16) u16 {
        const result = op1 ^ op2;
        self.flags = .{
            .zero = result == 0x0,
            .subtraction = false,
            .halfCarry = false,
            .carry = false,
        };
        return result;
    }
    pub fn cmp(self: *Self, op1: u16, op2: u16) void {
        _ = self.subtract(op1, op2, 1, false);
    }
    pub fn swap(self: *Self, op1: u16) u16 {
        const result = 0xFF & (op1 << 4) + (op1 >> 4);
        self.flags = .{
            .zero = result == 0x0,
            .subtraction = false,
            .halfCarry = false,
            .carry = false,
        };
        return result;
    }
    fn RegisterAMOps(self: *Self, operation: MOps, value: u16, size: u2, useCarry: bool) void {
        switch (operation) {
            MOps.add => {
                self.WriteRegister(RegisterName.A, self.add(self.ReadRegister(RegisterName.A), value, size, useCarry));
            },
            MOps.subtract => {
                self.WriteRegister(RegisterName.A, self.subtract(self.ReadRegister(RegisterName.A), value, size, useCarry));
            },
            MOps.logicalAnd => {
                self.WriteRegister(RegisterName.A, self.logicalAnd(self.ReadRegister(RegisterName.A), value));
            },
            MOps.logicalOr => {
                self.WriteRegister(RegisterName.A, self.logicalOr(self.ReadRegister(RegisterName.A), value));
            },
            MOps.logicalXor => {
                self.WriteRegister(RegisterName.A, self.logicalXor(self.ReadRegister(RegisterName.A), value));
            },
            MOps.cmp => {
                self.cmp(self.ReadRegister(RegisterName.A), value);
            },
        }
    }

    pub fn Tick(self: *Self) void {
        const opcode = self.memory[self.programCounter];
        self.currentIntruction = opcode;
        self.programCounter += 1;
        self.ticks += 1;

        switch (opcode) {
            // zig fmt: off

            //NOPE!
            0x00 => {},

            //8-bit loads

            //LD n,nn
            0x06 => { self.LoadRegister(RegisterName.B); },
            0x0E => { self.LoadRegister(RegisterName.C); },
            0x16 => { self.LoadRegister(RegisterName.D); },
            0x1E => { self.LoadRegister(RegisterName.E); },
            0x26 => { self.LoadRegister(RegisterName.H); },
            0x2E => { self.LoadRegister(RegisterName.L); },

            //LD r1,r2
            0x7F => { self.LoadRegisterFromRegister(RegisterName.A,RegisterName.A); },
            0x78 => { self.LoadRegisterFromRegister(RegisterName.B,RegisterName.A); },
            0x79 => { self.LoadRegisterFromRegister(RegisterName.C,RegisterName.A); },
            0x7A => { self.LoadRegisterFromRegister(RegisterName.D,RegisterName.A); },
            0x7B => { self.LoadRegisterFromRegister(RegisterName.E,RegisterName.A); },
            0x7C => { self.LoadRegisterFromRegister(RegisterName.H,RegisterName.A); },
            0x7D => { self.LoadRegisterFromRegister(RegisterName.L,RegisterName.A); },
            0x7E => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.A); },

            0x40 => { self.LoadRegisterFromRegister(RegisterName.B, RegisterName.B); },
            0x41 => { self.LoadRegisterFromRegister(RegisterName.C, RegisterName.B); },
            0x42 => { self.LoadRegisterFromRegister(RegisterName.D, RegisterName.B); },
            0x43 => { self.LoadRegisterFromRegister(RegisterName.E, RegisterName.B); },
            0x44 => { self.LoadRegisterFromRegister(RegisterName.H, RegisterName.B); },
            0x45 => { self.LoadRegisterFromRegister(RegisterName.L, RegisterName.B); },
            0x46 => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.B); },

            0x48 => { self.LoadRegisterFromRegister(RegisterName.B, RegisterName.C); },
            0x49 => { self.LoadRegisterFromRegister(RegisterName.C, RegisterName.C); },
            0x4A => { self.LoadRegisterFromRegister(RegisterName.D, RegisterName.C); },
            0x4B => { self.LoadRegisterFromRegister(RegisterName.E, RegisterName.C); },
            0x4C => { self.LoadRegisterFromRegister(RegisterName.H, RegisterName.C); },
            0x4D => { self.LoadRegisterFromRegister(RegisterName.L, RegisterName.C); },
            0x4E => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.C); },

            0x50 => { self.LoadRegisterFromRegister(RegisterName.B, RegisterName.D); },
            0x51 => { self.LoadRegisterFromRegister(RegisterName.C, RegisterName.D); },
            0x52 => { self.LoadRegisterFromRegister(RegisterName.D, RegisterName.D); },
            0x53 => { self.LoadRegisterFromRegister(RegisterName.E, RegisterName.D); },
            0x54 => { self.LoadRegisterFromRegister(RegisterName.H, RegisterName.D); },
            0x55 => { self.LoadRegisterFromRegister(RegisterName.L, RegisterName.D); },
            0x56 => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.D); },

            0x58 => { self.LoadRegisterFromRegister(RegisterName.B, RegisterName.E); },
            0x59 => { self.LoadRegisterFromRegister(RegisterName.C, RegisterName.E); },
            0x5A => { self.LoadRegisterFromRegister(RegisterName.D, RegisterName.E); },
            0x5B => { self.LoadRegisterFromRegister(RegisterName.E, RegisterName.E); },
            0x5C => { self.LoadRegisterFromRegister(RegisterName.H, RegisterName.E); },
            0x5D => { self.LoadRegisterFromRegister(RegisterName.L, RegisterName.E); },
            0x5E => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.E); },

            0x60 => { self.LoadRegisterFromRegister(RegisterName.B, RegisterName.H); },
            0x61 => { self.LoadRegisterFromRegister(RegisterName.C, RegisterName.H); },
            0x62 => { self.LoadRegisterFromRegister(RegisterName.D, RegisterName.H); },
            0x63 => { self.LoadRegisterFromRegister(RegisterName.E, RegisterName.H); },
            0x64 => { self.LoadRegisterFromRegister(RegisterName.H, RegisterName.H); },
            0x65 => { self.LoadRegisterFromRegister(RegisterName.L, RegisterName.H); },
            0x66 => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.H); },

            0x68 => { self.LoadRegisterFromRegister(RegisterName.B, RegisterName.L); },
            0x69 => { self.LoadRegisterFromRegister(RegisterName.C, RegisterName.L); },
            0x6A => { self.LoadRegisterFromRegister(RegisterName.D, RegisterName.L); },
            0x6B => { self.LoadRegisterFromRegister(RegisterName.E, RegisterName.L); },
            0x6C => { self.LoadRegisterFromRegister(RegisterName.H, RegisterName.L); },
            0x6D => { self.LoadRegisterFromRegister(RegisterName.L, RegisterName.L); },
            0x6E => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.L); },

            0x70 => { self.WriteMemoryByteFromRegister(RegisterName.B, RegisterName.HL); },
            0x71 => { self.WriteMemoryByteFromRegister(RegisterName.C, RegisterName.HL); },
            0x72 => { self.WriteMemoryByteFromRegister(RegisterName.D, RegisterName.HL); },
            0x73 => { self.WriteMemoryByteFromRegister(RegisterName.E, RegisterName.HL); },
            0x74 => { self.WriteMemoryByteFromRegister(RegisterName.H, RegisterName.HL); },
            0x75 => { self.WriteMemoryByteFromRegister(RegisterName.L, RegisterName.HL); },
            0x36 => { self.LoadRegister( RegisterName.HL); },

            0x0A => { self.LoadRegisterFromAddressRegister(RegisterName.BC, RegisterName.A); },
            0x1A => { self.LoadRegisterFromAddressRegister(RegisterName.DE, RegisterName.A); },
            0xFA => { self.WriteRegister(RegisterName.A, self.ReadMemory(self.ReadMemory(self.programCounter, 2), 1));},
            0x3E => { self.LoadRegister( RegisterName.A ); },

            0x47 => { self.LoadRegisterFromRegister( RegisterName.A, RegisterName.B ); },
            0x4F => { self.LoadRegisterFromRegister( RegisterName.A, RegisterName.C ); },
            0x57 => { self.LoadRegisterFromRegister( RegisterName.A, RegisterName.D ); },
            0x5F => { self.LoadRegisterFromRegister( RegisterName.A, RegisterName.E ); },
            0x67 => { self.LoadRegisterFromRegister( RegisterName.A, RegisterName.H ); },
            0x6F => { self.LoadRegisterFromRegister( RegisterName.A, RegisterName.L ); },
            0x02 => { self.WriteMemoryByteFromRegister(RegisterName.A, RegisterName.BC); },
            0x12 => { self.WriteMemoryByteFromRegister(RegisterName.A, RegisterName.DE); },
            0x77 => { self.WriteMemoryByteFromRegister(RegisterName.A, RegisterName.HL); },
            0xEA => { self.WriteMemoryByteFromAddressNN(RegisterName.A, 1); },

            // LDD A,(HL)
            0x3A => {
                self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.A);
                self.RegisterDecrement(RegisterName.HL);
            },
            // LDD (HL),A
            0x32 => {
                self.WriteMemoryByteFromRegister(RegisterName.A, RegisterName.HL);
                self.RegisterDecrement(RegisterName.HL);
            },
            // LDI A,(HL)
            0x2A => {
                self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.A);
                self.RegisterIncrement(RegisterName.HL);
            },
            // LDI (HL),A
            0x22 => {
                self.WriteMemoryByteFromRegister(RegisterName.A, RegisterName.HL);
                self.RegisterIncrement(RegisterName.HL);
            },

            // Writes the value of a register to memory address defined in the program counter + $FF00
            0xE0 => {
                self.WriteMemory(
                    self.ReadMemory(
                        self.programCounter,
                        1)
                        + MemoryOffset,
                    self.ReadRegister(RegisterName.A),
                    1);
                },

            // Write the value of memory address defined in the program counter + $FF00 to a register
            0xF0 => { self.WriteRegister(RegisterName.A, self.memory[self.memory[self.programCounter] + MemoryOffset]); },

            //16-bit loads
            0x01 => { self.WriteRegister(RegisterName.BC, self.ReadMemory(self.programCounter, 2)); },
            0x11 => { self.WriteRegister(RegisterName.DE, self.ReadMemory(self.programCounter, 2)); },
            0x21 => { self.WriteRegister(RegisterName.HL, self.ReadMemory(self.programCounter, 2)); },
            0x31 => { self.WriteRegister(RegisterName.SP, self.ReadMemory(self.programCounter, 2)); },

            0xF9 => { self.LoadRegisterFromRegister(RegisterName.HL, RegisterName.SP); },

            0xF8 => {
                // get effective address
                const eax = self.add(self.ReadRegister(RegisterName.SP), self.ReadMemory(self.programCounter,1), 2, false);
                self.WriteRegister(RegisterName.HL, self.ReadMemory(eax, 2));
            },

            0x08 => { self.WriteMemoryByteFromAddressNN(RegisterName.SP, 2); },

            0xF5 => { self.StackPush(RegisterName.AF); },
            0xC5 => { self.StackPush(RegisterName.BC); },
            0xD5 => { self.StackPush(RegisterName.DE); },
            0xE5 => { self.StackPush(RegisterName.HL); },

            0xF1 => { self.StackPop(RegisterName.AF); },
            0xC1 => { self.StackPop(RegisterName.BC); },
            0xD1 => { self.StackPop(RegisterName.DE); },
            0xE1 => { self.StackPop(RegisterName.HL); },

            // ADD A,m
            0x87 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.A), 1, false); },
            0x80 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.B), 1, false); },
            0x81 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.C), 1, false); },
            0x82 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.D), 1, false); },
            0x83 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.E), 1, false); },
            0x84 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.H), 1, false); },
            0x85 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.L), 1, false); },
            0x86 => { self.RegisterAMOps(MOps.add, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 1, false); },
            0xC6 => { self.RegisterAMOps(MOps.add, self.ReadMemory(self.programCounter, 1), 1, false); },

            // ADC A,n
            0x8F => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.A), 1, true); },
            0x88 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.B), 1, true); },
            0x89 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.C), 1, true); },
            0x8A => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.D), 1, true); },
            0x8B => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.E), 1, true); },
            0x8C => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.H), 1, true); },
            0x8D => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.L), 1, true); },
            0x8E => { self.RegisterAMOps(MOps.add, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 1, true); },
            0xCE => { self.RegisterAMOps(MOps.add, self.ReadMemory(self.programCounter, 1), 1, true); },

            // SUB A,n
            0x97 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.A), 1, false); },
            0x90 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.B), 1, false); },
            0x91 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.C), 1, false); },
            0x92 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.D), 1, false); },
            0x93 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.E), 1, false); },
            0x94 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.H), 1, false); },
            0x95 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.L), 1, false); },
            0x96 => { self.RegisterAMOps(MOps.subtract, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 1, false); },
            0xD6 => { self.RegisterAMOps(MOps.subtract, self.ReadMemory(self.programCounter, 1), 1, false); },

            // SBC A.n
            0x9F => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.A), 1, true); },
            0x98 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.B), 1, true); },
            0x99 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.C), 1, true); },
            0x9A => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.D), 1, true); },
            0x9B => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.E), 1, true); },
            0x9C => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.H), 1, true); },
            0x9D => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.L), 1, true); },
            0x9E => { self.RegisterAMOps(MOps.subtract, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 1, true); },
            // undefined 0x?? => { self.RegisterAMOps(MOps.subtract, self.ReadMemory(self.programCounter, 1), 1, true); }

            // AND
            0xA7 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadRegister(RegisterName.A), 0, false); },
            0xA0 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadRegister(RegisterName.B), 0, false); },
            0xA1 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadRegister(RegisterName.C), 0, false); },
            0xA2 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadRegister(RegisterName.D), 0, false); },
            0xA3 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadRegister(RegisterName.E), 0, false); },
            0xA4 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadRegister(RegisterName.H), 0, false); },
            0xA5 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadRegister(RegisterName.L), 0, false); },
            0xA6 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0, false); },
            0xE6 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadMemory(self.programCounter, 1), 0, false); },

            // OR
            0xB7 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.A), 0, false); },
            0xB0 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.B), 0, false); },
            0xB1 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.C), 0, false); },
            0xB2 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.D), 0, false); },
            0xB3 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.E), 0, false); },
            0xB4 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.H), 0, false); },
            0xB5 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.L), 0, false); },
            0xB6 => { self.RegisterAMOps(MOps.logicalOr, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0, false); },
            0xF6 => { self.RegisterAMOps(MOps.logicalOr, self.ReadMemory(self.programCounter, 1), 0, false); },

            // XOR
            0xAF => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.A), 0, false); },
            0xA8 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.B), 0, false); },
            0xA9 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.C), 0, false); },
            0xAA => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.D), 0, false); },
            0xAB => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.E), 0, false); },
            0xAC => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.H), 0, false); },
            0xAD => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.L), 0, false); },
            0xAE => { self.RegisterAMOps(MOps.logicalOr, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0, false); },
            0xEE => { self.RegisterAMOps(MOps.logicalOr, self.ReadMemory(self.programCounter, 1), 0, false); },

            // CMP
            0xBF => { self.RegisterAMOps(MOps.cmp, self.ReadRegister(RegisterName.A), 0, false); },
            0xB8 => { self.RegisterAMOps(MOps.cmp, self.ReadRegister(RegisterName.B), 0, false); },
            0xB9 => { self.RegisterAMOps(MOps.cmp, self.ReadRegister(RegisterName.C), 0, false); },
            0xBA => { self.RegisterAMOps(MOps.cmp, self.ReadRegister(RegisterName.D), 0, false); },
            0xBB => { self.RegisterAMOps(MOps.cmp, self.ReadRegister(RegisterName.E), 0, false); },
            0xBC => { self.RegisterAMOps(MOps.cmp, self.ReadRegister(RegisterName.H), 0, false); },
            0xBD => { self.RegisterAMOps(MOps.cmp, self.ReadRegister(RegisterName.L), 0, false); },
            0xBE => { self.RegisterAMOps(MOps.cmp, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0, false); },
            0xFE => { self.RegisterAMOps(MOps.cmp, self.ReadMemory(self.programCounter, 1), 0, false); },

            // INC
            0x3C => { self.RegisterIncrement(RegisterName.A); },
            0x04 => { self.RegisterIncrement(RegisterName.B); },
            0x0C => { self.RegisterIncrement(RegisterName.C); },
            0x14 => { self.RegisterIncrement(RegisterName.D); },
            0x1C => { self.RegisterIncrement(RegisterName.E); },
            0x24 => { self.RegisterIncrement(RegisterName.H); },
            0x2C => { self.RegisterIncrement(RegisterName.L); },
            0x34 => { self.WriteMemory(self.ReadRegister(RegisterName.HL), self.add(self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0x1, 1, false), 1); },
            0x03 => { self.RegisterIncrement(RegisterName.BC); },
            0x13 => { self.RegisterIncrement(RegisterName.DE); },
            0x23 => { self.RegisterIncrement(RegisterName.HL); },
            0x33 => { self.RegisterIncrement(RegisterName.SP); },

            // DEC
            0x3D => { self.RegisterDecrement(RegisterName.A); },
            0x05 => { self.RegisterDecrement(RegisterName.B); },
            0x0D => { self.RegisterDecrement(RegisterName.C); },
            0x15 => { self.RegisterDecrement(RegisterName.D); },
            0x1D => { self.RegisterDecrement(RegisterName.E); },
            0x25 => { self.RegisterDecrement(RegisterName.H); },
            0x2D => { self.RegisterDecrement(RegisterName.L); },
            0x35 => { self.WriteMemory(self.ReadRegister(RegisterName.HL), self.subtract(self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0x1, 1, false), 1); },
            0x0B => { self.RegisterDecrement(RegisterName.BC); },
            0x1B => { self.RegisterDecrement(RegisterName.DE); },
            0x2B => { self.RegisterDecrement(RegisterName.HL); },
            0x3B => { self.RegisterDecrement(RegisterName.SP); },

            // ADD HL,n
            0x09 => {self.WriteRegister(RegisterName.HL, self.add(self.ReadRegister(RegisterName.HL), self.ReadRegister(RegisterName.BC), 1, false)); },
            0x19 => {self.WriteRegister(RegisterName.HL, self.add(self.ReadRegister(RegisterName.HL), self.ReadRegister(RegisterName.DE), 1, false)); },
            0x29 => {self.WriteRegister(RegisterName.HL, self.add(self.ReadRegister(RegisterName.HL), self.ReadRegister(RegisterName.HL), 1, false)); },
            0x39 => {self.WriteRegister(RegisterName.HL, self.add(self.ReadRegister(RegisterName.HL), self.ReadRegister(RegisterName.SP), 1, false)); },

           // ADD SP,n
           0xE8 => {
                self.WriteRegister(RegisterName.SP, self.add( self.ReadRegister(RegisterName.SP), self.ReadMemory(self.programCounter, 1),  1, false ));
            },

            // JP nn
            0xC3 => { self.jump(self.ReadMemory(self.programCounter, 2)); },
            // JP cc,nn
            0xC2 => { if( self.flags.zero == false) { self.jump(self.ReadMemory(self.programCounter, 2)); } },
            0xCA => { if( self.flags.zero == true)  { self.jump(self.ReadMemory(self.programCounter, 2)); }  },
            0xD2 => { if( self.flags.carry == false) { self.jump(self.ReadMemory(self.programCounter, 2)); }  },
            0xDA => { if( self.flags.carry == true) { self.jump(self.ReadMemory(self.programCounter, 2)); }  },
            0xE9 => { self.jump(self.ReadMemory(self.ReadRegister(RegisterName.HL), 2)); },

            // JR n
            0x18 => { self.AddAndJump(); },
            0x20 => { if( self.flags.zero == false)  { self.AddAndJump(); } },
            0x28 => { if( self.flags.zero == true)   { self.AddAndJump(); } },
            0x30 => { if( self.flags.carry == false) { self.AddAndJump(); } },
            0x38 => { if( self.flags.carry == true)  { self.AddAndJump(); } },

            // CALL nn
            0xCD => {
                self.StackPush(RegisterName.HL);
                self.jump(self.ReadMemory(self.programCounter, 2));
            },
            // CALL cc,nn
            0xC4 => { if( self.flags.zero == false)
                self.StackPush(RegisterName.HL);
                self.jump(self.ReadMemory(self.programCounter, 2));
            },
            0xCC => { if( self.flags.zero == true)
                self.StackPush(RegisterName.HL);
                self.jump(self.ReadMemory(self.programCounter, 2));
            },
            0xD4 => { if( self.flags.carry == false)
                self.StackPush(RegisterName.HL);
                self.jump(self.ReadMemory(self.programCounter, 2));
            },
            0xDC => { if( self.flags.carry == true)
                self.StackPush(RegisterName.HL);
                self.jump(self.ReadMemory(self.programCounter, 2));
            },

            // RST
            0xC7 => { self.StackPush(RegisterName.HL); self.jump(0x00); },
            0xCF => { self.StackPush(RegisterName.HL); self.jump(0x08); },
            0xD7 => { self.StackPush(RegisterName.HL); self.jump(0x10); },
            0xDF => { self.StackPush(RegisterName.HL); self.jump(0x18); },
            0xE7 => { self.StackPush(RegisterName.HL); self.jump(0x20); },
            0xEF => { self.StackPush(RegisterName.HL); self.jump(0x28); },
            0xF7 => { self.StackPush(RegisterName.HL); self.jump(0x30); },
            0xFF => { self.StackPush(RegisterName.HL); self.jump(0x38); },

            // RET
            // todo: RETI
            0xC9, 0xD9 => { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); },
            // RET cc
            0xC0 => { if( self.flags.zero == false) { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); } },
            0xC8 => { if( self.flags.zero == true) { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); } },
            0xD0 => {  if( self.flags.carry == false) { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); } },
            0xD8 => { if( self.flags.carry == true) { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); } },

            // zig fmt: on
            else => undefined,
        }
    }
    pub fn AddAndJump(self: *Self) void {
        self.AddToHL(self.ReadMemory(self.programCounter, 1));
        self.jump(self.ReadRegister(RegisterName.HL));
    }
    pub fn AddToHL(self: *Self, value: u16) void {
        const HL = self.ReadRegister(RegisterName.HL);
        self.WriteRegister(RegisterName.HL, self.add(HL, value, 2, false));
    }
    pub fn jump(self: *Self, address: u16) void {
        self.programCounter = address;
    }
    pub fn RegisterIncrement(self: *Self, register: RegisterName) void {
        self.registers[@intFromEnum(register)] +%= 0x1;
    }
    pub fn RegisterDecrement(self: *Self, register: RegisterName) void {
        self.registers[@intFromEnum(register)] -%= 0x1;
    }

    fn dumpStack(self: *Self) void {
        std.debug.print("\n== Stack ==\n", .{});
        var stackPtrOffset: u16 = 0xFFFE;
        const SP = self.ReadRegister(RegisterName.SP);
        while (stackPtrOffset > SP) : (stackPtrOffset -= 2) {
            std.debug.print("{X}: {X} {X}\n", .{ stackPtrOffset, self.ReadMemory(stackPtrOffset, 1), self.ReadMemory(stackPtrOffset + 1, 1) });
        }
        std.debug.print("== \\Stack ==\n", .{});
    }
    pub fn dump(self: *Self, msg: []const u8) void {
        var x: u8 = 0;
        std.debug.print("====  {s}  ====\n", .{msg});
        std.debug.print("PC: {X} SP: {X} Flags: {}\n", .{
            self.programCounter,
            self.ReadRegister(RegisterName.SP),
            self.flags,
        });

        while (x < 13) : (x += 1) {
            std.debug.print("{}: {X} => ({X})\n", .{
                @as(RegisterName, @enumFromInt(x)),
                self.registers[x],
                self.memory[self.registers[x]],
            });
        }

        std.debug.print("\nMemory Block [0..63]:\n", .{});
        x = 1;
        while (x < 64) : (x += 1) {
            if (x % 8 == 0) {
                std.debug.print("\n", .{});
            }
            std.debug.print("{X} ", .{self.memory[x - 1]});
        }
        self.dumpStack();
        std.debug.print("\n====  {s}  ====\n", .{msg});
    }
};

test {
    _ = @import("tests.zig");
}
