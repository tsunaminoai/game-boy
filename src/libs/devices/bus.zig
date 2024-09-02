const std = @import("std");
const Device = @import("../device.zig");

const ReadError = Device.ReadError;
const WriteError = Device.WriteError;

const Interupt = packed struct(u8) {
    Vblank: bool = false,
    LCD: bool = false,
    Timer: bool = false,
    Joypad: bool = false,
    _: u4 = 0,
    pub fn set(self: *Interupt, value: u8) void {
        const req = std.mem.bytesToValue(Interupt, &value);
        self.* = .{
            .Vblank = self.Vblank or req.Vblank,
            .LCD = self.LCD or req.LCD,
            .Timer = self.Timer or req.Timer,
            .Joypad = self.Joypad or req.Joypad,
        };
    }
    pub fn isSet(self: Interupt) bool {
        return self.Vblank or self.LCD or self.Timer or self.Joypad;
    }
};

/// A Bus is a special type of device that is mapped across the entire address space.
/// Its read and write functions will delegate to the devices that are mapped to it.
const Bus = @This();

dev: Device,
devices: [10]?*Device,
next_dev: usize = 0,
irq_enable: bool = false,
irq_req: Interupt = .{},

pub fn init(comptime size: usize) !Bus {
    var self = Bus{
        .dev = undefined,
        .devices = [_]?*Device{null} ** 10,
    };
    self.dev = try Device.init(
        "Bus",
        0,
        size,
        .{ .read = read, .write = write, .tick = tick },
        null,
    );

    return self;
}

pub fn read(ptr: *anyopaque, address: u16, len: u2) ReadError!u16 {
    const self: *Bus = @ptrCast(@alignCast(ptr));
    switch (address) {
        else => for (0..self.next_dev) |i| {
            var d = self.devices[i] orelse return ReadError.InvalidAddress;
            if (address >= d.startAddress and address < d.endAddress) {
                return d.read(address, len);
            }
        },
    }

    return ReadError.InvalidAddress;
}

pub fn write(ptr: *anyopaque, address: u16, len: u2, value: u16) WriteError!void {
    const self: *Bus = @ptrCast(@alignCast(ptr));
    switch (address) {
        0xFF0F => self.irq_req.set(@truncate(value)),
        0xFFFF => self.irq_enable = value != 0,
        else => for (self.devices) |dMaybe| {
            if (dMaybe) |d| {
                if (address >= d.startAddress and address < d.endAddress) {
                    return d.write(address, len, value);
                }
            }
        },
    }
    return WriteError.InvalidAddress;
}
pub fn reset(ptr: *anyopaque) void {
    const self: *Bus = @ptrCast(@alignCast(ptr));
    for (self.devices) |dMaybe| {
        if (dMaybe) |d| d.reset();
    }
}

pub fn tick(ptr: *anyopaque) void {
    const self: *Bus = @ptrCast(@alignCast(ptr));
    self.irqHandler();
    for (self.devices) |dMaybe| {
        if (dMaybe) |d| d.tick();
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

//TODO: Should this go in the CPU?
pub fn irqHandler(self: *Bus) void {
    if (self.irq_enable and self.irq_req.isSet()) {
        var req = self.irq_req;
        std.log.debug("IRQ Handle: {any}\n", .{req});
        if (req.Vblank) {
            req.Vblank = false;
        }
        if (req.LCD) {
            req.LCD = false;
        }
        if (req.Timer) {
            req.Timer = false;
        }
        if (req.Joypad) {
            req.Joypad = false;
        }
    }
}

pub fn format(self: Bus, _: []const u8, _: anytype, writer: anytype) !void {
    for (self.devices) |dMaybe| {
        if (dMaybe) |d|
            try writer.print("{}\n", .{d.*});
    }
}

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
test "Bus" {
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

test "Interupts" {
    var Bus1 = try Bus.init(
        0xFFFF,
    );
    var bus_dev = Bus1.device();
    bus_dev.reset();

    std.debug.print("{}\n", .{Bus1});

    // Test Interupts
    try bus_dev.write(0xFFFF, 1, 0x1);
    try expectEqual(true, Bus1.irq_enable);

    try bus_dev.write(0xFF0F, 1, 0x1);
    try expectEqual(true, Bus1.irq_req.Vblank);
    try expectEqual(false, Bus1.irq_req.LCD);

    bus_dev.tick();
    try expectEqual(false, Bus1.irq_req.Vblank);

    try bus_dev.write(0xFF0F, 1, 0x2);
    try expectEqual(true, Bus1.irq_req.LCD);
    try expectEqual(false, Bus1.irq_req.Vblank);
    try bus_dev.write(0xFF0F, 1, 0x4);
    try expectEqual(true, Bus1.irq_req.LCD);
    try expectEqual(true, Bus1.irq_req.Timer);
}
