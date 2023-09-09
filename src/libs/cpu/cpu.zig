const std = @import("std");
pub const RegisterName = @import("types.zig").RegisterName;
const Flags = @import("types.zig").Flags;
const MOps = @import("types.zig").MathOperations;

const Self = @This();

memory: [MemorySize]u16 = [_]u16{0} ** MemorySize,
flags: Flags = Flags{},
programCounter: u16 = 0,
currentIntruction: u16 = 0,
ticks: u16 = 0,
halt: bool = false,
registers: std.EnumArray(RegisterName, u16) = std.EnumArray(RegisterName, u16).initFill(0),

const Address = u16;

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

pub fn Run(self: *Self) !void {
    _ = self;
}

pub fn ReadRegister(self: *Self, register: RegisterName) u16 {
    return self.registers.get(register);
}

// We're going to take advantage of the fact that there are 8 8bit registers and their
// doubled up counterparts are esily mappable.
pub fn WriteRegister(self: *Self, register: RegisterName, value: u16) void {
    self.registers.set(register, value);

    switch (register) {
        RegisterName.AF => {
            self.registers.set(RegisterName.A, getLSB(value));
            self.registers.set(RegisterName.F, getMSB(value));
        },
        RegisterName.BC => {
            self.registers.set(RegisterName.B, getLSB(value));
            self.registers.set(RegisterName.C, getMSB(value));
        },
        RegisterName.DE => {
            self.registers.set(RegisterName.D, getLSB(value));
            self.registers.set(RegisterName.E, getMSB(value));
        },
        RegisterName.HL => {
            self.registers.set(RegisterName.H, getLSB(value));
            self.registers.set(RegisterName.L, getMSB(value));
        },
        RegisterName.A => {
            self.registers.set(RegisterName.AF, setLSB(self.ReadRegister(RegisterName.AF), value));
        },
        RegisterName.F => {
            self.registers.set(RegisterName.AF, setMSB(self.ReadRegister(RegisterName.AF), value));
        },
        RegisterName.B => {
            self.registers.set(RegisterName.BC, setLSB(self.ReadRegister(RegisterName.BC), value));
        },
        RegisterName.C => {
            self.registers.set(RegisterName.BC, setMSB(self.ReadRegister(RegisterName.BC), value));
        },
        RegisterName.D => {
            self.registers.set(RegisterName.DE, setLSB(self.ReadRegister(RegisterName.DE), value));
        },
        RegisterName.E => {
            self.registers.set(RegisterName.DE, setMSB(self.ReadRegister(RegisterName.DE), value));
        },
        RegisterName.H => {
            self.registers.set(RegisterName.HL, setLSB(self.ReadRegister(RegisterName.HL), value));
        },
        RegisterName.L => {
            self.registers.set(RegisterName.HL, setMSB(self.ReadRegister(RegisterName.HL), value));
        },
        RegisterName.SP => {},
    }
}

