const std = @import("std");
const expect = @import("std").testing.expect;

const CPU = @import("cpu.zig").CPU;
const R = @import("types.zig").RegisterName;
const Flag = @import("types.zig").Flag;

test "Test a register can be written to" {
    var cpu = CPU{};
    cpu.WriteRegister(R.AF, 0xBEEF);
    try expect(cpu.ReadRegister(R.AF) == 0xBEEF);
}
test "Test that writing to an 16 bit register writes to the 8bit meta-registers" {
    var cpu = CPU{};

    cpu.WriteRegister(R.AF, 0xBEEF);

    try expect(cpu.ReadRegister(R.A) == 0xEF);
    try expect(cpu.ReadRegister(R.F) == 0xBE);
}
test "Test that writing to an 8bit register writes to the 16bit meta-register" {
    var cpu = CPU{};

    cpu.WriteRegister(R.C, 0xEF);
    cpu.WriteRegister(R.B, 0xBE);
    try expect(cpu.ReadRegister(R.BC) == 0xBEEF);
}
test "Writing memory for 1 byte" {
    var cpu = CPU{};
    cpu.WriteMemory(0x0, 0xBE, 1);
    try expect(cpu.memory[0x0] == 0xBE);
}
test "Writing memory for 2 bytes" {
    var cpu = CPU{};
    cpu.WriteMemory(0x0, 0xBEEF, 2);
    try expect(cpu.memory[0x0] == 0xEF);
    try expect(cpu.memory[0x1] == 0xBE);
}
test "Reading bytes from memory" {
    var cpu = CPU{};
    cpu.WriteMemory(0x0, 0xBEEF, 2);
    try expect(cpu.ReadMemory(0x0, 2) == 0xBEEF);
    try expect(cpu.ReadMemory(0x0, 1) == 0x00EF);
}
test "Test that flags can be set and unset" {
    var cpu = CPU{};
    cpu.FlagSet(Flag.Zero);
    try expect(cpu.FlagRead(Flag.Zero) == true);
    cpu.FlagUnSet(Flag.Zero);
    try expect(cpu.FlagRead(Flag.Zero) == false);
}
test "Test ticking increments PC" {
    var cpu = CPU{};
    const pc = cpu.programCounter;
    cpu.Tick();
    try expect(cpu.programCounter == pc + 1);
}
test "Test LD n,nn" {
    var cpu = CPU{};
    cpu.WriteMemory(0x0, 0x06, 1);
    cpu.WriteMemory(0x1, 0xFE, 1);
    cpu.Tick();
    try expect(cpu.ReadRegister(R.B) == 0xFE);
}
test "Test LD r1,r2" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteRegister(R.H, 0xBC);
    cpu.WriteMemory(0, 0x7C, 1); //LDA,L
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBC);
}
test "Test LD r1,r2 with address register" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteRegister(R.HL, 0xFFE);
    cpu.WriteMemory(0xFFE, 0xBE, 1);

    cpu.WriteMemory(0, 0x7E, 1); //LD A,(HL)
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LD A,n with address register" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteRegister(R.BC, 0xFF7);
    cpu.WriteMemory(0xFF7, 0xBE, 1);

    cpu.WriteMemory(0, 0x0A, 1); //LD A,(HL)
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LD A,(nn)" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteMemory(0xFF7, 0xBE, 1);

    cpu.WriteMemory(0, 0xFA, 1); //LD A,(nn)
    cpu.WriteMemory(1, 0xF7, 1);
    cpu.WriteMemory(2, 0x0F, 1);
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LD (nn),A" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0xBE);
    cpu.WriteMemory(0xFF7, 0x0, 1);

    cpu.WriteMemory(0, 0xEA, 1); //LD (nn),A
    cpu.WriteMemory(1, 0xF7, 1);
    cpu.WriteMemory(2, 0x0F, 1);
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LDD A,(HL)" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteMemory(0xFF7, 0xBE, 1);
    cpu.WriteRegister(R.HL, 0x0FF7);

    cpu.WriteMemory(0, 0x3A, 1);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
    try expect(cpu.ReadRegister(R.HL) == 0x0FF6);
}
test "Test LDD (HL),A" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0x00BE);
    cpu.WriteMemory(0x0040, 0x0, 1);
    cpu.WriteRegister(R.HL, 0x0040);

    cpu.WriteMemory(0, 0x32, 1);

    cpu.Tick();
    try expect(cpu.ReadMemory(0x0040, 1) == 0x00BE);
    try expect(cpu.ReadRegister(R.HL) == 0x003F);
}

