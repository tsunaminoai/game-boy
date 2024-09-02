const std = @import("std");

pub const Device = @import("device.zig");

const GB = @This();

rom0: Device.ROM,
cpu: Device.CPU,

pub fn init(comptime size: usize) !GB {
    var bus = try Device.Bus.init(size);
    var rom0 = try Device.ROM.init("Rom0", 0x0, 0x7FFF);
    var rom_dev = rom0.device();
    bus.addDev(&rom_dev);
    const cpu = try Device.CPU.init(&bus);
    return GB{
        .rom0 = rom0,
        .cpu = cpu,
    };
}

pub fn format(
    self: GB,
    _: []const u8,
    _: anytype,
    writer: anytype,
) !void {
    try writer.print("GB\n", .{});
    try writer.print("{}", .{self.cpu.bus});
}

test {
    std.testing.refAllDeclsRecursive(@This());
}
