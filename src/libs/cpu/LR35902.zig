const std = @import("std");
const MMU = @import("mmu.zig");
const Register = @import("register.zig");
const Instruction = @import("opcodes.zig").Instruction;
const InstructionList = @import("opcodes.zig").instructions;

pub fn CPU() type {
    return struct {
        programCounter: usize = 0,
        ram: MMU.StaticMemory("CPU Ram", 0x3FFF),
        registers: Register,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .ram = MMU.StaticMemory("CPU Ram", 0x3FFF).init(),
                .registers = Register.init(),
            };
        }
        pub fn loadImmediate(self: *Self, inst: Instruction) !void {
            const operand = switch (inst.category) {
                .byteLoad => self.ram.read(self.programCounter, 1),
                .wordLoad => self.ram.read(self.programCounter, 2),
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
    cpu.ram.write(0x0000, 2, 0xBEEF);
    const inst = InstructionList[0x01];
    try cpu.loadImmediate(inst);
    try eql(cpu.registers.readReg(.BC), 0xBEEF);
}
