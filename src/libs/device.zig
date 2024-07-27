const std = @import("std");
const testing = std.testing;

pub const ROM = @import("devices/rom.zig");
pub const RAM = @import("devices/ram.zig");
pub const Bus = @import("devices/bus.zig");
pub const Timers = @import("devices/timers.zig");

pub const ReadError = error{
    InvalidAddress,
    Unimplemented,
};
pub const WriteError = ReadError;

const Device = @This();

/// A device is a memory-mapped device that can be read from and written to.
/// This is the interface that all devcies can use
ptr: ?*anyopaque,
vtable: Vtable = .{},
startAddress: u16,
endAddress: u16,
name: []const u8,
data: ?[]u8,

const Self = @This();
const Vtable = struct {
    read: ?*const fn (*anyopaque, u16, u2) ReadError!u16 = null,
    write: ?*const fn (*anyopaque, u16, u2, u16) WriteError!void = null,
    reset: ?*const fn (*anyopaque) void = null,
};

/// Initialize a new device.
/// This will zero out the data and set the vtable to the given vtable.
/// Caller is responsible for the initial data block.
pub fn init(
    name: []const u8,
    startAddress: u16,
    endAddress: u16,
    vtable: ?Vtable,
    data: ?[]u8,
) !Self {
    if (startAddress >= endAddress)
        return error.InvalidAddress;

    if (data) |d| {
        if (d.len < endAddress - startAddress)
            return error.InvalidAddress;

        @memset(d, 0);
    }
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

pub fn reset(self: *Device) void {
    if (self.vtable.reset) |rst| {
        rst(self.ptr.?);
    }
}

pub fn format(
    self: Device,
    fmt: []const u8,
    options: anytype,
    writer: anytype,
) !void {
    _ = options;
    _ = fmt;
    try writer.print("[{X:0>4}-{X:0>4}] {s}", .{
        self.startAddress,
        self.endAddress,
        self.name,
    });
}

pub const std_options = .{
    // Set the log level to info
    .log_level = .debug,
};
test {
    testing.refAllDecls(@This());
}
