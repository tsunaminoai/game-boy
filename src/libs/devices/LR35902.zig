const std = @import("std");
const Device = @import("../device.zig");
const Bus = Device.Bus;
const OpCodes = @import("opcodes.zig");
const Instruction = OpCodes.Instruction;
const InstructionList = OpCodes.Instructions;

const ReadError = Device.ReadError;
const WriteError = Device.WriteError;
pub const RegisterID = enum { AF, DE, BC, HL, SP, PC, A, B, C, D, E, H, L };

bus: Device,
flags: Flags = .{},
stack: [0x100]u16 = undefined,
regs: [12]u8 = undefined,
total_cycles: u64 = 0,
remaining_cycles: u64 = 0,
halted: bool = false,

const CPU = @This();
var Regsiters: [6]Register = undefined;
var ticks: u64 = 0;

pub fn init(b: *Bus) !CPU {
    Regsiters = [_]Register{
        .{ .full = 0x01B0 }, // AF
        .{ .full = 0x0013 }, // BC
        .{ .full = 0x00D8 }, // DE
        .{ .full = 0x014D }, // HL
        .{ .full = 0xFFFE }, // SP
        .{ .full = 0x0100 }, // PC
    };
    const self = CPU{
        .bus = b.device(),
        .flags = .{},
        .stack = [_]u16{0} ** 0x100,
        .regs = [_]u8{0} ** 12,
    };
    return self;
}

pub fn tick(self: *CPU) !void {
    ticks += 1;
    if (self.remaining_cycles > 0)
        self.remaining_cycles -= 1
    else
        try self.fetch();
}

pub fn fetch(self: *CPU) !void {
    const opcode = try self.bus.read(self.readReg(.PC), 1);
    const instr = OpCodes.Instructions[opcode];
    if (instr.category == .illegal)
        return error.IllegalInstruction;

    self.total_cycles += instr.cycles;
    self.remaining_cycles = instr.cycles;
    self.writeReg(.PC, self.readReg(.PC) + 1);
    try self.execute(instr);
}

pub fn execute(self: *CPU, inst: Instruction) !void {
    std.log.debug("Executing instruction: {?}", .{inst});
    switch (inst.category) {
        .byteLoad, .wordLoad => {
            switch (inst.addressing) {
                .immediate => try self.loadImmediate(inst),
                // .absolute => try self.loadAbsolute(inst),
                // .relative => try self.loadRelative(inst),
                else => undefined,
            }
        },
        // .byteMath => try self.alu(inst),
        else => undefined,
    }
    const inc = inst.length;
    //TODO: This should be an optional
    if (inc > 0)
        self.writeReg(.PC, self.readReg(.PC) + inc - 1);
}

/// Loads an immediate value to the intructed destination
pub fn loadImmediate(self: *CPU, inst: Instruction) !void {
    std.log.debug("loadImmediate", .{});

    const operand = switch (inst.category) {
        // .byteLoad => try self.bus.read(self.programCounter.*, 1),
        // .wordLoad => try self.bus.read(self.programCounter.*, 2),
        else => unreachable,
    };
    // std.log.debug("Writing 0x{X:0>2}@0x{X:0>4} to register {s}", .{ operand, self.programCounter.*, @tagName(inst.destination.?) });
    try self.writeReg(inst.destination.?, operand);
}

pub fn writeReg(self: *CPU, reg: RegisterID, value: u16) void {
    switch (reg) {
        .AF, .BC, .DE, .HL, .PC, .SP => {
            std.mem.writeInt(
                u16,
                self.regs[@intFromEnum(reg) * 2 ..].ptr[0..2],
                value,
                .little,
            );
        },
        .A => self.regs[0] = @truncate(value),
        .B => self.regs[2] = @truncate(value),
        .C => self.regs[3] = @truncate(value),
        .D => self.regs[4] = @truncate(value),
        .E => self.regs[5] = @truncate(value),
        .H => self.regs[6] = @truncate(value),
        .L => self.regs[7] = @truncate(value),
    }
}
pub fn readReg(self: *CPU, reg: RegisterID) u16 {
    return switch (reg) {
        .AF, .BC, .DE, .HL, .PC, .SP => std.mem.readInt(
            u16,
            self.regs[@intFromEnum(reg) * 2 ..].ptr[0..2],
            .little,
        ),
        .A => self.regs[0],
        .B => self.regs[2],
        .C => self.regs[3],
        .D => self.regs[4],
        .E => self.regs[5],
        .H => self.regs[6],
        .L => self.regs[7],
    };
}

