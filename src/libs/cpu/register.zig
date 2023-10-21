const std = @import("std");

/// This is the regsiter bank. This is the 4th or 5th time I've attempted this.
/// This version is what I'm going with. Its not elegant. Its not pretty.
/// Its probably not even "ziggy" if such a thing exists at time of writing.
/// But its low-level-af
var data = [_]u8{
    0x01, 0xB0, // af
    0x00, 0x13, // bc
    0x00, 0xD8, // de
    0x01, 0x4D, // hl
    0xFF, 0xFE, // sp
    0x00, 0x00, // pc
};
af: *u16 = @as(*u16, @ptrCast(@alignCast(data[0..2]))),
a: *u8 = &data[1],
f: *u8 = &data[0],

bc: *u16 = @as(*u16, @ptrCast(@alignCast(data[2..4]))),
b: *u8 = &data[3],
c: *u8 = &data[2],

de: *u16 = @as(*u16, @ptrCast(@alignCast(data[4..6]))),
d: *u8 = &data[5],
e: *u8 = &data[4],

hl: *u16 = @as(*u16, @ptrCast(@alignCast(data[6..8]))),
h: *u8 = &data[7],
l: *u8 = &data[6],

sp: *u16 = @as(*u16, @ptrCast(@alignCast(data[8..10]))),

pc: *u16 = @as(*u16, @ptrCast(@alignCast(data[10..12]))),

const Self = @This();

pub fn init() Self {
    return Self{};
}

pub const RegisterID = enum {
    AF,
    DE,
    BC,
    HL,
    SP,
    PC,
    A,
    B,
    C,
    D,
    E,
    H,
    L,
};
pub fn writeReg(self: *Self, reg: RegisterID, value: u16) !void {
    switch (reg) {
        .AF => self.af.* = value,
        .BC => self.bc.* = value,
        .DE => self.de.* = value,
        .HL => self.hl.* = value,
        .PC => self.pc.* = value,
        .SP => self.sp.* = value,
        else => |r| {
            const value8 = @as(u8, @truncate(value));
            switch (r) {
                .A => self.a.* = value8,
                .B => self.b.* = value8,
                .C => self.c.* = value8,
                .D => self.d.* = value8,
                .E => self.e.* = value8,
                .H => self.h.* = value8,
                .L => self.l.* = value8,
                else => return error.InvalidRegister,
            }
        },
    }
}
pub fn increment(self: *Self, reg: RegisterID) !void {
    const value = try self.readReg(reg) + 1;
    // std.debug.print("Incrementing: {s} to {X:0>4}\n", .{ @tagName(reg), value });

    try self.writeReg(reg, value);
}
pub fn decrement(self: *Self, reg: RegisterID) !void {
    const value = try self.readReg(reg) - 1;
    // std.debug.print("Decrementing: {s} to {X:0>4}\n", .{ @tagName(reg), value });

    try self.writeReg(reg, value);
}

pub fn readReg(self: *Self, reg: RegisterID) !u16 {
    return switch (reg) {
        .AF => self.af.*,
        .BC => self.bc.*,
        .DE => self.de.*,
        .HL => self.hl.*,
        .PC => self.pc.*,
        .SP => self.sp.*,
        .A => self.a.*,
        .B => self.b.*,
        .C => self.c.*,
        .D => self.d.*,
        .E => self.e.*,
        .H => self.h.*,
        .L => self.l.*,
    };
}

const eql = std.testing.expectEqual;
test "More Registers" {
    var reg = init();
    reg.b.* = 0xBE;
    reg.c.* = 0xEF;

    try eql(reg.bc.*, 0xBEEF);

    reg.bc.* = 0xDEAD;
    try eql(reg.b.*, 0xDE);
    try eql(reg.c.*, 0xAD);

    try reg.writeReg(.B, 0xB0);
    try reg.writeReg(.C, 0xDE);

    try eql(try reg.readReg(.BC), 0xB0DE);
    try reg.writeReg(.BC, 0xF00F);
    try eql(try reg.readReg(.B), 0xF0);
    try eql(try reg.readReg(.C), 0x0F);

    // std.debug.print("{s}\n", .{reg});
}

pub fn format(
    self: Self,
    comptime _: []const u8,
    _: std.fmt.FormatOptions,
    writer: anytype,
) !void {
    try writer.print("\n|A {X:0>2} |F {X:0>2} | = {X:0>4}\n", .{ self.a.*, self.f.*, self.af.* });
    try writer.print("|B {X:0>2} |C {X:0>2} | = {X:0>4}\n", .{ self.b.*, self.c.*, self.bc.* });
    try writer.print("|D {X:0>2} |E {X:0>2} | = {X:0>4}\n", .{ self.d.*, self.e.*, self.de.* });
    try writer.print("|H {X:0>2} |L {X:0>2} | = {X:0>4}\n", .{ self.h.*, self.l.*, self.hl.* });
    try writer.print("|SP   {X:0>4}   |\n", .{self.sp.*});
    try writer.print("|PC   {X:0>4}   |\n", .{self.pc.*});
}
