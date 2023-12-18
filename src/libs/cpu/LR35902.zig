const std = @import("std");
// const MMU = @import("mmu.zig");
const Bus = @import("bus.zig");
const Register = @import("register.zig");
const Instruction = @import("opcodes.zig").Instruction;
const InstructionList = @import("opcodes.zig").Instructions;

const Flags = struct { carry: bool = false, halfCarry: bool = false, zero: bool = false, subtraction: bool = false };

/// The CPU LR35902 is the heart of the gameboy.
pub fn CPU() type {
    return struct {
        programCounter: *u16, // pointer to the value in the PC register
        //todo: this needs to be connected to the bus
        ram: Bus.Bus(), //ROM0
        registers: Register, // the GB register bank
        currentInstruction: ?Instruction = null,
        totalCycles: usize = 0, // how many cycles since boot
        remainingCycles: usize = 0, // how many cycles to wait until next tick
        flags: Flags = Flags{},

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator) !Self {
            const reg = Register.init();
            const bus = try Bus.Bus().init(alloc);
            return Self{
                .ram = bus,
                .registers = reg,
                .programCounter = reg.pc,
            };
        }
        pub fn deinit(self: *Self) void {
            self.ram.deinit();
        }

        /// Ticks the CPU. An instruction is executed all at once. We then wait
        /// for the correct number of ticks until the next fetch. This decouples
        /// the clock rate of the GB from the lock rate of the emulator
        pub fn tick(self: *Self) !void {
            if (self.remainingCycles > 0) {
                self.remainingCycles -= 1;
            } else {
                try self.fetch();
            }
        }

        /// Fetches the next instruction from memory. Updates cycle counts and
        /// the program counter.
        pub fn fetch(self: *Self) !void {
            const opcode = try self.ram.read(self.programCounter.*, 1);
            self.currentInstruction = InstructionList[opcode];
            if (self.currentInstruction.?.category == .illegal) {
                std.debug.print("ILLEGAL OPCODE: 0x{X:0>2}\n", .{opcode});
            }

            self.totalCycles += self.currentInstruction.?.cycles;
            self.remainingCycles += self.currentInstruction.?.cycles;
            self.programCounter.* += 1;
            self.execute() catch |err| {
                std.debug.print("Failed executing instruction: {}\n", .{self.currentInstruction.?});
                return err;
            };
        }

        /// The main switching logic from instruction to emulator method
        pub fn execute(self: *Self) !void {
            switch (self.currentInstruction.?.category) {
                .byteLoad, .wordLoad => {
                    switch (self.currentInstruction.?.addressing) {
                        .immediate => try self.loadImmediate(self.currentInstruction.?),
                        .absolute => try self.loadAbsolute(self.currentInstruction.?),
                        .relative => try self.loadRelative(self.currentInstruction.?),
                        else => undefined,
                    }
                },
                .byteMath => try self.alu(self.currentInstruction.?),
                else => undefined,
            }
            const increment = self.currentInstruction.?.length;
            if (increment > 0)
                self.programCounter.* += increment - 1;
        }

        /// Loads an immediate value to the intructed destination
        pub fn loadImmediate(self: *Self, inst: Instruction) !void {
            const operand = switch (inst.category) {
                .byteLoad => try self.ram.read(self.programCounter.*, 1),
                .wordLoad => try self.ram.read(self.programCounter.*, 2),
                else => unreachable,
            };
            // std.debug.print("Writing 0x{X:0>2}@0x{X:0>4} to register {s}\n", .{ operand, self.programCounter.*, @tagName(inst.destination.?) });
            try self.registers.writeReg(inst.destination.?, operand);
        }

        /// Loads a value from the source register to the address at the location
        /// speicied by the destination
        pub fn loadAbsolute(self: *Self, inst: Instruction) !void {
            const commaPosition = std.mem.indexOf(u8, inst.name, ",");
            const parenPosition = std.mem.indexOf(u8, inst.name, "(");
            const decPos = std.mem.indexOf(u8, inst.name, "-");
            const incPos = std.mem.indexOf(u8, inst.name, "+");

            var address: u16 = 0;
            var value: u16 = 0;

            // hacky way to avoid adding more metadata to the opcodes
            if (parenPosition) |pos| {
                if (commaPosition.? > pos) {
                    address = try self.registers.readReg(inst.destination.?);
                    value = try self.registers.readReg(inst.source.?);
                    try self.ram.write(address, 1, value);
                } else if (commaPosition.? < pos) {
                    address = try self.registers.readReg(inst.source.?);
                    value = try self.ram.read(address, 1);
                    try self.registers.writeReg(inst.destination.?, value);
                }
            } else {
                address = try self.registers.readReg(inst.destination.?);
                value = try self.registers.readReg(inst.source.?);
                try self.ram.write(address, 1, value);
            }

            if (incPos) |pos| {
                if (pos > commaPosition.?) {
                    try self.registers.increment(inst.source.?);
                } else if (pos < commaPosition.?) {
                    try self.registers.increment(inst.destination.?);
                }
            }
            if (decPos) |pos| {
                if (pos > commaPosition.?) {
                    try self.registers.decrement(inst.source.?);
                } else if (pos < commaPosition.?) {
                    try self.registers.decrement(inst.destination.?);
                }
            }
            // std.debug.print(
            //     "Writing from ({s}) 0x{X:0>2} to ({s})0x{X:0>4} \n",
            //     .{ @tagName(inst.destination.?), value, @tagName(inst.source.?), address },
            // );
        }
        /// Loads a value from the source register to the location
        /// speicied by the destination + the program counter
        pub fn loadRelative(self: *Self, inst: Instruction) !void {
            const operand = switch (inst.category) {
                .byteLoad => try self.ram.read(self.programCounter.*, 1),
                .wordLoad => try self.ram.read(self.programCounter.*, 2),
                else => unreachable,
            };
            const address = try self.registers.readReg(inst.destination.?) + operand;
            const value = try self.registers.readReg(inst.source.?);
            // std.debug.print(
            //     "Writing from ({s}) 0x{X:0>2} to ({s})0x{X:0>4} \n",
            //     .{ @tagName(inst.destination.?), value, @tagName(inst.source.?), address },
            // );
            try self.ram.write(address, 2, value);
        }
        pub fn alu(self: *Self, inst: Instruction) !void {
            const originValue = switch (inst.addressing) {
                .absolute => try self.ram.read(try self.registers.readReg(inst.source.?), 1),
                .none => try self.registers.readReg(inst.source.?),
                .immediate => try self.ram.read(self.programCounter.*, 1),
                else => return error.InvalidAddressingForMathOperation,
            };
            const targetValue: u16 = try self.registers.readReg(inst.destination.?);
            var result: u16 = 0;
            var sub: bool = false;

            switch (inst.opcode) {
                0x80...0x87 => { // ADD
                    result = originValue + targetValue;
                    try self.registers.writeReg(inst.destination.?, result);
                    self.setFlags(originValue, targetValue, result, sub);
                },
                0x88...0x8F => { // ADC
                    result = originValue + targetValue + @intFromBool(self.flags.carry);
                    try self.registers.writeReg(inst.destination.?, result);
                    self.setFlags(originValue, targetValue, result, sub);
                },
                0x90...0x97 => { // SUB
                    result = targetValue - originValue;
                    sub = true;
                    try self.registers.writeReg(inst.destination.?, result);
                    self.setFlags(originValue, targetValue, result, sub);
                },
                0x98...0x9F => { // SBC
                    result = targetValue - originValue - @intFromBool(self.flags.carry);
                    sub = true;
                    try self.registers.writeReg(inst.destination.?, result);
                    self.setFlags(originValue, targetValue, result, sub);
                },
                0xA0...0xA7 => { // AND
                    result = targetValue & originValue;
                    try self.registers.writeReg(inst.destination.?, result);
                    self.flags.zero = result == 0;
                },
                0xA8...0xAF => { // XOR
                    result = targetValue ^ originValue;
                    try self.registers.writeReg(inst.destination.?, result);
                    self.flags.zero = result == 0;
                },
                0xB0...0xB7 => { // OR
                    result = targetValue | originValue;
                    try self.registers.writeReg(inst.destination.?, result);
                    self.flags.zero = result == 0;
                },
                0xB8...0xBF => { // CP
                    result = @intFromBool(targetValue == originValue);
                    try self.registers.writeReg(inst.destination.?, result);
                    self.flags.zero = result == 0;
                },
                else => return error.InvalidMathInstruction,
            }
        }
        pub fn setFlags(self: *Self, op1: u16, op2: u16, result: u16, sub: bool) void {
            const half_carry_8bit = (op1 ^ op2 ^ result) & 0x10 == 0x10;
            const carry_8bit = (op1 ^ op2 ^ result) & 0x100 == 0x100;
            const zero = result & 0xFF == 0;
            self.flags = .{
                .carry = carry_8bit,
                .halfCarry = half_carry_8bit,
                .subtraction = sub,
                .zero = zero,
            };
        }
    };
}

