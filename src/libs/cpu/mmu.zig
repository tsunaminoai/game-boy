const std = @import("std");

pub const MemoryError = error{
    AddressOutOfRange,
    InvalidValueLength,
    TooMuchCapacityRequested,
    SizeDoesntMatchAdddressRange,
} || std.mem.Allocator.Error;

const ReadError = MemoryError;
const WriteError = MemoryError;

/// An emulator of an mmu. I'm sure there are zig std library functions that
/// could handle this more ellegantly, but with the way the GB works on both u8
/// and u16 cells it's clearer whats happening this way
///
/// Returns a static memory unit with 16kB capacity
pub fn StaticMemory() type {
    return struct {
        name: []const u8,
        size: usize,
        startAddress: u16,
        endAddress: u16,
        alloc: std.mem.Allocator,
        data: []u8,

        const Self = @This();

        pub fn init(
            name: []const u8,
            size: usize,
            startAddress: u16,
            endAddress: u16,
            alloc: std.mem.Allocator,
        ) !Self {
            if (endAddress - startAddress > size) {
                std.log.err("Address range of 0x{X:02} to 0x{X:02} requested, but size is 0x{X:02}\n", .{ startAddress, endAddress, size });
                return MemoryError.SizeDoesntMatchAdddressRange;
            }

            var data = try alloc.alloc(u8, size);
            @memset(data, 0);

            return Self{
                .name = name,
                .size = size,
                .startAddress = startAddress,
                .endAddress = endAddress,
                .alloc = alloc,
                .data = data,
            };
        }

        pub fn deinit(self: *Self) void {
            self.alloc.free(self.name);
            self.alloc.free(self.data);
        }

        fn fatal(self: *Self, fmt: []const u8, args: anytype) noreturn {
            _ = self;
            std.debug.print(fmt, args);
            std.process.exit(1);
        }

        fn addressIsValid(self: Self, address: u16) bool {
            return self.startAddress <= address and address <= self.endAddress;
        }
        fn translateAddress(self: Self, address: u16) MemoryError!u16 {
            return if (self.addressIsValid(address))
                address - self.startAddress
            else
                error.AddressOutOfRange;
        }

        /// Read up to 2 bytes from memory. The caller is responsible for knowing
        /// how to handle u8 v u16, per the len agrument.
        pub fn read(self: *Self, address: u16, len: u2) ReadError!u16 {
            std.log.debug("MMU address range: 0x{X:02}-0x{X:02}. Reading 0x{X:02} =>  0x{X:02}\n", .{
                // self.name,
                self.startAddress,
                self.endAddress,
                address,
                address - self.startAddress,
            });

            const localAddr = self.translateAddress(address) catch |err| {
                std.log.err("Read error: Address out of range.\nAttempted to access: 0x{X:02}\n", .{address});
                return err;
            };

            return switch (len) {
                1 => self.data[localAddr],
                2 => std.mem.readIntSliceBig(u16, self.data[address .. address + 2]),
                else => ReadError.InvalidValueLength,
            };
        }

        /// Write up to 2 bytes to memory. The caller is responsible for knowing
        /// how to handle u8 v u16, per the len agrument.
        pub fn write(self: *Self, address: u16, len: u2, value: u16) WriteError!void {
            std.debug.print("MMU address range: 0x{X:02}-0x{X:02}. Writing value 0x{X:02} to 0x{X:02}\n", .{
                // self.name.len,
                self.startAddress,
                self.endAddress,
                value,
                address,
            });
            const localAddr = self.translateAddress(address) catch |err| {
                std.debug.print("Write error: Address out of range.\nAttempted to access: 0x{X:02}\nAddress start: 0x{X:02} end: 0x{X:02}\n", .{
                    address,
                    self.startAddress,
                    self.endAddress,
                });
                return err;
            };

            switch (len) {
                1 => self.data[localAddr] = @as(u8, @truncate(value)),
                2 => {
                    self.data[localAddr] = @as(u8, @truncate(value >> 8));
                    self.data[localAddr + 1] = @as(u8, @truncate(value & 0xFF));
                },
                else => return WriteError.InvalidValueLength,
            }
        }
        pub fn format(
            self: Self,
            comptime _: []const u8,
            _: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            for (self.data, 0..) |byte, i| {
                if (i >= self.data.len) {
                    break;
                }
                if (i % 16 == 0) {
                    try writer.print("\n0x{X:0>4} | ", .{i});
                }
                try writer.print("{X:0>2} ", .{byte});
            }
        }
    };
}

const eql = std.testing.expectEqual;
test "StaticMemory" {
    var mem = try StaticMemory().init("Test", 0x3fff, 0, 0x3fff, std.testing.allocator);
    defer mem.deinit();
    try mem.write(0x0, 1, 0xBE);
    try mem.write(0x1, 2, 0xEFED);

    // std.debug.print("{any}\n", .{mem});
    // std.debug.print("{X:0>4}\n", .{try mem.read(0x2, 1)});
    try eql(try mem.read(0x0, 2), 0xBEEF);
    try eql(try mem.read(0x2, 1), 0xED);
}