fn LoadRegister(self: *Self, register: RegisterName) void {
    self.WriteRegister(register, self.memory[self.programCounter]);
    self.incPC(1);
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

fn incPC(self: *Self, by: u16) void {
    self.programCounter += by;
}

fn fetchInstruction(self: *Self) u16 {
    const inst = self.memory[self.programCounter];
    self.currentIntruction = inst;
    self.incPC(1);
    return inst;
}

pub fn Tick(self: *Self) void {
    const opcode = self.fetchInstruction();
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
        0x78 ... 0x7D => { self.LoadRegisterFromRegister(@as(RegisterName,@enumFromInt(opcode - 0x78)),RegisterName.A); },
        0x7E => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.A); },
        0x7F => { self.LoadRegisterFromRegister(RegisterName.A,RegisterName.A); },

        0x40 ... 0x45 => { self.LoadRegisterFromRegister(@as(RegisterName,@enumFromInt(opcode - 0x40)), RegisterName.B); },
        0x46 => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.B); },

        0x48 ... 0x4D => { self.LoadRegisterFromRegister(@as(RegisterName,@enumFromInt(opcode - 0x48)), RegisterName.C); },
        0x4E => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.C); },

        0x50 ... 0x55 => { self.LoadRegisterFromRegister(@as(RegisterName,@enumFromInt(opcode - 0x50)), RegisterName.D); },
        0x56 => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.D); },

        0x58 ... 0x5D => { self.LoadRegisterFromRegister(@as(RegisterName,@enumFromInt(opcode - 0x58)), RegisterName.E); },
        0x5E => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.E); },

        0x60 ... 0x65 => { self.LoadRegisterFromRegister(@as(RegisterName,@enumFromInt(opcode - 0x60)), RegisterName.H); },
        0x66 => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.H); },

        0x68 ... 0x6D => { self.LoadRegisterFromRegister(@as(RegisterName,@enumFromInt(opcode - 0x68)), RegisterName.L); },
        0x6E => { self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.L); },

        0x70 ... 0x75 => { self.WriteMemoryByteFromRegister(@as(RegisterName,@enumFromInt(opcode - 0x70)), RegisterName.HL); },
        0x36 => { self.LoadRegister( RegisterName.HL); },

        0x0A => { self.LoadRegisterFromAddressRegister(RegisterName.BC, RegisterName.A); },
        0x1A => { self.LoadRegisterFromAddressRegister(RegisterName.DE, RegisterName.A); },
        0xFA => { self.WriteRegister(RegisterName.A, self.ReadMemory(self.ReadMemory(self.programCounter, 2), 1)); self.incPC(2); },
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
            self.incPC(2); self.RegisterDecrement(RegisterName.HL);
        },
        // LDD (HL),A
        0x32 => {
            self.WriteMemoryByteFromRegister(RegisterName.A, RegisterName.HL);
            self.incPC(2); self.RegisterDecrement(RegisterName.HL);
        },
        // LDI A,(HL)
        0x2A => {
            self.LoadRegisterFromAddressRegister(RegisterName.HL, RegisterName.A);
            self.incPC(2); self.RegisterIncrement(RegisterName.HL);
        },
        // LDI (HL),A
        0x22 => {
            self.WriteMemoryByteFromRegister(RegisterName.A, RegisterName.HL);
            self.incPC(2); self.RegisterIncrement(RegisterName.HL);
        },
        // LD (C),A
        0xE2 => {
            self.WriteMemory(0xFF00 + self.ReadRegister(RegisterName.C), self.ReadRegister(RegisterName.A), 1);
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
        0x01 => { self.WriteRegister(RegisterName.BC, self.ReadMemory(self.programCounter, 2)); self.incPC(2); },
        0x11 => { self.WriteRegister(RegisterName.DE, self.ReadMemory(self.programCounter, 2)); self.incPC(2); },
        0x21 => { self.WriteRegister(RegisterName.HL, self.ReadMemory(self.programCounter, 2)); self.incPC(2); },
        0x31 => { self.WriteRegister(RegisterName.SP, self.ReadMemory(self.programCounter, 2)); self.incPC(2); },

        0xF9 => { self.LoadRegisterFromRegister(RegisterName.HL, RegisterName.SP); },

        0xF8 => {
            // get effective address
            const eax = self.add(self.ReadRegister(RegisterName.SP), self.ReadMemory(self.programCounter,1), 2, false);
            self.incPC(1);
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
        0x80 ... 0x85 => { self.RegisterAMOps(MOps.add, self.ReadRegister(@as(RegisterName,@enumFromInt(opcode - 0x80))), 1, false); },
        0x86 => { self.RegisterAMOps(MOps.add, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 1, false); },
        0x87 => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.A), 1, false); },
        0xC6 => { self.RegisterAMOps(MOps.add, self.ReadMemory(self.programCounter, 1), 1, false); },

        // ADC A,n
        0x88 ... 0x8D => { self.RegisterAMOps(MOps.add, self.ReadRegister(@as(RegisterName,@enumFromInt(opcode - 0x88))), 1, true); },
        0x8E => { self.RegisterAMOps(MOps.add, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 1, true); },
        0x8F => { self.RegisterAMOps(MOps.add, self.ReadRegister(RegisterName.A), 1, true); },
        0xCE => { self.RegisterAMOps(MOps.add, self.ReadMemory(self.programCounter, 1), 1, true); },

        // SUB A,n
        0x90 ... 0x95 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(@as(RegisterName,@enumFromInt(opcode - 0x90))), 1, false); },
        0x96 => { self.RegisterAMOps(MOps.subtract, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 1, false); },
        0x97 => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.A), 1, false); },
        0xD6 => { self.RegisterAMOps(MOps.subtract, self.ReadMemory(self.programCounter, 1), 1, false); },

        // SBC A.n
        0x98 ... 0x9D => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(@as(RegisterName,@enumFromInt(opcode - 0x98))), 1, true); },
        0x9E => { self.RegisterAMOps(MOps.subtract, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 1, true); },
        0x9F => { self.RegisterAMOps(MOps.subtract, self.ReadRegister(RegisterName.A), 1, true); },
        // undefined 0x?? => { self.RegisterAMOps(MOps.subtract, self.ReadMemory(self.programCounter, 1), 1, true); }

        // AND
        0xA0 ... 0xA5 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadRegister(@as(RegisterName,@enumFromInt(opcode - 0xA0))), 0, false); },
        0xA6 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0, false); },
        0xA7 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadRegister(RegisterName.A), 0, false); },
        0xE6 => { self.RegisterAMOps(MOps.logicalAnd, self.ReadMemory(self.programCounter, 1), 0, false); },

        // XOR
        0xA8 ... 0xAD => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(@as(RegisterName,@enumFromInt(opcode - 0xA8))), 0, false); },
        0xAE => { self.RegisterAMOps(MOps.logicalOr, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0, false); },
        0xAF => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.A), 0, false); },
        0xEE => { self.RegisterAMOps(MOps.logicalOr, self.ReadMemory(self.programCounter, 1), 0, false); },

        // OR
        0xB0 ... 0xB5 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(@as(RegisterName,@enumFromInt(opcode - 0xB0))), 0, false); },
        0xB6 => { self.RegisterAMOps(MOps.logicalOr, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0, false); },
        0xB7 => { self.RegisterAMOps(MOps.logicalOr, self.ReadRegister(RegisterName.A), 0, false); },
        0xF6 => { self.RegisterAMOps(MOps.logicalOr, self.ReadMemory(self.programCounter, 1), 0, false); },


        // CMP
        0xB8 ... 0xBD => { self.RegisterAMOps(MOps.cmp, self.ReadRegister(@as(RegisterName,@enumFromInt(opcode - 0xB8))), 0, false); },
        0xBE => { self.RegisterAMOps(MOps.cmp, self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0, false); },
        0xBF => { self.RegisterAMOps(MOps.cmp, self.ReadRegister(RegisterName.A), 0, false); },
        0xFE => { self.RegisterAMOps(MOps.cmp, self.ReadMemory(self.programCounter, 1), 0, false); },

        // INC
        0x04 ,0x0C ,0x14 ,0x1C ,0x24 ,0x2C => { self.RegisterIncrement(@as(RegisterName,@enumFromInt((opcode - 0x04)/8 ))); },
        0x34 => { self.WriteMemory(self.ReadRegister(RegisterName.HL), self.add(self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0x1, 1, false), 1); },
        0x3C => { self.RegisterIncrement(RegisterName.A); },
        0x03 => { self.RegisterIncrement(RegisterName.BC); },
        0x13 => { self.RegisterIncrement(RegisterName.DE); },
        0x23 => { self.RegisterIncrement(RegisterName.HL); },
        0x33 => { self.RegisterIncrement(RegisterName.SP); },

        // DEC
        0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D => { self.RegisterDecrement(@as(RegisterName,@enumFromInt((opcode - 0x05)/8 ))); },
        0x35 => { self.WriteMemory(self.ReadRegister(RegisterName.HL), self.subtract(self.ReadMemory(self.ReadRegister(RegisterName.HL), 1), 0x1, 1, false), 1); },
        0x3D => { self.RegisterDecrement(RegisterName.A); },
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
            self.incPC(1);
        },

        // JP nn
        0xC3 => { self.jump(self.ReadMemory(self.programCounter, 2)); },
        // JP cc,nn
        0xC2 => { if( self.flags.zero == false)  { self.jump(self.ReadMemory(self.programCounter, 2)); } else { self.incPC(2) ; } },
        0xCA => { if( self.flags.zero == true)   { self.jump(self.ReadMemory(self.programCounter, 2)); } else { self.incPC(2) ; } },
        0xD2 => { if( self.flags.carry == false) { self.jump(self.ReadMemory(self.programCounter, 2)); } else { self.incPC(2) ; } },
        0xDA => { if( self.flags.carry == true)  { self.jump(self.ReadMemory(self.programCounter, 2)); } else { self.incPC(2) ; } },
        0xE9 => { self.jump(self.ReadMemory(self.ReadRegister(RegisterName.HL), 2)); },

        // JR n
        0x18 => { self.AddAndJump(); },
        0x20 => { if( self.flags.zero == false)  { self.AddAndJump(); } else { self.incPC(1); } },
        0x28 => { if( self.flags.zero == true)   { self.AddAndJump(); } else { self.incPC(1); } },
        0x30 => { if( self.flags.carry == false) { self.AddAndJump(); } else { self.incPC(1); } },
        0x38 => { if( self.flags.carry == true)  { self.AddAndJump(); } else { self.incPC(1); } },

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
        0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF => { self.StackPush(RegisterName.HL); self.jump(opcode - 0xC7); },

        // RET
        // todo: RETI
        0xC9, 0xD9 => { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); },
        // RET cc
        0xC0 => { if( self.flags.zero == false) { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); } },
        0xC8 => { if( self.flags.zero == true) { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); } },
        0xD0 => {  if( self.flags.carry == false) { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); } },
        0xD8 => { if( self.flags.carry == true) { self.StackPop(RegisterName.HL); self.jump(self.ReadRegister(RegisterName.HL)); } },

        // RLA
        0x17 => {
            self.flags.halfCarry = false;
            self.flags.subtraction = false;
            var A = self.ReadRegister(RegisterName.A);
            const bit7 = A & 0x80;
            A = A << 1;
            A = A & 0xFF;
            A += @as(u16, @intFromBool(self.flags.carry));
            self.flags.carry = bit7 == 0x80;
            self.WriteRegister(RegisterName.A, A);
            self.flags.zero = A == 0x0;
        },
        // RRA
        0x1F => {
            self.flags.halfCarry = false;
            self.flags.subtraction = false;
            var A = self.ReadRegister(RegisterName.A);
            const bit0 = A & 0x1;
            A = A >> 1;
            A += @as(u16, @intFromBool(self.flags.carry)) << 7;
            A = A & 0xFF;
            self.flags.carry = bit0 == 0x1;
            self.WriteRegister(RegisterName.A, A);
            self.flags.zero = A == 0x0;
        },
        // PREFIX CB
        0xCB => {
            const notPrefix = self.fetchInstruction();
            switch (notPrefix) {

                0x10...0x15 => {
                    self.WriteRegister(@as(RegisterName, @enumFromInt(notPrefix - 0x10)), self.ReadRegister(@as(RegisterName, @enumFromInt(notPrefix - 0x10))));
                },
                0x16 => {
                    self.WriteMemory(self.ReadRegister(RegisterName.HL), self.RotateL(self.ReadMemory(self.ReadRegister(RegisterName.HL), 1)), 1);
                },
                0x17 => {
                    self.WriteRegister(RegisterName.A, self.ReadRegister(RegisterName.A));
                },
                0x30...0x35 => {
                    self.WriteRegister(@as(RegisterName, @enumFromInt(notPrefix - 0x30)), self.swap(self.ReadRegister(@as(RegisterName, @enumFromInt(notPrefix - 0x30)))));
                },
                0x36 => {
                    self.WriteMemory(self.ReadRegister(RegisterName.HL), self.swap(self.ReadMemory(self.ReadRegister(RegisterName.HL), 1)), 1);
                },
                0x37 => {
                    self.WriteRegister(RegisterName.A, self.swap(self.ReadRegister(RegisterName.A)));
                },
                else => {
                    std.debug.panic("PREFIX OPERATION {x} NOT IMPLEMENTED", .{notPrefix});
                    unreachable;
            },
            }
        },

            else => {
                std.debug.panic("OPCODE {x} NOT IMPLEMENTED", .{opcode});
                unreachable;
            },
        }
}

fn RotateL(self: *Self, value: u16) u16 {
    const C: u16 = if (self.flags.carry) 1 else 0;
    self.flags.carry = (value & 0x80) == 0x80;
    return value * 2 + C;
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
    self.registers.set(register, self.registers.get(register) +% 0x1);
}
pub fn RegisterDecrement(self: *Self, register: RegisterName) void {
    self.registers.set(register, self.registers.get(register) -% 0x1);
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
            self.registers.get(@enumFromInt(x)),
            self.memory[self.registers.get(@enumFromInt(x))],
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
    //self.dumpStack();
    std.debug.print("\n====  {s}  ====\n", .{msg});
}

test {
    _ = @import("tests.zig");
}
