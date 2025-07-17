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

/// Software emulator for MOS Technologies 6502 CPU
///
/// It is little endian (least significant byte first in 16bit words)
///
/// References:
///     [1] https://www.masswerk.at/6502/6502_instruction_set.html
///     [2] http://www.obelisk.me.uk/6502/addressing.html
///     [3] https://www.csh.rit.edu/~moffitt/docs/6502.html
///
///     [4] V-flag:  http://www.6502.org/tutorials/vflag.html
///     [5] Decimal mode: http://www.6502.org/tutorials/decimal_mode.html
///     [6] PC: http://6502.org/tutorials/6502opcodes.html#PC
///     [7] http://forum.6502.org/viewtopic.php?t=1708
///
///     [8] Assembler online: https://www.masswerk.at/6502/assembler.html
///     [9] CPU startup sequence:  https://www.pagetable.com/?p=410
///     [10] B-flag: http://wiki.nesdev.com/w/index.php/Status_flags#The_B_flag
///     [11] V-flag: http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html
///     [12] JMP indirect 'bug':  http://forum.6502.org/viewtopic.php?f=2&t=6170
///
///     [13] Undocumented opcodes: http://nesdev.com/undocumented_opcodes.txt
///     [14] Undocumented opcodes: http://www.ffd2.com/fridge/docs/6502-NMOS.extra.opcodes
///
///     [15] Amazing timing data: http://www.6502.org/users/andre/petindex/local/64doc.txt
///
///     [16] Undocumented opcodes: http://hitmen.c02.at/files/docs/c64/NoMoreSecrets-NMOS6510UnintendedOpcodes-20162412.pdf
const MOS6502 = struct {
    memory: MemoryModule,
    instuctions: void,

    registers: struct { a: Byte, x: Byte, y: Byte },

    pc: Address,
    sp: Address,

    flags: packed struct(Byte) {
        n: bool = false,
        v: bool = false,
        d: bool = false,
        i: bool = false,
        z: bool = false,
        c: bool = false,
        _: u2 = 0,
    },
    cycles_since_reset: usize = 0,
    started: false,

    last_pc: Address,
    support_BCD: bool = false,
    aax_sets_flags: bool = false,
    undoc_support_level: usize = 1,
    stack_underflow_causes_exception: bool = true,

    const StatusRegisterMasks = enum(Byte) {
        n = 0b1000_0000, // negative
        v = 0b0100_0000, // overflow
        x = 0b0010_0000, // unused, always 1
        b = 0b0001_0000, // break (indicates brk was excuted. only set on stack copy)
        d = 0b0000_1000, // decimal
        i = 0b0000_0100, // interupt disable
        z = 0b0000_0010, // zero
        c = 0b0000_0001, // carry
    };

    // mem locations
    const StackPage = 0x0100;
    const IRQBRKVectorAddr = 0xFFFE;
    const ResetVectorAddr = 0xFFFC;
    const NMIVectorAddr = 0xFFFA;

    // cycles taken to do the NMI or IRQ interrupt - (this is a guess, based on BRK, couldn't find a ref for this!)
    const InteruptRequestCyles = 7;
    const OAMDMACPUCycles = 513;

    pub fn reset() void {}
    pub fn set_reset_vector() void {}
    pub fn trigger() void {}
    pub fn run_next() void {}
    pub fn stack_push() void {}
    pub fn stack_pop() void {}
};
const Cart = struct {
    ptr: *anyopaque,
    vtab: struct {
        read_ppu: ?*const fn (*anyopaque, Address) Byte = null,
        write_ppu: ?*const fn (*anyopaque, Address, Byte) void = null,
    },

    const NES0 = struct {
        // cpu
        const RamStart = 0x6000;
        const PrgRamStart = 0x8000;

        const ChrRomStart = 0x0000; // ppu

        pub fn init(rom_data: []const Byte, chr_rom_data: []const u8, ram_size_kb: usize, prog_start_addr: Address, mirror: MirrorPattern) !NES0 {
            _ = rom_data; // autofix
            _ = chr_rom_data; // autofix
            _ = ram_size_kb; // autofix
            _ = prog_start_addr; // autofix
            _ = mirror; // autofix
        }
        pub fn cartridge(self: *NES0) Cart {
            return .{
                .ptr = self,
                .vtab = .{
                    .read_ppu = read_ppu,
                    .write_ppu = write_ppu,
                },
            };
        }
        pub fn read(self: NES0) Byte {
            _ = self; // autofix
        }
        pub fn write(self: *NES0, value: Byte) void {
            _ = self; // autofix
            _ = value; // autofix
        }
        fn read_ppu(ptr: *anyopaque, addr: Address) Byte {
            _ = ptr; // autofix
            _ = addr; // autofix
        }
        fn write_ppu(ptr: *anyopaque, addr: Address, value: Byte) void {
            _ = ptr; // autofix
            _ = addr; // autofix
            _ = value; // autofix
        }
    };
};

pub const PPU = struct {
    pub fn write_oam(self: *PPU) void {
        _ = self; // autofix
    }
    pub fn ppu_status(self: *PPU) void {
        _ = self; // autofix
    }
    pub fn read_register(self: *PPU) void {
        _ = self; // autofix
    }
    pub fn write_register(self: *PPU) void {
        _ = self; // autofix
    }
    pub fn run_cycles(self: *PPU) void {
        _ = self; // autofix
    }
    pub fn fill_bkg_latches(self: *PPU) void {
        _ = self; // autofix
    }
    pub fn shift_bkg_latches(self: *PPU) void {
        _ = self; // autofix
    }
    pub fn decode_pallet(self: *PPU) void {
        _ = self; // autofix
    }
    fn new_frame(self: *PPU) void {
        _ = self; // autofix
    }
};

pub const InteruptListener = struct {
    nmi: bool = false,
    irq: bool = false, // the actual IRQ line on the 6502 rests high and is low-triggered
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

const MirrorPattern = [4]u2;

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
    const Horizontal: MirrorPattern = &.{ 0, 0, 1, 1 };
    const Vertical: MirrorPattern = &.{ 0, 1, 0, 1 };
    const Single: MirrorPattern = &.{ 0, 0, 0, 0 };
    const FourScreen: MirrorPattern = &.{ 0, 1, 2, 3 };
    const Diagonal: MirrorPattern = &.{ 0, 1, 1, 0 };
    const LShaped: MirrorPattern = &.{ 0, 1, 1, 1 };
    const @"3ScreenV": MirrorPattern = &.{ 0, 2, 1, 2 };
    const @"3ScreenH": MirrorPattern = &.{ 0, 1, 2, 2 };
    const @"3ScreenDiag": MirrorPattern = &.{ 0, 1, 1, 2 };

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
