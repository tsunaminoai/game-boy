const std = @import("std");
const expect = @import("std").testing.expect;

const CPU = @import("cpu.zig").CPU;
const R = @import("types.zig").RegisterName;
const Flags = @import("types.zig").Flags;

test "Test a register can be written to" {
    var cpu = CPU{};
    cpu.WriteRegister(R.AF, 0xBEEF);
    try expect(cpu.ReadRegister(R.AF) == 0xBEEF);
}
test "Test that writing to an 16 bit register writes to the 8bit meta-registers" {
    var cpu = CPU{};

    cpu.WriteRegister(R.AF, 0xBEEF);
    cpu.WriteRegister(R.HL, 0xBEEF);

    try expect(cpu.ReadRegister(R.A) == 0xEF);
    try expect(cpu.ReadRegister(R.F) == 0xBE);
    try expect(cpu.ReadRegister(R.H) == 0xEF);
    try expect(cpu.ReadRegister(R.L) == 0xBE);
}
test "Test that writing to an 8bit register writes to the 16bit meta-register" {
    var cpu = CPU{};

    cpu.WriteRegister(R.C, 0xEF);
    cpu.WriteRegister(R.B, 0xBE);
    cpu.WriteRegister(R.L, 0xEF);
    cpu.WriteRegister(R.H, 0xBE);

    try expect(cpu.ReadRegister(R.BC) == 0xBEEF);
    try expect(cpu.ReadRegister(R.HL) == 0xBEEF);
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
    cpu.WriteMemory(0x0FF7, 0xBE, 1);

    cpu.WriteMemory(0x0, 0xFA, 1); //LD A,(nn)
    cpu.WriteMemory(0x1, 0x0FF7, 2);

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
    cpu.WriteRegister(R.SP, 0xFFFC);
    cpu.WriteMemory(0xFFFE, 0xDEAD, 2);

    cpu.WriteMemory(0x0, 0xF8, 1);
    cpu.WriteMemory(0x1, 0x02, 1);

    cpu.Tick();

    try expect(cpu.ReadRegister(R.HL) == 0xDEAD);

    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
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
    try expect(cpu.ReadMemory(cpu.ReadRegister(R.SP) + 2, 2) == 0xBEEF);
}

test "Test POP" {
    var cpu = CPU{};
    cpu.WriteRegister(R.SP, 0xFFFC);
    cpu.WriteRegister(R.BC, 0x0000);

    cpu.WriteMemory(0, 0xC1, 1);
    cpu.WriteMemory(0xFFFE, 0xBEEF, 2);

    cpu.Tick();

    try expect(cpu.ReadRegister(R.BC) == 0xBEEF);
    try expect(cpu.ReadRegister(R.SP) == 0xFFFE);
}

test "Flag bitfield can be written and read to" {
    var cpu = CPU{};
    cpu.flags.zero = true;

    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}

test "ALU: Add8 with no carry" {
    var cpu = CPU{};

    const result = cpu.add(0x0002, 0x0003, 1, false);
    try expect(result == 0x0005);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}

test "ALU: Add8 with half carry" {
    var cpu = CPU{};

    const result = cpu.add(0x000E, 0x0002, 1, false);
    try expect(result == 0x0010);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == false);
}

test "ALU: Add8 with Full carry" {
    var cpu = CPU{};

    const result = cpu.add(0x00FF, 0x0001, 1, false);
    try expect(result == 0x0000);
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == true);
}

test "ALU: Add16 with no carry" {
    var cpu = CPU{};

    const result = cpu.add(0x00F2, 0x0003, 2, false);
    try expect(result == 0x00F5);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}

test "ALU: Add16 with half carry" {
    var cpu = CPU{};

    const result = cpu.add(0xEFF0, 0x0010, 2, false);

    try expect(result == 0xF000);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == false);
}

test "ALU: Add16 with Full carry" {
    var cpu = CPU{};

    const result = cpu.add(0xFFFF, 0x0001, 2, false);
    try expect(result == 0x0000);
    try expect(cpu.flags.zero == true);
    try expect(cpu.flags.subtraction == false);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == true);
}

test "ALU: ADC A,n n=B" {
    var cpu = CPU{};
    cpu.flags.carry = true;
    cpu.WriteRegister(R.A, 0x05);
    cpu.WriteMemory(0x0, 0x88, 1);
    cpu.WriteRegister(R.B, 0x05);

    cpu.Tick();

    try expect(cpu.ReadRegister(R.A) == 0x0B);
}

test "ALU: ADC A,n n=(HL)" {
    var cpu = CPU{};
    cpu.flags.carry = true;
    cpu.WriteRegister(R.A, 0x05);
    cpu.WriteRegister(R.HL, 0xDEAD);
    cpu.WriteMemory(0xDEAD, 0x06, 1);

    cpu.WriteMemory(0x0, 0x8E, 1);

    cpu.Tick();

    try expect(cpu.ReadRegister(R.A) == 0x0C);
}

test "ALU: ADC A,n n=#" {
    var cpu = CPU{};
    cpu.flags.carry = true;
    cpu.WriteRegister(R.A, 0x05);

    cpu.WriteMemory(0x0, 0xCE, 1);
    cpu.WriteMemory(0x1, 0x15, 1);

    cpu.Tick();

    try expect(cpu.ReadRegister(R.A) == 0x1B);
}

test "ALU: SUB with no carry" {
    var cpu = CPU{};

    const result = cpu.subtract(0x0010, 0x0005, 1, false);
    try expect(result == 0x000B);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == true);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == false);
}

test "ALU: SUB with half carry" {
    var cpu = CPU{};

    const result = cpu.subtract(0x00FF, 0x00CC, 1, false);
    try expect(result == 0x0033);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == true);
    try expect(cpu.flags.halfCarry == false);
    try expect(cpu.flags.carry == false);
}

