const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;

const Z80 = @import("z80.zig");

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
        lcdLine: u8 = 0,
        lcdMode: u8 = 0,
        lcdStatus: u8 = 0,

        divider: u8 = 0,
        timer: u8 = 0,

        stopped: bool = false,
        paused: bool = false,
        fps: usize = 60,

        keys: u8 = 255,

        transfer: u8 = 0,
        transferBytes: u8 = 0xFF,
        transferIncoming: ?u8 = null,
        transferOutgoing: ?u8 = null,
        transferClockOrigin: u8 = 0,

        audioEnabled: bool = true,

        io: [127]u8 = [_]u8{0} ** 127,
        vram: [8192]u8 = [_]u8{0} ** 8192,
        wram: [8192]u8 = [_]u8{0} ** 8192,
        oam: [160]u8 = [_]u8{0} ** 160,
        stack: [256]u8 = [_]u8{0} ** 256,
        cartRam: ?[]u8 = null,
        intEnable: u8 = 0,

        divAPU: f32 = 0.0,

        z80: Z80 = Z80{
            .getAddress = GB._getAddress,
            .putAddress = GB._putAddress,
            .checkForInterupts = GB._checkInterupts,
            .system = undefined,
        },

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
        fn _checkInterupts(ptr: *anyopaque) void {
            const self: *GB = @alignCast(@ptrCast(ptr));
            self.checkInterupts();
        }
        fn _getAddress(ptr: *anyopaque, address: u16) u8 {
            const self: *GB = @alignCast(@ptrCast(ptr));
            return self.getAddress(address);
        }
        fn _putAddress(ptr: *anyopaque, address: u16, value: u8) void {
            const self: *GB = @alignCast(@ptrCast(ptr));
            self.putAddress(address, value);
        }
        fn checkInterupts(self: *GB) void {
            var vector: u8 = self.io[0x0F];
            if (vector & 1 != 0 and self.intEnable & 1 != 0) {
                self.z80.cont();
                if (self.z80.IME > 0) {
                    vector &= ~@as(u8, 1);
                    self.z80.interupt(0x40);
                }
            } else if (vector & 2 != 0 and self.intEnable & 2 != 0) {
                self.z80.cont();
                if (self.z80.IME > 0) {
                    vector &= ~@as(u8, 2);
                    self.z80.interupt(0x48);
                }
            } else if (vector & 4 != 0 and self.intEnable & 4 != 0) {
                self.z80.cont();
                if (self.z80.IME > 0) {
                    vector &= ~@as(u8, 4);
                    self.z80.interupt(0x50);
                }
            } else if (vector & 8 != 0 and self.intEnable & 8 != 0) {
                self.z80.cont();
                if (self.z80.IME > 0) {
                    vector &= ~@as(u8, 8);
                    self.z80.interupt(0x58);
                }
            } else if (vector & 16 != 0 and self.intEnable & 16 != 0) {
                self.z80.cont();
                if (self.z80.IME > 0) {
                    vector &= ~@as(u8, 16);
                    self.z80.interupt(0x60);
                }
            }
            self.io[0x0F] = vector;
        }
        fn putAddress(self: *GB, address: u16, value: u8) void {
            switch (address) {
                0x0...0x1FFF => { // RAM
                    if (value == 0) self.ramEnabled = false;
                    if (value == 0x0A) self.ramEnabled = true;
                },
                0x2000...0x3FFF => { // ROM
                    self.activeBank = @mod(value, 32);
                },
                0x4000...0x5FFF => { // RAM Banks
                    if (!self.ramRomMode) { // rom mode
                        self.activeBank = (self.activeBank & 0x1F) | @mod(value, 4) << 5;
                    } else { // ram mode
                        self.activeBank = @mod(value, 4);
                    }
                },
                0x6000...0x7FFF => { // RAM Banks
                    self.ramRomMode = value & 1 == 0;
                },
                0x8000...0x9FFF => { // Video
                    self.vram[address - 0x8000] = value;
                },
                0xA000...0xBFFF => { // Cart RAM
                    if (self.cartRam == null or !self.ramEnabled) return;
                    if ((address - 0xA00 + self.activeRamBank * 8192) >= self.cartRam.?.len) return;
                    self.cartRam.?[address - 0xA00 + self.activeRamBank * 8192] = value;
                },
                0xC000...0xDFFF => { // Work RAM
                    self.wram[address - 0xC000] = value;
                },
                0xE000...0xFDFF => { // Work RAM
                    self.wram[address - 0xE000] = value;
                },
                0xFE00...0xFE9F => { // OAM
                    self.oam[address - 0xFE00] = value;
                },
                0xFF00...0xFF7F => { // IO
                    self.putIO(@mod(address, 0xFF00), value);
                },
                0xFF80...0xFFFE => { // Stack
                    self.stack[address - 0xFF80] = value;
                },
                0xFFFF => { // Interrupt enable
                    self.intEnable = value;
                },
                else => {
                    std.debug.print("Unknown address: {x}\n", .{address});
                },
            }
        }
        fn getAddress(self: *GB, address: u16) u8 {
            std.debug.print("Getting address 0x{X:0>2}\n", .{address});
            switch (address) {
                0x0...0x3FFF => { // ROM
                    std.debug.print("got {}\n", .{self.rom[address]});
                    return self.rom[address];
                },
                0x4000...0x7FFF => { // RAM Banks
                    return self.rom[address + 0x4000 * (self.activeBank - 1)];
                },
                0x8000...0x9FFF => { // Video
                    return self.vram[address - 0x8000];
                },
                0xA000...0xBFFF => { // Cart RAM
                    if (self.cartRam == null or !self.ramEnabled) return 0;
                    if (address - 0xA000 + self.activeRamBank * 8192 >= self.cartRam.?.len) return 0;
                    return self.cartRam.?[address - 0xA000 + self.activeRamBank * 8192];
                },
                0xC000...0xDFFF => { // Work RAM
                    return self.wram[address - 0xC000];
                },
                0xE000...0xFDFF => { // Work RAM
                    return self.wram[address - 0xE000];
                },
                0xFE00...0xFE9F => { // OAM
                    return self.oam[address - 0xFE00];
                },
                0xFF00...0xFF7F => { // IO
                    return self.getIO(@mod(address, 0xFF00));
                },
                0xFF80...0xFFFE => { // Stack
                    return self.stack[address - 0xFF80];
                },
                0xFFFF => { // Interrupt enable
                    return self.intEnable;
                },
                else => {
                    std.debug.print("Unknown address: {x}\n", .{address});
                },
            }
            return 0;
        }
        fn getIO(self: *GB, address: u16) u8 {
            return switch (address) {
                0 => blk: {
                    if (self.io[0] & 48 == 48)
                        break :blk self.io[0] & ~@as(u8, 15)
                    else if (self.io[0] & 48 == 32) // dir keys
                        break :blk (self.io[0] & ~@as(u8, 15)) | (self.keys & 15)
                    else if (self.io[0] & 48 == 16) // buttons
                        break :blk (self.io[0] & ~@as(u8, 15)) | (self.keys >> 4);

                    break :blk self.io[0] | 15;
                },
                0x01 => self.transferBytes,
                0x02 => (self.transfer << 7) | self.transferClockOrigin,
                0x04 => self.divider,
                0x05 => self.timer,
                0x41 => self.lcdStatus,
                0x44 => self.lcdLine,
                0x26 => if (self.audioEnabled) 0x8F else 0,
                else => self.io[address],
            };
        }
        fn putIO(self: *GB, address: u16, value: u8) void {
            switch (address) {
                //TODO: add actual functionality
                0xFF00...0xFF7F => { // IO
                    self.io[address - 0xFF00] = value;
                },
                else => {
                    std.debug.print("Unknown address: {x}\n", .{address});
                },
            }
        }
    };
}
test {
    const ROM = [_]u8{0x03};
    const rom: [0x7FFF]u8 = ROM ++ ([_]u8{0} ** (0x7FFF - ROM.len));
    const canvas = [_]u8{0} ** 0x7FFF;
    var gb = GameBoy(rom, canvas){};
    gb.z80.system = &gb;

    gb.z80.registers.B = 0x01;
    gb.z80.registers.C = 0x02;
    gb.putAddress(0x0000, 0x03);
    std.debug.print("{any}\n", .{gb.rom[0..10]});
    std.debug.print("{s}\n", .{canvas});
    // try gb.z80.execute(10);
    // std.debug.print("{}\n", .{gb.z80});
    // try tst.expectEqual(0x01, gb.z80.registers.B);
    // try tst.expectEqual(0x03, gb.z80.registers.C);

    // gb.putAddress(0xffff, 10);
    // try tst.expectEqual(10, gb.getAddress(0xffff));
}