/// Loads a value from the source register to the address at the location
/// speicied by the destination
pub fn loadAbsolute(self: *CPU, inst: Instruction) !void {
    std.log.debug("loadAbsolute", .{});
    const commaPosition = std.mem.indexOf(u8, inst.name, ",");
    const parenPosition = std.mem.indexOf(u8, inst.name, "(");
    const decPos = std.mem.indexOf(u8, inst.name, "-");
    const incPos = std.mem.indexOf(u8, inst.name, "+");

    const operand = switch (inst.category) {
        .byteLoad => try self.bus.read(self.readReg(.PC), 1),
        .wordLoad => try self.bus.read(self.readReg(.PC), 2),
        else => unreachable,
    };

    const source = if (inst.source) |d| d else null;
    const destination = if (inst.destination) |d| d else null;
    if (source == null) std.log.warn("loadAbsolute: source is null", .{});
    if (destination == null) std.log.warn("loadAbsolute: destination is null", .{});

    var address: u16 = 0;
    var value: u16 = 0;

    // hacky way to avoid adding more metadata to the opcodes
    if (parenPosition) |pos| {

        // this is for (x),R instructions
        if (commaPosition.? > pos) {
            address = if (destination) |d| self.readReg(d) else operand;
            value = self.readReg(source.?);
            try self.bus.write(address, 1, value);
            // this is for R,(x) instructions
        } else if (commaPosition.? < pos) {
            address = self.readReg(source.?);
            value = try self.bus.read(address, 1);

            self.writeReg(destination.?, value);
        }
    } else {
        address = self.readReg(destination.?);
        value = self.readReg(source.?);
        try self.bus.write(address, 1, value);
    }

    if (incPos) |pos| {
        if (pos > commaPosition.?) {
            self.increment(source.?);
        } else if (pos < commaPosition.?) {
            self.increment(destination.?);
        }
    }
    if (decPos) |pos| {
        if (pos > commaPosition.?) {
            self.decrement(source.?);
        } else if (pos < commaPosition.?) {
            self.decrement(destination.?);
        }
    }
    // std.log.debug(
    //     "Writing from ({s}) 0x{X:0>2} to ({s})0x{X:0>4} \n",
    //     .{ @tagName(inst.destination.?), value, @tagName(inst.source.?), address },
    // );
}

fn increment(self: *CPU, reg: RegisterID) void {
    const value = self.readReg(reg) + 1;
    self.writeReg(reg, value);
}
fn decrement(self: *CPU, reg: RegisterID) void {
    const value = self.readReg(reg) - 1;
    self.writeReg(reg, value);
}

/// Loads a value from the source register to the location
/// speicied by the destination + the program counter
pub fn loadRelative(self: *CPU, inst: Instruction) !void {
    std.log.debug("loadRelative", .{});

    const operand = switch (inst.category) {
        .byteLoad => try self.bus.read(self.readReg(.PC), 1),
        .wordLoad => try self.bus.read(self.readReg(.PC), 2),
        else => unreachable,
    };

    const dest = if (inst.destination) |d| d else {
        std.log.err("Desination not provided for relative load: {}\n", .{inst});
        return error.InvalidInstruction;
    };

    const src = if (inst.source) |d| d else {
        std.log.err("Source not provided for relative load: {}\n", .{inst});
        return error.InvalidInstruction;
    };

    const address = self.readReg(dest) + operand;
    const value = self.readReg(src);
    // std.log.debug(
    //     "Writing from ({s}) 0x{X:0>2} to ({s})0x{X:0>4} \n",
    //     .{ @tagName(inst.destination.?), value, @tagName(inst.source.?), address },
    // );
    try self.bus.write(address, 2, value);
}