test "ALU: SUB with Full carry" {
    var cpu = CPU{};

    const result = cpu.subtract(0x0000, 0x0001, 1, false);

    try expect(result == 0xFF);
    try expect(cpu.flags.zero == false);
    try expect(cpu.flags.subtraction == true);
    try expect(cpu.flags.halfCarry == true);
    try expect(cpu.flags.carry == true);
}

test "ALU: AND" {
    var cpu = CPU{};

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
    var cpu = CPU{};

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
    var cpu = CPU{};

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
    var cpu = CPU{};

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
    var cpu = CPU{};

    const result = cpu.swap(0xEB);

    try expect(result == 0xBE);
}

test "JUMP: JP" {
    var cpu = CPU{};

    cpu.WriteMemory(0x0, 0xC3, 1);
    cpu.WriteMemory(0x1, 0x0080, 2);
    cpu.Tick();
    try expect(cpu.programCounter == 0x0080);
}

test "JUMP: JP cc,nn NZ" {
    var cpu = CPU{};
    const opCode = 0xC2;

    cpu.WriteMemory(0x0, opCode, 1);
    cpu.WriteMemory(0x1, 0x0080, 2);
    cpu.flags.zero = false;
    cpu.Tick();

    try expect(cpu.programCounter == 0x0080);

    cpu.WriteMemory(0x0080, opCode, 1);
    cpu.WriteMemory(0x0081, 0xDEAD, 2);
    cpu.flags.zero = true;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0083);
}

test "JUMP: JP cc,nn Z" {
    var cpu = CPU{};
    const opCode = 0xCA;

    cpu.WriteMemory(0x0, opCode, 1);
    cpu.WriteMemory(0x1, 0x0080, 2);
    cpu.flags.zero = true;
    cpu.Tick();

    try expect(cpu.programCounter == 0x0080);

    cpu.WriteMemory(0x0080, opCode, 1);
    cpu.WriteMemory(0x0081, 0xDEAD, 2);
    cpu.flags.zero = false;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0083);
}

test "JUMP: JP cc,nn NC" {
    var cpu = CPU{};
    const opCode = 0xD2;

    cpu.WriteMemory(0x0, opCode, 1);
    cpu.WriteMemory(0x1, 0x0080, 2);
    cpu.flags.carry = false;
    cpu.Tick();

    try expect(cpu.programCounter == 0x0080);

    cpu.WriteMemory(0x0080, opCode, 1);
    cpu.WriteMemory(0x0081, 0xDEAD, 2);
    cpu.flags.carry = true;
    cpu.Tick();
    try expect(cpu.programCounter == 0x0083);
}

test "JUMP: JP cc,nn C" {
    var cpu = CPU{};
    const opCode = 0xDA;

    cpu.WriteMemory(0x0, opCode, 1);
    cpu.WriteMemory(0x1, 0x0080, 2);
    cpu.flags.carry = true;
    cpu.Tick();

    try expect(cpu.programCounter == 0x0080);

    cpu.WriteMemory(0x0080, opCode, 1);
    cpu.WriteMemory(0x0081, 0xDEAD, 2);
    cpu.flags.carry = false;
    cpu.Tick();

    try expect(cpu.programCounter == 0x0083);
}

test "JUMP: JP (HL)" {
    var cpu = CPU{};

    cpu.WriteMemory(0x0, 0xE9, 1);
    cpu.WriteRegister(R.HL, 0xBEEF);
    cpu.WriteMemory(0xBEEF, 0xDEAD, 2);
    cpu.Tick();

    try expect(cpu.programCounter == 0xDEAD);
}

test "JUMP: JR n" {
    var cpu = CPU{};

    cpu.WriteMemory(0x0, 0x18, 1);
    cpu.WriteRegister(R.HL, 0xBEEF);
    cpu.WriteMemory(0x1, 0x05, 1);
    cpu.Tick();

    try expect(cpu.programCounter == 0xBEF4);
}

test "CALL: CALL nn" {
    var cpu = CPU{};

    cpu.WriteMemory(0x0, 0xCD, 1);
    cpu.WriteRegister(R.SP, 0xFFFE);
    cpu.WriteRegister(R.HL, 0xBEEF);
    cpu.WriteMemory(0x1, 0xDEAD, 2);
    cpu.Tick();

    try expect(cpu.programCounter == 0xDEAD);
    try expect(cpu.ReadRegister(R.SP) == 0xFFFC);
    try expect(cpu.memory[0xFFFF] == 0xBE);
    try expect(cpu.memory[0xFFFE] == 0xEF);
}

test "RST n" {
    var cpu = CPU{};

    cpu.WriteMemory(0x0, 0xEF, 1);
    cpu.WriteRegister(R.SP, 0xFFFE);
    cpu.WriteRegister(R.HL, 0xBEEF);
    cpu.Tick();

    try expect(cpu.programCounter == 0x28);
    try expect(cpu.ReadRegister(R.SP) == 0xFFFC);
    try expect(cpu.memory[0xFFFF] == 0xBE);
    try expect(cpu.memory[0xFFFE] == 0xEF);
}

test "RET" {
    var cpu = CPU{};

    cpu.WriteMemory(0x0, 0xC9, 1);
    cpu.WriteRegister(R.SP, 0xFFFC);
    cpu.WriteMemory(0xFFFE, 0xBEEF, 2);
    cpu.WriteRegister(R.HL, 0x0);
    cpu.Tick();

    try expect(cpu.programCounter == 0xBEEF);
    try expect(cpu.ReadRegister(R.SP) == 0xFFFE);

}
