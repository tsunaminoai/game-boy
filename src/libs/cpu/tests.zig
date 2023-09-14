const std = @import("std");
const expect = @import("std").testing.expect;
const CPU = @import("cpu.zig");
const R = @import("types.zig").RegisterName;
const Flags = @import("types.zig").Flags;
test "Test a register can be written to" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.AF, 0xBEEF);
    try expect(cpu.ReadRegister(R.AF) == 0xBEEF);
}
test "Test that writing to an 16 bit register writes to the 8bit meta-registers" {
    var cpu = try CPU.init();

    cpu.WriteRegister(R.AF, 0xBEEF);
    cpu.WriteRegister(R.HL, 0xBEEF);
    try expect(cpu.ReadRegister(R.A) == 0xEF);
    try expect(cpu.ReadRegister(R.F) == 0xBE);
    try expect(cpu.ReadRegister(R.H) == 0xEF);
    try expect(cpu.ReadRegister(R.L) == 0xBE);
}
test "Test that writing to an 8bit register writes to the 16bit meta-register" {
    var cpu = try CPU.init();

    cpu.WriteRegister(R.C, 0xEF);
    cpu.WriteRegister(R.B, 0xBE);
    cpu.WriteRegister(R.L, 0xEF);
    cpu.WriteRegister(R.H, 0xBE);
    try expect(cpu.ReadRegister(R.BC) == 0xBEEF);
    try expect(cpu.ReadRegister(R.HL) == 0xBEEF);
}
test "Writing memory for 1 byte" {
    var cpu = try CPU.init();
    cpu.mmu.write(0x0, 0xBE);
    try expect(cpu.mmu.read(0x0) == 0xBE);
}
test "Writing memory for 2 bytes" {
    var cpu = try CPU.init();
    cpu.mmu.write16(0x0, 0xBEEF);
    try expect(cpu.mmu.read(0x0) == 0xEF);
    try expect(cpu.mmu.read(0x1) == 0xBE);
}
test "Reading bytes from memory" {
    var cpu = try CPU.init();
    cpu.mmu.write16(0x0, 0xBEEF);
    try expect(cpu.mmu.read16(0x0) == 0xBEEF);
    try expect(cpu.mmu.read(0x0) == 0xEF);
}
test "Test ticking increments PC" {
    var cpu = try CPU.init();
    const pc = cpu.programCounter;
    cpu.Tick();
    try expect(cpu.programCounter == pc + 1);
}
test "Test LD n,nn" {
    var cpu = try CPU.init();
    cpu.mmu.write(0x0, 0x06);
    cpu.mmu.write(0x1, 0xFE);
    cpu.Tick();
    try expect(cpu.ReadRegister(R.B) == 0xFE);
}
test "Test LD r1,r2" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteRegister(R.H, 0xBC);
    cpu.mmu.write(0, 0x7C);
 //LDA,L
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBC);
}
test "Test LD r1,r2 with address register" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteRegister(R.HL, 0xFFE);
    cpu.mmu.write(0xFFE, 0xBE);

    cpu.mmu.write(0, 0x7E);
 //LD A,(HL)
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LD A,n with address register" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0x0);
    cpu.WriteRegister(R.BC, 0xFF7);
    cpu.mmu.write(0xFF7, 0xBE);

    cpu.mmu.write(0, 0x0A);
 //LD A,(HL)
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LD A,(nn)" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0x0);
    cpu.mmu.write(0x0FF7, 0xBE);

    cpu.mmu.write(0x0, 0xFA);
 //LD A,(nn)
    cpu.mmu.write16(0x1, 0x0FF7);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LD (nn),A" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0xBE);
    cpu.mmu.write(0xFF7, 0x0);

    cpu.mmu.write(0, 0xEA);
 //LD (nn),A
    cpu.mmu.write(1, 0xF7);
    cpu.mmu.write(2, 0x0F);
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LDD A,(HL)" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0x0);
    cpu.mmu.write(0xFF7, 0xBE);
    cpu.WriteRegister(R.HL, 0x0FF7);
    cpu.mmu.write(0, 0x3A);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
    try expect(cpu.ReadRegister(R.HL) == 0x0FF6);
}
test "Test LDD (HL),A" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0x00BE);
    cpu.mmu.write(0x0040, 0x0);
    cpu.WriteRegister(R.HL, 0x0040);
    cpu.mmu.write(0, 0x32);

    cpu.Tick();
    try expect(cpu.mmu.read(0x0040) == 0x00BE);
    try expect(cpu.ReadRegister(R.HL) == 0x003F);
}
test "Test LDI A,(HL)" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0x0);
    cpu.mmu.write(0xFF7, 0xBE);
    cpu.WriteRegister(R.HL, 0x0FF7);
    cpu.mmu.write(0, 0x2A);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
    try expect(cpu.ReadRegister(R.HL) == 0x0FF8);
}
test "Test LDI (HL),A" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0x00BE);
    cpu.mmu.write(0x0040, 0x0);
    cpu.WriteRegister(R.HL, 0x0040);
    cpu.mmu.write(0, 0x22);

    cpu.Tick();
    try expect(cpu.mmu.read(0x0040) == 0x00BE);
    try expect(cpu.ReadRegister(R.HL) == 0x0041);
}
test "Test LDH A,(n)" {
    var cpu = try CPU.init();
    const offset = 0x09;
    cpu.WriteRegister(R.A, 0x0);
    cpu.mmu.write(0xFF00 + offset, 0xBE);

    cpu.mmu.write(0, 0xF0);
    cpu.mmu.write(0x1, offset);
 // offset value + $FF00
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0xBE);
}
test "Test LDH (n),A" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.A, 0x00BE);
    cpu.mmu.write(0x0040, 0x0);
    cpu.WriteRegister(R.HL, 0x0040);
    cpu.mmu.write(0, 0x22);

    cpu.Tick();
    try expect(cpu.mmu.read(0x0040) == 0x00BE);
    try expect(cpu.ReadRegister(R.HL) == 0x0041);
}
test "Test LD n,nn (16bit)" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.HL, 0x0000);
    cpu.mmu.write(0, 0x21);
    cpu.mmu.write(1, 0xF7);
    cpu.mmu.write(2, 0x0F);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.HL) == 0x0FF7);
}
test "Test LDHL SP,n" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.HL, 0x0000);
    cpu.WriteRegister(R.SP, 0xFFFC);
    cpu.mmu.write16(0xFFFE, 0xDEAD);

    cpu.mmu.write(0x0, 0xF8);
    cpu.mmu.write(0x1, 0x02);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.HL) == 0xDEAD);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}
