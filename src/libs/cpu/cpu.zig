const std = @import("std");
const Register = @import("types.zig").Register;
const Flag = @import("types.zig").Flag;

// todo: fix this before merging, its only 10x because of the dump() fn
const MemorySize = 80000;
const MemoryOffset: u16 = 0xFF00;

pub const CPU = struct {
    memory: [MemorySize]u8 = [_]u8{0} ** MemorySize,
    registers: [14]u16 = [_]u16{0} ** 14,
    flags: [4]bool = [_]bool{false} ** 4,
    programCounter: u16 = 0,

    const Self = @This();
    const Address = u16;

    pub fn ReadRegister(self: *Self, register: Register) u16 {
        return self.registers[@intFromEnum(register)];
    }

    fn internalWriteRegister(self: *Self, register: Register, value: u16) void {
        self.registers[@intFromEnum(register)] = value;
    }

    pub fn WriteRegister(self: *Self, register: Register, value: u16) void {
        // std.debug.print("WriteRegister({},{}: {X})\n", .{ register, @TypeOf(value), value });
        self.internalWriteRegister(register, value);
        switch (register) {
            Register.AF => {
                self.internalWriteRegister(Register.A, value >> 8);
                self.internalWriteRegister(Register.F, value & 0x0F);
            },
            Register.BC => {
                self.internalWriteRegister(Register.B, value >> 8);
                self.internalWriteRegister(Register.C, value & 0x0F);
            },
            Register.DE => {
                self.internalWriteRegister(Register.D, value >> 8);
                self.internalWriteRegister(Register.E, value & 0x0F);
            },
            Register.HL => {
                self.internalWriteRegister(Register.H, value >> 8);
                self.internalWriteRegister(Register.L, value & 0x0F);
            },
            Register.A => {
                const currentValue = self.ReadRegister(Register.AF);
                self.internalWriteRegister(Register.AF, (value << 8) | currentValue);
            },
            Register.F => {
                const currentValue = self.ReadRegister(Register.AF);
                self.internalWriteRegister(Register.AF, (value & 0x0F) | currentValue);
            },
            Register.B => {
                const currentValue = self.ReadRegister(Register.BC);
                self.internalWriteRegister(Register.BC, (value << 8) | currentValue);
            },
            Register.C => {
                const currentValue = self.ReadRegister(Register.BC);
                self.internalWriteRegister(Register.BC, (value & 0x0F) | currentValue);
            },
            Register.D => {
                const currentValue = self.ReadRegister(Register.DE);
                self.internalWriteRegister(Register.DE, (value << 8) | currentValue);
            },
            Register.E => {
                const currentValue = self.ReadRegister(Register.DE);
                self.internalWriteRegister(Register.DE, (value & 0x0F) | currentValue);
            },
            Register.H => {
                const currentValue = self.ReadRegister(Register.HL);
                self.internalWriteRegister(Register.HL, (value << 8) | currentValue);
            },
            Register.L => {
                const currentValue = self.ReadRegister(Register.HL);
                self.internalWriteRegister(Register.HL, (value & 0x0F) | currentValue);
            },
            Register.SP => {},
        }
    }

    pub fn FlagSet(self: *Self, flag: Flag) void {
        self.flags[@intFromEnum(flag)] = true;
    }

    pub fn FlagUnSet(self: *Self, flag: Flag) void {
        self.flags[@intFromEnum(flag)] = false;
    }
    pub fn FlagRead(self: *Self, flag: Flag) bool {
        return self.flags[@intFromEnum(flag)];
    }

    fn LoadRegister(self: *Self, register: Register) void {
        self.WriteRegister(register, self.memory[self.programCounter]);
    }
    fn LoadRegisterFromNN(self: *Self, register: Register) void {
        var value: u16 = @as(u16, self.memory[self.programCounter + 1]);
        value = value << 8;
        value += self.memory[self.programCounter];
        self.WriteRegister(register, value);
    }
    fn LoadRegisterFromRegister(self: *Self, source: Register, destination: Register) void {
        self.WriteRegister(destination, self.ReadRegister(source));
    }
    fn LoadRegisterFromAddressNN(self: *Self, destination: Register) void {
        var address: u16 = @as(u16, self.memory[self.programCounter + 1]);
        address = address << 8;
        address += self.memory[self.programCounter];

        self.WriteRegister(destination, self.memory[address]);
    }
    fn LoadRegisterFromAddressRegister(self: *Self, source: Register, destination: Register) void {
        self.WriteRegister(destination, self.memory[self.ReadRegister(source)]);
    }
    fn LoadRegisterFromOffsetN(self: *Self, register: Register) void {
        self.WriteRegister(register, self.memory[self.memory[self.programCounter] + MemoryOffset]);
    }
    fn WriteMemoryFromOffsetN(self: *Self, register: Register) void {
        self.memory[self.memory[self.programCounter] + MemoryOffset] = @as(u8, @truncate(self.ReadRegister(register)));
    }
    fn WriteMemoryByteFromRegister(self: *Self, sourceRegister: Register, addressRegister: Register) void {
        self.memory[self.ReadRegister(addressRegister)] = @as(u8, @truncate(self.ReadRegister(sourceRegister)));
    }
    fn WriteMemoryByteFromAddressNN(self: *Self, sourceRegister: Register, double: bool) void {
        var address: u16 = @as(u16, self.memory[self.programCounter + 1]);
        address = address << 8;
        address += self.memory[self.programCounter];
        if (double) {
            self.memory[address] =  @as(u8, @truncate(self.ReadRegister(sourceRegister) >> 8));
            self.memory[address + 1] = @as(u8, @truncate(self.ReadRegister(sourceRegister)));
        } else {
            self.memory[address] = @as(u8, @truncate(self.ReadRegister(sourceRegister)));
        }
    }

    pub fn Tick(self: *Self) void {
        self.dump("Start");
        const opcode = self.memory[self.programCounter];
        self.programCounter += 1;
        switch (opcode) {
            // zig fmt: off

            //NOPE!
            0x00 => {},

            //8-bit loads

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
            0x7E => { self.LoadRegisterFromAddressRegister(Register.HL, Register.A); },

            0x40 => { self.LoadRegisterFromRegister(Register.B, Register.B); },
            0x41 => { self.LoadRegisterFromRegister(Register.C, Register.B); },
            0x42 => { self.LoadRegisterFromRegister(Register.D, Register.B); },
            0x43 => { self.LoadRegisterFromRegister(Register.E, Register.B); },
            0x44 => { self.LoadRegisterFromRegister(Register.H, Register.B); },
            0x45 => { self.LoadRegisterFromRegister(Register.L, Register.B); },
            0x46 => { self.LoadRegisterFromAddressRegister(Register.HL, Register.B); },

            0x48 => { self.LoadRegisterFromRegister(Register.B, Register.C); },
            0x49 => { self.LoadRegisterFromRegister(Register.C, Register.C); },
            0x4A => { self.LoadRegisterFromRegister(Register.D, Register.C); },
            0x4B => { self.LoadRegisterFromRegister(Register.E, Register.C); },
            0x4C => { self.LoadRegisterFromRegister(Register.H, Register.C); },
            0x4D => { self.LoadRegisterFromRegister(Register.L, Register.C); },
            0x4E => { self.LoadRegisterFromAddressRegister(Register.HL, Register.C); },

            0x50 => { self.LoadRegisterFromRegister(Register.B, Register.D); },
            0x51 => { self.LoadRegisterFromRegister(Register.C, Register.D); },
            0x52 => { self.LoadRegisterFromRegister(Register.D, Register.D); },
            0x53 => { self.LoadRegisterFromRegister(Register.E, Register.D); },
            0x54 => { self.LoadRegisterFromRegister(Register.H, Register.D); },
            0x55 => { self.LoadRegisterFromRegister(Register.L, Register.D); },
            0x56 => { self.LoadRegisterFromAddressRegister(Register.HL, Register.D); },

            0x58 => { self.LoadRegisterFromRegister(Register.B, Register.E); },
            0x59 => { self.LoadRegisterFromRegister(Register.C, Register.E); },
            0x5A => { self.LoadRegisterFromRegister(Register.D, Register.E); },
            0x5B => { self.LoadRegisterFromRegister(Register.E, Register.E); },
            0x5C => { self.LoadRegisterFromRegister(Register.H, Register.E); },
            0x5D => { self.LoadRegisterFromRegister(Register.L, Register.E); },
            0x5E => { self.LoadRegisterFromAddressRegister(Register.HL, Register.E); },

            0x60 => { self.LoadRegisterFromRegister(Register.B, Register.H); },
            0x61 => { self.LoadRegisterFromRegister(Register.C, Register.H); },
            0x62 => { self.LoadRegisterFromRegister(Register.D, Register.H); },
            0x63 => { self.LoadRegisterFromRegister(Register.E, Register.H); },
            0x64 => { self.LoadRegisterFromRegister(Register.H, Register.H); },
            0x65 => { self.LoadRegisterFromRegister(Register.L, Register.H); },
            0x66 => { self.LoadRegisterFromAddressRegister(Register.HL, Register.H); },

            0x68 => { self.LoadRegisterFromRegister(Register.B, Register.L); },
            0x69 => { self.LoadRegisterFromRegister(Register.C, Register.L); },
            0x6A => { self.LoadRegisterFromRegister(Register.D, Register.L); },
            0x6B => { self.LoadRegisterFromRegister(Register.E, Register.L); },
            0x6C => { self.LoadRegisterFromRegister(Register.H, Register.L); },
            0x6D => { self.LoadRegisterFromRegister(Register.L, Register.L); },
            0x6E => { self.LoadRegisterFromAddressRegister(Register.HL, Register.L); },

            0x70 => { self.WriteMemoryByteFromRegister(Register.B, Register.HL); },
            0x71 => { self.WriteMemoryByteFromRegister(Register.C, Register.HL); },
            0x72 => { self.WriteMemoryByteFromRegister(Register.D, Register.HL); },
            0x73 => { self.WriteMemoryByteFromRegister(Register.E, Register.HL); },
            0x74 => { self.WriteMemoryByteFromRegister(Register.H, Register.HL); },
            0x75 => { self.WriteMemoryByteFromRegister(Register.L, Register.HL); },
            0x36 => { self.LoadRegister( Register.HL); },

            0x0A => { self.LoadRegisterFromAddressRegister(Register.BC, Register.A); },
            0x1A => { self.LoadRegisterFromAddressRegister(Register.DE, Register.A); },
            0xFA => { self.LoadRegisterFromAddressNN( Register.A); },
            0x3E => { self.LoadRegister( Register.A ); },

            0x47 => { self.LoadRegisterFromRegister( Register.A, Register.B ); },
            0x4F => { self.LoadRegisterFromRegister( Register.A, Register.C ); },
            0x57 => { self.LoadRegisterFromRegister( Register.A, Register.D ); },
            0x5F => { self.LoadRegisterFromRegister( Register.A, Register.E ); },
            0x67 => { self.LoadRegisterFromRegister( Register.A, Register.H ); },
            0x6F => { self.LoadRegisterFromRegister( Register.A, Register.L ); },
            0x02 => { self.WriteMemoryByteFromRegister(Register.A, Register.BC); },
            0x12 => { self.WriteMemoryByteFromRegister(Register.A, Register.DE); },
            0x77 => { self.WriteMemoryByteFromRegister(Register.A, Register.HL); },
            0xEA => { self.WriteMemoryByteFromAddressNN(Register.A, false); },

            // LDD A,(HL)
            0x3A => {
                self.LoadRegisterFromAddressRegister(Register.HL, Register.A);
                self.RegisterDecrement(Register.HL);
            },
            // LDD (HL),A
            0x32 => {
                self.WriteMemoryByteFromRegister(Register.A, Register.HL);
                self.RegisterDecrement(Register.HL);
            },
            // LDI A,(HL)
            0x2A => {
                self.LoadRegisterFromAddressRegister(Register.HL, Register.A);
                self.RegisterIncrement(Register.HL);
            },
            // LDI (HL),A
            0x22 => {
                self.WriteMemoryByteFromRegister(Register.A, Register.HL);
                self.RegisterIncrement(Register.HL);
            },

            0xE0 => { self.WriteMemoryFromOffsetN(Register.A); },
            0xF0 => { self.LoadRegisterFromOffsetN(Register.A); },

            //16-bit loads

            0x01 => { self.LoadRegisterFromNN(Register.BC); },
            0x11 => { self.LoadRegisterFromNN(Register.DE); },
            0x21 => { self.LoadRegisterFromNN(Register.HL); },
            0x31 => { self.LoadRegisterFromNN(Register.SP); },

            0xF9 => { self.LoadRegisterFromRegister(Register.HL, Register.SP); },

            0xF8 => {
                var SP: u32 = self.ReadRegister(Register.SP);
                var NL: u32 =  self.memory[self.programCounter];
                const result = SP + NL;
                const halfCarry: bool = ((SP ^ NL ^ result) & 0x10) == 0x10;
                const carry: bool = (result & 0x10000) == 0x10000;
                if (halfCarry) self.FlagSet(Flag.HalfCarry) else self.FlagUnSet(Flag.HalfCarry);
                if (carry) self.FlagSet(Flag.Carry) else self.FlagUnSet(Flag.Carry);
                self.FlagUnSet(Flag.Zero);
                self.FlagUnSet(Flag.Subtraction);
                self.WriteRegister(Register.SP, @as(u16,@truncate(result)));

            },

            0x08 => { self.WriteMemoryByteFromAddressNN(Register.SP, true); },

            // zig fmt: on
            else => undefined,
        }

        self.dump("End");
    }
    pub fn RegisterIncrement(self: *Self, register: Register) void {
        self.registers[@intFromEnum(register)] +%= 0x1;
    }
    pub fn RegisterDecrement(self: *Self, register: Register) void {
        self.registers[@intFromEnum(register)] -%= 0x1;
    }

    pub fn dump(self: *Self, msg: []const u8) void {
        var x: u8 = 0;
        std.debug.print("====  {s}  ====\n", .{msg});
        std.debug.print("PC: {X} SP: {X} Flags: Z{} S{} H{} C{}\n", .{
            self.programCounter,
            self.ReadRegister(Register.SP),
            self.FlagRead(Flag.Zero),
            self.FlagRead(Flag.Subtraction),
            self.FlagRead(Flag.HalfCarry),
            self.FlagRead(Flag.Carry),
        });

        while (x < 13) : (x += 1) {
            std.debug.print("{}: {X} => ({X})\n", .{
                @as(Register, @enumFromInt(x)),
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
        std.debug.print("\n====  {s}  ====\n", .{msg});
    }
};

test {
    _ = @import("tests.zig");
}
