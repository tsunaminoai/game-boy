const std = @import("std");
const CPU = @import("cpu.zig").CPU;
const Register = @import("types.zig").Register;
const Flag = @import("types.zig").Flag;

test "Test a register can be written to" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.AF, @as(u16, 0x0A0B));
    try std.testing.expect(cpu.registers[@intFromEnum(Register.AF)] == 0x0A0B);
}
test "Test that writing to a sub-register writes to the parent and vice versa" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.AF, @as(u16, 0x0A0B));
    try std.testing.expect(cpu.registers[@intFromEnum(Register.A)] == 0x0A);
    try std.testing.expect(cpu.registers[@intFromEnum(Register.F)] == 0x0B);

    cpu.WriteRegister(Register.C, @as(u16, 0x0B));
    cpu.WriteRegister(Register.B, @as(u16, 0x0A));
    try std.testing.expect(cpu.registers[@intFromEnum(Register.BC)] == 0x0A0B);
}
test "Test that flags can be set and unset" {
    var cpu = CPU{};
    cpu.FlagSet(Flag.Zero);
    try std.testing.expect(cpu.FlagRead(Flag.Zero) == true);
    cpu.FlagUnSet(Flag.Zero);
    try std.testing.expect(cpu.FlagRead(Flag.Zero) == false);
}
test "Test ticking increments PC" {
    var cpu = CPU{};
    const pc = cpu.programCounter;
    cpu.Tick();
    try std.testing.expect(cpu.programCounter == pc + 1);
}
test "Test LD n,nn" {
    var cpu = CPU{};
    cpu.memory[0] = 0x06; // LDB,d8
    cpu.memory[1] = 0xFE;
    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.B) == 0xFE);
}
test "Test LD r1,r2" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0x0);
    cpu.WriteRegister(Register.H, 0xBC);
    cpu.memory[0] = 0x7C; //LDA,L
    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.A) == 0xBC);
}
test "Test LD r1,r2 with address register" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0x0);
    cpu.WriteRegister(Register.HL, 0xFFE);
    cpu.memory[0xFFE] = 0xBE;

    cpu.memory[0] = 0x7E; //LD A,(HL)
    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.A) == 0xBE);
}
test "Test LD A,n with address register" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0x0);
    cpu.WriteRegister(Register.BC, 0xFF7);
    cpu.memory[0xFF7] = 0xBE;

    cpu.memory[0] = 0x0A; //LD A,(HL)
    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.A) == 0xBE);
}
test "Test LD A,(nn)" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0x0);
    cpu.memory[0xFF7] = 0xBE;

    cpu.memory[0] = 0xFA; //LD A,(nn)
    cpu.memory[1] = 0xF7;
    cpu.memory[2] = 0x0F;
    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.A) == 0xBE);
}
test "Test LD (nn),A" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0xBE);
    cpu.memory[0xFF7] = 0x0;

    cpu.memory[0] = 0xEA; //LD (nn),A
    cpu.memory[1] = 0xF7;
    cpu.memory[2] = 0x0F;
    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.A) == 0xBE);
}
test "Test LDD A,(HL)" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0x0);
    cpu.memory[0xFF7] = 0xBE;
    cpu.WriteRegister(Register.HL, 0x0FF7);

    cpu.memory[0] = 0x3A;

    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.A) == 0xBE);
    try std.testing.expect(cpu.ReadRegister(Register.HL) == 0x0FF6);
}
test "Test LDD (HL),A" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0x00BE);
    cpu.memory[0x0040] = 0x0;
    cpu.WriteRegister(Register.HL, 0x0040);

    cpu.memory[0] = 0x32;

    cpu.Tick();
    try std.testing.expect(cpu.memory[0x0040] == 0x00BE);
    try std.testing.expect(cpu.ReadRegister(Register.HL) == 0x003F);
}

test "Test LDI A,(HL)" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0x0);
    cpu.memory[0xFF7] = 0xBE;
    cpu.WriteRegister(Register.HL, 0x0FF7);

    cpu.memory[0] = 0x2A;

    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.A) == 0xBE);
    try std.testing.expect(cpu.ReadRegister(Register.HL) == 0x0FF8);
}
test "Test LDI (HL),A" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0x00BE);
    cpu.memory[0x0040] = 0x0;
    cpu.WriteRegister(Register.HL, 0x0040);

    cpu.memory[0] = 0x22;

    cpu.Tick();
    try std.testing.expect(cpu.memory[0x0040] == 0x00BE);
    try std.testing.expect(cpu.ReadRegister(Register.HL) == 0x0041);
}

test "Test LDH A,(n)" {
    var cpu = CPU{};
    const offset = 0x09;
    cpu.WriteRegister(Register.A, 0x0);
    cpu.memory[0xFF00 + offset] = 0xBE;

    cpu.memory[0] = 0xF0;
    cpu.memory[1] = offset; // offset value + $FF00

    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.A) == 0xBE);
}
test "Test LDH (n),A" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.A, 0x00BE);
    cpu.memory[0x0040] = 0x0;
    cpu.WriteRegister(Register.HL, 0x0040);

    cpu.memory[0] = 0x22;

    cpu.Tick();
    try std.testing.expect(cpu.memory[0x0040] == 0x00BE);
    try std.testing.expect(cpu.ReadRegister(Register.HL) == 0x0041);
}

test "Test LD n,nn (16bit)" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.HL, 0x0000);

    cpu.memory[0] = 0x21;
    cpu.memory[1] = 0xF7;
    cpu.memory[2] = 0x0F;

    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.HL) == 0x0FF7);
}

test "Test LDHL SP,n" {
    var cpu = CPU{};
    cpu.WriteRegister(Register.HL, 0x0000);
    cpu.WriteRegister(Register.SP, 0xBEEA);

    cpu.memory[0] = 0xF8;
    cpu.memory[1] = 0x05;

    cpu.Tick();
    try std.testing.expect(cpu.ReadRegister(Register.SP) == 0xBEEF);
    try std.testing.expect(cpu.FlagRead(Flag.Zero) == false);
    try std.testing.expect(cpu.FlagRead(Flag.Subtraction) == false);
    try std.testing.expect(cpu.FlagRead(Flag.HalfCarry) == false);
    try std.testing.expect(cpu.FlagRead(Flag.Carry) == false);
}
