/// This is going to be a general purpose 16 bit register
const std = @import("std");

const RegisterMethods = @This();

const Size = enum { Byte, Double };

fn Register(comptime size: Size) type {
    switch (size) {
        .Byte => {
            return struct {
                value: u32 = 0,
                size: Size = size,

                const Self = @This();

                pub usingnamespace RegisterMethods;
            };
        },
        .Double => {
            return struct {
                value: u32 = 0,
                size: Size = size,
                upper: Register(.Byte) = Register(.Byte){},
                lower: Register(.Byte) = Register(.Byte){},

                const Self = @This();

                pub usingnamespace RegisterMethods;
            };
        },
    }
}

pub fn getUpper(self: *Register(.Double)) *Register(.Byte) {
    return &self.upper;
}
pub fn getLower(self: *Register(.Double)) *Register(.Byte) {
    return &self.lower;
}

test "8bit registers" {
    var r = Register(.Byte){};
    try std.testing.expect(r.value == 0);
    try std.testing.expect(r.size == .Byte);
}

test "16bit registers" {
    var AF = Register(.Double){};
    var A = AF.getUpper();
    var F = AF.getLower();
    try std.testing.expect(AF.value == 0);
    try std.testing.expect(AF.size == .Double);
    try std.testing.expect(A.size == .Byte);
    try std.testing.expect(F.size == .Byte);
}
