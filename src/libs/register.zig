const std = @import("std");
const expect = @import ("std").testing.expect;
const RegisterName = @import("./cpu/types.zig").RegisterName;

const RegisterValue = union { half: u8, full: u16 };

const Register8Bit = struct {
    value: RegisterValue,

    const Self = @This();

    pub fn get(self: *Self) RegisterValue {
        return self.value;
    }
    pub fn set(self: *Self, value: RegisterValue) !void {
        self.value = value;
    }
    pub fn init(value: RegisterValue) Self {
        return .{
            .value = value
        };
    }
};

test "Set 8bit register" {
    const v: RegisterValue = @as(u8, 0x1);
    var r1 = Register8Bit.init(v);
    try r1.set(0x1);
    try expect(r1.get() == v);
}

