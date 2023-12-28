const std = @import("std");
const MMU = @import("mmu.zig");
// pub usingnamespace MMU.StaticMemory();

const VGMem_Size = 8 * 1014;
const OAM = 0xA0;
const Num_Rows = 144;
const Num_Cols = 160;
const Num_Tiles = 384;

const Frame_Cyles = 70_224;
const Background_Priority = 0b10;
const Col0_Flag = 0b01;

const Interrupt = enum(u5) {
    none = 0,
    vBlank = 1,
    lcdC = 2,
    timer = 4,
    serial = 8,
    high_to_low = 16,
};

const LCD_Register = enum(u8) {
    none = 0,
    background_enable = 1,
    sprite_enable = 2,
    sprite_height = 4,
    backgroundmap_select = 8,
    tiledata_select = 16,
    window_enable = 32,
    windowmap_select = 64,
    lcd_enable = 128,
    _,

    pub fn set(self: LCD_Register, value: u8) LCD_Register {
        return @enumFromInt(@intFromEnum(self) | value);
    }
    pub fn isSet(self: LCD_Register, check: LCD_Register) bool {
        return 0 != @intFromEnum(self) & @intFromEnum(check);
    }
};

const Stat_Register = struct {
    value: u8 = 0b1000_0000,
    mode: u3 = 0,

    pub fn init(value: u8) Stat_Register {
        var s = Stat_Register{};
        s.set(value);
        return s;
    }
    pub fn set(self: *Stat_Register, value: u8) void {
        const v = value & 0b0111_1000; // bit 7 is always true. bits 0-2 are RO
        self.value &= 0b1000_0111; // keep RO buts and clear all else
        self.value |= v;
    }

    pub fn updateLYC(self: *Stat_Register, LYC: u8, LY: u8) Interrupt {
        if (LYC == LY) {
            self.value |= 0b100; // sets the LYC flag
            if (self.value & 0b0100_0000 == 0b0100_0000)
                return Interrupt.lcdC;
        } else self.value &= 0b1111_1011; // clear LYC flag

        return Interrupt.none;
    }

    pub fn setMode(self: *Stat_Register, mode: u3) Interrupt {
        if (self.mode == mode)
            return Interrupt.none;

        self.mode = mode;
        self.value &= 0b1111_1100; //clear LSBs
        self.value |= mode; //apply mode to LSBs

        var t: u8 = 1;
        t = t << @as(u3, 3 + mode);

        if (mode != 3 and (t & self.value) != 0) {
            return Interrupt.lcdC;
        }
        return Interrupt.none;
    }
};

const PalletteRegister = struct {
    value: u8 = 0,
    lookup: [4]u8 = [_]u8{0} ** 4,
    mem_rgb: [4]u8 = [_]u8{0} ** 4,

    pub fn init(value: u8) PalletteRegister {
        return .{ .value = value };
    }

    pub fn set(self: *PalletteRegister, value: u8) bool {
        if (self.value == value)
            return false;

        self.value = value;
        inline for (0..4) |i|
            self.lookup[i] = 0b11 & (value >> i * 2);

        return true;
    }

    pub fn color(self: *PalletteRegister, idx: u4) u8 {
        return self.mem_rgb[self.lookup[idx]];
    }
};

