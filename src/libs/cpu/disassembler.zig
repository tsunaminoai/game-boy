const std = @import("std");
const Register = @import("register.zig");
const OC = @import("opcodes.zig");

const DAsm = @This();

const Command = struct {
    instruction: OC.Instruction,
    operand: ?u16,
};

position: u64 = 0,
alloc: std.mem.Allocator,
file: std.fs.File,
commands: std.ArrayList(Command),

pub fn init(alloc: std.mem.Allocator, file: std.fs.File) DAsm {
    return DAsm{
        .alloc = alloc,
        .file = file,
        .commands = std.ArrayList(Command).init(alloc),
    };
}

pub fn deinit(self: *DAsm) void {
    self.commands.deinit();
}

pub fn parse(self: *DAsm) !void {
    var reader = self.file.reader();
    const end = try reader.context.getEndPos();
    while (self.position < end) : (self.position += 1) {
        const opcode = try reader.readByte();
        var inst = OC.Instructions[opcode];
        var operand: ?u16 = null;
        switch (inst.length) {
            1 => {},
            2 => {
                operand = try reader.readByte();
                self.position += 1;
            },
            3 => {
                operand = try reader.readIntBig(u16);
                self.position += 2;
            },
            else => return error.UnknownOpcode,
        }
        var command = Command{ .instruction = inst, .operand = operand };
        try self.commands.append(command);
    }
}

pub fn print(self: *DAsm, writer: anytype) !void {
    try writer.writeAll("Disassmbly\n");
    var addressSpace: u16 = 0;
    for (self.commands.items) |cmd| {
        try writer.print("{X:0>4}: {s}\n", .{ addressSpace, cmd.instruction.name });
        addressSpace += cmd.instruction.length;
    }
}

test "Disassembler" {
    var gpa = std.testing.allocator;
    var rom = try std.fs.cwd().openFile("rom.bin", .{});
    var ds = DAsm.init(gpa, rom);
    defer ds.deinit();
    try ds.parse();
    var stdout = std.io.getStdOut();
    try ds.print(stdout.writer());
}
