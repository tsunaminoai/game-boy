/// This is going to be a general purpose 16 bit register
const std = @import("std");

const RegisterMethods = @This();

const Size = enum { Byte, Double };

fn Register8() type {
    return struct {
        value: u32 = 0,

        const Self = @This();
        var parent: Register(.Double) = undefined;

        pub usingnamespace RegisterMethods;
    };
}

fn Register16() type {
    const upper = Register(.Byte){};
    const lower = Register(.Byte){};

    return struct {
        value: u32 = 0,
        upper: Register(.Byte) = upper,
        lower: Register(.Byte) = lower,

        const Self = @This();

        pub usingnamespace RegisterMethods;
    };
}

fn Register(comptime size: Size) type {
    switch (size) {
        .Byte => { return Register8(); },
        .Double => { return Register16(); },
    }
}

pub fn getUpper(self: *Register(.Double)) *Register(.Byte) {
    return &self.upper;
}
pub fn getLower(self: *Register(.Double)) *Register(.Byte) {
    return &self.lower;
}

pub fn set(self: *Register(.Double), value: u32) void {
    self.value = value;
    self.lower.value = value & 0xff;
    self.upper.value = (value >> 8) & 0xff;
}

test "8bit registers" {
    var r = Register(.Byte){};
    try std.testing.expect(r.value == 0);
}

test "16bit registers" {
    var AF = Register(.Double){};
    var A = AF.getUpper();
    var F = AF.getLower();
    try std.testing.expect(AF.value == 0);

    AF.set(0xBEEF);
    try std.testing.expectEqual(AF.value, 0xBEEF);
    try std.testing.expectEqual(A.value, 0xBE);
    try std.testing.expectEqual(F.value, 0xEF);
}
