const std = @import("std");
const MMU = @import("mmu.zig");
const Register = @import("register.zig");
const Instruction = @import("opcodes.zig").Instruction;
const InstructionList = @import("opcodes.zig").instructions;

pub fn CPU() type {
    return struct {
        programCounter: *u16,
        ram: MMU.StaticMemory("CPU Ram", 0x3FFF),
        registers: Register,
        currentInstruction: ?Instruction = null,
        totalCycles: usize = 0,
        remainingCycles: usize = 0,

        const Self = @This();

        pub fn init() Self {
            var reg = Register.init();
            return Self{
                .ram = MMU.StaticMemory("CPU Ram", 0x3FFF).init(),
                .registers = reg,
                .programCounter = reg.pc,
            };
        }
        pub fn tick(self: *Self) !void {
            if (self.remainingCycles > 0) {
                self.remainingCycles -= 1;
            } else {
                try self.fetch();
            }
        }

        pub fn fetch(self: *Self) !void {
            const opcode = try self.ram.read(self.programCounter.*, 1);
            self.currentInstruction = InstructionList[opcode];
            self.totalCycles += self.currentInstruction.?.cycles;
            self.remainingCycles += self.currentInstruction.?.cycles;
            self.programCounter.* += 1;
            try self.execute();
        }

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
                else => undefined,
            }
            const increment = self.currentInstruction.?.length;
            if (increment > 0)
                self.programCounter.* += increment - 1;
        }
        pub fn loadImmediate(self: *Self, inst: Instruction) !void {
            const operand = switch (inst.category) {
                .byteLoad => try self.ram.read(self.programCounter.*, 1),
                .wordLoad => try self.ram.read(self.programCounter.*, 2),
                else => unreachable,
            };
            // std.debug.print("Writing 0x{X:0>2}@0x{X:0>4} to register {s}\n", .{ operand, self.programCounter.*, @tagName(inst.destination.?) });
            try self.registers.writeReg(inst.destination.?, operand);
        }
        pub fn loadAbsolute(self: *Self, inst: Instruction) !void {
            const address = try self.registers.readReg(inst.destination.?);
            const value = try self.registers.readReg(inst.source.?);
            // std.debug.print(
            //     "Writing from ({s}) 0x{X:0>2} to ({s})0x{X:0>4} \n",
            //     .{ @tagName(inst.destination.?), value, @tagName(inst.source.?), address },
            // );
            try self.ram.write(address, 1, value);
        }
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
    };
}

const eql = std.testing.expectEqual;
test "CPU: LoadImmediate" {
    var cpu = CPU().init();
    try cpu.ram.write(0x0, 2, 0xBEEF);
    const inst = InstructionList[0x01];
    try cpu.loadImmediate(inst);
    try eql(cpu.registers.readReg(.BC), 0xBEEF);
}

test "CPU: LoadAbsolute" {
    var cpu = CPU().init();
    try cpu.registers.writeReg(.A, 0x42);
    try cpu.registers.writeReg(.BC, 0x1337);
    const inst = InstructionList[0x02];
    try cpu.loadAbsolute(inst);
    try eql(try cpu.ram.read(0x1337, 1), 0x42);
}

test "CPU: LoadRelative" {
    var cpu = CPU().init();
    try cpu.registers.writeReg(.PC, 0x0);
    try cpu.registers.writeReg(.SP, 0xBEEF);
    try cpu.ram.write(0x0, 2, 0x1337);
    const inst = InstructionList[0x08];
    try cpu.loadRelative(inst);
    try eql(try cpu.ram.read(0x1337, 2), 0xBEEF);
}

test "CPU: Tick & Fetch" {
    var cpu = CPU().init();
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
    //try eql(try cpu.registers.readReg(.E), 0x42);
}
