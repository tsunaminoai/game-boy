const std = @import("std");

const Self = @This();
const BUFFER_SIZE: usize = 0x12;

blocks: extern struct {
    internal_rom: [BUFFER_SIZE]u8 align(8),
    video_ram: [0x2000]u8 align(8),
},

pub fn deinit(self: *Self) void {
    self.* = undefined;
}

pub fn write(self: *Self, address: u16, value: u8) void {
    std.debug.assert(address <= BUFFER_SIZE);
    const bytes = std.mem.asBytes(&self.blocks);
    bytes[address] = value;
}

pub fn read(self: *Self, address: u16) u8 {
    return std.mem.asBytes(&self.blocks)[address];
}

pub fn write16(self: *Self, address: u16, value: u16) void {
    std.debug.assert(address <= BUFFER_SIZE - 2);

    self.write(address, @truncate(0xff & value));
    self.write(address + 1, @truncate(0xff & (value >> 8)));
}

pub fn read16(self: *Self, address: u16) u16 {
    const msb: u8 = self.read(address + 1);
    const lsb: u8 = self.read(address);
    var composite: u16 = msb;
    composite = (composite << 8) | lsb;
    return composite;
}

pub fn hexDump(self: *Self, address: u16, size: u16) void {
    var cursor = address;
    const end = address + size;
    std.debug.assert(end <= size);
    while (cursor < end) : (cursor += 8) blk: {
        if (cursor % 8 == 0) {
            std.debug.print("\n{X:0>4}: ", .{cursor});
        }
        for (0..8) |i| {
            if (cursor + i >= end) break :blk;
            std.debug.print("{X:0>2} ", .{self.read(@intCast(cursor + i))});
        }
    }
    std.debug.print("\n", .{});
}

pub fn reset(self: *Self) void {
    @memset(&self.blocks.internal_rom, 0);
}

test "8bit rw" {
    const Mmu = @import("mmu.zig");

    var val: u16 = 0;

    var mmu = Mmu{
        .blocks = undefined,
    };

    for (0..BUFFER_SIZE) |i| {
        const addr: u16 = @intCast(i);
        mmu.write(addr, 0xff);
        val = mmu.read(addr);
        try std.testing.expect(val == 0xff);
    }
}

test "16bit rw" {
    const Mmu = @import("mmu.zig");
    var mmu = Mmu{
        .blocks =  undefined
    };

    for (0..(BUFFER_SIZE / 2) - 1) |i| {
        const addr: u16 = @intCast(i * 2);
        mmu.write16(addr, 0xaabb);
        try std.testing.expectEqual(mmu.read(addr), 0xbb);
        try std.testing.expectEqual(mmu.read(addr + 1), 0xaa);
        try std.testing.expectEqual(mmu.read16(addr), 0xaabb);
    }
}

test {
    std.testing.refAllDecls(@This());
}
