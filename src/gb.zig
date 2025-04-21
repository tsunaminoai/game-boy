const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;

const Z80 = struct {
    pub fn execute(_: anytype) !void {}
};

pub fn GameBoy(rom: [0x7FFF]u8, canvas: anytype) type {
    return struct {
        const GB = @This();

        rom: []u8 = &rommap,
        canvas: @TypeOf(canvas) = canvas,
        romBanks: usize = 2 * math.pow(usize, 2, rom[0x0148]),
        activeBank: usize = 1,
        ramSpace: usize = switch (rom[0x0149]) {
            0 => 0,
            1 => 2048,
            2 => 8192,
            3 => 32768,
            else => 0,
        },
        ramBanks: usize = switch (rom[0x0149]) {
            0 => 0,
            1 => 1,
            2 => 1,
            3 => 4,
            else => 0,
        },
        activeRamBank: usize = 0,
        ramEnabled: bool = false,
        ramRomMode: bool = false, // true for RAM, false for ROM

        lcd: [LCD_HEIGHT * LCD_WIDTH]u8 = [_]u8{0} ** (LCD_HEIGHT * LCD_WIDTH),

        lcdEnabled: bool = true,
        lcdLine: usize = 0,
        lcdMode: u8 = 0,
        lcdStatus: u8 = 0,

        divider: usize = 0,
        timer: usize = 0,

        stopped: bool = false,
        paused: bool = false,
        fps: usize = 60,

        keys: usize = 255,

        transfer: usize = 0,
        transferBytes: usize = 0xFF,
        transferIncoming: ?usize = null,
        transferOutgoing: ?usize = null,
        transferClockOrigin: usize = 0,

        io: [127]u8 = [_]u8{0} ** 127,

        divAPU: f32 = 0.0,

        z80: Z80 = Z80{},

        const Colors = &.{
            .{ 255, 255, 255 },
            .{ 204, 204, 204 },
            .{ 152, 152, 152 },
            .{ 0, 0, 0 },
        };

        const LCD_HEIGHT = 144;
        const LCD_WIDTH = 160;

        var rommap: [rom.len]u8 = rom;

        pub fn pause(self: *GB) void {
            if (!self.paused) {
                self.paused = true;
            } else {
                self.paused = false;
            }
        }

        pub fn stop(self: *GB) void {
            self.stopped = true;
            self.pause();
        }

        pub fn exec(self: *GB) !void {
            if (self.stopped) return;

            if (self.paused) return;

            for (0..LCD_HEIGHT) |i| {
                self.LCDStatusSet(i, 2);
                try self.z80.execute(80);

                self.LCDStatusSet(i, 3);
                try self.z80.execute(172);

                self.LCDStatusSet(i, 0);
                try self.z80.execute(204);
            }
            for (LCD_HEIGHT..154) |i| {
                self.LCDStatusSet(i, 1);
                try self.z80.execute(456);
            }
        }

        fn LCDStatusSet(self: *GB, line: usize, mode: u8) void {
            self.lcdLine = line;
            self.lcdMode = mode;

            if (self.lcdLine == self.io[0x45]) { //LYC == LY
                self.lcdStatus |= 0x04;
                if (self.lcdMode == 0 and self.lcdStatus & 65 != 0) {
                    self.LCDInt();
                }
            } else {
                self.lcdStatus &= ~0x04;
            }

            self.lcdStatus &= ~0x03;
            self.lcdStatus |= mode;

            if (self.lcdMode == 0) {
                if (self.io[0x40] & 128 != 0) self.drawLine(self.lcdLine);
            }
            if (self.lcdLine == LCD_HEIGHT) {
                //TODO render canvas

                self.vBlankInt();
                if (self.lcdStatus & 16 != 0)
                    self.LCDInt();
            }
        }
        fn LCDInt(self: *GB) void {
            self.io[0x0F] |= 0x02;
            self.checkInterupts();
        }
        fn vBlankInt(self: *GB) void {
            self.io[0x0F] |= 0x01;
            self.checkInterupts();
        }
        fn timerInt(self: *GB) void {
            self.io[0x0F] |= 0x01;
            self.checkInterupts();
        }
        fn serialInt(self: *GB) void {
            self.io[0x0F] |= 0x01;
            self.checkInterupts();
        }
        fn joyInt(self: *GB) void {
            self.io[0x0F] |= 0x01;
            self.checkInterupts();
        }
        fn drawLine(self: *GB, line: usize) void {
            for (0..LCD_WIDTH) |i| {
                self.lcd[line * LCD_WIDTH + i] = self.Colors[self.lcd[i]];
            }
        }
        fn checkInterupts(self: *GB) void {
            if (self.io[0xFF0F] & self.io[0xFFFF] != 0) {
                self.io[0xFFFF] = 0;
            }
        }
    };
}
test {
    const rom: [0x7FFF]u8 = [_]u8{1} ** 0x7FFF;
    const canvas = [_]u8{0} ** 0x7FFF;
    const gb = GameBoy(rom, canvas){};
    std.debug.print("{}\n", .{gb});
}
