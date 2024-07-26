const std = @import("std");
const Device = @import("../device.zig");

const ReadError = Device.ReadError;
const WriteError = Device.WriteError;

const RAM = @This();

/// A RAM device is a memory-mapped device that can be read from and written to.
dev: Device,
mem: []u8 = undefined,

/// Initialize a new ROM device with the given name, start, and end addresses.
/// This will zero out the data and initialize the device.
pub fn init(comptime Name: []const u8, comptime Start: u16, comptime End: u16) !RAM {
    var data: [End - Start]u8 = undefined;
    const self = RAM{
        .dev = try Device.init(
            Name,
            Start,
            End,
            .{ .read = read, .write = write },
            &data,
        ),
        .mem = &data,
    };
    return self;
}

/// Read up to 2 bytes from memory.
fn read(ptr: *anyopaque, address: u16, len: usize) ReadError!u16 {
    var self: *RAM = @ptrCast(@alignCast(ptr));
    if (len == 1) {
        return self.mem[address];
    } else {
        return std.mem.readInt(
            u16,
            self.mem[address..].ptr[0..2],
            .little,
        );
    }
}

/// Write up to 2 bytes to memory.
fn write(ptr: *anyopaque, address: u16, len: usize, value: u16) WriteError!void {
    var self: *RAM = @ptrCast(@alignCast(ptr));
    if (len == 1) {
        self.mem[address] = @truncate(value);
    } else {
        std.mem.writeInt(
            u16,
            self.mem[address..].ptr[0..2],
            value,
            .little,
        );
    }
}

/// Get the device from the ROM.
pub fn device(self: *RAM) Device {
    self.dev.ptr = self;
    return self.dev;
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
test "Device" {
    var Rom0 = try RAM.init("rom0", 0xFF, 0x1FF);
    var dev = Rom0.device();
    var res: u16 = undefined;

    try dev.write(0xFF, 1, 0x1);
    res = try dev.read(0xFF, 1);
    try expectEqual(0x1, res);
    try dev.write(0xFF, 2, 0x1234);
    res = try dev.read(0xFF, 2);
    try expectEqual(0x1234, res);

    try expectError(ReadError.InvalidAddress, dev.read(0x10, 1));
    try expectError(WriteError.InvalidAddress, dev.write(0x10, 1, 0x1));
}
