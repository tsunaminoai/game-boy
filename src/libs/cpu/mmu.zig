const std = @import("std");

const Self = @This();
const size: usize = 0x8000;

gpa: std.mem.Allocator,
bytes: []u8,

pub fn init() !Self {
    var buffer = [_]u8{0} ** size;
    var fba = std.heap.FixedBufferAllocator.init(buffer[0..]);
    var allocator = fba.allocator();
    var bytes = try allocator.alloc(u8, size);

    return Self{ .gpa = allocator, .bytes = bytes };
}

pub fn deinit(self: *Self) void {
    self.* = undefined;
}

pub fn write(self: *Self, address: u16, value: u8) void {
    std.debug.assert(address <= size);
    self.bytes[address] = value;
}

pub fn read(self: *Self, address: u16) u8 {
    return self.bytes[address];
}

test "test mmu" {
    const Mmu = @import("mmu.zig");

    var val: u16 = 0;

    var mmu = try Mmu.init();
    defer mmu.deinit();

    for (0..size) |i| {
        const addr :u16 = @intCast(i);
        mmu.write(addr, 0xff);
        val = mmu.read(addr);
        try std.testing.expect(val == 0xff);
    }
}

test {
    std.testing.refAllDecls(@This());
}