test "Test LD (nn),SP" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.SP, 0x0100);
    cpu.mmu.write(0, 0x08);
    cpu.mmu.write16(1, 0xBEEF);

    cpu.Tick();
    try expect(cpu.mmu.read16(0x1) == 0xBEEF);
}
test "Test PUSH" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.SP, 0xFFFE);
    cpu.WriteRegister(R.BC, 0xBEEF);
    cpu.mmu.write(0, 0xC5);

    cpu.Tick();
    try expect(cpu.mmu.read16(cpu.ReadRegister(R.SP) + 2) == 0xBEEF);
}
test "Test POP" {
    var cpu = try CPU.init();
    cpu.WriteRegister(R.SP, 0xFFFC);
    cpu.WriteRegister(R.BC, 0x0000);
    cpu.mmu.write(0, 0xC1);
    cpu.mmu.write16(0xFFFE, 0xBEEF);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.BC) == 0xBEEF);
    try expect(cpu.ReadRegister(R.SP) == 0xFFFE);
}
test "Flag bitfield can be written and read to" {
    var cpu = try CPU.init();
    cpu.flags.zero = true;
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}
test "ALU: Add8 with no carry" {
    var cpu = try CPU.init();

    const result = cpu.add(0x0002, 0x0003, 1, false);
    try expect(result == 0x0005);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}
test "ALU: Add8 with half carry" {
    var cpu = try CPU.init();

    const result = cpu.add(0x000E, 0x0002, 1, false);
    try expect(result == 0x0010);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == false);
}
test "ALU: Add8 with Full carry" {
    var cpu = try CPU.init();

    const result = cpu.add(0x00FF, 0x0001, 1, false);
    try expect(result == 0x0000);
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == true);
}
test "ALU: Add16 with no carry" {
    var cpu = try CPU.init();

    const result = cpu.add(0x00F2, 0x0003, 2, false);
    try expect(result == 0x00F5);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}