pub fn alu(self: *CPU, inst: Instruction) !void {
    std.log.debug("ALU instruction: {}", .{inst});

    const originValue = switch (inst.addressing) {
        .absolute => try self.bus.read(self.readReg(inst.source.?), 1),
        .none => self.readReg(inst.source.?),
        .immediate => try self.bus.read(self.readReg(.PC), 1),
        else => return error.InvalidAddressingForMathOperation,
    };
    const targetValue: u16 = self.readReg(inst.destination.?);
    var result: u16 = 0;
    var sub: bool = false;
    std.debug.print("ALU input: origin:{} target:{}\n", .{ originValue, targetValue });

    switch (inst.opcode) {
        0x80...0x87 => { // ADD
            result = originValue + targetValue;
            self.writeReg(inst.destination.?, result);
            self.setFlags(originValue, targetValue, result, sub);
        },
        0x88...0x8F, 0xCE => { // ADC
            result = originValue + targetValue + @intFromBool(self.flags.carry);
            self.writeReg(inst.destination.?, result);
            self.setFlags(originValue, targetValue, result, sub);
        },
        0x90...0x97 => { // SUB
            result = targetValue - originValue;
            sub = true;
            self.writeReg(inst.destination.?, result);
            self.setFlags(originValue, targetValue, result, sub);
        },
        0x98...0x9F => { // SBC
            result = targetValue - originValue - @intFromBool(self.flags.carry);
            sub = true;
            self.writeReg(inst.destination.?, result);
            self.setFlags(originValue, targetValue, result, sub);
        },
        0xA0...0xA7 => { // AND
            result = targetValue & originValue;
            self.writeReg(inst.destination.?, result);
            self.flags.zero = result == 0;
        },
        0xA8...0xAF => { // XOR
            result = targetValue ^ originValue;
            self.writeReg(inst.destination.?, result);
            self.flags.zero = result == 0;
        },
        0xB0...0xB7 => { // OR
            result = targetValue | originValue;
            self.writeReg(inst.destination.?, result);
            self.flags.zero = result == 0;
        },
        0xB8...0xBF => { // CMP
            result = @intFromBool(targetValue == originValue);
            self.writeReg(inst.destination.?, result);
            self.flags.zero = result == 0;
        },
        0xFE => { // CMP
            result = targetValue -% originValue;
            std.debug.print("sub: {} - {}  = {}\n", .{
                targetValue,
                originValue,
                result,
            });
            self.setFlags(targetValue, originValue, result, true);
        },
        0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D => { // DECs
            self.writeReg(inst.destination.?, self.readReg(inst.source.?) - 1);
        },
        0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C => { // INCs
            self.writeReg(inst.destination.?, self.readReg(inst.source.?) + 1);
        },
        else => return error.InvalidMathInstruction,
    }
}
pub fn setFlags(self: *CPU, op1: u16, op2: u16, result: u16, sub: bool) void {
    std.log.debug("setFlags", .{});

    const half_carry_8bit = (op1 ^ op2 ^ result) & 0x10 == 0x10;
    const carry_8bit = (op1 ^ op2 ^ result) & 0x100 == 0x100;
    const zero = result & 0xFF == 0;
    self.flags = .{
        .carry = carry_8bit,
        .halfCarry = half_carry_8bit,
        .sub = sub,
        .zero = zero,
    };
}

pub const Flags = packed struct(u4) {
    carry: bool = false,
    halfCarry: bool = false,
    zero: bool = false,
    sub: bool = false,
};
pub const Register = packed union {
    full: u16,
    half: packed struct {
        hi: u8,
        lo: u8,
    },
};

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;

test "CPU" {
    var b = try Bus.init(0xFFFF);
    var c = try CPU.init(&b);
    std.debug.print("{any}\n", .{c.regs});

    try expectEqual(c.flags.carry, false);
    try expectEqual(c.flags.halfCarry, false);
    try expectEqual(c.flags.zero, false);
    try expectEqual(c.flags.sub, false);

    try expectEqual(c.stack[0], 0);

    try expectEqual(c.readReg(.A), 0x01);
    try expectEqual(c.readReg(.B), 0x00);
}

const eql = std.testing.expectEqual;
test "CPU: LoadImmediate" {
    var b = try Bus.init(0xFFFF);
    var cpu = try CPU.init(&b);

    try cpu.bus.write(0x0, 2, 0xBEEF);
    const inst = InstructionList[0x01];
    try cpu.loadImmediate(inst);
    try eql(cpu.readReg(.BC), 0xBEEF);
}

test "CPU: LoadAbsolute" {
    var b = try Bus.init(0xFFFF);
    var cpu = try CPU.init(&b);

    cpu.writeReg(.A, 0x42);
    cpu.writeReg(.BC, 0x1337);
    const inst = InstructionList[0x02];
    try cpu.loadAbsolute(inst);
    try eql(try cpu.bus.read(0x1337, 1), 0x42);
}

