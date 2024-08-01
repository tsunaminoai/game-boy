const std = @import("std");

pub const Device = @import("device.zig");

const GB = @This();

bus: Device.Bus,
rom0: Device.ROM,
cpu: Device.CPU,

pub fn init() !GB {
    var bus = try Device.Bus.init(0xFFFF);
    const rom0 = try Device.ROM.init("Rom0", 0x0, 0x7FFF);
    const cpu = try Device.CPU.init(&bus);
    return GB{
        .bus = bus,
        .rom0 = rom0,
        .cpu = cpu,
    };
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