test "ALU: Add16 with half carry" {
    var cpu = try CPU.init();

    const result = cpu.add(0xEFF0, 0x0010, 2, false);
    try expect(result == 0xF000);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == false);
}
test "ALU: Add16 with Full carry" {
    var cpu = try CPU.init();

    const result = cpu.add(0xFFFF, 0x0001, 2, false);
    try expect(result == 0x0000);
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == true);
}
test "ALU: ADC A,n n=B" {
    var cpu = try CPU.init();
    cpu.flags.carry = true;
    cpu.WriteRegister(R.A, 0x05);
    cpu.mmu.write(0x0, 0x88);
    cpu.WriteRegister(R.B, 0x05);
    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0x0B);
}
test "ALU: ADC A,n n=(HL)" {
    var cpu = try CPU.init();
    cpu.flags.carry = true;
    cpu.WriteRegister(R.A, 0x05);
    cpu.WriteRegister(R.HL, 0xDEAD);
    cpu.mmu.write(0xDEAD, 0x06);

    cpu.mmu.write(0x0, 0x8E);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0x0C);
}
test "ALU: ADC A,n n=#" {
    var cpu = try CPU.init();
    cpu.flags.carry = true;
    cpu.WriteRegister(R.A, 0x05);
    cpu.mmu.write(0x0, 0xCE);
    cpu.mmu.write(0x1, 0x15);

    cpu.Tick();
    try expect(cpu.ReadRegister(R.A) == 0x1B);
}
test "ALU: SUB with no carry" {
    var cpu = try CPU.init();

    const result = cpu.subtract(0x0010, 0x0005, 1, false);
    try expect(result == 0x000B);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == true);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == false);
}
test "ALU: SUB with half carry" {
    var cpu = try CPU.init();

    const result = cpu.subtract(0x00FF, 0x00CC, 1, false);
    try expect(result == 0x0033);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == true);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}
test "ALU: SUB with Full carry" {
    var cpu = try CPU.init();

    const result = cpu.subtract(0x0000, 0x0001, 1, false);
    try expect(result == 0xFF);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == true);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == true);
}
test "ALU: AND" {
    var cpu = try CPU.init();

    try expect(cpu.logicalAnd(0xF0, 0x0F) == 0x0);
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == false);
    try expect(cpu.logicalAnd(0x52, 0x75) == 0x50);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == false);
}
test "ALU: OR" {
    var cpu = try CPU.init();

    try expect(cpu.logicalOr(0x0, 0x0) == 0x0);
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
    try expect(cpu.logicalOr(0xF0, 0x0F) == 0xFF);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}
test "ALU: XOR" {
    var cpu = try CPU.init();

    try expect(cpu.logicalXor(0xFF, 0xFF) == 0x0);
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
    try expect(cpu.logicalXor(0x66, 0xAA) == 0xCC);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}
