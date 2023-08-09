const std = @import("std");
const cpu2 = @import("./libs/cpu");

///The Registers for the CPU
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

///The Opcodes for the CPU
const OPCodes = enum(u8) {
    ///LD nn,n
    LDB = 0x06,
    LDC = 0x0E,
    LDD = 0x16,
    LDE = 0x1E,
    LDH = 0x26,
    LDL = 0x2E,
};

///The CPU itself
const CPU = struct {
    Registers: CPURegisters = undefined,
    Memory: []u8 = undefined,

    pub fn init(self: *CPU) !void {
        const allocator = std.heap.page_allocator;
        self.Memory = try allocator.alloc(u8, 8000);
        defer allocator.free(self.Memory);

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

    pub fn tick(self: *CPU) void {
        self.Registers.ProgramCounter += 1;
    }
    test "Test that the tick increments the counter" {
        var cpu = CPU{};
        try cpu.init();
        cpu.tick();
        try std.testing.expect(cpu.Registers.ProgramCounter == 0x101);
    }

    fn load(self: *CPU, register: *u8, address: u16) void {
        register.* = self.Memory[address];
    }
    test "Test that the load opcode function moves whats at the address to the register" {
        var cpu = CPU{};
        try cpu.init();
        cpu.Memory[cpu.Registers.ProgramCounter] = 0x06;
        cpu.Memory[cpu.Registers.ProgramCounter + 1] = 0xFF;
        cpu.execute();
        try std.testing.expect(cpu.Registers.B == 0xFF);
    }

    fn execute(self: *CPU) void {
        const memoryValue = self.Memory[self.Registers.ProgramCounter];
        var opcode = memoryValue;
        switch (@as(OPCodes, @enumFromInt(opcode))) {
            OPCodes.LDB => {
                self.load(&self.Registers.B, self.Registers.ProgramCounter + 1);
            },
            else => unreachable,
        }
    }
};

test "CPU init" {
    var cpu = CPU{};
    try cpu.init();
    try std.testing.expect(cpu.Registers.ProgramCounter == 0x100);
    try std.testing.expect(cpu.Memory.len == 8000);
}

pub fn main() !void {
    var cpu = CPU{};
    try cpu.init();
}
