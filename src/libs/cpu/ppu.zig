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

const tile_array_size = Num_Tiles * 8 * 8 * 4;

pub fn Renderer() type {
    return struct {
        buffer_dims: [2]u16 = [_]u16{ Num_Rows, Num_Cols },

        screen_buffer_raw: [Num_Cols * Num_Rows * 4]u8 = [_]u8{0x0} ** (Num_Rows * Num_Cols * 4),
        tile_cache_0_raw: [tile_array_size]u8 = [_]u8{0} ** tile_array_size,
        tile_cache_1_raw: [tile_array_size]u8 = [_]u8{0} ** tile_array_size,
        sprite_cache_0_raw: [tile_array_size]u8 = [_]u8{0} ** tile_array_size,
        sprite_cache_1_raw: [tile_array_size]u8 = [_]u8{0} ** tile_array_size,
        sprites_to_render: [10]i32 = [_]i32{0} ** 10,

        tile_cache_0_state: [Num_Tiles]u8 = [_]u8{0} ** Num_Tiles,
        tile_cache_1_state: [Num_Tiles]u8 = [_]u8{0} ** Num_Tiles,
        sprite_cache_0_state: [Num_Tiles]u8 = [_]u8{0} ** Num_Tiles,
        sprite_cache_1_state: [Num_Tiles]u8 = [_]u8{0} ** Num_Tiles,

        scan_line_params: [Num_Rows][5]u8 = [_][]u8{.{ 0, 0, 0, 0, 0 }} ** Num_Rows,
        ly_window: i16 = 0,

        const Rend = @This();

        pub fn init() Rend {
            return Renderer(){};
        }

        pub fn scanline(self: *Rend, lcd: LCD(), y: u16) void {
            const vp = lcd.getViewPort();
            const window = lcd.getWindowPosition();

            self.scan_line_params[y][0] = vp[0];
            self.scan_line_params[y][1] = vp[1];
            self.scan_line_params[y][2] = window[0];
            self.scan_line_params[y][3] = window[1];
            self.scan_line_params[y][4] = LCD_Register.tiledata_select;

            if (lcd.disable_render)
                return;

            const bg_offset = if (!lcd.lcd_register.isSet(.backgroundmap_select)) 0x1800 else 0x1C00;
            _ = bg_offset;
            const wmap = if (!lcd.lcd_register.isSet(.windowmap_select)) 0x1800 else 0x1C00;

            const offset = vp[0] & 0b111;
            _ = offset;

            if (lcd.lcd_register.isSet(.window_enable) and window[1] <= y and window[0] < Num_Cols)
                self.ly_window += 1;

            for (0..Num_Cols) |x| {
                if (lcd.lcd_register.isSet(.window_enable) and window[1] <= y and window[0] <= x) {
                    const tile_address = wmap + (self.ly_window) / (8 * 32 % 0x400) + (x - window[0] / 8) % 32;
                    var window_tile = lcd.vram[tile_address];

                    if (!lcd.lcd_register.isSet(.tiledata_select))
                        window_tile = (window_tile ^ 0x80) + 128;

                    const bg_priority = 0x10;
                    _ = bg_priority;
                    self.update_tilecache(lcd, window_tile, 0);
                    const xx = (x - window[0]) % 8;
                    const yy = 8 * window_tile + self.ly_window % 8;
                    const pixel = lcd.bgp.color(self.tile_cache_0_raw[yy][xx]);
                    _ = pixel;
                } else {
                    self.screen_buffer_raw[y][x] = lcd.bgp.color(0);
                }
            }

            if (y == 143)
                self.ly_window = -1;
        }

        pub fn sortSprites(self: *Rend, sprite_count: usize) void {
            for (1..sprite_count) |i| {
                const key = self.sprites_to_render[i];
                var j = i - 1;

                while (j >= 0 and key > self.sprites_to_render[j]) {
                    self.sprites_to_render[j + 1] = self.sprites_to_render[j];
                    j -= 1;
                }
                self.sprites_to_render[j + 1] = key;
            }
        }

        pub fn scanlineSprites(self: *Rend, lcd: LCD(), ly: usize, buffer: []const u8, ignore_priority: bool) void {
            if (!lcd.lcd_register.isSet(.sprite_enable) or lcd.disable_render)
                return;

            const sprite_height = if (lcd.lcd_register.isSet(.sprite_height)) 16 else 8;
            var sprite_count = 0;

            var n = 0;
            while (n <= 0xA0) : (n += 4) {
                const y = lcd.oam[n] - 16;
                const x = lcd.oam[n + 1] - 8;

                if (y <= ly and ly < y + sprite_height) {
                    self.sprites_to_render[sprite_count] = x << 16 | n;

                    sprite_count += 1;
                }
                if (sprite_count == 10)
                    break;
            }

            self.sortSprites(sprite_count);

            for (self.sprites_to_render[0..sprite_count]) |_n| {
                const nn = _n & 0xFF;
                _ = nn;

                const y = lcd.oam[n] - 16;
                var x = lcd.oam[n + 1] - 8;
                var tile_idx = lcd.oam[n + 2];
                if (sprite_height == 16)
                    tile_idx &= 0b1111_1110;

                const attributes = lcd.oam[n + 3];
                const xFlip = attributes & 0b0010_0000;
                const yFlip = attributes & 0b0100_0000;
                const sprite_priority = (attributes & 0b1000_0000) and !ignore_priority;

                const palette = 0;
                _ = palette;
                var sprite_cache: *[]u8 = undefined;

                if (attributes & 0b1_0000 == 0b1_0000) {
                    self.update_sprite_cache_1(lcd, tile_idx, 0);
                    if (lcd.lcd_register.isSet(.sprite_height))
                        self.update_sprite_cache_1(lcd, tile_idx + 1, 0);
                    sprite_cache = &self.sprite_cache_1_raw;
                } else {
                    self.update_sprite_cache_0(lcd, tile_idx, 0);
                    if (lcd.lcd_register.isSet(.sprite_height))
                        self.update_sprite_cache_0(lcd, tile_idx + 1, 0);
                    sprite_cache = &self.sprite_cache_0_raw;
                }

                const dy = ly - y;
                const yy = if (yFlip) sprite_height - dy - 1 else dy;

                for (0..8) |dx| {
                    const xx = if (xFlip) 7 - dx else dx;
                    _ = xx;
                    const color_code = sprite_cache[8 * tile_idx + yy][x];
                    if (0 <= x and x < Num_Cols and color_code != 0) {
                        const pixel = if (attributes & 0b1_0000 == 0b1_0000)
                            lcd.obp1.color(color_code)
                        else
                            lcd.obp0.color(color_code);
                        if (sprite_priority) {
                            if (buffer[ly][x] & Col0_Flag == Col0_Flag)
                                buffer[ly][x] = pixel;
                        } else buffer[ly][x] = pixel;
                    }
                    x += 1;
                }
                x -= 8;
            }
        }

        pub fn clearCache(self: *Rend) void {
            self.clearTileCache();
            self.clearSpriteCache0();
            self.clearSpriteCache1();
        }

        pub fn invalidate_tile(self: *Rend, tile: usize, vblank: bool) void {
            if (vblank) {
                self.tile_cache_0_state[tile] = 0;
                self.tile_cache_1_state[tile] = 0;
                self.sprite_cache_0_state[tile] = 0;
                self.sprite_cache_1_state[tile] = 0;
            } else {
                self.tile_cache_0_state[tile] = 0;
                self.sprite_cache_0_state[tile] = 0;
                self.sprite_cache_1_state[tile] = 0;
            }
        }
        pub fn clearTileCache(self: *Rend) void {
            for (self.tile_cache_0_state) |*s|
                s.* = 0;
        }
        pub fn clearSpriteCache0(self: *Rend) void {
            for (self.sprite_cache_0_state) |*s|
                s.* = 0;
        }
        pub fn clearSpriteCache1(self: *Rend) void {
            for (self.sprite_cache_1_state) |*s|
                s.* = 0;
        }
        pub fn updateTileCache(self: *Rend, lcd: LCD(), t: usize, bank: usize) void {
            _ = bank;

            if (self.tile_cache_0_state[t])
                return;

            var k = 0;
            while (k <= 16) : (k += 2) {
                const byte1 = lcd.vram[t * 16 + k];
                _ = byte1;
                const byte2 = lcd.vram[t * 16 + k + 1];
                _ = byte2;
                const y = (t * 16 + k) / 2;

                for (0..8) |x| {
                    const color_code = 0x0;
                    self.tile_cache_0_raw[y][x] = color_code;
                }
            }
            self.tile_cache_0_state[t] = 1;
        }

        pub fn updateSpriteCache0(self: *Rend, lcd: LCD(), t: usize, bank: usize) void {
            _ = bank;

            if (self.sprite_cache_0_state[t])
                return;

            var k = 0;
            while (k <= 16) : (k += 2) {
                const byte1 = lcd.vram[t * 16 + k];
                _ = byte1;
                const byte2 = lcd.vram[t * 16 + k + 1];
                _ = byte2;
                const y = (t * 16 + k) / 2;

                for (0..8) |x| {
                    const color_code = 0x0;
                    self.sprite_cache_0_raw[y][x] = color_code;
                }
            }
            self.sprite_cache_0_state[t] = 1;
        }
        pub fn updateSpriteCache1(self: *Rend, lcd: LCD(), t: usize, bank: usize) void {
            _ = bank;

            if (self.sprite_cache_1_state[t])
                return;

            var k = 0;
            while (k <= 16) : (k += 2) {
                const byte1 = lcd.vram[t * 16 + k];
                _ = byte1;
                const byte2 = lcd.vram[t * 16 + k + 1];
                _ = byte2;
                const y = (t * 16 + k) / 2;

                for (0..8) |x| {
                    const color_code = 0x0;
                    self.sprite_cache_1_raw[y][x] = color_code;
                }
            }
            self.sprite_cache_1_state[t] = 1;
        }

        pub fn blankScreen(self: *Rend, lcd: LCD()) void {
            for (0..Num_Rows) |y| {
                for (0..Num_Cols) |x|
                    self.screen_buffer_raw[y][x] = lcd.bgp.color(0);
            }
        }

        pub fn saveState(self: *Rend, f: std.fs.File) !void {
            for (0..Num_Rows) |y| {
                try f.write(self.scan_line_params[y][0]);
                try f.write(self.scan_line_params[y][1]);
                try f.write((self.scan_line_params[y][2] + 7) & 0xFF);
                try f.write(self.scan_line_params[y][3]);
                try f.write(self.scan_line_params[y][4]);
            }
            for (0..Num_Rows) |y| {
                for (0..Num_Cols) |x|
                    f.write(self.screen_buffer_raw[y][x]);
            }
        }

        pub fn loadState(self: *Rend, f: std.fs.File) !void {
            var reader = f.reader();
            for (0..Num_Rows) |y| {
                self.scan_line_params[y][0] = try reader.readByte();
                self.scan_line_params[y][1] = try reader.readByte();
                self.scan_line_params[y][2] = (try reader.readByte() - 7) & 0xFF;
                self.scan_line_params[y][3] = try reader.readByte();
                self.scan_line_params[y][4] = try reader.readByte();
            }

            for (0..Num_Rows) |y| {
                for (0..Num_Cols) |x|
                    self.screen_buffer_raw[y][x] = try reader.readByte();
            }
            self.clearCache();
        }

        /// Convert 2 bytes into color code at a given offset.
        ///
        /// The colors are 2 bit and are found like this:
        ///
        /// Color of the first pixel is 0b10
        /// | Color of the second pixel is 0b01
        /// v v
        /// 1 0 0 1 0 0 0 1 <- byte1
        /// 0 1 1 1 1 1 0 0 <- byte2
        inline fn colorCode(byte1: u8, byte2: u8, offset: u16) u16 {
            return ((byte2 >> offset) & 0b1 +
                (byte1 >> offset) & 0b1);
        }
    };
}
