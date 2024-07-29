const std = @import("std");
const Device = @import("../device.zig");

const ReadError = Device.ReadError;
const WriteError = Device.WriteError;

const Timers = @This();

const ClkSelect = enum(u2) {
    @"4096Hz" = 0,
    @"262144Hz" = 1,
    @"65536Hz" = 2,
    @"16384Hz" = 3,
};
const TimerControl = packed struct {
    _1: u6,
    enabled: bool,
    clk_select: ClkSelect,
};

/// A ROM device is a memory-mapped device that can be read from. It is read-only and will error on writes.
dev: Device,
mem: []u8 = undefined,

DIV: *u8, // Divider Register
TIMA: *u8, // Timer Counter
TMA: *u8, // Timer Modulo
TAC: *TimerControl, // Timer Control

/// Initialize a new ROM device with the given name, start, and end addresses.
/// This will zero out the data and initialize the device.
pub fn init(comptime Name: []const u8, comptime Start: u16, comptime End: u16) !Timers {
    var data: [End - Start + 1]u8 = undefined;

    const self = Timers{
        .dev = try Device.init(
            Name,
            Start,
            End,
            .{ .read = read, .write = write, .tick = tick },
            &data,
        ),
        .mem = &data,
        .DIV = &data[0],
        .TIMA = &data[1],
        .TMA = &data[2],
        .TAC = @ptrCast(@alignCast(&data[3])),
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

fn write(ptr: *anyopaque, address: u16, len: u2, value: u16) WriteError!void {
    _ = value; // autofix
    _ = len; // autofix
    const self: *Timers = @ptrCast(@alignCast(ptr));
    switch (address) {
        0xFF04 => self.DIV.* = 0,
        0xFF05 => undefined,
        0xFF06 => undefined,
        0xFF07 => undefined,
        else => return WriteError.InvalidAddress,
    }
}

pub fn tick(ptr: *anyopaque) void {
    const self: *Timers = @ptrCast(@alignCast(ptr));

    const div = @addWithOverflow(self.DIV.*, 1);
    self.DIV.* += div[0];
    if (div[1] == 1) {
        self.TIMA.* = self.TMA.*;
        //TODO: Interrupt
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
test "Timers" {
    var t1 = try Timers.init("rom1", 0xFF04, 0xFF07);
    var dev = t1.device();
    // var res: u16 = undefined;
    for (0..255) |_| dev.tick();
    try expectEqual(t1.DIV.*, 0xFF);

    try dev.write(0xFF04, 1, 0x1);
    try expectEqual(t1.DIV.*, 0);
    std.debug.print("{any}\n", .{t1});
}
