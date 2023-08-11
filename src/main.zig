const std = @import("std");

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
    _,
};

///The CPU itself
const CPU = struct {
    Registers: CPURegisters = undefined,
    Memory: [8000]u8 = undefined,
    MemoryAllocator: std.mem.Allocator = undefined,

    pub fn init(self: *CPU) !void {
        var fba = std.heap.FixedBufferAllocator.init(&self.Memory);
        self.MemoryAllocator = fba.allocator();

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

    ///Returns the current value of and increments the program counter
    pub fn tick(self: *CPU) OPCodes {
        const OpCode = try @as(OPCodes, @enumFromInt(self.Memory[self.Registers.ProgramCounter]));
        self.Registers.ProgramCounter += 1;
        return OpCode;
    }
    test "Test that the tick increments the counter and the OpCode is output" {
        var cpu = CPU{};
        try cpu.init();
        const OpCode = cpu.tick();
        try std.testing.expect(cpu.Registers.ProgramCounter == 0x101);
        try std.testing.expect(OpCode == 0x100);
    }

    ///Loads values from an address to a register
    fn load(self: *CPU, register: *u8) void {
        // I dont know if we need to be keeping track of cycles, but this one is 2 machine cycles
        register.* = self.Memory[self.Registers.ProgramCounter];
        // todo: write to the combined registers as well
    }
    test "Test that the load opcode function moves whats at the address to the register" {
        var cpu = CPU{};
        try cpu.init();
        cpu.Memory[0x0100] = 0x06;
        cpu.Memory[0x0101] = 0xFF;
        cpu.execute();
        try std.testing.expect(cpu.Registers.B == 0xFF);
    }

    ///Executes the current opcode
    fn execute(self: *CPU) void {
        var opcode = self.tick();
        switch (opcode) {
            OPCodes.LDB => {
                self.load(&self.Registers.B);
            },
            OPCodes.LDC => {
                self.load(&self.Registers.C);
            },
            OPCodes.LDD => {
                self.load(&self.Registers.D);
            },
            OPCodes.LDE => {
                self.load(&self.Registers.E);
            },
            OPCodes.LDH => {
                self.load(&self.Registers.H);
            },
            OPCodes.LDL => {
                self.load(&self.Registers.L);
            },
            else => unreachable,
        }
    }
};

test "CPU init" {
    var cpu = CPU{};
    try cpu.init();
    try std.testing.expect(cpu.Registers.ProgramCounter == 0x0100);
    try std.testing.expect(cpu.Memory.len == 8000);
}

pub fn main() !void {
    var cpu = CPU{};
    try cpu.init();
}