test "Test LDI A,(HL)" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteMemory(0xFF7, 0xBE, 1);
    cpu.WriteRegister(R.HL, 0x0FF7);

    cpu.WriteMemory(0, 0x2A, 1);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
    try expect(cpu.ReadRegister(R.HL) == 0x0FF8);
}
test "Test LDI (HL),A" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0x00BE);
    cpu.WriteMemory(0x0040, 0x0, 1);
    cpu.WriteRegister(R.HL, 0x0040);

    cpu.WriteMemory(0, 0x22, 1);

    cpu.Tick();
    try expect(cpu.memory[0x0040] == 0x00BE);
    try expect(cpu.ReadRegister(R.HL) == 0x0041);
}

test "Test LDH A,(n)" {
    var cpu = CPU{};
    const offset = 0x09;
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteMemory(0xFF00 + offset, 0xBE, 1);

    cpu.WriteMemory(0, 0xF0, 1);
    cpu.WriteMemory(0x1, offset, 1); // offset value + $FF00

    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LDH (n),A" {
    var cpu = CPU{};
    cpu.WriteRegister(R.A, 0x00BE);
    cpu.WriteMemory(0x0040, 0x0, 1);
    cpu.WriteRegister(R.HL, 0x0040);

    cpu.WriteMemory(0, 0x22, 1);

    cpu.Tick();
    try expect(cpu.memory[0x0040] == 0x00BE);
    try expect(cpu.ReadRegister(R.HL) == 0x0041);
}

test "Test LD n,nn (16bit)" {
    var cpu = CPU{};
    cpu.WriteRegister(R.HL, 0x0000);

    cpu.WriteMemory(0, 0x21, 1);
    cpu.WriteMemory(1, 0xF7, 1);
    cpu.WriteMemory(2, 0x0F, 1);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.HL) == 0x0FF7);
}

test "Test LDHL SP,n" {
    var cpu = CPU{};
    cpu.WriteRegister(R.HL, 0x0000);
    cpu.WriteRegister(R.SP, 0xBEEA);

    cpu.WriteMemory(0, 0xF8, 1);
    cpu.WriteMemory(1, 0x06, 1);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.SP) == 0xBEF0);
    try expect(cpu.FlagRead(Flag.Zero) == false);
    try expect(cpu.FlagRead(Flag.Subtraction) == false);
    try expect(cpu.FlagRead(Flag.HalfCarry) == true);
    try expect(cpu.FlagRead(Flag.Carry) == false);
}

test "Test LD (nn),SP" {
    var cpu = CPU{};
    cpu.WriteRegister(R.SP, 0x0100);

    cpu.WriteMemory(0, 0x08, 1);
    cpu.WriteMemory(1, 0xBEEF, 2);

    cpu.Tick();
    try expect(cpu.ReadMemory(0x1, 2) == 0xBEEF);
}

test "Test PUSH" {
    var cpu = CPU{};
    cpu.WriteRegister(R.SP, 0xFFFE);
    cpu.WriteRegister(R.BC, 0xBEEF);

    cpu.WriteMemory(0, 0xC5, 1);

    cpu.Tick();
    try expect(cpu.ReadMemory(cpu.ReadRegister(R.SP)+2, 2) == 0xBEEF);

}

test "Test POP" {
    var cpu = CPU{};
    cpu.WriteRegister(R.SP, 0xFFFC);
    cpu.WriteRegister(R.BC, 0x0000);

    cpu.WriteMemory(0, 0xC1, 1);
    cpu.WriteMemory(0xFFFC, 0xBEEF, 2);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.BC) == 0xBEEF);
    try expect(cpu.ReadRegister(R.SP) == 0xFFFE);
}