test "CPU: LoadAbsolute(HL-)" {
    var b = try Bus.init(0xFFFF);
    var cpu = try CPU.init(&b);

    cpu.writeReg(.A, 0x42);
    cpu.writeReg(.HL, 0x1337);
    var inst = InstructionList[0x32];
    try cpu.loadAbsolute(inst);
    try eql(cpu.bus.read(0x1337, 1), 0x42);
    try eql(cpu.readReg(.HL), 0x1336);

    cpu.writeReg(.A, 0x0);
    cpu.writeReg(.HL, 0x1111);
    try cpu.bus.write(0x1111, 1, 0x49);
    inst = InstructionList[0x3A];
    try cpu.loadAbsolute(inst);
    try eql(cpu.readReg(.A), 0x49);
    try eql(cpu.readReg(.HL), 0x1110);
}

test "CPU: LoadRelative" {
    var b = try Bus.init(0xFFFF);
    var cpu = try CPU.init(&b);

    cpu.writeReg(.PC, 0x0);
    cpu.writeReg(.SP, 0xBEEF);
    try cpu.bus.write(0x0, 2, 0x1337);
    const inst = InstructionList[0x08];
    try cpu.loadRelative(inst);
    try eql(try cpu.bus.read(0x1337, 2), 0xBEEF);
}

test "CPU: Tick & Fetch" {
    var b = try Bus.init(0xFFFF);
    var cpu = try CPU.init(&b);

    const ldDEA = InstructionList[0x12];
    const ldEd8 = InstructionList[0x1E];

    // set up regsiters
    cpu.writeReg(.DE, 0x1337);
    cpu.writeReg(.A, 0x42);

    // manually write the instructions to ram
    try cpu.bus.write(0x0, 1, 0x12); // LD (DE),A
    try cpu.bus.write(0x1, 2, 0x1E11); //LD E,d8

    try cpu.tick();

    try eql(try cpu.bus.read(0x1337, 1), 0x42);
    try eql(cpu.readReg(.PC), ldDEA.length);
    try eql(cpu.remaining_cycles, ldDEA.cycles);
    try eql(cpu.total_cycles, ldDEA.cycles);
    for (cpu.remaining_cycles) |_| {
        try cpu.tick();
    }
    try eql(cpu.total_cycles, 8);
    try eql(cpu.remaining_cycles, 0);
    try eql(cpu.readReg(.PC), ldDEA.length);

    try cpu.tick();

    // std.log.debug("{s}", .{cpu.registers});
    // std.log.debug("{s}", .{cpu.bus});
    try eql(cpu.readReg(.E), 0x11);
    try eql(cpu.readReg(.PC), ldDEA.length + ldEd8.length);
    try eql(cpu.remaining_cycles, ldEd8.cycles);
    try eql(cpu.total_cycles, ldDEA.cycles + ldEd8.cycles);
}

test "ALU: ADD" {
    var b = try Bus.init(0xFFFF);
    var cpu = try CPU.init(&b);

    // ADD A, A
    cpu.writeReg(.A, 2);
    cpu.writeReg(.L, 243);
    var inst = InstructionList[0x85];
    try cpu.alu(inst);
    try eql(cpu.readReg(.A), 245);

    // ADD A,(HL)
    cpu.writeReg(.HL, 0x1337);
    cpu.writeReg(.A, 0xFF);
    try cpu.bus.write(0x1337, 1, 7);
    inst = InstructionList[0x86];
    try cpu.alu(inst);
    try eql(cpu.readReg(.A), 6);
    try eql(cpu.flags, Flags{ .zero = false, .carry = true, .halfCarry = true, .sub = false });
}

test "ALU: CMP" {
    var b = try Bus.init(0xFFFF);
    var cpu = try CPU.init(&b);

    // CMP d8
    cpu.writeReg(.A, 0x42);
    try cpu.bus.write(0x0, 1, 0x42);
    const inst = InstructionList[0xFE];
    try cpu.alu(inst);

    try std.testing.expectEqualDeep(cpu.flags, Flags{
        .zero = true,
        .carry = false,
        .halfCarry = false,
        .sub = true,
    });
}

// fn MakeRegs(comptime rs: type) type {
//     const inFields = std.meta.fields(rs);
//     var fields: [inFields.len]std.builtin.Type.StructField = undefined;

//     for (std.meta.fields(rs), 0..) |field, i| {
//         const f: std.builtin.Type.EnumField = field;
//         fields[i] = .{
//             .name = f.name,
//             .type = if (f.name[0] == 'f') *u16 else *u8,
//             .default_value = null,
//             .is_comptime = false,
//             .alignment = 0,
//         };
//     }
//     return @Type(.{
//         .Struct = .{
//             .layout = .auto,
//             .fields = fields[0..],
//             .decls = &[_]std.builtin.Type.Declaration{},
//             .is_tuple = false,
//         },
//     });
// }
