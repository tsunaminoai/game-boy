const std = @import("std");

fn StaticMemory(comptime name: []const u8, comptime size: usize) type {
    return struct {
        name: []const u8 = name,
        size: usize = size,
        stream: *std.io.FixedBufferStream([]u8),

        const Self = @This();

        var data: [size]u8 = [_]u8{0} ** size;

        pub fn init() Self {
            var stream: std.io.FixedBufferStream([]u8) = std.io.fixedBufferStream(&data);
            return Self{
                .stream = &stream,
            };
        }
        pub fn read(self: *Self, address: u16, len: u2) !u16 {
            if (address + len > size) {
                return error.AddressOutOfRange;
            } else {
                var reader = self.stream.reader();
                try self.stream.seekTo(address);
                return switch (len) {
                    1 => try reader.readByte(),
                    2 => try reader.readIntBig(u16),
                    else => error.InvalidValueLength,
                };
            }
        }
        pub fn write(self: *Self, address: u16, len: u2, value: u16) !void {
            if (address + len > data.len) {
                return error.AddressOutOfRange;
            } else {
                var writer = self.stream.writer();
                try self.stream.seekTo(address);
                switch (len) {
                    1 => try writer.writeByte(@as(u8, @truncate(value))),
                    2 => try writer.writeIntBig(u16, value),
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
            for (self.stream.buffer, 0..) |byte, i| {
                if (i >= self.stream.buffer.len) {
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
