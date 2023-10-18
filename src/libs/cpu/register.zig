const std = @import("std");

const RegisterSegment = enum { MSB, LSB };
pub fn HalfRegister(comptime segment: RegisterSegment) type {
    return struct {
        value: u8,
        parent: *Register(),
        segment: RegisterSegment = segment,

        const Self = @This();

        pub fn init(parent: *Register(), value: u8) Self {
            return Self{
                .value = value,
                .parent = parent,
            };
        }

        pub fn set(self: *Self, value: u8) void {
            self.value = value;

            var newValue: u16 = value;

            self.parent.value = switch (self.segment) {
                .MSB => (self.parent.value & 0x00FF) | newValue << 8,
                .LSB => (self.parent.value & 0xFF00) | newValue,
            };
        }

        pub fn setRaw(self: *Self, value: u8) void {
            self.value = value;
        }
        pub fn format(
            self: Self,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print("{X:0>2}", .{self.value});
        }
    };
}
pub fn Register() type {
    return struct {
        value: u16,
        msb: HalfRegister(.MSB) = undefined,
        lsb: HalfRegister(.LSB) = undefined,

        const Self = @This();

        pub fn init(initialValue: u16) Self {
            var reg = Self{
                .value = initialValue,
            };
            return reg;
        }
        pub fn setParents(self: *Self) void {
            self.msb = HalfRegister(.MSB).init(self, Self.getSegment(self.value, .MSB));
            self.lsb = HalfRegister(.LSB).init(self, Self.getSegment(self.value, .LSB));
        }
        pub fn getMSB(self: *Self) *HalfRegister(.MSB) {
            return &self.msb;
        }
        pub fn getLSB(self: *Self) *HalfRegister(.LSB) {
            return &self.lsb;
        }

        pub fn getSegment(value: u16, segment: RegisterSegment) u8 {
            return switch (segment) {
                .MSB => @as(u8, @truncate(value >> 8)),
                .LSB => @as(u8, @truncate(value & 0xFF)),
            };
        }

        pub fn set(self: *Self, value: u16) void {
            self.value = value;
            self.msb.setRaw(Self.getSegment(value, .MSB));
            self.lsb.setRaw(Self.getSegment(value, .LSB));
        }

        pub fn format(
            self: Self,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            try writer.print("{X:0>4} [{}][{}]\n", .{ self.value, self.msb, self.lsb });
        }
    };
}

const eql = std.testing.expectEqual;
test "Simple regsiter" {
    var AF = Register().init(0xBEEF);
    AF.setParents();
    var A = AF.getMSB();
    var F = AF.getLSB();
    try eql(&AF, A.parent);
    try eql(&AF, F.parent);

    try eql(AF.value, 0xBEEF);

    try eql(A.value, 0xBE);
    try eql(F.value, 0xEF);

    A.set(0xDE);
    try eql(A.value, 0xDE);
    try eql(AF.value, 0xDEEF);

    F.set(0xAD);
    try eql(F.value, 0xAD);
    try eql(AF.value, 0xDEAD);

    std.debug.print("AF: {}\n", .{AF});
}
