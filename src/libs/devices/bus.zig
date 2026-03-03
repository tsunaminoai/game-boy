const std = @import("std");
const Device = @import("../device.zig");

const ReadError = Device.ReadError;
const WriteError = Device.WriteError;

const Interrupt = packed struct(u8) {
    Vblank: bool = false,
    LCD: bool = false,
    Timer: bool = false,
    Joypad: bool = false,
    _: u4 = 0,

    pub fn set(self: *Interrupt, value: u8) void {
        const req = std.mem.bytesToValue(Interrupt, &value);
        self.* = .{
            .Vblank = self.Vblank or req.Vblank,
            .LCD = self.LCD or req.LCD,
            .Timer = self.Timer or req.Timer,
            .Joypad = self.Joypad or req.Joypad,
        };
    }

    pub fn isSet(self: Interrupt) bool {
        return self.Vblank or self.LCD or self.Timer or self.Joypad;
    }
};

const Bus = @This();

devices: [10]?*Device,
next_dev: usize = 0,
irq_enable: bool = false,
irq_req: Interrupt = .{},

// IO position for sequential access
position: u16 = 0,

// Reader/Writer interfaces
reader_buf: [256]u8 = undefined,
writer_buf: [256]u8 = undefined,
reader_interface: std.io.Reader = undefined,
writer_interface: std.io.Writer = undefined,

pub fn init(comptime size: usize) !Bus {
    _ = size;
    var self = Bus{
        .devices = [_]?*Device{null} ** 10,
    };

    // Initialize reader per actual std.io.Reader definition
    self.reader_interface = .{
        .vtable = &.{
            .stream = readerStream,
        },
        .buffer = &self.reader_buf,
        .seek = 0,
        .end = 0,
    };

    // Initialize writer per actual std.io.Writer definition
    self.writer_interface = .{
        .vtable = &.{
            .drain = writerDrain,
        },
        .buffer = &self.writer_buf,
        .end = 0,
    };

    return self;
}

/// Reader stream function: read from bus and write to provided Writer
fn readerStream(r: *std.io.Reader, w: *std.io.Writer, limit: std.io.Limit) std.io.Reader.StreamError!usize {
    const self: *Bus = @alignCast(@fieldParentPtr("reader_interface", r));

    const to_read = @min(@intFromEnum(limit), 256); // Read up to buffer size
    var bytes_written: usize = 0;

    while (bytes_written < to_read and self.position < 0xFFFF) {
        const value = self.readAddress(self.position, 1) catch |err| switch (err) {
            ReadError.InvalidAddress, ReadError.Unimplemented => break,
        };

        const byte: u8 = @truncate(value);
        _ = w.write(&[_]u8{byte}) catch |err| switch (err) {
            error.WriteFailed => return error.WriteFailed,
        };
        bytes_written += 1;
        self.position += 1;
    }

    if (bytes_written == 0 and self.position >= 0xFFFF) {
        return error.EndOfStream;
    }

    return bytes_written;
}

/// Writer drain function: write buffered data to bus
fn writerDrain(w: *std.io.Writer, _: []const []const u8, _: usize) std.io.Writer.Error!usize {
    const self: *Bus = @alignCast(@fieldParentPtr("writer_interface", w));

    const data = w.buffer[0..w.end];
    for (data) |byte| {
        self.writeAddress(self.position, 1, byte) catch |err| switch (err) {
            WriteError.InvalidAddress, WriteError.Unimplemented => return error.WriteFailed,
        };
        self.position += 1;
    }

    w.end = 0; // Clear buffer after draining
    return w.end;
}

/// Core address-based read
pub fn readAddress(self: *Bus, address: u16, len: u2) ReadError!u16 {
    switch (address) {
        0xFF0F => return @as(u16, @intCast(@as(u8, @bitCast(self.irq_req)))),
        0xFFFF => return if (self.irq_enable) 1 else 0,
        else => {},
    }

    for (0..self.next_dev) |i| {
        const d = self.devices[i] orelse continue;
        if (address >= d.startAddress and address < d.endAddress) {
            return d.read(address, len);
        }
    }

    return ReadError.InvalidAddress;
}

/// Core address-based write
pub fn writeAddress(self: *Bus, address: u16, len: u2, value: u16) WriteError!void {
    switch (address) {
        0xFF0F => {
            self.irq_req.set(@truncate(value));
            return;
        },
        0xFFFF => {
            self.irq_enable = value != 0;
            return;
        },
        else => {},
    }

    for (self.devices) |dMaybe| {
        if (dMaybe) |d| {
            if (address >= d.startAddress and address < d.endAddress) {
                return d.write(address, len, value);
            }
        }
    }

    return WriteError.InvalidAddress;
}

pub fn reader(self: *Bus) *std.io.Reader {
    return &self.reader_interface;
}

pub fn writer(self: *Bus) *std.io.Writer {
    return &self.writer_interface;
}

pub fn seekTo(self: *Bus, pos: u16) void {
    self.position = pos;
    // Invalidate reader buffer
    self.reader_interface.seek = 0;
    self.reader_interface.end = 0;
}

pub fn reset(self: *Bus) void {
    for (self.devices) |dMaybe| {
        if (dMaybe) |d| d.reset();
    }
    self.position = 0;
    self.reader_interface.seek = 0;
    self.reader_interface.end = 0;
    self.writer_interface.end = 0;
}

pub fn tick(self: *Bus) void {
    self.irqHandler();
    for (self.devices) |dMaybe| {
        if (dMaybe) |d| d.tick();
    }
}

pub fn addDev(self: *Bus, dev: *Device) void {
    self.devices[self.next_dev] = dev;
    self.next_dev += 1;
}

pub fn irqHandler(self: *Bus) void {
    if (self.irq_enable and self.irq_req.isSet()) {
        var req = self.irq_req;
        std.log.debug("IRQ Handle: {any}\n", .{req});
        if (req.Vblank) req.Vblank = false;
        if (req.LCD) req.LCD = false;
        if (req.Timer) req.Timer = false;
        if (req.Joypad) req.Joypad = false;
        self.irq_req = req;
    }
}

pub fn format(self: Bus, w: *std.Io.Writer) !void {
    for (self.devices) |dMaybe| {
        if (dMaybe) |d|
            try w.print("{f}\n", .{d.*});
    }
}
