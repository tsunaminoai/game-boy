const std = @import("std");

const BusError = error{
    InvalidAddress,
};

pub fn Device() type {
    return struct {
        endAddress: u16,
        startAddress: u16,
        name: []const u8,
        data: []u8 = undefined,
        alloc: std.mem.Allocator,
        read: ?*const fn (self: *Self, address: u16) BusError!u16 = null,
        write: ?*const fn (self: *Self, address: u16, value: u16) BusError!void = null,

        const Self = @This();

        pub fn init(name: []const u8, start: u16, end: u16, alloc: std.mem.Allocator) !Self {
            const size = end - start;
            var d = try alloc.alloc(u8, size);
            return Self{
                .name = name,
                .startAddress = start,
                .endAddress = end,
                .alloc = alloc,
                .data = d,
            };
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.data);
        }
    };
}

pub fn Bus() type {
    return struct {
        arena: std.mem.Allocator,

        const Self = @This();

        pub fn init(arena: std.mem.Allocator) Self {
            return Self{
                .arena = arena,
            };
        }
        pub fn deinit(self: *Self) void {
            _ = self;
        }

        pub fn getDevice(self: *Self, address: u16) !Device {
            _ = self;
            return switch (address) {
                0x0000...0x3FFF => {}, // 16k rom bank 0    ¯|_ 32k cart
                0x4000...0x7FFF => {}, // 16k switable bank _|
                0x8000...0x9FFF => {}, // 8k video ram
                0xA000...0xBFFF => {}, // 8k switchable ram bank
                0xC000...0xDFFF => {}, // 8k internal ram
                0xE000...0xFD77 => {}, // Internal ram echo
                0xFE00...0xFEBF => {}, // OAM
                0xFEA0...0xFEFF => unreachable, // empty and unusable
                0xFF00...0xFF4B => {}, // io ports
                0xFF4C...0xFF7F => undefined, // empty and unusable
                0xFF80...0xFFFE => {}, // internal ram
                0xFFFF => {}, // IRQ enable
                else => unreachable,
            };
        }
    };
}

const eql = std.testing.expectEqual;
test "Bus" {
    var gpa = std.testing.allocator;
    var bus = Bus().init(gpa);
    defer bus.deinit();
}

test "Device" {
    var gpa = std.testing.allocator;

    var d = try Device().init("Test", 0x0, 0x100, gpa);
    defer d.deinit();
    try eql(d.name, "Test");
    try eql(d.data.len, 0x100);
}