pub fn LCD() type {
    return struct {
        alloc: std.mem.Allocator,

        vram: []u8,
        oam: []u8,
        disable_render: bool,
        lcd_register: LCD_Register = .none,
        stat_register: Stat_Register = Stat_Register.init(1 << 7),
        next_stat_mode: u8 = 2,
        scy: u8 = 0x00,
        scx: u8 = 0x00,
        ly: u8 = 0x00,
        lyc: u8 = 0x00,
        bgp: PalletteRegister = PalletteRegister.init(0xFC),
        obp0: PalletteRegister = PalletteRegister.init(0xFF),
        obp1: PalletteRegister = PalletteRegister.init(0xFF),
        wy: u8 = 0x00,
        wx: u8 = 0x00,

        clock: usize = 0,
        clock_target: usize = 0,
        frame_done: bool = false,
        double_speed: bool = false,

        const Self = @This();

        pub fn init(alloc: std.mem.Allocator, disable_render: bool) !Self {
            //           self.BGP.palette_mem_rgb = [(c << 8) for c in color_palette]
            // self.OBP0.palette_mem_rgb = [(c << 8) for c in color_palette]
            // self.OBP1.palette_mem_rgb = [(c << 8) for c in color_palette]
            //             self.BGP.palette_mem_rgb[0] |= COL0_FLAG
            // self.OBP0.palette_mem_rgb[0] |= COL0_FLAG
            // self.OBP1.palette_mem_rgb[0] |= COL0_FLAG
            return Self{
                .alloc = alloc,
                .vram = try alloc.alloc(u8, VGMem_Size),
                .oam = try alloc.alloc(u8, OAM),
                .disable_render = disable_render,
            };
        }
        pub fn deinit(self: *Self) void {
            self.alloc.free(self.vram);
            self.alloc.free(self.oam);
        }

        pub fn getLCDC(self: *Self) u8 {
            return @as(u8, @intFromEnum(self.lcd_register));
        }

        pub fn setLCDC(self: *Self, value: u8) void {
            _ = self.lcd_register.set(value);
            if (!self.lcd_register.isSet(.lcd_enable)) {
                self.clock = 0;
                self.clock_target = Frame_Cyles;
                _ = self.stat_register.setMode(0);
                self.next_stat_mode = 2;
                self.ly = 0;
            }
        }

        pub fn getStat(self: *Self) u8 {
            return self.stat_register.value;
        }
        pub fn setStat(self: *Self, value: u8) void {
            self.stat_register.set(value);
        }

        pub fn cyclesToInterrupt(self: *Self) u8 {
            return self.clock_target - self.clock;
        }

        pub fn cyclesToMode0(self: *Self) u8 {
            const mult = if (self.double_speed) 2 else 1;
            const mode2 = 80 * mult;
            const mode3 = 170 * mult;
            const mode1 = 456 * mult;

            var mode = self.stat_register.mode;
            const rem = self.clock_target - self.clock;

            mode &= 0b11;
            switch (mode) {
                2 => return rem + mode3,
                3 => return rem,
                0 => return 0,
                1 => {
                    const rem_ly = 153 - self.ly;
                    return rem + mode1 * rem_ly + mode2 + mode3;
                },
                else => unreachable,
            }
        }

        pub fn tick(self: *Self, cycles: usize) void {
            var interrupt_flag: u8 = 0;
            self.clock += cycles;

            if (self.lcd_register.isSet(.lcd_enable)) {
                if (self.clock >= self.clock_target) {
                    interrupt_flag |= self.stat_register.setMode(self.next_stat_mode);
                    const multiplier = if (self.double_speed) 2 else 1;

                    // state machine
                    switch (self.stat_register.mode) {
                        2 => { // OAM
                            if (self.ly == 153) {
                                self.ly = 0;
                                self.clock %= Frame_Cyles;
                                self.clock_target %= Frame_Cyles;
                            } else {
                                self.ly += 1;
                            }

                            self.clock_target += 80 * multiplier;
                            self.next_stat_mode = 3;
                            interrupt_flag |= self.stat_register.updateLYC(self.lyc, self.ly);
                        },
                        3 => {
                            self.clock_target += 170 * multiplier;
                            self.next_stat_mode = 0;
                        },
                        0 => { // HBLANK
                            self.clock_target += 206 * multiplier;

                            // self.renderer.scanLine(self, self.ly);
                            // self.renderer.scanLineSprites(self, self.ly, self.renderer.screenbuffer, false);
                            self.next_stat_mode = if (self.ly < 143) 2 else 1;
                        },
                        1 => { // VBLANK
                            self.clock_target += 456 * multiplier;
                            self.next_stat_mode = 1;
                            self.ly += 1;
                            interrupt_flag |= self.stat_register.updateLYC(self.lyc, self.ly);

                            if (self.ly == 144) {
                                interrupt_flag |= Interrupt.vBlank;
                                self.frame_done = true;
                            }
                            if (self.ly == 153)
                                self.next_stat_mode = 2; // new frame in mode 2
                        },
                    }
                }
            } else {
                if (self.clock >= Frame_Cyles) {
                    self.frame_done = true;
                    self.clock %= Frame_Cyles;

                    self.renderer.blank_screen(self);
                }
            }

            return interrupt_flag;
        }

        pub fn saveState(self: Self, f: std.fs.File) !void {
            for (self.vram) |c|
                try f.write(c);
            for (self.oam) |c|
                try f.write(c);

            try f.write(@as(u8, @intFromEnum(self.lcd_register)));
            try f.write(@as(u8, self.bgp.value));
            try f.write(@as(u8, self.obp0.value));
            try f.write(@as(u8, self.obp1.value));

            try f.write(self.stat_register.value);
            try f.write(self.ly);
            try f.write(self.lyc);
            try f.write(self.scy);
            try f.write(self.scx);
            try f.write(self.wy);
            try f.write(self.wx);
        }

        pub fn loadState(self: Self, f: std.fs.File) !void {
            var reader = f.reader();

            for (0..VGMem_Size) |i|
                self.vram[i] = try reader.readByte();
            for (0..OAM) |i|
                self.oam[i] = try reader.readByte();

            self.setLCDC(try reader.readByte());
            self.bgp.set(try reader.readByte());
            self.obp0.set(try reader.readByte());
            self.obp1.set(try reader.readByte());

            self.scy = try reader.readByte();
            self.scx = try reader.readByte();
            self.wy = try reader.readByte();
            self.wx = try reader.readByte();
        }

        pub const Position: type = .{ u8, u8 };
        pub const ViewPort = Position;
        pub fn getWindowPosition(self: *Self) Position {
            return .{ self.wx - 7, self.wy };
        }
        pub fn getViewPort(self: *Self) ViewPort {
            return .{ self.scx, self.scy };
        }
    };
}
const test_color_palette = .{
    0xFFFFFF,
    0x999999,
    0x555555,
    0x000000,
};
test "LCD - Stat Mode" {
    var lcd = try LCD().init(std.testing.allocator, false);
    defer lcd.deinit();

    lcd.stat_register.mode = 2;
    try std.testing.expectEqual(lcd.stat_register.setMode(2), .none);
    lcd.stat_register.mode = 0;
    try std.testing.expectEqual(lcd.stat_register.setMode(1), .none);

    lcd.stat_register.mode = 0;
    lcd.stat_register.set(1 << (1 + 3));
    try std.testing.expectEqual(lcd.stat_register.setMode(1), .lcdC);
}

