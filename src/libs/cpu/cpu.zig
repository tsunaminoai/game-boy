const std = @import("std");

const HalfRegister = struct {
    value: u8 = 0,

    pub fn set(self: *HalfRegister, value: u8) !void {
        self.value = value;
    }

    pub fn get(self: *HalfRegister) u8 {
        return self.value;
    }
};
test "Test a half register works as expected" {
    const testVal1: u8 = 0xFF;
    const testVal2: u8 = 0xBC;
    var R1 = HalfRegister{ .value = testVal1 };
    try std.testing.expect(R1.get() == testVal1);
    try R1.set(testVal2);
    try std.testing.expect(R1.get() == testVal2);
}

const FullRegister = struct {
    UpperByte: *HalfRegister,
    LowerByte: *HalfRegister,
    pub fn get(self: *FullRegister) u16 {
        return self.UpperByte.get() << 8 + self.LowerByte.get();
    }
    pub fn set(self: *FullRegister, value: u16) !void {
        try self.LowerByte.set(@as(u8, @truncate(value)));
        try self.UpperByte.set(@as(u8, @truncate(value >> 8)));
    }
};

fn createRegister() *FullRegister {
    var h1 = HalfRegister{ .value = 0 };
    var h2 = HalfRegister{ .value = 0 };
    var newRegister = FullRegister{
        .LowerByte = &h1,
        .UpperByte = &h2,
    };

    return &newRegister;
}

test "Test a full register sets its bytes correctly" {
    const testVal1: u16 = 0x0A0B;
    _ = testVal1;
    var R1: *FullRegister = createRegister();
    try R1.set(0x0A0B);
}

const Flags = packed struct(u8) {
    Zero: bool,
    Subtract: bool,
    HalfCarry: bool,
    Carry: bool,
    _: u4, //unused
};

test "Test flags will work" {}
