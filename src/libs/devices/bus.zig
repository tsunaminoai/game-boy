const std = @import("std");
const Device = @import("../device.zig");

const ReadError = Device.ReadError;
const WriteError = Device.WriteError;

/// A Bus is a special type of device that is mapped across the entire address space.
/// Its read and write functions will delegate to the devices that are mapped to it.
const Bus = @This();

dev: Device,
devices: [10]?Device,
next_dev: usize = 0,
mem: []u8,

var memory: [0xFFFF]u8 = undefined;

pub fn init(comptime size: usize) !Bus {
    var self = Bus{
        .dev = undefined,
        .devices = [_]?Device{null} ** 10,
        .mem = &memory,
    };
    self.dev = try Device.init(
        "Bus",
        0,
        size,
        .{ .read = read, .write = write },
        &memory,
    );

    return self;
}

pub fn read(ptr: *anyopaque, address: u16, len: u2) ReadError!u16 {
    const self: *Bus = @ptrCast(@alignCast(ptr));
    for (self.devices) |dMaybe| {
        if (dMaybe) |d| {
            if (address >= d.startAddress and address < d.endAddress) {
                return d.read(address, len);
            }
        }
    }
    return ReadError.InvalidAddress;
}

pub fn write(ptr: *anyopaque, address: u16, len: u2, value: u16) WriteError!void {
    const self: *Bus = @ptrCast(@alignCast(ptr));
    for (self.devices) |dMaybe| {
        if (dMaybe) |d| {
            if (address >= d.startAddress and address < d.endAddress) {
                return d.write(address, len, value);
            }
        }
    }
    return WriteError.InvalidAddress;
}

pub fn addDev(self: *Bus, dev: Device) void {
    for (self.devices) |d| {
        if (d == null)
            d = dev;
    }
}

pub fn device(self: *Bus) Device {
    return self.dev;
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
test "Device" {
    var Rom0 = try Device.ROM.init("Rom0", 0x0, 0xFF);
    const rom_dev = Rom0.device();
    var Bus1 = try Bus.init(
        0xFFFF,
    );
    try Bus1.addDev(rom_dev);
    var dev = Bus1.device();
    std.debug.print("{any}\n", .{dev});

    // Test ROM device
    var res = try dev.read(0x0000, 1);
    try expectEqual(0, res);
    res = try dev.read(0x0000, 2);
    try expectEqual(0, res);
    try expectError(WriteError.Unimplemented, dev.write(0x0000, 1, 0x1));
}
