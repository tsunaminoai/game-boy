const std = @import("std");

const BusError = error{
    InvalidAddress,
};
const Device = struct {
    startAddress: u16,
    endAddress: u16,
    // read: fn (self: *Device, address: u16) BusError!u16,
    // write: fn (self: *Device, address: u16, value: u16) BusError!void,
};

pub fn Bus() type {
    return struct {
        devices: std.ArrayList(Device) = undefined,
        arena: std.mem.Allocator,

        const Self = @This();

        pub fn init(arena: std.mem.Allocator) Self {
            return Self{
                .arena = arena,
                .devices = std.ArrayList(Device).init(arena),
            };
        }
        pub fn deinit(self: *Self) void {
            self.devices.deinit();
        }

        pub fn getDevice(self: *Self, address: u16) u8 {
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

test "Bus" {
    var gpa = std.testing.allocator;
    var bus = Bus().init(gpa);
    defer bus.deinit();
}
