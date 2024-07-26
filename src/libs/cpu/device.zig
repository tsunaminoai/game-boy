const std = @import("std");
const testing = std.testing;

const ReadError = error{
    InvalidAddress,
    Unimplemented,
};
const WriteError = ReadError;

/// A device is a memory-mapped device that can be read from and written to.
/// This is the interface that all devcies can use
pub const Device = struct {
    ptr: ?*anyopaque,
    vtable: Vtable = .{},
    startAddress: u16,
    endAddress: u16,
    name: []const u8,
    data: []u8,

    const Self = @This();
    const Vtable = struct {
        read: ?*const fn (*anyopaque, u16, usize) ReadError!u16 = null,
        write: ?*const fn (*anyopaque, u16, usize, u16) WriteError!void = null,
    };

    /// Initialize a new device.
    /// This will zero out the data and set the vtable to the given vtable.
    /// Caller is responsible for the initial data block.
    pub fn init(
        name: []const u8,
        startAddress: u16,
        endAddress: u16,
        vtable: ?Vtable,
        data: []u8,
    ) !Self {
        if (startAddress >= endAddress or data.len < endAddress - startAddress)
            return error.InvalidAddress;

        @memset(data, 0);
        var self = Self{
            .ptr = null,
            .name = name,
            .startAddress = startAddress,
            .endAddress = endAddress,
            .data = data,
            .vtable = vtable orelse .{},
        };
        self.ptr = &self;
        return self;
    }

    /// Read up to 2 bytes from memory.
    /// This will map the address to the device space
    pub fn read(self: *Device, address: u16, len: u2) ReadError!u16 {
        if (self.vtable.read == null or self.ptr == null)
            return ReadError.Unimplemented;

        if (address < self.startAddress or address > self.endAddress)
            return ReadError.InvalidAddress;

        std.log.debug(
            "Device read: (0x{X:0>4}) {s}\n",
            .{ address, self.name },
        );
        return self.vtable.read.?(self.ptr.?, address - self.startAddress, len);
    }

    /// Write up to 2 bytes to memory.
    /// This will map the address to the device space
    pub fn write(self: *Device, address: u16, len: u2, value: u16) WriteError!void {
        if (self.vtable.write == null or self.ptr == null)
            return WriteError.Unimplemented;
        if (address < self.startAddress or address > self.endAddress)
            return ReadError.InvalidAddress;
        std.log.debug(
            "Device write: (0x{X:0>4}) {s} : 0x{X:0>4}\n",
            .{ address, self.name, value },
        );
        return self.vtable.write.?(self.ptr.?, address - self.startAddress, len, value);
    }
};

/// A ROM device is a memory-mapped device that can be read from. It is read-only and will error on writes.
const ROM = struct {
    dev: Device,
    mem: []u8 = undefined,

    /// Initialize a new ROM device with the given name, start, and end addresses.
    /// This will zero out the data and initialize the device.
    pub fn init(comptime Name: []const u8, comptime Start: u16, comptime End: u16) !ROM {
        var data: [End - Start]u8 = undefined;

        const self = ROM{
            .dev = try Device.init(
                Name,
                Start,
                End,
                .{ .read = read },
                &data,
            ),
            .mem = &data,
        };
        return self;
    }

    /// Read up to 2 bytes from memory.
    fn read(ptr: *anyopaque, address: u16, len: usize) ReadError!u16 {
        var self: *ROM = @ptrCast(@alignCast(ptr));
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

    /// Get the device from the ROM.
    pub fn device(self: *ROM) Device {
        self.dev.ptr = self;
        return self.dev;
    }
};

/// A RAM device is a memory-mapped device that can be read from and written to.
const RAM = struct {
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
};

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

    var Rom1 = try ROM.init("rom1", 0x200, 0x2FF);
    dev = Rom1.device();
    res = try dev.read(0x200, 1);
    try expectEqual(0, res);
    res = try dev.read(0x200, 2);
    try expectEqual(0, res);
    try expectError(WriteError.Unimplemented, dev.write(0x200, 1, 0x1));
}
