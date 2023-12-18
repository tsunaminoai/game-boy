const std = @import("std");

const MMU = @import("mmu.zig");

pub const BusError = error{
    InvalidAddress,
    Unimplemented,
} || std.mem.Allocator.Error || MMU.MemoryError;

/// The bus is an abstract connector that will be used to connect all of the
/// devices together. It will be used to read and write to the devices.
pub fn Bus() type {
    return struct {
        arena: std.heap.ArenaAllocator,
        alloc: std.mem.Allocator,
        devices: std.StringHashMap(MMU.StaticMemory()),

        const Self = @This();

        /// Initialize the bus with the given allocator. This will allocate the
        /// arena and the devices hashmap.
        pub fn init(alloc: std.mem.Allocator) BusError!Self {
            var arena = std.heap.ArenaAllocator.init(alloc);
            const ally = arena.allocator();
            var d = std.StringHashMap(MMU.StaticMemory()).init(ally);

            // var rom0 = try MMU.StaticMemory().init("rom0", 0x4000, 0, 0x3fff, ally);
            var rom0 = try MMU.StaticMemory().init("rom0", 0xffff, 0, 0xffff, ally);
            try d.put("rom0", rom0);

            return Self{
                .arena = arena,
                .alloc = ally,
                .devices = d,
            };
        }
        /// Deinitialize the bus. This will deinitialize all of the devices and
        /// the arena.
        pub fn deinit(self: *Self) void {
            var devIter = self.devices.valueIterator();
            while (devIter.next()) |*dev|
                dev.*.deinit();
            self.arena.deinit();
        }

        /// Get the device at the given address. This will return an error if
        /// the address is not mapped to a device.
        pub fn getDevice(self: *Self, address: u16) BusError!?MMU.StaticMemory() {
            return switch (address) {
                0x0000...0xFFFF => self.devices.get("rom0").?, // 16k rom bank 0    ¯|_ 32k cart
                // 0x4000...0x7FFF => error.Unimplemented, // 16k switable bank _|
                // 0x8000...0x9FFF => error.Unimplemented, // 8k video ram
                // 0xA000...0xBFFF => error.Unimplemented, // 8k switchable ram bank
                // 0xC000...0xDFFF => error.Unimplemented, // 8k internal ram
                // 0xE000...0xFD77 => error.Unimplemented, // Internal ram echo
                // 0xFE00...0xFE0F => error.Unimplemented, // OAM
                // 0xFEA0...0xFEFF => error.InvalidAddress, // empty and unusable
                // 0xFF00...0xFF4B => error.Unimplemented, // io ports
                // 0xFF4C...0xFF7F => error.InvalidAddress, // empty and unusable
                // 0xFF80...0xFFFE => error.Unimplemented, // internal ram
                // 0xFFFF => error.Unimplemented, // IRQ enable
                // else => error.InvalidAddress,
            };
        }

        /// Wrapper around the device read function. This will get the device
        /// at the given address and then call the read function on it.
        pub fn read(self: *Self, address: u16, length: u2) BusError!u16 {
            var dev = if (try self.getDevice(address)) |d| d else return error.InvalidAddress;
            return try dev.read(address, length);
        }

        /// Wrapper around the device write function. This will get the device
        /// at the given address and then call the write function on it.
        pub fn write(self: *Self, address: u16, len: u2, value: u16) BusError!void {
            var dev = if (try self.getDevice(address)) |d| d else return error.InvalidAddress;
            std.log.debug("Bus Write (0x{X:02}) using device '{s}'\n", .{ address, dev.name });
            return dev.write(address, len, value) catch |err| {
                std.log.err("Could not write! \n{s}\n", .{@errorName(err)});
                return err;
            };
        }
    };
}

const eql = std.testing.expectEqual;
test "bus" {
    var bus = try Bus().init(std.testing.allocator);
    defer bus.deinit();
    // std.log.debug("start: {x:02}\n", .{bus.devices.get("rom0").?.startAddress});

    try bus.write(0x3ff0, 1, 0xff);
    try std.testing.expectEqual(try bus.read(0x3ff0, 1), 0xff);
}
