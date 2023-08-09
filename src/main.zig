const std = @import("std");

const CPURegisters = struct {
    A: u8,
    B: u8,
    C: u8,
    D: u8,
    E: u8,
    H: u8,
    L: u8,
    StackPointer: u16,
    ProgramCounter: u16,
    AF: u16,
    BC: u16,
    DE: u16,
    HL: u16,
    ZeroFlag: bool,
    SubtractionFlag: bool,
    HalfCarryFlag: bool,
    CarryFlag: bool,
};

const CPU = struct {
    Registers: CPURegisters = undefined,
    Memory: []u8 = &[0]u8{},

    pub fn init(self: *CPU) void {
        self.Registers = CPURegisters{
            .A = 0x01,
            .B = 0x00,
            .C = 0x13,
            .D = 0x00,
            .E = 0xD8,
            .H = 0x01,
            .L = 0x4D,
            .StackPointer = 0xFFFE,
            .ProgramCounter = 0x0100,
            .AF = 0x01B0,
            .BC = 0x0013,
            .DE = 0x00D8,
            .HL = 0x014D,
            .ZeroFlag = false,
            .SubtractionFlag = false,
            .HalfCarryFlag = false,
            .CarryFlag = false,
        };
    }
};

test "CPU init" {
    var cpu = CPU{};
    cpu.init();
    try std.testing.expect(cpu.Registers.ProgramCounter == 0x100);
}

pub fn main() !void {
    var cpu = CPU{};
    cpu.init();
}
