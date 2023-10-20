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

        const Self = @This();

        pub fn init() Self {
            var reg = Register.init();
            return Self{
                .ram = MMU.StaticMemory("CPU Ram", 0x3FFF).init(),
                .registers = reg,
                .programCounter = reg.pc,
            };
        }
        pub fn loadImmediate(self: *Self, inst: Instruction) !void {
            const operand = switch (inst.category) {
                .byteLoad => try self.ram.read(self.programCounter.*, 1),
                .wordLoad => try self.ram.read(self.programCounter.*, 2),
                else => unreachable,
            };
            // std.debug.print("Operand: {X:0>4}\n", .{operand});
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
