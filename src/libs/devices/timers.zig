const std = @import("std");
const Device = @import("../device.zig");

const ReadError = Device.ReadError;
const WriteError = Device.WriteError;

const Timers = @This();

/// A ROM device is a memory-mapped device that can be read from. It is read-only and will error on writes.
dev: Device,
mem: []u8 = undefined,

/// Initialize a new ROM device with the given name, start, and end addresses.
/// This will zero out the data and initialize the device.
pub fn init(comptime Name: []const u8, comptime Start: u16, comptime End: u16) !Timers {
    var data: [End - Start]u8 = undefined;

    const self = Timers{
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
fn read(ptr: *anyopaque, address: u16, len: u2) ReadError!u16 {
    var self: *Timers = @ptrCast(@alignCast(ptr));
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
pub fn device(self: *Timers) Device {
    self.dev.ptr = self;
    return self.dev;
}

pub fn reset(ptr: *anyopaque) void {
    const self: *Timers = @ptrCast(@alignCast(ptr));
    @memset(self.mem, 0);
}
const testing = std.testing;

const expectEqual = testing.expectEqual;
const expectError = testing.expectError;
test "Device" {
    const t1 = try Timers.init("rom1", 0xFF04, 0xFF07);
    _ = t1; // autofix
}
