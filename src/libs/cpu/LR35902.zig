const std = @import("std");

const Bus = @import("bus.zig");
const Register = @import("register.zig");
const Instruction = @import("opcodes.zig").Instruction;
const InstructionList = @import("opcodes.zig").Instructions;

pub const Flags = struct { carry: bool = false, halfCarry: bool = false, zero: bool = false, subtraction: bool = false };

pub const CPUError = error{
    InvalidInstruction,
    InvalidAddressingForMathOperation,
    InvalidMathInstruction,
} || Bus.BusError || Register.RegisterError;

/// The CPU LR35902 is the heart of the gameboy.
pub fn CPU() type {
    return struct {
        programCounter: *u16, // pointer to the value in the PC register
        //todo: this needs to be connected to the bus
        bus: Bus.Bus(), //ROM0
        registers: Register.Register, // the GB register bank
        currentInstruction: ?Instruction = null,
        totalCycles: usize = 0, // how many cycles since boot
        remainingCycles: usize = 0, // how many cycles to wait until next tick
        flags: Flags = Flags{},

        const Self = @This();
        var ticks: usize = 0;

        /// Initializes the CPU. This will also initialize the bus and the
        /// register bank
        pub fn init(alloc: std.mem.Allocator) CPUError!Self {
            const reg = Register.Register.init();
            const bus = try Bus.Bus().init(alloc);
            return Self{
                .bus = bus,
                .registers = reg,
                .programCounter = reg.pc,
            };
        }
        pub fn deinit(self: *Self) void {
            self.bus.deinit();
        }

        /// Ticks the CPU. An instruction is executed all at once. We then wait
        /// for the correct number of ticks until the next fetch. This decouples
        /// the clock rate of the GB from the lock rate of the emulator
        pub fn tick(self: *Self) CPUError!void {
            std.log.debug("Tick: {}\tCurrent Cycles: {}", .{ ticks, self.remainingCycles });
            ticks += 1;
            if (self.remainingCycles > 0) {
                self.remainingCycles -= 1;
            } else {
                try self.fetch();
            }
        }

        /// Fetches the next instruction from memory. Updates cycle counts and
        /// the program counter.
        pub fn fetch(self: *Self) CPUError!void {
            const opcode = try self.bus.read(self.programCounter.*, 1);
            self.currentInstruction = InstructionList[opcode];
            if (self.currentInstruction.?.category == .illegal) {
                std.log.debug("ILLEGAL OPCODE: 0x{X:0>2}", .{opcode});
            }

            self.totalCycles += self.currentInstruction.?.cycles;
            self.remainingCycles += self.currentInstruction.?.cycles;
            self.programCounter.* += 1;
            self.execute() catch |err| {
                std.log.debug("Failed executing instruction: {}", .{self.currentInstruction.?});
                return err;
            };
        }

        /// The main switching logic from instruction to emulator method
        pub fn execute(self: *Self) CPUError!void {
            std.log.debug("Executing instruction: {?}", .{self.currentInstruction});
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
        pub fn loadImmediate(self: *Self, inst: Instruction) CPUError!void {
            std.log.debug("loadImmediate", .{});

            const operand = switch (inst.category) {
                .byteLoad => try self.bus.read(self.programCounter.*, 1),
                .wordLoad => try self.bus.read(self.programCounter.*, 2),
                else => unreachable,
            };
            // std.log.debug("Writing 0x{X:0>2}@0x{X:0>4} to register {s}", .{ operand, self.programCounter.*, @tagName(inst.destination.?) });
            try self.registers.writeReg(inst.destination.?, operand);
        }

        /// Loads a value from the source register to the address at the location
        /// speicied by the destination
        pub fn loadAbsolute(self: *Self, inst: Instruction) CPUError!void {
            std.log.debug("loadAbsolute", .{});
            const commaPosition = std.mem.indexOf(u8, inst.name, ",");
            const parenPosition = std.mem.indexOf(u8, inst.name, "(");
            const decPos = std.mem.indexOf(u8, inst.name, "-");
            const incPos = std.mem.indexOf(u8, inst.name, "+");

            const operand = switch (inst.category) {
                .byteLoad => try self.bus.read(self.programCounter.*, 1),
                .wordLoad => try self.bus.read(self.programCounter.*, 2),
                else => unreachable,
            };

            const source = if (inst.source) |d| d else null;
            const destination = if (inst.destination) |d| d else null;
            if (source == null) std.log.warn("loadAbsolute: source is null", .{});
            if (destination == null) std.log.warn("loadAbsolute: destination is null", .{});

            var address: u16 = 0;
            var value: u16 = 0;

            // hacky way to avoid adding more metadata to the opcodes
            if (parenPosition) |pos| {

                // this is for (x),R instructions
                if (commaPosition.? > pos) {
                    address = if (destination) |d| try self.registers.readReg(d) else operand;
                    value = try self.registers.readReg(source);
                    try self.bus.write(address, 1, value);
                    // this is for R,(x) instructions
                } else if (commaPosition.? < pos) {
                    address = try self.registers.readReg(source);
                    value = try self.bus.read(address, 1);

                    try self.registers.writeReg(destination, value);
                }
            } else {
                address = try self.registers.readReg(destination);
                value = try self.registers.readReg(source);
                try self.bus.write(address, 1, value);
            }

            if (incPos) |pos| {
                if (pos > commaPosition.?) {
                    try self.registers.increment(source);
                } else if (pos < commaPosition.?) {
                    try self.registers.increment(destination);
                }
            }
            if (decPos) |pos| {
                if (pos > commaPosition.?) {
                    try self.registers.decrement(source);
                } else if (pos < commaPosition.?) {
                    try self.registers.decrement(destination);
                }
            }
            // std.log.debug(
            //     "Writing from ({s}) 0x{X:0>2} to ({s})0x{X:0>4} \n",
            //     .{ @tagName(inst.destination.?), value, @tagName(inst.source.?), address },
            // );
        }
        /// Loads a value from the source register to the location
        /// speicied by the destination + the program counter
        pub fn loadRelative(self: *Self, inst: Instruction) CPUError!void {
            std.log.debug("loadRelative", .{});

            const operand = switch (inst.category) {
                .byteLoad => try self.bus.read(self.programCounter.*, 1),
                .wordLoad => try self.bus.read(self.programCounter.*, 2),
                else => unreachable,
            };

            const dest = if (inst.destination) |d| d else {
                std.log.err("Desination not provided for relative load: {}\n", .{inst});
                return error.InvalidInstruction;
            };

            const src = if (inst.source) |d| d else {
                std.log.err("Source not provided for relative load: {}\n", .{inst});
                return error.InvalidInstruction;
            };

            const address = try self.registers.readReg(dest) + operand;
            const value = try self.registers.readReg(src);
            // std.log.debug(
            //     "Writing from ({s}) 0x{X:0>2} to ({s})0x{X:0>4} \n",
            //     .{ @tagName(inst.destination.?), value, @tagName(inst.source.?), address },
            // );
            try self.bus.write(address, 2, value);
        }
        pub fn alu(self: *Self, inst: Instruction) CPUError!void {
            std.log.debug("ALU instruction: {}", .{inst});

            const originValue = switch (inst.addressing) {
                .absolute => try self.bus.read(try self.registers.readReg(inst.source.?), 1),
                .none => try self.registers.readReg(inst.source.?),
                .immediate => try self.bus.read(self.programCounter.*, 1),
                else => return error.InvalidAddressingForMathOperation,
            };
            const targetValue: u16 = try self.registers.readReg(inst.destination.?);
            var result: u16 = 0;
            var sub: bool = false;
            std.log.debug("ALU input: origin:{} target:{}\n", .{ originValue, targetValue });

            switch (inst.opcode) {
                0x80...0x87 => { // ADD
                    result = originValue +% targetValue;
                    try self.registers.writeReg(inst.destination.?, result);
                    self.setFlags(originValue, targetValue, result, sub);
                },
                0x88...0x8F, 0xCE => { // ADC
                    result = originValue +% targetValue +% @intFromBool(self.flags.carry);
                    try self.registers.writeReg(inst.destination.?, result);
                    self.setFlags(originValue, targetValue, result, sub);
                },
                0x90...0x97 => { // SUB
                    result = targetValue -% originValue;
                    sub = true;
                    try self.registers.writeReg(inst.destination.?, result);
                    self.setFlags(originValue, targetValue, result, sub);
                },
                0x98...0x9F => { // SBC
                    result = targetValue -% originValue -% @intFromBool(self.flags.carry);
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
                0xB8...0xBF => { // CMP
                    result = @intFromBool(targetValue == originValue);
                    try self.registers.writeReg(inst.destination.?, result);
                    self.flags.zero = result == 0;
                },
                0xFE => { // CMP
                    result = targetValue -% originValue;
                    sub = true;

                    self.flags.zero = (result != 0);

                    self.setFlags(targetValue, originValue, result, sub);
                },
                0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D => { // DECs
                    if (inst.addressing == .absolute) {
                        try self.bus.write(try self.registers.readReg(inst.destination.?), 1, originValue - 1);
                    } else if (inst.addressing == .none) {
                        try self.registers.writeReg(inst.destination.?, originValue - 1);
                    }
                },
                0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C => { // INCs
                    if (inst.addressing == .absolute) {
                        try self.bus.write(try self.registers.readReg(inst.destination.?), 1, originValue + 1);
                    } else if (inst.addressing == .none) {
                        try self.registers.writeReg(inst.destination.?, originValue + 1);
                    }
                },
                else => return error.InvalidMathInstruction,
            }
        }
        pub fn setFlags(self: *Self, op1: u16, op2: u16, result: u16, sub: bool) void {
            std.log.debug("setFlags", .{});

            const half_carry_8bit = (op1 ^ op2 ^ result) & 0x10 == 0x10;
            const carry_8bit = (op1 ^ op2 ^ result) & 0x100 == 0x100;
            const zero = (result & 0xFF) == 0;
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

    var bus = cpu.bus;
    try bus.write(0x000, 2, 0xBEEF);
    // std.debug.print("{X}\n", .{try bus.read(0x0, 2)});
    // try cpu.bus.write(0x0, 2, 0xBEEF);
    // std.debug.print("{s}\n", .{cpu.bus.rom0.name});
    // std.debug.print("{s}\n", .{cpu.bus.rom0.name});
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
    try eql(try cpu.bus.read(0x1337, 1), 0x42);
}

test "CPU: LoadAbsolute(HL-)" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    try cpu.registers.writeReg(.A, 0x42);
    try cpu.registers.writeReg(.HL, 0x1337);
    var inst = InstructionList[0x32];
    try cpu.loadAbsolute(inst);
    try eql(try cpu.bus.read(0x1337, 1), 0x42);
    try eql(try cpu.registers.readReg(.HL), 0x1336);

    try cpu.registers.writeReg(.A, 0x0);
    try cpu.registers.writeReg(.HL, 0x1111);
    try cpu.bus.write(0x1111, 1, 0x49);
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
    try cpu.bus.write(0x0, 2, 0x1337);
    const inst = InstructionList[0x08];
    try cpu.loadRelative(inst);
    try eql(try cpu.bus.read(0x1337, 2), 0xBEEF);
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
    try cpu.bus.write(0x0, 1, 0x12); // LD (DE),A
    try cpu.bus.write(0x1, 2, 0x1E11); //LD E,d8

    try cpu.tick();

    try eql(try cpu.bus.read(0x1337, 1), 0x42);
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

    // std.log.debug("{s}", .{cpu.registers});
    // std.log.debug("{s}", .{cpu.ram});
    try eql(try cpu.registers.readReg(.E), 0x11);
    try eql(cpu.programCounter.*, ldDEA.length + ldEd8.length);
    try eql(cpu.remainingCycles, ldEd8.cycles);
    try eql(cpu.totalCycles, ldDEA.cycles + ldEd8.cycles);
}

test "ALU: ADD" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    // ADD A, A
    try cpu.registers.writeReg(.A, 2);
    try cpu.registers.writeReg(.L, 243);
    var inst = InstructionList[0x85];
    try cpu.alu(inst);
    try eql(try cpu.registers.readReg(.A), 245);

    // ADD A,(HL)
    try cpu.registers.writeReg(.HL, 0x1337);
    try cpu.registers.writeReg(.A, 0xFF);
    try cpu.bus.write(0x1337, 1, 7);
    inst = InstructionList[0x86];
    try cpu.alu(inst);
    try eql(try cpu.registers.readReg(.A), 6);
    try eql(cpu.flags, .{ .zero = false, .carry = true, .halfCarry = true, .subtraction = false });
}

//todo: this test is failing and even with live debugging, it *should* be working
test "ALU: CMP" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    // CMP d8
    try cpu.registers.writeReg(.A, 0x42);
    try cpu.bus.write(0x0, 1, 0x42);

    //     try cpu.ram.write(0x0, 1, 0x12); // LD (DE),A
    // try cpu.ram.write(0x1, 2, 0x1E11); //LD E,d8
    const inst = InstructionList[0xFE];
    try cpu.alu(inst);
    // std.debug.print("{any}\n", .{cpu.flags});
    try std.testing.expectEqualDeep(
        Flags{
            .zero = false,
            .carry = false,
            .halfCarry = false,
            .subtraction = true,
        },
        cpu.flags,
    );
}

test "ALU: INC/DEC" {
    var cpu = try CPU().init(std.testing.allocator);
    defer cpu.deinit();

    // INC A
    try cpu.registers.writeReg(.A, 0x42);
    var inst = InstructionList[0x3C];
    try cpu.alu(inst);
    try eql(try cpu.registers.readReg(.A), 0x43);

    // DEC A
    try cpu.registers.writeReg(.A, 0x42);
    inst = InstructionList[0x3D];
    try cpu.alu(inst);
    try eql(try cpu.registers.readReg(.A), 0x41);

    // INC (HL)
    try cpu.registers.writeReg(.HL, 0x1337);
    try cpu.bus.write(0x1337, 1, 0x42);
    inst = InstructionList[0x34];
    try cpu.alu(inst);
    try eql(try cpu.bus.read(0x1337, 1), 0x43);

    // DEC (HL)
    try cpu.registers.writeReg(.HL, 0x1337);
    try cpu.bus.write(0x1337, 1, 0x42);
    inst = InstructionList[0x35];
    try cpu.alu(inst);
    try eql(try cpu.bus.read(0x1337, 1), 0x41);
}

test {
    std.testing.refAllDecls(@This());
}