const eql = std.testing.expectEqual;
test "CPU: LoadImmediate" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    try cpu.ram.write(0x0, 2, 0xBEEF);
    const inst = InstructionList[0x01];
    try cpu.loadImmediate(inst);
    try eql(cpu.registers.readReg(.BC), 0xBEEF);
}

test "CPU: LoadAbsolute" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    try cpu.registers.writeReg(.A, 0x42);
    try cpu.registers.writeReg(.BC, 0x1337);
    const inst = InstructionList[0x02];
    try cpu.loadAbsolute(inst);
    try eql(try cpu.ram.read(0x1337, 1), 0x42);
}

test "CPU: LoadAbsolute(HL-)" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    try cpu.registers.writeReg(.A, 0x42);
    try cpu.registers.writeReg(.HL, 0x1337);
    var inst = InstructionList[0x32];
    try cpu.loadAbsolute(inst);
    try eql(try cpu.ram.read(0x1337, 1), 0x42);
    try eql(try cpu.registers.readReg(.HL), 0x1336);

    try cpu.registers.writeReg(.A, 0x0);
    try cpu.registers.writeReg(.HL, 0x1111);
    try cpu.ram.write(0x1111, 1, 0x49);
    inst = InstructionList[0x3A];
    try cpu.loadAbsolute(inst);
    try eql(try cpu.registers.readReg(.A), 0x49);
    try eql(try cpu.registers.readReg(.HL), 0x1110);
}

