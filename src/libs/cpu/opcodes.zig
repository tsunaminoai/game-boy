const std = @import("std");
const Register = @import("register.zig");

/// Categories for opcodes
/// Inspired by https://www.pastraiser.com/cpu/gameboy/gameboy_opcodes.html
pub const Category = enum {
    control,
    jump,
    byteLoad,
    wordLoad,
    byteMath,
    wordMath,
    bit,
    illegal,

    /// Prints the ascii escape secquence for the color of the category
    /// Dont forget to send '\x1b[0m' when completing the output
    pub fn color(self: @This()) []const u8 {
        return "\x1b[" ++ switch (self) {
            .control => "31m", //red
            .jump => "91m", //salmon
            .byteLoad => "94m", //purple
            .wordLoad => "92m", //green
            .byteMath => "93m", //yellow
            .wordMath => "95m", //magenta
            .bit => "96m", //cyan
            .illegal => "97m", //greyish
        };
    }
};

/// What kind of addressing will be used
pub const AddressingMethod = enum {
    immediate,
    absolute,
    relative,
    none,
};

/// Instruction object
pub const Instruction = struct {
    opcode: u8,
    length: u3,
    cycles: u8,
    addressing: AddressingMethod,
    category: Category,
    name: []const u8,
    source: ?Register.RegisterID = null,
    destination: ?Register.RegisterID = null,

    // std.debug.print("{s}{s}", .{ op.category.color(), op.name });
    //     // padding
    //     for (12 - op.name.len) |_|
    //         std.debug.print(" ", .{});
    //     // newline every 16 intstructions
    //     if (op.opcode & 0xF == 0xF)
    //         std.debug.print("\x1b[0m\n", .{});
    pub fn format(self: Instruction, fmt: []const u8, options: anytype, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("Opcode: ({X:0>2}) \"{s}\"\nCategory: {s} Length: {} Cycles: {}\nSource: {?} Destination: {?}\n", .{
            self.opcode,
            self.name,
            @tagName(self.category),
            self.length,
            self.cycles,
            self.source,
            self.destination,
        });
    }
};