test "LCD - Stat register" {
    var lcd = try LCD().init(std.testing.allocator, false);
    defer lcd.deinit();

    lcd.setLCDC(0b1000_0000);
    lcd.stat_register.value &= 0b1111_1000;
    lcd.setStat(0b0111_1111);
    try std.testing.expectEqual(lcd.getStat() & 0b1000_0000, 0x80);
    try std.testing.expectEqual(lcd.getStat() & 0b0000_0111, 0b000);

    try std.testing.expectEqual(lcd.getStat() & 0b11, 0b00);
    _ = lcd.stat_register.setMode(2);
    try std.testing.expectEqual(lcd.getStat() & 0b11, 0b10);
}

test "LCD - LYC" {
    var lcd = try LCD().init(std.testing.allocator, false);
    defer lcd.deinit();

    lcd.lyc = 0;
    lcd.ly = 0;

    try std.testing.expectEqual(lcd.getStat() & 0b100, 0);
    try std.testing.expectEqual(lcd.stat_register.updateLYC(lcd.lyc, lcd.ly), .none);
    try std.testing.expectEqual(lcd.getStat() & 0b100, 0b100);

    lcd.lyc = 0;
    lcd.ly = 1;

    try std.testing.expectEqual(lcd.stat_register.updateLYC(lcd.lyc, lcd.ly), .none);
    try std.testing.expectEqual(lcd.getStat() & 0b100, 0);

    lcd.lyc = 0;
    lcd.ly = 0;
    lcd.setStat(0b0100_0000);
    try std.testing.expectEqual(lcd.getStat() & 0b100, 0);
    try std.testing.expectEqual(lcd.stat_register.updateLYC(lcd.lyc, lcd.ly), .lcdC);
    try std.testing.expectEqual(lcd.stat_register.updateLYC(lcd.lyc, lcd.ly), .lcdC);
    try std.testing.expectEqual(lcd.getStat() & 0b100, 0b100);
}
