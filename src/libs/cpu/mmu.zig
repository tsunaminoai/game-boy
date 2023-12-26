const std = @import("std");
const Device = @import("device.zig");

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
/// Returns a static memory unit with specified capacity
pub fn StaticMemory(
    comptime Name: []const u8,
    comptime startAddress: u16,
    comptime endAddress: u16,
) type {
    const size = endAddress - startAddress;
    return struct {
        alloc: std.mem.Allocator,

        data: []u8,

        const Self = @This();

        /// Initialize a static memory unit with specified capacity and address
        pub fn init(
            alloc: std.mem.Allocator,
        ) !Self {
            const data = try alloc.alloc(u8, size);
            @memset(data, 0);

            const mmu = Self{
                .alloc = alloc,
                .data = data,
            };

            return mmu;
        }
        /// Deinitialize a static memory unit. Unneeded, but here for completeness
        pub fn deinit(s: *Self) void {
            _ = s;
        }

        fn fatal(self: *Self, fmt: []const u8, args: anytype) noreturn {
            _ = self;
            std.log.debug(fmt, args);
            std.process.exit(1);
        }

        /// Read up to 2 bytes from memory. The caller is responsible for knowing
        /// how to handle u8 v u16, per the len agrument.
        pub fn read(s: *anyopaque, address: u16, len: u2) ReadError!u16 {
            const self = @as(*Self, @alignCast(@ptrCast(s)));

            const value = switch (len) {
                1 => self.data[address],
                2 => std.mem.readInt(u16, @as(*[2]u8, @ptrCast(self.data[address .. address + 2])), .big),
                else => return ReadError.InvalidValueLength,
            };
            std.log.debug("MMU read value {X:0>2}", .{value});
            return value;
        }

        /// Write up to 2 bytes to memory. The caller is responsible for knowing
        /// how to handle u8 v u16, per the len agrument.
        pub fn write(s: *anyopaque, address: u16, len: u2, value: u16) WriteError!void {
            const self = @as(*Self, @alignCast(@ptrCast(s)));
            std.debug.assert(@alignOf(Self) == @alignOf(@TypeOf(self)));
            std.debug.assert(self.data.len == endAddress - startAddress);
            std.log.debug("Writing {X:0>2} to local address: 0x{X:0>2}", .{ value, address });

            var writeValue: []u8 = undefined;
            switch (len) {
                1 => {
                    // std.debug.print(">> current value @{X} = {}\n\n going to {}, {any}\n", .{ address, self.data[address], @as(u8, @truncate(value)), self.data.len });
                    self.data[address] = @as(u8, @truncate(value));
                    // std.debug.print(">> new value @{} = {}\n\n", .{ address, self.data[address] });
                    writeValue = self.*.data[address .. address + 1];
                },
                2 => {
                    self.*.data[address] = @as(u8, @truncate(value >> 8));
                    self.*.data[address + 1] = @as(u8, @truncate(value & 0xFF));
                    writeValue = self.*.data[address .. address + 2];
                },
                else => return WriteError.InvalidValueLength,
            }
            std.log.debug("MMU Wrote: {s}", .{std.fmt.fmtSliceHexUpper(writeValue)});
        }

        /// Print the contents of the memory unit to the console
        /// By default, it will display the first 256 bytes.
        /// This can be changed by using {:NNN} as the formatting string
        /// where NNN is an integer.
        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            const limit: usize = options.width orelse 256;
            std.log.debug("{any}\n", .{limit});
            for (self.data, 0..) |byte, i| {
                if (i >= self.data.len or i >= limit) {
                    break;
                }
                if (i % 16 == 0) {
                    try writer.print("\n0x{X:0>4} | ", .{i + startAddress});
                }
                try writer.print("{X:0>2} ", .{byte});
            }
            std.log.debug("{s}\n", .{fmt});
        }

        pub fn getDevice(self: *Self) Device {
            return Device.init(
                self,
                Name,
                startAddress,
                endAddress,
                Self.read,
                Self.write,
            );
        }
    };
}

const eql = std.testing.expectEqual;

test "StaticMemory" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const alloc = arena.allocator();
    defer arena.deinit();

    var m = try StaticMemory("test", 0, 0xff).init(alloc);
    // defer m.deinit();
    var mem = m.getDevice();
    try mem.write(0x0, 1, 0xBE);
    try mem.write(0x1, 2, 0xEFED);

    // std.debug.print("sm: {}\n", .{m});
    // std.debug.print("dev: {any}\n", .{mem.read(0x0, 2)});
    // std.log.debug("{X:0>4}", .{try mem.read(0x2, 1)});
    try eql(try mem.read(0x0, 2), 0xBEEF);
    try eql(try mem.read(0x2, 1), 0xED);
}