// Load 'em up
pub const Instructions = [256]Instruction{
    // 0x0X
    .{ .opcode = 0x00, .name = "NOP", .length = 1, .cycles = 4, .addressing = .none, .category = .control },
    .{ .opcode = 0x01, .name = "LD BC,d16", .length = 3, .cycles = 12, .addressing = .immediate, .category = .wordLoad, .destination = .BC },
    .{ .opcode = 0x02, .name = "LD (BC),A", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteLoad, .source = .A, .destination = .BC },
    .{ .opcode = 0x03, .name = "INC BC", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x04, .name = "INC B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x05, .name = "DEC B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x06, .name = "LD B,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteLoad, .destination = .B },
    .{ .opcode = 0x07, .name = "RLCA", .length = 1, .cycles = 4, .addressing = .none, .category = .bit },
    .{ .opcode = 0x08, .name = "LD (a16),SP", .length = 3, .cycles = 20, .addressing = .relative, .category = .wordLoad, .source = .SP, .destination = .PC },
    .{ .opcode = 0x09, .name = "ADD HL,BC", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x0A, .name = "LD A,(BC)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteLoad, .destination = .A, .source = .BC },
    .{ .opcode = 0x0B, .name = "DEC BC", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x0C, .name = "INC C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x0D, .name = "DEC C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x0E, .name = "LD C,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteLoad, .destination = .C },
    .{ .opcode = 0x0F, .name = "RRCA", .length = 1, .cycles = 4, .addressing = .none, .category = .bit },

    // 0x1X
    .{ .opcode = 0x10, .name = "STOP 0", .length = 2, .cycles = 4, .addressing = .none, .category = .control },
    .{ .opcode = 0x11, .name = "LD DE,d16", .length = 3, .cycles = 12, .addressing = .immediate, .category = .wordLoad, .destination = .DE },
    .{ .opcode = 0x12, .name = "LD (DE),A", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteLoad, .source = .A, .destination = .DE },
    .{ .opcode = 0x13, .name = "INC DE", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x14, .name = "INC D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x15, .name = "DEC D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x16, .name = "LD D,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteLoad, .destination = .D },
    .{ .opcode = 0x17, .name = "RLA", .length = 1, .cycles = 4, .addressing = .none, .category = .bit },
    .{ .opcode = 0x18, .name = "JR r8", .length = 2, .cycles = 12, .addressing = .relative, .category = .jump },
    .{ .opcode = 0x19, .name = "ADD HL,DE", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x1A, .name = "LD A,(DE)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteLoad, .source = .DE, .destination = .A },
    .{ .opcode = 0x1B, .name = "DEC DE", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x1C, .name = "INC E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x1D, .name = "DEC E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x1E, .name = "LD E,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteLoad, .destination = .E },
    .{ .opcode = 0x1F, .name = "RRA", .length = 1, .cycles = 4, .addressing = .none, .category = .bit },

    // 0x2X
    .{ .opcode = 0x20, .name = "JR NZ,r8", .length = 2, .cycles = 12, .addressing = .relative, .category = .jump },
    .{ .opcode = 0x21, .name = "LD HL,d16", .length = 3, .cycles = 12, .addressing = .immediate, .category = .wordLoad, .destination = .HL },
    .{ .opcode = 0x22, .name = "LD (HL+),A", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteLoad, .destination = .HL, .source = .A },
    .{ .opcode = 0x23, .name = "INC HL", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x24, .name = "INC H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x25, .name = "DEC H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x26, .name = "LD H,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteLoad, .destination = .H },
    .{ .opcode = 0x27, .name = "DAA", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x28, .name = "JR Z,r8", .length = 2, .cycles = 12, .addressing = .relative, .category = .jump },
    .{ .opcode = 0x29, .name = "ADD HL,HL", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x2A, .name = "LD A,(HL+)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteLoad, .destination = .A, .source = .HL },
    .{ .opcode = 0x2B, .name = "DEC HL", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x2C, .name = "INC L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x2D, .name = "DEC L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x2E, .name = "LD L,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteLoad, .destination = .L },
    .{ .opcode = 0x2F, .name = "CPL", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },

    // 0x3X
    .{ .opcode = 0x30, .name = "JR NC,r8", .length = 2, .cycles = 12, .addressing = .relative, .category = .jump },
    .{ .opcode = 0x31, .name = "LD SP,d16", .length = 3, .cycles = 12, .addressing = .immediate, .category = .wordLoad, .destination = .SP },
    .{ .opcode = 0x32, .name = "LD (HL-),A", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteLoad, .destination = .HL, .source = .A },
    .{ .opcode = 0x33, .name = "INC SP", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x34, .name = "INC (HL)", .length = 1, .cycles = 12, .addressing = .absolute, .category = .byteMath },
    .{ .opcode = 0x35, .name = "DEC (HL)", .length = 1, .cycles = 12, .addressing = .absolute, .category = .byteMath },
    .{ .opcode = 0x36, .name = "LD (HL),d8", .length = 2, .cycles = 12, .addressing = .immediate, .category = .byteLoad },
    .{ .opcode = 0x37, .name = "SCF", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x38, .name = "JR C,r8", .length = 2, .cycles = 12, .addressing = .relative, .category = .jump },
    .{ .opcode = 0x39, .name = "ADD HL,SP", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x3A, .name = "LD A,(HL-)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteLoad, .destination = .A, .source = .HL },
    .{ .opcode = 0x3B, .name = "DEC SP", .length = 1, .cycles = 8, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0x3C, .name = "INC A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x3D, .name = "DEC A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },
    .{ .opcode = 0x3E, .name = "LD A,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteLoad, .destination = .A },
    .{ .opcode = 0x3F, .name = "CCF", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath },

    // 0x4X
    .{ .opcode = 0x40, .name = "LD B,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .B, .source = .B },
    .{ .opcode = 0x41, .name = "LD B,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .B, .source = .C },
    .{ .opcode = 0x42, .name = "LD B,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .B, .source = .D },
    .{ .opcode = 0x43, .name = "LD B,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .B, .source = .E },
    .{ .opcode = 0x44, .name = "LD B,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .B, .source = .H },
    .{ .opcode = 0x45, .name = "LD B,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .B, .source = .L },
    .{ .opcode = 0x46, .name = "LD B,(HL)", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .B, .source = .HL },
    .{ .opcode = 0x47, .name = "LD B,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .B, .source = .A },
    .{ .opcode = 0x48, .name = "LD C,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .C, .source = .B },
    .{ .opcode = 0x49, .name = "LD C,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .C, .source = .C },
    .{ .opcode = 0x4A, .name = "LD C,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .C, .source = .D },
    .{ .opcode = 0x4B, .name = "LD C,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .C, .source = .E },
    .{ .opcode = 0x4C, .name = "LD C,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .C, .source = .H },
    .{ .opcode = 0x4D, .name = "LD C,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .C, .source = .L },
    .{ .opcode = 0x4E, .name = "LD C,(HL)", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .C, .source = .HL },
    .{ .opcode = 0x4F, .name = "LD C,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .C, .source = .A },

    // 0x5X
    .{ .opcode = 0x50, .name = "LD D,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .D, .source = .B },
    .{ .opcode = 0x51, .name = "LD D,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .D, .source = .C },
    .{ .opcode = 0x52, .name = "LD D,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .D, .source = .D },
    .{ .opcode = 0x53, .name = "LD D,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .D, .source = .E },
    .{ .opcode = 0x54, .name = "LD D,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .D, .source = .H },
    .{ .opcode = 0x55, .name = "LD D,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .D, .source = .L },
    .{ .opcode = 0x56, .name = "LD D,(HL)", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .D, .source = .HL },
    .{ .opcode = 0x57, .name = "LD D,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .D, .source = .A },
    .{ .opcode = 0x58, .name = "LD E,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .E, .source = .B },
    .{ .opcode = 0x59, .name = "LD E,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .E, .source = .C },
    .{ .opcode = 0x5A, .name = "LD E,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .E, .source = .D },
    .{ .opcode = 0x5B, .name = "LD E,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .E, .source = .E },
    .{ .opcode = 0x5C, .name = "LD E,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .E, .source = .H },
    .{ .opcode = 0x5D, .name = "LD E,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .E, .source = .L },
    .{ .opcode = 0x5E, .name = "LD E,(HL)", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .D, .source = .HL },
    .{ .opcode = 0x5F, .name = "LD E,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .D, .source = .A },

    // 0x6X
    .{ .opcode = 0x60, .name = "LD H,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .H, .source = .B },
    .{ .opcode = 0x61, .name = "LD H,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .H, .source = .C },
    .{ .opcode = 0x62, .name = "LD H,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .H, .source = .D },
    .{ .opcode = 0x63, .name = "LD H,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .H, .source = .E },
    .{ .opcode = 0x64, .name = "LD H,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .H, .source = .H },
    .{ .opcode = 0x65, .name = "LD H,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .H, .source = .L },
    .{ .opcode = 0x66, .name = "LD H,(HL)", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .H, .source = .HL },
    .{ .opcode = 0x67, .name = "LD H,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .H, .source = .A },
    .{ .opcode = 0x68, .name = "LD L,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .L, .source = .B },
    .{ .opcode = 0x69, .name = "LD L,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .L, .source = .C },
    .{ .opcode = 0x6A, .name = "LD L,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .L, .source = .D },
    .{ .opcode = 0x6B, .name = "LD L,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .L, .source = .E },
    .{ .opcode = 0x6C, .name = "LD L,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .L, .source = .H },
    .{ .opcode = 0x6D, .name = "LD L,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .L, .source = .L },
    .{ .opcode = 0x6E, .name = "LD L,(HL)", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .L, .source = .HL },
    .{ .opcode = 0x6F, .name = "LD L,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .L, .source = .A },

    // 0x7X
    .{ .opcode = 0x70, .name = "LD (HL),B", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .HL, .source = .B },
    .{ .opcode = 0x71, .name = "LD (HL),C", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .HL, .source = .C },
    .{ .opcode = 0x72, .name = "LD (HL),D", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .HL, .source = .D },
    .{ .opcode = 0x73, .name = "LD (HL),E", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .HL, .source = .E },
    .{ .opcode = 0x74, .name = "LD (HL),H", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .HL, .source = .H },
    .{ .opcode = 0x75, .name = "LD (HL),L", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .HL, .source = .L },
    .{ .opcode = 0x76, .name = "HALT", .length = 1, .cycles = 4, .addressing = .none, .category = .control },
    .{ .opcode = 0x77, .name = "LD (HL),A", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .HL, .source = .A },
    .{ .opcode = 0x78, .name = "LD A,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .A, .source = .B },
    .{ .opcode = 0x79, .name = "LD A,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .A, .source = .C },
    .{ .opcode = 0x7A, .name = "LD A,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .A, .source = .D },
    .{ .opcode = 0x7B, .name = "LD A,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .A, .source = .E },
    .{ .opcode = 0x7C, .name = "LD A,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .A, .source = .H },
    .{ .opcode = 0x7D, .name = "LD A,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .A, .source = .L },
    .{ .opcode = 0x7E, .name = "LD A,(HL)", .length = 1, .cycles = 4, .addressing = .absolute, .category = .byteLoad, .destination = .A, .source = .HL },
    .{ .opcode = 0x7F, .name = "LD A,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteLoad, .destination = .A, .source = .A },

    // 0x8X
    .{ .opcode = 0x80, .name = "ADD A,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .B },
    .{ .opcode = 0x81, .name = "ADD A,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .C },
    .{ .opcode = 0x82, .name = "ADD A,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .D },
    .{ .opcode = 0x83, .name = "ADD A,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .E },
    .{ .opcode = 0x84, .name = "ADD A,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .H },
    .{ .opcode = 0x85, .name = "ADD A,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .L },
    .{ .opcode = 0x86, .name = "ADD A,(HL)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteMath, .destination = .A, .source = .HL },
    .{ .opcode = 0x87, .name = "ADD A,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .A },
    .{ .opcode = 0x88, .name = "ADC A,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .B },
    .{ .opcode = 0x89, .name = "ADC A,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .C },
    .{ .opcode = 0x8A, .name = "ADC A,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .D },
    .{ .opcode = 0x8B, .name = "ADC A,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .E },
    .{ .opcode = 0x8C, .name = "ADC A,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .H },
    .{ .opcode = 0x8D, .name = "ADC A,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .L },
    .{ .opcode = 0x8E, .name = "ADC A,(HL)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteMath, .destination = .A, .source = .HL },
    .{ .opcode = 0x8F, .name = "ADC A,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .A },

    // 0x9X
    .{ .opcode = 0x90, .name = "SUB A,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .B },
    .{ .opcode = 0x91, .name = "SUB A,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .C },
    .{ .opcode = 0x92, .name = "SUB A,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .D },
    .{ .opcode = 0x93, .name = "SUB A,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .E },
    .{ .opcode = 0x94, .name = "SUB A,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .H },
    .{ .opcode = 0x95, .name = "SUB A,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .L },
    .{ .opcode = 0x96, .name = "SUB A,(HL)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteMath, .destination = .A, .source = .HL },
    .{ .opcode = 0x97, .name = "SUB A,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .A },
    .{ .opcode = 0x98, .name = "SBC A,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .B },
    .{ .opcode = 0x99, .name = "SBC A,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .C },
    .{ .opcode = 0x9A, .name = "SBC A,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .D },
    .{ .opcode = 0x9B, .name = "SBC A,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .E },
    .{ .opcode = 0x9C, .name = "SBC A,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .H },
    .{ .opcode = 0x9D, .name = "SBC A,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .L },
    .{ .opcode = 0x9E, .name = "SBC A,(HL)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteMath, .destination = .A, .source = .HL },
    .{ .opcode = 0x9F, .name = "SBC A,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .A },

    // 0xAX
    .{ .opcode = 0xA0, .name = "AND A,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .B },
    .{ .opcode = 0xA1, .name = "AND A,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .C },
    .{ .opcode = 0xA2, .name = "AND A,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .D },
    .{ .opcode = 0xA3, .name = "AND A,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .E },
    .{ .opcode = 0xA4, .name = "AND A,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .H },
    .{ .opcode = 0xA5, .name = "AND A,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .L },
    .{ .opcode = 0xA6, .name = "AND A,(HL)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteMath, .destination = .A, .source = .HL },
    .{ .opcode = 0xA7, .name = "AND A,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .A },
    .{ .opcode = 0xA8, .name = "XOR A,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .B },
    .{ .opcode = 0xA9, .name = "XOR A,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .C },
    .{ .opcode = 0xAA, .name = "XOR A,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .D },
    .{ .opcode = 0xAB, .name = "XOR A,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .E },
    .{ .opcode = 0xAC, .name = "XOR A,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .H },
    .{ .opcode = 0xAD, .name = "XOR A,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .L },
    .{ .opcode = 0xAE, .name = "XOR A,(HL)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteMath, .destination = .A, .source = .HL },
    .{ .opcode = 0xAF, .name = "XOR A,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .A },

    // 0xBX
    .{ .opcode = 0xB0, .name = "OR A,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .B },
    .{ .opcode = 0xB1, .name = "OR A,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .C },
    .{ .opcode = 0xB2, .name = "OR A,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .D },
    .{ .opcode = 0xB3, .name = "OR A,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .E },
    .{ .opcode = 0xB4, .name = "OR A,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .H },
    .{ .opcode = 0xB5, .name = "OR A,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .L },
    .{ .opcode = 0xB6, .name = "OR A,(HL)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteMath, .destination = .A, .source = .HL },
    .{ .opcode = 0xB7, .name = "OR A,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .A },
    .{ .opcode = 0xB8, .name = "CP A,B", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .B },
    .{ .opcode = 0xB9, .name = "CP A,C", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .C },
    .{ .opcode = 0xBA, .name = "CP A,D", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .D },
    .{ .opcode = 0xBB, .name = "CP A,E", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .E },
    .{ .opcode = 0xBC, .name = "CP A,H", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .H },
    .{ .opcode = 0xBD, .name = "CP A,L", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .L },
    .{ .opcode = 0xBE, .name = "CP A,(HL)", .length = 1, .cycles = 8, .addressing = .absolute, .category = .byteMath, .destination = .A, .source = .HL },
    .{ .opcode = 0xBF, .name = "CP A,A", .length = 1, .cycles = 4, .addressing = .none, .category = .byteMath, .destination = .A, .source = .A },

    // 0xCX
    .{ .opcode = 0xC0, .name = "RET NZ", .length = 1, .cycles = 20, .addressing = .none, .category = .jump },
    .{ .opcode = 0xC1, .name = "POP BC", .length = 1, .cycles = 12, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0xC2, .name = "JP NZ,a16", .length = 3, .cycles = 16, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xC3, .name = "JP a16", .length = 3, .cycles = 16, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xC4, .name = "CALL NZ,a16", .length = 3, .cycles = 24, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xC5, .name = "PUSH BC", .length = 1, .cycles = 16, .addressing = .none, .category = .wordMath },
    .{ .opcode = 0xC6, .name = "ADD A,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteMath, .destination = .A },
    .{ .opcode = 0xC7, .name = "RST 00H", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },
    .{ .opcode = 0xC8, .name = "RET Z", .length = 1, .cycles = 20, .addressing = .none, .category = .jump },
    .{ .opcode = 0xC9, .name = "RET", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },
    .{ .opcode = 0xCA, .name = "JP Z,a16", .length = 3, .cycles = 16, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xCB, .name = "PREFIX CB", .length = 1, .cycles = 4, .addressing = .none, .category = .control },
    .{ .opcode = 0xCC, .name = "CALL Z,a16", .length = 3, .cycles = 24, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xCD, .name = "CALL a16", .length = 3, .cycles = 24, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xCE, .name = "ADC A,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteMath, .destination = .A },
    .{ .opcode = 0xCF, .name = "RST 08H", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },

    // 0xDX
    .{ .opcode = 0xD0, .name = "RET NC", .length = 1, .cycles = 20, .addressing = .none, .category = .jump },
    .{ .opcode = 0xD1, .name = "POP DC", .length = 1, .cycles = 12, .addressing = .none, .category = .wordLoad },
    .{ .opcode = 0xD2, .name = "JP NC,a16", .length = 3, .cycles = 16, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xD3, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .none, .category = .illegal },
    .{ .opcode = 0xD4, .name = "CALL NC,a16", .length = 3, .cycles = 24, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xD5, .name = "PUSH DE", .length = 1, .cycles = 16, .addressing = .none, .category = .wordLoad },
    .{ .opcode = 0xD6, .name = "SUB A,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteMath, .destination = .A },
    .{ .opcode = 0xD7, .name = "RST 10H", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },
    .{ .opcode = 0xD8, .name = "RET C", .length = 1, .cycles = 20, .addressing = .none, .category = .jump },
    .{ .opcode = 0xD9, .name = "RETI", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },
    .{ .opcode = 0xDA, .name = "JP C,a16", .length = 3, .cycles = 16, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xDB, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .none, .category = .illegal },
    .{ .opcode = 0xDC, .name = "CALL C,a16", .length = 3, .cycles = 24, .addressing = .relative, .category = .jump },
    .{ .opcode = 0xDD, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .relative, .category = .illegal },
    .{ .opcode = 0xDE, .name = "SBC A,d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteMath, .destination = .A },
    .{ .opcode = 0xDF, .name = "RST 18H", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },

    // 0xEX
    .{ .opcode = 0xE0, .name = "LDH (a8),A", .length = 2, .cycles = 12, .addressing = .relative, .category = .byteLoad, .source = .A },
    .{ .opcode = 0xE1, .name = "POP HL", .length = 1, .cycles = 12, .addressing = .none, .category = .wordLoad },
    .{ .opcode = 0xE2, .name = "LD (C),A", .length = 2, .cycles = 8, .addressing = .relative, .category = .byteLoad, .source = .A, .destination = .C },
    .{ .opcode = 0xE3, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .none, .category = .illegal },
    .{ .opcode = 0xE4, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .none, .category = .illegal },
    .{ .opcode = 0xE5, .name = "PUSH HL", .length = 1, .cycles = 16, .addressing = .none, .category = .wordLoad },
    .{ .opcode = 0xE6, .name = "SUB d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteMath },
    .{ .opcode = 0xE7, .name = "RST 20H", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },
    .{ .opcode = 0xE8, .name = "ADD SP,r8", .length = 2, .cycles = 16, .addressing = .relative, .category = .wordMath },
    .{ .opcode = 0xE9, .name = "JP (HL)", .length = 1, .cycles = 4, .addressing = .absolute, .category = .jump, .source = .HL },
    .{ .opcode = 0xEA, .name = "LD (a16),A", .length = 3, .cycles = 16, .addressing = .relative, .category = .byteLoad, .source = .A },
    .{ .opcode = 0xEB, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .none, .category = .illegal },
    .{ .opcode = 0xEC, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .none, .category = .illegal },
    .{ .opcode = 0xED, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .relative, .category = .illegal },
    .{ .opcode = 0xEE, .name = "XOR d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteMath },
    .{ .opcode = 0xEF, .name = "RST 28H", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },

    // 0xFX
    .{ .opcode = 0xF0, .name = "LDH A,(a8)", .length = 2, .cycles = 12, .addressing = .relative, .category = .byteLoad, .destination = .A },
    .{ .opcode = 0xF1, .name = "POP AF", .length = 1, .cycles = 12, .addressing = .none, .category = .wordLoad },
    .{ .opcode = 0xF2, .name = "LD A,(C)", .length = 2, .cycles = 8, .addressing = .relative, .category = .byteLoad, .source = .C, .destination = .A },
    .{ .opcode = 0xF3, .name = "DI", .length = 1, .cycles = 4, .addressing = .none, .category = .control },
    .{ .opcode = 0xF4, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .none, .category = .illegal },
    .{ .opcode = 0xF5, .name = "PUSH AF", .length = 1, .cycles = 16, .addressing = .none, .category = .wordLoad },
    .{ .opcode = 0xF6, .name = "OR d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteMath },
    .{ .opcode = 0xF7, .name = "RST 30H", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },
    .{ .opcode = 0xF8, .name = "LD HL,SP+r8", .length = 2, .cycles = 12, .addressing = .relative, .category = .wordLoad },
    .{ .opcode = 0xF9, .name = "LD SP,HL", .length = 1, .cycles = 8, .addressing = .none, .category = .wordLoad, .source = .HL, .destination = .SP },
    .{ .opcode = 0xFA, .name = "LD A,(a16)", .length = 3, .cycles = 16, .addressing = .relative, .category = .byteLoad },
    .{ .opcode = 0xFB, .name = "EI", .length = 1, .cycles = 0, .addressing = .none, .category = .control },
    .{ .opcode = 0xFC, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .none, .category = .illegal },
    .{ .opcode = 0xFD, .name = "ILLEGAL", .length = 1, .cycles = 0, .addressing = .relative, .category = .illegal },
    .{ .opcode = 0xFE, .name = "CP d8", .length = 2, .cycles = 8, .addressing = .immediate, .category = .byteMath },
    .{ .opcode = 0xFF, .name = "RST 38H", .length = 1, .cycles = 16, .addressing = .none, .category = .jump },
};
comptime {
    std.debug.assert(Instructions.len == 256);
}

/// Prints the known opcodes in terminal
pub fn printOpcodes() void {
    std.debug.print("\n", .{});

    for (Instructions) |op| {
        std.debug.print("{s}{s}", .{ op.category.color(), op.name });
        // padding
        for (12 - op.name.len) |_|
            std.debug.print(" ", .{});
        // newline every 16 intstructions
        if (op.opcode & 0xF == 0xF)
            std.debug.print("\x1b[0m\n", .{});
    }
}

test "Opcodes" {
    // printOpcodes();
}
