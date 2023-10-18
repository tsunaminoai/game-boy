const std = @import("std");

/// Whather a halfregister is considering itself an upper or lower byte
const RegisterSegment = enum { MSB, LSB };

/// Half registers are for representing the concept that gameboy 16bit registers
/// are really 2 8bit registers in a trechcoat. Thus, if the H register is set
/// to "0xBE" and the L register is set to "0xEF" then the HL register should
/// read "0xBEEF"
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
        /// Sets the HalfRegister's internal value. When called, the parent
        /// 16bit register's value is updated directly
        pub fn set(self: *Self, value: u8) void {
            self.value = value;

            var newValue: u16 = value;

            self.parent.value = switch (self.segment) {
                .MSB => (self.parent.value & 0x00FF) | newValue << 8,
                .LSB => (self.parent.value & 0xFF00) | newValue,
            };
        }

        // internal function for the parent 16bit register to call to set child values
        fn setRaw(self: *Self, value: u8) void {
            self.value = value;
        }

        // formatter
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

/// Registers are represented as u16 bit registers with a MSB and LSB represented
/// as HalfRegsiters. Modifying either the parent or child will update the other.
pub fn Register() type {
    return struct {
        value: u16,
        msb: HalfRegister(.MSB) = undefined,
        lsb: HalfRegister(.LSB) = undefined,

        const Self = @This();

        /// initiializes the register. setChildren() must be called *directly after* this
        pub fn init(initialValue: u16) Self {
            var reg = Self{
                .value = initialValue,
            };
            return reg;
        }

        /// Sets the up the children. Best way I know how to do this as placing
        /// it in the init method causes additional phantom registers to appear.
        pub fn setChildren(self: *Self) void {
            self.msb = HalfRegister(.MSB).init(self, Self.getSegment(self.value, .MSB));
            self.lsb = HalfRegister(.LSB).init(self, Self.getSegment(self.value, .LSB));
        }

        /// Returns a pointer to the MSB. Thereafter, the MSB can be considered like any other register
        /// ex. `var H = HL.getMSB();`
        pub fn getMSB(self: *Self) *HalfRegister(.MSB) {
            return &self.msb;
        }

        /// Returns a pointer to the LSB. Thereafter, the LSB can be considered like any other register
        /// ex. `var L = HL.getLSB();`
        pub fn getLSB(self: *Self) *HalfRegister(.LSB) {
            return &self.lsb;
        }

        /// Retrived the desired segment a u16 int
        pub fn getSegment(value: u16, segment: RegisterSegment) u8 {
            return switch (segment) {
                .MSB => @as(u8, @truncate(value >> 8)),
                .LSB => @as(u8, @truncate(value & 0xFF)),
            };
        }

        /// Sets the value of the register. Also updates the children.
        pub fn set(self: *Self, value: u16) void {
            self.value = value;
            self.msb.setRaw(Self.getSegment(value, .MSB));
            self.lsb.setRaw(Self.getSegment(value, .LSB));
        }

        // formatter
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
    AF.setChildren();
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
