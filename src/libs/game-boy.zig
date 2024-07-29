const std = @import("std");

pub const Device = @import("device.zig");

pub fn init(comptime size: usize) !Device.CPU {
    var bus = try Device.Bus.init(size);
    var Rom0 = try Device.ROM.init("Rom0", 0x0000, 0x4000);
    var rom_dev = Rom0.device();
    bus.addDev(&rom_dev);
    const cpu = try Device.CPU.init(&bus);
    return cpu;
}

test {
    std.testing.refAllDeclsRecursive(@This());

    const cpu = try init(0xFFFF);
    _ = cpu; // autofix
}
