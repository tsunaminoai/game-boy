const std = @import("std");

pub fn StaticMemory(comptime name: []const u8, comptime size: usize) type {
    return struct {
        name: []const u8 = name,
        size: usize = size,

        const Self = @This();

        var data: [size]u8 = [_]u8{0} ** size;

        pub fn init() Self {
            return Self{};
        }
        pub fn read(self: *Self, address: u16, len: u2) !u16 {
            _ = self;
            if (address + len > size) {
                return error.AddressOutOfRange;
            } else {
                return switch (len) {
                    1 => data[address],
                    2 => std.mem.readIntSliceBig(u16, data[address .. address + 2]),
                    else => error.InvalidValueLength,
                };
            }
        }
        pub fn write(self: *Self, address: u16, len: u2, value: u16) !void {
            _ = self;
            if (address + len > data.len) {
                return error.AddressOutOfRange;
            } else {
                switch (len) {
                    1 => data[address] = @as(u8, @truncate(value)),
                    2 => {
                        data[address] = @as(u8, @truncate(value >> 8));
                        data[address + 1] = @as(u8, @truncate(value & 0xFF));
                    },
                    else => return error.InvalidValueLength,
                }
            }
        }
        pub fn format(
            self: Self,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = self;
            for (data, 0..) |byte, i| {
                if (i >= data.len) {
                    break;
                }
                if (i % 16 == 0) {
                    try writer.print("\n0x{X:0>4} | ", .{i});
                }
                try writer.print("{X:0>2} ", .{byte});
            }
        }
    };
}

const eql = std.testing.expectEqual;
test "StaticMemory" {
    var mem = StaticMemory("Test", 0x10).init();
    try mem.write(0x0, 1, 0xBE);
    try mem.write(0x1, 2, 0xEFED);

    std.debug.print("{any}\n", .{mem});
    std.debug.print("{X:0>4}\n", .{try mem.read(0x2, 1)});
    try eql(try mem.read(0x0, 2), 0xBEEF);
    try eql(try mem.read(0x2, 1), 0xED);
}