test "ALU: CP" {
    var cpu = try CPU.init();

    cpu.cmp(0xFF, 0xFF);
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == true);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
    cpu.cmp(0x66, 0xAA);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == true);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == true);
}
test "Misc: SWAP" {
    var cpu = try CPU.init();

    cpu.mmu.write(0x0, 0x33);
    cpu.flags.carry = true;
    cpu.WriteRegister(R.E, 0xEB);
    cpu.Tick();
    // try expect(cpu.ReadRegister(R.E) == 0xBE);
}
test "JUMP: JP" {
    var cpu = try CPU.init();

    cpu.mmu.write(0x0, 0xC3);
    cpu.mmu.write16(0x1, 0x0080);
    cpu.Tick();
    try expect(cpu.programCounter == 0x0080);
}
test "JUMP: JP cc,nn NZ" {
    var cpu = try CPU.init();
    const opCode = 0xC2;
    cpu.mmu.write(0x0, opCode);
    cpu.mmu.write16(0x1, 0x0080);
    cpu.flags.zero = false;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0080);
    cpu.mmu.write(0x0080, opCode);
    cpu.mmu.write16(0x0081, 0xDEAD);
    cpu.flags.zero = true;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0083);
}
test "JUMP: JP cc,nn Z" {
    var cpu = try CPU.init();
    const opCode = 0xCA;
    cpu.mmu.write(0x0, opCode);
    cpu.mmu.write16(0x1, 0x0080);
    cpu.flags.zero = true;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0080);
    cpu.mmu.write(0x0080, opCode);
    cpu.mmu.write16(0x0081, 0xDEAD);
    cpu.flags.zero = false;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0083);
}
test "JUMP: JP cc,nn NC" {
    var cpu = try CPU.init();
    const opCode = 0xD2;
    cpu.mmu.write(0x0, opCode);
    cpu.mmu.write16(0x1, 0x0080);
    cpu.flags.carry = false;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0080);
    cpu.mmu.write(0x0080, opCode);
    cpu.mmu.write16(0x0081, 0xDEAD);
    cpu.flags.carry = true;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0083);
}
test "JUMP: JP cc,nn C" {
    var cpu = try CPU.init();
    const opCode = 0xDA;
    cpu.mmu.write(0x0, opCode);
    cpu.mmu.write16(0x1, 0x0080);
    cpu.flags.carry = true;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0080);
    cpu.mmu.write(0x0080, opCode);
    cpu.mmu.write16(0x0081, 0xDEAD);
    cpu.flags.carry = false;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0083);
}
test "JUMP: JP (HL)" {
    var cpu = try CPU.init();

    cpu.mmu.write(0x0, 0xE9);
    cpu.WriteRegister(R.HL, 0xBEEF);
    cpu.mmu.write16(0xBEEF, 0xDEAD);
    cpu.Tick();
    try expect(cpu.programCounter == 0xDEAD);
}
test "JUMP: JR n" {
    var cpu = try CPU.init();

    cpu.mmu.write(0x0, 0x18);
    cpu.WriteRegister(R.HL, 0xBEEF);
    cpu.mmu.write(0x1, 0x05);
    cpu.Tick();
    try expect(cpu.programCounter == 0xBEF4);
}
test "CALL: CALL nn" {
    var cpu = try CPU.init();

    cpu.mmu.write(0x0, 0xCD);
    cpu.WriteRegister(R.SP, 0xFFFE);
    cpu.WriteRegister(R.HL, 0xBEEF);
    cpu.mmu.write16(0x1, 0xDEAD);
    cpu.Tick();
    try expect(cpu.programCounter == 0xDEAD);
    try expect(cpu.ReadRegister(R.SP) == 0xFFFC);
    try expect(cpu.mmu.read(0xFFFF) == 0xBE);
    try expect(cpu.mmu.read(0xFFFE) == 0xEF);
}
test "RST n" {
    var cpu = try CPU.init();

    cpu.mmu.write(0x0, 0xEF);
    cpu.WriteRegister(R.SP, 0xFFFE);
    cpu.WriteRegister(R.HL, 0xBEEF);
    cpu.Tick();
    try expect(cpu.programCounter == 0x28);
    try expect(cpu.ReadRegister(R.SP) == 0xFFFC);
    try expect(cpu.mmu.read(0xFFFF) == 0xBE);
    try expect(cpu.mmu.read(0xFFFE) == 0xEF);
}
test "RET" {
    var cpu = try CPU.init();

    cpu.mmu.write(0x0, 0xC9);
    cpu.WriteRegister(R.SP, 0xFFFC);
    cpu.mmu.write16(0xFFFE, 0xBEEF);
    cpu.WriteRegister(R.HL, 0x0);
    cpu.Tick();
    try expect(cpu.programCounter == 0xBEEF);
    try expect(cpu.ReadRegister(R.SP) == 0xFFFE);
}
test "RLA" {
    var cpu = try CPU.init();
    cpu.flags.carry = false;
    cpu.WriteRegister(R.A, 0x80);
    cpu.mmu.write(0x0, 0x17);
    cpu.Tick();
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.carry == true);
    try expect(cpu.ReadRegister(R.A) == 0x0);
}
test "RRA" {
    var cpu = try CPU.init();
    cpu.flags.carry = false;
    cpu.WriteRegister(R.A, 0x1);
    cpu.mmu.write(0x0, 0x1F);
    cpu.Tick();
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.carry == true);
    try expect(cpu.ReadRegister(R.A) == 0x0);
}
