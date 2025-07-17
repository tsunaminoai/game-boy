const std = @import("std");
const Array = std.ArrayList;
const Allocator = std.mem.Allocator;
const tst = std.testing;
const math = std.math;

const Byte = u8;
const Word = u16;
const Address = Word;

const Width = 256;
const Height = 240;

const CPUHz = 1_789_773;
const VBlank = enum(usize) {
    start = 240,
    nmi = 241,
    end = 261,
    vreturn = 262,
};
const MemoryModule = struct {
    ptr: *anyopaque,
    vtab: struct {
        read: ?*const fn (*anyopaque, Address) Byte = null,
        write: ?*const fn (*anyopaque, Address, Byte) void = null,
        read_block: ?*const fn (*anyopaque, Address, usize) []const Byte = null,
    },
    pub fn read(self: MemoryModule, addr: Address) Byte {
        return if (self.vtab.read) |f| f(self.ptr, addr) else unreachable;
    }
    pub fn write(self: MemoryModule, addr: Address, value: Byte) void {
        return if (self.vtab.write) |f| f(self.ptr, addr, value) else unreachable;
    }
    pub fn read_block(self: MemoryModule, addr: Address, size: usize) []const Byte {
        return if (self.vtab.read_block) |f| f(self.ptr, addr, size) else unreachable;
    }
    pub fn init(comptime T: anytype) MemoryModule {
        var t: T = .{};
        return .{
            .ptr = &t,
            .vtab = .{
                .read = T.read,
                .write = T.write,
                .read_block = T.read_block,
            },
        };
    }
    pub fn dump(self: MemoryModule, start: Address, count: usize) void {
        const width = 10;
        for (0..count) |i| {
            if (@mod(i, width) == 0) {
                if (i > 0) {
                    std.debug.print("\n", .{});
                }
                std.debug.print("${X:0>4}:\t", .{start + i});
            }
            std.debug.print("{X:0>2} ", .{self.read(start + @as(u16, @intCast(i)))});
        }
        std.debug.print("\n", .{});
    }
};
const EmptyRam = struct {
    ram: [0x10000]u8 = [_]u8{0} ** 0x10000,

    pub fn init() EmptyRam {
        return .{};
    }
    pub fn mem(self: *EmptyRam) MemoryModule {
        return .{
            .ptr = self,
            .vtab = .{
                .read = EmptyRam.read,
                .write = EmptyRam.write,
            },
        };
    }
    fn read_block(ptr: *anyopaque, addr: Address, size: usize) []const Byte {
        const self: *EmptyRam = @alignCast(@ptrCast(ptr));
        return self.ram[addr .. addr + size];
    }
    fn read(ptr: *anyopaque, addr: Address) Byte {
        const self: *EmptyRam = @alignCast(@ptrCast(ptr));
        return self.ram[addr];
    }
    fn write(ptr: *anyopaque, addr: Address, value: Byte) void {
        const self: *EmptyRam = @alignCast(@ptrCast(ptr));
        self.ram[addr] = value;
    }
};
const Controller = struct {
    pub fn read_bit(self: Controller) Byte {
        _ = self; // autofix
        return 0;
    }
    pub fn set_strobe(self: *Controller, value: Byte) void {
        _ = self; // autofix
        _ = value; // autofix
    }
};
pub const InteruptListener = struct {
    nmi: bool = false,
    irq: bool = false,
    oam_dma_pause: bool = false,

    pub fn raise(self: *InteruptListener, comptime name: []const u8) void {
        @field(self.*, name) = true;
    }
    pub fn active(self: *InteruptListener, comptime name: []const u8) bool {
        return @field(self.*, name);
    }
    pub fn anyActive(self: InteruptListener) bool {
        return self.nmi or self.irq or self.oam_dma_pause;
    }
};
test {
    var il = InteruptListener{};
    il.raise("nmi");
    try tst.expect(il.nmi);
}
/// https://wiki.nesdev.com/w/index.php/CPU_memory_map
const NESMappedRam = struct {
    const RamSize = 0x800; // 2kB of internal RAM
    const NumPPURegisters = 8; // number of ppu registers
    const RamEnd = 0x0800; // NES main ram to here
    const PPUEnd = 0x4000; // PPU registers to here
    const APUEnd = 0x4018; // APU registers (+OAM DMA reg) to here
    const APUUnusedEnd = 0x4020; // generally unused APU and I/O functionality
    const OAMDMA = 0x0414; // OAM DMA register address
    const Controller1 = 0x4016; // port for controller (read controller 1 / write both controllers)
    const Controller2 = 0x4017; // port for controller 2 (read only, writes to this port go to the APU)
    const CartStart = 0x4020; // start of cartridge address space
    const OAMSize = 256;
    ram: [RamSize]u8 = [_]u8{0} ** RamSize,
    apu: void = {},
    ppu: struct {
        pub fn read_register(_: @This(), _: anytype) Byte {
            return 0;
        }
        pub fn write_register(_: @This(), _: anytype, _: anytype) void {}
        pub fn write_oam(_: @This(), _: anytype) void {}
    } = .{},
    cart: struct {
        pub fn read(_: @This(), _: anytype) Byte {
            return 0;
        }
        pub fn write(_: @This(), _: anytype, _: anytype) void {}
    } = .{},
    cont1: Controller = .{},
    cont2: Controller = .{},
    intrListener: InteruptListener = .{},

    last_bus: void = {},

    pub fn mem(self: *NESMappedRam) MemoryModule {
        return .{
            .ptr = self,
            .vtab = .{
                .read = NESMappedRam.read,
                .write = NESMappedRam.write,
            },
        };
    }
    /// Read one byte of memory from the NES address space
    fn read(ptr: *anyopaque, addr: Address) Byte {
        const self: *NESMappedRam = @alignCast(@ptrCast(ptr));
        var value: Byte = 0;
        if (addr < RamEnd)
            value = self.ram[@mod(addr, RamSize)]
        else if (addr < PPUEnd) {
            value = self.ppu.read_register(@mod(addr, NumPPURegisters));
        } else if (addr < APUEnd) {
            value = if (addr == OAMDMA)
                0 //write only
            else if (addr == Controller1)
                (self.cont1.read_bit() & 0b0001_1111) + (0x40 & 0b1110_0000)
            else if (addr == Controller2)
                (self.cont2.read_bit() & 0b0001_1111) + (0x40 & 0b1110_0000)
            else
                0; // APU registers
        } else value = self.cart.read(addr);
        return value;
    }
    fn write(ptr: *anyopaque, addr: Address, value: Byte) void {
        const self: *NESMappedRam = @alignCast(@ptrCast(ptr));
        if (addr < RamEnd)
            self.ram[@mod(addr, RamSize)] = value
        else if (addr < PPUEnd) {
            self.ppu.write_register(@mod(addr, NumPPURegisters), value);
        } else if (addr < APUEnd) {
            if (addr == OAMDMA)
                self.runOAMDMA(value)
            else if (addr == Controller1) {
                self.cont1.set_strobe(value);
                self.cont1.set_strobe(value);
            } else return; // APU registers
        } else self.cart.write(addr, value);
    }
    fn read_block(ptr: *anyopaque, addr: Address, size: usize) []const Byte {
        const self: *NESMappedRam = @alignCast(@ptrCast(ptr));
        return self.ram[addr .. addr + size];
    }
    fn runOAMDMA(self: *NESMappedRam, page: u16) void {
        var block: [256]u8 = undefined;
        const PPUAddr = 0;
        const m = self.mem();
        @memcpy(block[PPUAddr..OAMSize], m.read_block(page << 8, OAMSize - PPUAddr));
        @memcpy(block[0..PPUAddr], m.read_block(page << 8, OAMSize));

        self.ppu.write_oam(block);
        // tell the interrupt listener that the CPU should pause due to OAM DMA
        self.intrListener.raise("oam_dma_pause");
    }
};
/// NES video (PPU) RAM, following the PPU memory map pattern
/// map: https://wiki.nesdev.com/w/index.php/PPU_memory_map
const NESVRAM = struct {
    const PatternTableSizeBytes = 4096; //   # provided by the rom
    const NametablesSizeBytes = 2048; //
    const PaletteSizeBytes = 32; //
    const NametableLengthBytes = 1024; //  # single nametime is this big

    // memory map
    const NametableStart = 0x2000; //
    const AttributeTableOffset = 0x3C0; //  # offset of the attribute table from the start of the corresponding nametable
    const PaletteStart = 0x3F00; //

    // Mirror patterns
    // The mirror pattern specifies the underlying nametable at locations 0x2000, 0x2400, 0x2800 and 0x3200
    const MirrorHorizontal = .{ 0, 0, 1, 1 };
    const MirrorVertical = .{ 0, 1, 0, 1 };
    const MirrorSingle = .{ 0, 0, 0, 0 };
    const MirrorFourScreen = .{ 0, 1, 2, 3 };
    const MirrorDiagonal = .{ 0, 1, 1, 0 };
    const MirrorLShaped = .{ 0, 1, 1, 1 };
    const Mirror3ScreenV = .{ 0, 2, 1, 2 };
    const Mirror3ScreenH = .{ 0, 1, 2, 2 };
    const Mirror3ScreenDiag = .{ 0, 1, 1, 2 };

    pallet_ram: [PaletteSizeBytes]Byte = [_]Byte{0} ** PaletteSizeBytes,
    nametables: [NametablesSizeBytes]Byte = [_]Byte{0} ** NametablesSizeBytes,
    pattern_table: [PatternTableSizeBytes]Byte = [_]Byte{0} ** PatternTableSizeBytes,

    pub fn init() NESVRAM {
        return .{};
    }
    fn decode_address(self: NESVRAM, addr: Address) struct { []const Byte, Address } {
        if (addr < NametableStart) {
            return .{ &.{}, 0x0 }; //todo: cart
        } else if (addr < PaletteStart) {
            const page = @divFloor((addr - NametableStart), NametableLengthBytes);
            const offset = @mod((addr - NametableStart), NametableLengthBytes);

            // const true_page; TODO mirror pattern

            return .{ &self.nametables, page * NametableLengthBytes + offset };
        } else {
            // "addresses $3F10/$3F14/$3F18/$3F1C are mirrors of $3F00/$3F04/$3F08/$3F0C"
            // (https://wiki.nesdev.com/w/index.php/PPU_palettes)
            if (addr == 0x3F10 or addr == 0x3F14 or addr == 0x3F18 or addr == 0x3F1C)
                return .{ &self.pallet_ram, @mod(addr - 0x10, PaletteSizeBytes) }
            else
                return .{ &self.pallet_ram, @mod(addr, PaletteSizeBytes) };
        }
    }
    fn read(ptr: *anyopaque, addr: Address) Byte {
        const self: *NESVRAM = @alignCast(@ptrCast(ptr));
        const dc = self.decode_address(addr);
        const m = dc[0];
        const a = dc[1];
        return m[a];
    }
    fn write(ptr: *anyopaque, addr: Address, value: Byte) void {
        _ = value; // autofix
        const self: *NESVRAM = @alignCast(@ptrCast(ptr));
        const dc = self.decode_address(addr);
        const m = dc[0];
        _ = m; // autofix
        const a = dc[1];
        _ = a; // autofix
        // m[a] = value;
    }
    fn read_block(_: *anyopaque, _: Address, _: usize) []const Byte {
        return &.{};
    }
};
test {
    var mem = MemoryModule.init(NESVRAM);
    mem.write(0x0, 1);
    // try tst.expectEqual(1, mem.read(0x0));
}
test {
    var mem = MemoryModule.init(EmptyRam);
    mem.write(0x0, 1);
    try tst.expectEqual(1, mem.read(0x0));
}

test {
    var mem = MemoryModule.init(NESMappedRam);
    mem.write(0x0, 1);
    try tst.expectEqual(1, mem.read(0x0));
}

pub const NES = struct {
    const PPUCyclesPerCpuCycle = 3;
    const FrameRateFPS = 240;

    rom: struct {} = .{},
    cont1: struct {} = .{},
    cont2: struct {} = .{},
    cart: struct {} = .{},
    ppu: struct {} = .{},
    screen: struct {} = .{},
    scale: struct {} = .{},
    memory: struct {} = .{},
    cpu: struct {} = .{},
    interupts: InteruptListener = .{},

    pub fn init() NES {}

    pub fn load(self: *NES) !void {
        _ = self; // autofix
    }
    pub fn save(self: *NES) !void {
        _ = self; // autofix
    }
    pub fn step(self: *NES) !void {
        _ = self; // autofix
    }
    pub fn run(self: *NES) !void {
        _ = self; // autofix
    }
};
