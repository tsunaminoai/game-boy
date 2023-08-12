const std = @import("std");
const RegisterName = @import("types.zig").RegisterName;
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

    pub fn ReadRegister(self: *Self, register: RegisterName) u16 {
        return self.registers[@intFromEnum(register)];
    }

    fn internalWriteRegister(self: *Self, register: RegisterName, value: u16) void {
        self.registers[@intFromEnum(register)] = value;
    }

    pub fn WriteRegister(self: *Self, register: RegisterName, value: u16) void {
        // std.debug.print("WriteRegister({},{}: {X})\n", .{ register, @TypeOf(value), value });
        self.internalWriteRegister(register, value);
        switch (register) {
            RegisterName.AF => {
                self.internalWriteRegister(RegisterName.A, value >> 8);
                self.internalWriteRegister(RegisterName.F, value & 0x0F);
            },
            RegisterName.BC => {
                self.internalWriteRegister(RegisterName.B, value >> 8);
                self.internalWriteRegister(RegisterName.C, value & 0x0F);
            },
            RegisterName.DE => {
                self.internalWriteRegister(RegisterName.D, value >> 8);
                self.internalWriteRegister(RegisterName.E, value & 0x0F);
            },
            RegisterName.HL => {
                self.internalWriteRegister(RegisterName.H, value >> 8);
                self.internalWriteRegister(RegisterName.L, value & 0x0F);
            },
            RegisterName.A => {
                const currentValue = self.ReadRegister(RegisterName.AF);
                self.internalWriteRegister(RegisterName.AF, (value << 8) | currentValue);
            },
            RegisterName.F => {
                const currentValue = self.ReadRegister(RegisterName.AF);
                self.internalWriteRegister(RegisterName.AF, (value & 0x0F) | currentValue);
            },
            RegisterName.B => {
                const currentValue = self.ReadRegister(RegisterName.BC);
                self.internalWriteRegister(RegisterName.BC, (value << 8) | currentValue);
            },
            RegisterName.C => {
                const currentValue = self.ReadRegister(RegisterName.BC);
                self.internalWriteRegister(RegisterName.BC, (value & 0x0F) | currentValue);
            },
            RegisterName.D => {
                const currentValue = self.ReadRegister(RegisterName.DE);
                self.internalWriteRegister(RegisterName.DE, (value << 8) | currentValue);
            },
            RegisterName.E => {
                const currentValue = self.ReadRegister(RegisterName.DE);
                self.internalWriteRegister(RegisterName.DE, (value & 0x0F) | currentValue);
            },
            RegisterName.H => {
                const currentValue = self.ReadRegister(RegisterName.HL);
                self.internalWriteRegister(RegisterName.HL, (value << 8) | currentValue);
            },
            RegisterName.L => {
                const currentValue = self.ReadRegister(RegisterName.HL);
                self.internalWriteRegister(RegisterName.HL, (value & 0x0F) | currentValue);
            },
            RegisterName.SP => {},
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

    fn LoadRegister(self: *Self, register: RegisterName) void {
        self.WriteRegister(register, self.memory[self.programCounter]);
    }
    fn LoadRegisterFromNN(self: *Self, register: RegisterName) void {
        var value: u16 = @as(u16, self.memory[self.programCounter + 1]);
        value = value << 8;
        value += self.memory[self.programCounter];
        self.WriteRegister(register, value);
    }
    fn LoadRegisterFromRegister(self: *Self, source: RegisterName, destination: RegisterName) void {
        self.WriteRegister(destination, self.ReadRegister(source));
    }
    fn LoadRegisterFromAddressNN(self: *Self, destination: RegisterName) void {
        var address: u16 = @as(u16, self.memory[self.programCounter + 1]);
        address = address << 8;
        address += self.memory[self.programCounter];

        self.WriteRegister(destination, self.memory[address]);
    }
    fn LoadRegisterFromAddressRegister(self: *Self, source: RegisterName, destination: RegisterName) void {
        self.WriteRegister(destination, self.memory[self.ReadRegister(source)]);
    }
    fn LoadRegisterFromOffsetN(self: *Self, register: RegisterName) void {
        self.WriteRegister(register, self.memory[self.memory[self.programCounter] + MemoryOffset]);
    }
    fn WriteMemoryFromOffsetN(self: *Self, register: RegisterName) void {
        self.memory[self.memory[self.programCounter] + MemoryOffset] = @as(u8, @truncate(self.ReadRegister(register)));
    }
    fn WriteMemoryByteFromRegister(self: *Self, sourceRegisterName: RegisterName, addressRegisterName: RegisterName) void {
        self.memory[self.ReadRegister(addressRegisterName)] = @as(u8, @truncate(self.ReadRegister(sourceRegisterName)));
    }
    fn WriteMemoryByteFromAddressNN(self: *Self, sourceRegisterName: RegisterName, double: bool) void {
        var address: u16 = @as(u16, self.memory[self.programCounter + 1]);
        address = address << 8;
        address += self.memory[self.programCounter];
        if (double) {
            self.memory[address] = @as(u8, @truncate(self.ReadRegister(sourceRegisterName) >> 8));
            self.memory[address + 1] = @as(u8, @truncate(self.ReadRegister(sourceRegisterName)));
        } else {
            self.memory[address] = @as(u8, @truncate(self.ReadRegister(sourceRegisterName)));
        }
    }
    fn StackPush(self: *Self, sourceRegisterName: RegisterName) void {
        const SP = self.ReadRegister(RegisterName.SP);
        const LSB = @as(u8, @truncate(self.ReadRegister(sourceRegisterName) >> 8));
        const MSB = @as(u8, @truncate(self.ReadRegister(sourceRegisterName)));
        self.memory[SP] = LSB;
        self.memory[SP + 1] = MSB;
        self.RegisterDecrement(RegisterName.SP);
        self.RegisterDecrement(RegisterName.SP);
    }
    fn StackPop(self: *Self, destinationRegisterName: RegisterName) void {
        const SP = self.ReadRegister(RegisterName.SP);
        var value: u16 = @as(u16, self.memory[SP]) << 8;
        value += @as(u16, self.memory[SP + 1]);

        self.WriteRegister(destinationRegisterName, value);
        self.RegisterIncrement(RegisterName.SP);
        self.RegisterIncrement(RegisterName.SP);
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
            0xFA => { self.LoadRegisterFromAddressNN( RegisterName.A); },
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
            0xEA => { self.WriteMemoryByteFromAddressNN(RegisterName.A, false); },

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

            0xE0 => { self.WriteMemoryFromOffsetN(RegisterName.A); },
            0xF0 => { self.LoadRegisterFromOffsetN(RegisterName.A); },

            //16-bit loads

            0x01 => { self.LoadRegisterFromNN(RegisterName.BC); },
            0x11 => { self.LoadRegisterFromNN(RegisterName.DE); },
            0x21 => { self.LoadRegisterFromNN(RegisterName.HL); },
            0x31 => { self.LoadRegisterFromNN(RegisterName.SP); },

            0xF9 => { self.LoadRegisterFromRegister(RegisterName.HL, RegisterName.SP); },

            0xF8 => {
                var SP: u32 = self.ReadRegister(RegisterName.SP);
                var NL: u32 =  self.memory[self.programCounter];
                const result = SP + NL;
                const halfCarry: bool = ((SP ^ NL ^ result) & 0x10) == 0x10;
                const carry: bool = (result & 0x10000) == 0x10000;
                if (halfCarry) self.FlagSet(Flag.HalfCarry) else self.FlagUnSet(Flag.HalfCarry);
                if (carry) self.FlagSet(Flag.Carry) else self.FlagUnSet(Flag.Carry);
                self.FlagUnSet(Flag.Zero);
                self.FlagUnSet(Flag.Subtraction);
                self.WriteRegister(RegisterName.SP, @as(u16,@truncate(result)));

            },

            0x08 => { self.WriteMemoryByteFromAddressNN(RegisterName.SP, true); },

            0xF5 => { self.StackPush(RegisterName.AF); },
            0xC5 => { self.StackPush(RegisterName.BC); },
            0xD5 => { self.StackPush(RegisterName.DE); },
            0xE5 => { self.StackPush(RegisterName.HL); },

            0xF1 => { self.StackPop(RegisterName.AF); },
            0xC1 => { self.StackPop(RegisterName.BC); },
            0xD1 => { self.StackPop(RegisterName.DE); },
            0xE1 => { self.StackPop(RegisterName.HL); },

            // zig fmt: on
            else => undefined,
        }

        self.dump("End");
    }
    pub fn RegisterIncrement(self: *Self, register: RegisterName) void {
        self.registers[@intFromEnum(register)] +%= 0x1;
    }
    pub fn RegisterDecrement(self: *Self, register: RegisterName) void {
        self.registers[@intFromEnum(register)] -%= 0x1;
    }

    pub fn dump(self: *Self, msg: []const u8) void {
        var x: u8 = 0;
        std.debug.print("====  {s}  ====\n", .{msg});
        std.debug.print("PC: {X} SP: {X} Flags: Z{} S{} H{} C{}\n", .{
            self.programCounter,
            self.ReadRegister(RegisterName.SP),
            self.FlagRead(Flag.Zero),
            self.FlagRead(Flag.Subtraction),
            self.FlagRead(Flag.HalfCarry),
            self.FlagRead(Flag.Carry),
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
        std.debug.print("\n====  {s}  ====\n", .{msg});
    }
};

test {
    _ = @import("tests.zig");
}
