const std = @import("std");
const Register = @import("r2.zig");
const Instruction = @import("opcodes.zig").Instruction;
const InstructionList = @import("opcodes.zig").instructions;

pub fn CPU() type {
    return struct {
        programCounter: usize = 0,
        ram: [0x3FFF]u8 = [_]u8{0} ** 0x3FFF,
        registers: Register,

        const Self = @This();

        pub fn init() Self {
            return Self{
                .ram = [_]u8{0} ** 0x3fff,
                .registers = Register.init(),
            };
        }
        pub fn loadImmediate(self: *Self, inst: Instruction) !void {
            const operand = switch (inst.category) {
                .byteLoad => self.ram[self.programCounter],
                .wordLoad => std.mem.readIntSliceLittle(u16, self.ram[self.programCounter .. self.programCounter + 2]),
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
    cpu.ram[0] = [_]u8{ 0x01, 0xBE, 0xEF };
    const inst = InstructionList[0x01];
    try cpu.loadImmediate(inst);
    try eql(cpu.registers.readReg(.BC), 0xBEEF);
}
