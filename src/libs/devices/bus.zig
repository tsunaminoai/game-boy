const std = @import("std");
const Device = @import("../device.zig");

const ReadError = Device.ReadError;
const WriteError = Device.WriteError;

/// A Bus is a special type of device that is mapped across the entire address space.
/// Its read and write functions will delegate to the devices that are mapped to it.
const Bus = @This();

dev: Device,
devices: [10]?*Device,
next_dev: usize = 0,

pub fn init(comptime size: usize) !Bus {
    var self = Bus{
        .dev = undefined,
        .devices = [_]?*Device{null} ** 10,
    };
    self.dev = try Device.init(
        "Bus",
        0,
        size,
        .{ .read = read, .write = write },
        null,
    );

    return self;
}

pub fn read(ptr: *anyopaque, address: u16, len: u2) ReadError!u16 {
    const self: *Bus = @ptrCast(@alignCast(ptr));
    for (0..self.next_dev) |i| {
        var d = self.devices[i] orelse return ReadError.InvalidAddress;
        if (address >= d.startAddress and address < d.endAddress) {
            return d.read(address, len);
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
pub fn reset(ptr: *anyopaque) void {
    const self: *Bus = @ptrCast(@alignCast(ptr));
    for (self.devices) |dMaybe| {
        if (dMaybe) |d| d.reset();
    }
}

pub fn addDev(self: *Bus, dev: *Device) void {
    self.devices[self.next_dev] = dev;
    self.next_dev += 1;
}

pub fn device(self: *Bus) Device {
    self.dev.ptr = self;
    return self.dev;
}

pub fn format(self: Bus, _: []const u8, _: anytype, writer: anytype) !void {
    for (self.devices) |dMaybe| {
        if (dMaybe) |d|
            try writer.print("{}\n", .{d});
    }
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
test "Device" {
    var Rom0 = try Device.ROM.init("Rom0", 0x0, 0xFF);
    var rom_dev = Rom0.device();
    var Bus1 = try Bus.init(
        0xFFFF,
    );
    Bus1.addDev(&rom_dev);
    var bus_dev = Bus1.device();
    bus_dev.reset();

    std.debug.print("{}\n", .{Bus1});

    // Test ROM device
    var res = try bus_dev.read(0x0000, 1);
    try expectEqual(0, res);
    res = try bus_dev.read(0x0000, 2);
    try expectEqual(0, res);
    try expectError(WriteError.Unimplemented, bus_dev.write(0x0000, 1, 0x1));
}
