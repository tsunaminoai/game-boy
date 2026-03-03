const std = @import("std");
const Device = @import("../device.zig");

const ReadError = Device.ReadError;
const WriteError = Device.WriteError;

const ROM = @This();

/// A ROM device is a memory-mapped device that can be read from.
/// It is read-only and will error on writes.
dev: Device,
mem: []u8 = undefined,

// IO interface state
position: usize = 0,
reader_buf: [256]u8 = undefined,
reader_interface: std.io.Reader = undefined,

pub fn init(comptime Name: []const u8, comptime Start: u16, comptime End: u16) !ROM {
    const _internal = struct {
        var data: [End - Start + 1]u8 = [_]u8{0} ** (End - Start + 1);
    };

    var self = ROM{
        .dev = try Device.init(
            Name,
            Start,
            End,
            .{ .read = read, .reset = reset },
            &_internal.data,
        ),
        .mem = &_internal.data,
    };

    // Initialize reader interface per actual definition
    self.reader_interface = .{
        .vtable = &.{
            .stream = stream,
        },
        .buffer = &self.reader_buf,
        .seek = 0,
        .end = 0,
    };

    return self;
}

/// VTable stream function: writes data from ROM to the provided Writer
fn stream(r: *std.io.Reader, w: *std.io.Writer, limit: std.io.Limit) std.io.Reader.StreamError!usize {
    const self: *ROM = @alignCast(@fieldParentPtr("reader_interface", r));

    // Calculate how much we can read from ROM
    const remaining = self.mem.len - self.position;
    const to_read = @min(@intFromEnum(limit), remaining);

    if (to_read == 0) return error.EndOfStream;

    // Write directly from ROM to the writer
    const slice = self.mem[self.position..][0..to_read];
    const n = try w.write(slice);
    self.position += n;

    return n;
}

/// Address-based read (for Device interface compatibility)
fn read(ptr: *anyopaque, address: u16, len: u2) ReadError!u16 {
    const self: *ROM = @ptrCast(@alignCast(ptr));

    if (address >= self.mem.len) return ReadError.InvalidAddress;

    if (len == 1) {
        return self.mem[address];
    } else {
        if (address + 1 >= self.mem.len) return ReadError.InvalidAddress;
        return std.mem.readInt(
            u16,
            self.mem[address..][0..2],
            .little,
        );
    }
}

/// Get Reader interface for sequential ROM reading
pub fn reader(self: *ROM) *std.io.Reader {
    return &self.reader_interface;
}

/// Seek to a specific position in ROM for IO operations
pub fn seekTo(self: *ROM, pos: usize) void {
    self.position = @min(pos, self.mem.len);
    // Invalidate buffer on seek
    self.reader_interface.seek = 0;
    self.reader_interface.end = 0;
}

pub fn getPos(self: *ROM) usize {
    return self.position;
}

pub fn device(self: *ROM) Device {
    self.dev.ptr = self;
    return self.dev;
}

pub fn reset(ptr: *anyopaque) void {
    const self: *ROM = @ptrCast(@alignCast(ptr));
    @memset(self.mem, 0);
    self.position = 0;
    self.reader_interface.seek = 0;
    self.reader_interface.end = 0;
}

/// Load ROM data from a file using new IO interface
pub fn loadFromFile(self: *ROM, path: []const u8) !void {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > self.mem.len) {
        std.log.err(
            "ROM file '{s}' too large. Found {} bytes but can hold {}.\n",
            .{ path, stat.size, self.mem.len },
        );
        return error.LoadFileData;
    }

    // Use the file's reader - it already implements the new interface
    var file_reader = file.reader(self.mem[0..stat.size]);
    const bytes_read = try file_reader.interface.readVec(@as([][]u8, @ptrCast(@alignCast(self.mem))));
    _ = bytes_read;

    std.log.info("Loaded {} bytes from '{s}'\n", .{ stat.size, path });
    self.position = 0;
}

pub fn loadFromSlice(self: *ROM, data: []const u8) !void {
    if (data.len > self.mem.len) {
        std.log.err(
            "ROM data too large. Found {} bytes but can hold {}.\n",
            .{ data.len, self.mem.len },
        );
        return error.LoadDataTooLarge;
    }

    @memcpy(self.mem[0..data.len], data);
    self.position = 0;
}

// Tests remain similar but use the correct Reader API
const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectError = testing.expectError;

test "ROM Device - IO interface sequential read" {
    var Rom1 = try ROM.init("rom1", 0x0, 0xFF);

    const test_data = [_]u8{ 0xDE, 0xAD, 0xBE, 0xEF };
    try Rom1.loadFromSlice(&test_data);
    Rom1.seekTo(0);

    const r = Rom1.reader();
    const byte1 = try r.takeByte();
    try expectEqual(0xDE, byte1);

    const byte2 = try r.takeByte();
    try expectEqual(0xAD, byte2);
}
