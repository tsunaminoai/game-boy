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
            try self.registers.writeReg(inst.destination.?, operand);
            std.debug.print("Operand: {X:0>4}\n", .{operand});
        }
    };
}

const eql = std.testing.expectEqual;
test "CPU: LoadImmediate" {
    var cpu = CPU().init();
    try cpu.ram.write(0x0000, 2, 0xBEEF);
    const inst = InstructionList[0x01];
    try cpu.loadImmediate(inst);
    try eql(cpu.registers.readReg(.BC), 0xBEEF);
}
