const std = @import("std");

const MMU = @import("mmu.zig");
const PPU = @import("ppu.zig");

const DeviceError = error{} || MMU.MemoryError;

const Device = @This();

ptr: *anyopaque,
vtable: *const VTable,
startAddress: u16,
endAddress: u16,
size: u16,
name: []const u8,

pub const VTable = struct {
    read: readProto,
    write: writeProto,
};

const readProto = *const fn (ptr: *anyopaque, address: u16, len: u2) DeviceError!u16;
const writeProto = *const fn (ptr: *anyopaque, address: u16, len: u2, value: u16) DeviceError!void;

pub fn read(s: *Device, address: u16, len: u2) !u16 {
    return try s.vtable.read(s.ptr, address, len);
}

pub fn write(s: *Device, address: u16, len: u2, value: u16) !void {
    try s.vtable.write(s.ptr, address, len, value);
}

pub fn init(
    optr: *anyopaque,
    comptime name: []const u8,
    comptime startAddress: u16,
    comptime endAddress: u16,
    comptime readI: readProto,
    comptime writeI: writeProto,
) Device {
    std.debug.assert(@typeInfo(@TypeOf(optr)) == .Pointer);
    const gen = struct {
        pub fn readProtoImpl(ptr: *anyopaque, address: u16, len: u2) !u16 {
            const localAddr = try translateAddress(address);
            return try @call(.auto, readI, .{ ptr, localAddr, len });
        }
        pub fn writeProtoImpl(ptr: *anyopaque, address: u16, len: u2, value: u16) !void {
            const localAddr = try translateAddress(address);
            try @call(.auto, writeI, .{ ptr, localAddr, len, value });
        }

        inline fn isAddressValid(address: u16) bool {
            return address >= startAddress and address <= endAddress;
        }

        /// Translate an address to a local address within the memory unit
        inline fn translateAddress(address: u16) !u16 {
            return if (isAddressValid(address))
                address - startAddress
            else {
                std.log.err("[{s}]Address translation error\nRequested address 0x{X:0>2} is not within 0x{X:0>2} - 0x{X:0>2}\n", .{
                    name,
                    address,
                    startAddress,
                    endAddress,
                });
                return error.AddressOutOfRange;
            };
        }
        const vtable = VTable{
            .read = readProtoImpl,
            .write = writeProtoImpl,
        };
    };
    return .{
        .ptr = optr,
        .vtable = &gen.vtable,
        .name = name,
        .startAddress = startAddress,
        .endAddress = endAddress,
        .size = endAddress - startAddress,
    };
}

test "Device" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    var m = try MMU.StaticMemory("test", 0, 0xff).init(alloc);
    // defer m.deinit();
    var mem = m.getDevice();
    try mem.write(0x0, 1, 0xBE);
    try mem.write(0x1, 2, 0xEFED);

    // std.debug.print("sm: {}\n", .{m});
    // std.debug.print("dev: {any}\n", .{mem.read(0x0, 2)});
    // std.log.debug("{X:0>4}", .{try mem.read(0x2, 1)});
    try std.testing.expectEqual(try mem.read(0x0, 2), 0xBEEF);
    try std.testing.expectEqual(try mem.read(0x2, 1), 0xED);
}