test "CPU: LoadRelative" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    try cpu.registers.writeReg(.PC, 0x0);
    try cpu.registers.writeReg(.SP, 0xBEEF);
    try cpu.ram.write(0x0, 2, 0x1337);
    const inst = InstructionList[0x08];
    try cpu.loadRelative(inst);
    try eql(try cpu.ram.read(0x1337, 2), 0xBEEF);
}

test "CPU: Tick & Fetch" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    const ldDEA = InstructionList[0x12];
    const ldEd8 = InstructionList[0x1E];

    // set up regsiters
    try cpu.registers.writeReg(.DE, 0x1337);
    try cpu.registers.writeReg(.A, 0x42);

    // manually write the instructions to ram
    try cpu.ram.write(0x0, 1, 0x12); // LD (DE),A
    try cpu.ram.write(0x1, 2, 0x1E11); //LD E,d8

    try cpu.tick();

    try eql(try cpu.ram.read(0x1337, 1), 0x42);
    try eql(cpu.programCounter.*, ldDEA.length);
    try eql(cpu.remainingCycles, ldDEA.cycles);
    try eql(cpu.totalCycles, ldDEA.cycles);
    for (cpu.remainingCycles) |_| {
        try cpu.tick();
    }
    try eql(cpu.totalCycles, 8);
    try eql(cpu.remainingCycles, 0);
    try eql(cpu.programCounter.*, ldDEA.length);

    try cpu.tick();

    // std.debug.print("{s}\n", .{cpu.registers});
    // std.debug.print("{s}\n", .{cpu.ram});
    try eql(try cpu.registers.readReg(.E), 0x11);
    try eql(cpu.programCounter.*, ldDEA.length + ldEd8.length);
    try eql(cpu.remainingCycles, ldEd8.cycles);
    try eql(cpu.totalCycles, ldDEA.cycles + ldEd8.cycles);
}

test "ALU: ADD" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    try cpu.registers.writeReg(.A, 2);
    try cpu.registers.writeReg(.L, 243);
    var inst = InstructionList[0x85];
    try cpu.alu(inst);
    try eql(try cpu.registers.readReg(.A), 245);

    try cpu.registers.writeReg(.HL, 0x1337);
    try cpu.registers.writeReg(.A, 0xFF);
    try cpu.ram.write(0x1337, 1, 7);
    inst = InstructionList[0x86];
    try cpu.alu(inst);
    try eql(try cpu.registers.readReg(.A), 6);
    try eql(cpu.flags, .{ .zero = false, .carry = true, .halfCarry = true, .subtraction = false });
}

test {
    std.testing.refAllDecls(@This());
}
