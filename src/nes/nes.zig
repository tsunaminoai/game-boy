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

const MOS6502Hz = 1_789_773;
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

/// Software emulator for MOS Technologies 6502 MOS6502
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
///     [9] MOS6502 startup sequence:  https://www.pagetable.com/?p=410
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
    // instuctions: void,

    registers: struct { a: Byte = 0, x: Byte = 0, y: Byte = 0 } = .{},

    pc: Address = 0,
    sp: Address = 0,

    flags: packed struct(Byte) {
        n: bool = false,
        v: bool = false,
        d: bool = false,
        i: bool = false,
        z: bool = false,
        c: bool = false,
        _: u2 = 0,
    } = .{},
    cycles_since_reset: usize = 0,
    started: bool = false,

    last_pc: Address = 0,
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
    const OAMDMAMOS6502Cycles = 513;

    pub fn reset() void {}
    pub fn set_reset_vector() void {}
    pub fn trigger() void {}
    pub fn run_next() void {}
    pub fn stack_push() void {}
    pub fn stack_pop() void {}

    const instructions = BYTECODE_DICT;

    const byte_codes = std.StaticStringMap(*const fn (*MOS6502) void).initComptime(.{
        .{ "adc", &MOS6502._adc },
        .{ "and", &MOS6502._and },
        .{ "asl", &MOS6502._asl },
        .{ "bcc", &MOS6502._bcc },
        .{ "bcs", &MOS6502._bcs },
        .{ "beq", &MOS6502._beq },
        .{ "bit", &MOS6502._bit },
        .{ "bmi", &MOS6502._bmi },
        .{ "bne", &MOS6502._bne },
        .{ "bpl", &MOS6502._bpl },
        .{ "sty", &MOS6502._sty },
        .{ "tax", &MOS6502._tax },
        .{ "tay", &MOS6502._tay },
        .{ "tsx", &MOS6502._tsx },
        .{ "txa", &MOS6502._txa },
        .{ "txs", &MOS6502._txs },
        .{ "tya", &MOS6502._tya },
        .{ "dop", &MOS6502._dop },
        .{ "top", &MOS6502._top },
        .{ "kil", &MOS6502._kil },
        .{ "lax", &MOS6502._lax },
        .{ "aax", &MOS6502._aax },
        .{ "dcp", &MOS6502._dcp },
        .{ "isc", &MOS6502._isc },
        .{ "slo", &MOS6502._slo },
        .{ "rla", &MOS6502._rla },
        .{ "sre", &MOS6502._sre },
        .{ "rra", &MOS6502._rra },
        .{ "arr", &MOS6502._arr },
        .{ "asr", &MOS6502._asr },
        .{ "atx", &MOS6502._atx },
        .{ "aac", &MOS6502._aac },
        .{ "axa", &MOS6502._axa },
        .{ "axs", &MOS6502._axs },
        .{ "lar", &MOS6502._lar },
        .{ "sxa", &MOS6502._sxa },
        .{ "sya", &MOS6502._sya },
        .{ "xaa", &MOS6502._xaa },
        .{ "xas", &MOS6502._xas },
    });

    // Helper function to get function pointer for an instruction
    fn get_instruction_function(name: []const u8) *const fn (*MOS6502) void {
        return byte_codes.FUNCTION_LOOKUP.get(name) orelse &MOS6502._nop;
    }

    // Usage functions
    pub fn get_instruction_by_bytecode(bytecode: Byte) ?NamedInstruction {
        return BYTECODE_DICT[bytecode];
    }

    pub fn execute_instruction(cpu: *MOS6502, bytecode: Byte) void {
        if (get_instruction_by_bytecode(bytecode)) |instr| {
            const func = get_instruction_function(instr.name);
            func(cpu);
        }
    }
    // All instruction implementation functions
    fn _adc(self: *MOS6502) void {
        _ = self;
    }
    fn _and(self: *MOS6502) void {
        _ = self;
    }
    fn _asl(self: *MOS6502) void {
        _ = self;
    }
    fn _bcc(self: *MOS6502) void {
        _ = self;
    }
    fn _bcs(self: *MOS6502) void {
        _ = self;
    }
    fn _beq(self: *MOS6502) void {
        _ = self;
    }
    fn _bit(self: *MOS6502) void {
        _ = self;
    }
    fn _bmi(self: *MOS6502) void {
        _ = self;
    }
    fn _bne(self: *MOS6502) void {
        _ = self;
    }
    fn _bpl(self: *MOS6502) void {
        _ = self;
    }
    fn _sty(self: *MOS6502) void {
        _ = self;
    }
    fn _tax(self: *MOS6502) void {
        _ = self;
    }
    fn _tay(self: *MOS6502) void {
        _ = self;
    }
    fn _tsx(self: *MOS6502) void {
        _ = self;
    }
    fn _txa(self: *MOS6502) void {
        _ = self;
    }
    fn _txs(self: *MOS6502) void {
        _ = self;
    }
    fn _tya(self: *MOS6502) void {
        _ = self;
    }
    fn _dop(self: *MOS6502) void {
        _ = self;
    }
    fn _top(self: *MOS6502) void {
        _ = self;
    }
    fn _kil(self: *MOS6502) void {
        _ = self;
    }
    fn _lax(self: *MOS6502) void {
        _ = self;
    }
    fn _aax(self: *MOS6502) void {
        _ = self;
    }
    fn _dcp(self: *MOS6502) void {
        _ = self;
    }
    fn _isc(self: *MOS6502) void {
        _ = self;
    }
    fn _slo(self: *MOS6502) void {
        _ = self;
    }
    fn _rla(self: *MOS6502) void {
        _ = self;
    }
    fn _sre(self: *MOS6502) void {
        _ = self;
    }
    fn _rra(self: *MOS6502) void {
        _ = self;
    }
    fn _arr(self: *MOS6502) void {
        _ = self;
    }
    fn _asr(self: *MOS6502) void {
        _ = self;
    }
    fn _atx(self: *MOS6502) void {
        _ = self;
    }
    fn _aac(self: *MOS6502) void {
        _ = self;
    }
    fn _axa(self: *MOS6502) void {
        _ = self;
    }
    fn _axs(self: *MOS6502) void {
        _ = self;
    }
    fn _lar(self: *MOS6502) void {
        _ = self;
    }
    fn _sxa(self: *MOS6502) void {
        _ = self;
    }
    fn _sya(self: *MOS6502) void {
        _ = self;
    }
    fn _xaa(self: *MOS6502) void {
        _ = self;
    }
    fn _xas(self: *MOS6502) void {
        _ = self;
    }
    fn _nop(self: *MOS6502) void {
        _ = self;
    }
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
/// https://wiki.nesdev.com/w/index.php/MOS6502_memory_map
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
        // tell the interrupt listener that the MOS6502 should pause due to OAM DMA
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

const AddressMode = enum(Byte) {
    immediate = 0,
    zeropage = 1,
    zeropage_x = 2,
    zeropage_y = 20,
    absolute = 3,
    absolute_x = 4,
    absolute_y = 5,
    indirect_x = 6,
    indirect_y = 7,
    implied = 10,
    relative = 11,
    accumulator = 12,
    indirect = 13,
};

// Handle fractional cycles by storing as tenths of cycles
const Instruction = struct {
    bytecode: union(enum) {
        single: Byte,
        multiple: []const Byte,
    },
    size_bytes: usize,
    cycles_tenths: u16, // Store cycles * 10 to handle fractional values
    name: []const u8 = "Unlabeled",

    pub fn init_single(bytecode: Byte, size_bytes: usize, cycles: f32) Instruction {
        return Instruction{
            .bytecode = .{ .single = bytecode },
            .size_bytes = size_bytes,
            .cycles_tenths = @intFromFloat(cycles * 10),
        };
    }

    pub fn init_multiple(bytecodes: []const Byte, size_bytes: usize, cycles: f32) Instruction {
        return Instruction{
            .bytecode = .{ .multiple = bytecodes },
            .size_bytes = size_bytes,
            .cycles_tenths = @intFromFloat(cycles * 10),
        };
    }

    pub fn get_cycles(self: Instruction) f32 {
        return @as(f32, @floatFromInt(self.cycles_tenths)) / 10.0;
    }
};

const InstructionSet = struct {
    name: []const u8,
    modes: std.EnumMap(AddressMode, ?Instruction),

    pub fn init(name: []const u8) InstructionSet {
        return InstructionSet{
            .name = name,
            .modes = std.EnumMap(AddressMode, ?Instruction).init(.{}),
        };
    }

    pub fn add_mode(self: *InstructionSet, mode: AddressMode, instruction: Instruction) void {
        self.modes.put(mode, instruction);
    }
};

// Helper function to create instruction sets
fn create_instruction_set(name: []const u8, modes: anytype) InstructionSet {
    @setEvalBranchQuota(100_000);

    var instruction_set = InstructionSet.init(name);

    inline for (std.meta.fields(@TypeOf(modes))) |field| {
        const mode = std.meta.stringToEnum(AddressMode, field.name) orelse continue;
        const mode_data = @field(modes, field.name);
        instruction_set.add_mode(mode, mode_data);
    }

    return instruction_set;
}

// Static arrays for multiple bytecode instructions
const DopZeropageBytecodes = [_]Byte{ 0x04, 0x14, 0x44, 0x64 };
const DopZeropageXBytecodes = [_]Byte{ 0x14, 0x34, 0x54, 0x74, 0xD4, 0xF4 };
const DopImmediateBytecodes = [_]Byte{ 0x80, 0x82, 0x89, 0xC2, 0xE2 };
const TopAbsoluteXBytecodes = [_]Byte{ 0x1C, 0x3C, 0x5C, 0x7C, 0xDC, 0xFC };
const KilImpliedBytecodes = [_]Byte{ 0x02, 0x12, 0x22, 0x32, 0x42, 0x52, 0x62, 0x72, 0x92, 0xB2, 0xD2, 0xF2 };
const AacImmediateBytecodes = [_]Byte{ 0x0B, 0x2B };
const NamedInstruction = struct {
    name: []const u8,
    bytecode: Byte,
    mode: AddressMode,
    size_bytes: usize,
    cycles_tenths: u16,
    function: *const fn (*MOS6502) void, // Adjust MOS6502 type as needed

    pub fn get_cycles(self: NamedInstruction) f32 {
        return @as(f32, @floatFromInt(self.cycles_tenths)) / 10.0;
    }
};

const Instructions = std.StaticStringMap(InstructionSet).initComptime(.{
    .{ "ADC", create_instruction_set("adc", .{
        .immediate = Instruction.init_single(0x69, 2, 2),
        .zeropage = Instruction.init_single(0x65, 2, 3),
        .zeropage_x = Instruction.init_single(0x75, 2, 4),
        .absolute = Instruction.init_single(0x6D, 3, 4),
        .absolute_x = Instruction.init_single(0x7D, 3, 4.1),
        .absolute_y = Instruction.init_single(0x79, 3, 4.1),
        .indirect_x = Instruction.init_single(0x61, 2, 6),
        .indirect_y = Instruction.init_single(0x71, 2, 5.1),
    }) },

    .{ "AND", create_instruction_set("and", .{
        .immediate = Instruction.init_single(0x29, 2, 2),
        .zeropage = Instruction.init_single(0x25, 2, 3),
        .zeropage_x = Instruction.init_single(0x35, 2, 4),
        .absolute = Instruction.init_single(0x2D, 3, 4),
        .absolute_x = Instruction.init_single(0x3D, 3, 4.1),
        .absolute_y = Instruction.init_single(0x39, 3, 4.1),
        .indirect_x = Instruction.init_single(0x21, 2, 6),
        .indirect_y = Instruction.init_single(0x31, 2, 5.1),
    }) },

    .{ "ASL", create_instruction_set("asl", .{
        .accumulator = Instruction.init_single(0x0A, 1, 2),
        .zeropage = Instruction.init_single(0x06, 2, 5),
        .zeropage_x = Instruction.init_single(0x16, 2, 6),
        .absolute = Instruction.init_single(0x0E, 3, 6),
        .absolute_x = Instruction.init_single(0x1E, 3, 7),
    }) },

    .{ "BCC", create_instruction_set("bcc", .{
        .relative = Instruction.init_single(0x90, 2, 2.12),
    }) },

    .{ "BCS", create_instruction_set("bcs", .{
        .relative = Instruction.init_single(0xB0, 2, 2.12),
    }) },

    .{ "BEQ", create_instruction_set("beq", .{
        .relative = Instruction.init_single(0xF0, 2, 2.12),
    }) },

    .{ "BIT", create_instruction_set("bit", .{
        .zeropage = Instruction.init_single(0x24, 2, 3),
        .absolute = Instruction.init_single(0x2C, 3, 4),
    }) },

    .{ "BMI", create_instruction_set("bmi", .{
        .relative = Instruction.init_single(0x30, 2, 2.12),
    }) },

    .{ "BNE", create_instruction_set("bne", .{
        .relative = Instruction.init_single(0xD0, 2, 2.12),
    }) },

    .{ "BPL", create_instruction_set("bpl", .{
        .relative = Instruction.init_single(0x10, 2, 2.12),
    }) },

    .{ "STY", create_instruction_set("sty", .{
        .zeropage = Instruction.init_single(0x84, 2, 3),
        .zeropage_x = Instruction.init_single(0x94, 2, 4),
        .absolute = Instruction.init_single(0x8C, 3, 4),
    }) },

    .{ "TAX", create_instruction_set("tax", .{
        .implied = Instruction.init_single(0xAA, 1, 2),
    }) },

    .{ "TAY", create_instruction_set("tay", .{
        .implied = Instruction.init_single(0xA8, 1, 2),
    }) },

    .{ "TSX", create_instruction_set("tsx", .{
        .implied = Instruction.init_single(0xBA, 1, 2),
    }) },

    .{ "TXA", create_instruction_set("txa", .{
        .implied = Instruction.init_single(0x8A, 1, 2),
    }) },

    .{ "TXS", create_instruction_set("txs", .{
        .implied = Instruction.init_single(0x9A, 1, 2),
    }) },

    .{ "TYA", create_instruction_set("tya", .{
        .implied = Instruction.init_single(0x98, 1, 2),
    }) },

    // Undocumented instructions
    .{ "DOP", create_instruction_set("dop", .{
        .zeropage = Instruction.init_multiple(&DopZeropageBytecodes, 2, 3),
        .zeropage_x = Instruction.init_multiple(&DopZeropageXBytecodes, 2, 4),
        .immediate = Instruction.init_multiple(&DopImmediateBytecodes, 2, 2),
    }) },

    .{ "TOP", create_instruction_set("top", .{
        .absolute = Instruction.init_single(0x0C, 3, 4),
        .absolute_x = Instruction.init_multiple(&TopAbsoluteXBytecodes, 3, 4.1),
    }) },

    .{ "KIL", create_instruction_set("kil", .{
        .implied = Instruction.init_multiple(&KilImpliedBytecodes, 1, 1),
    }) },

    .{ "LAX", create_instruction_set("lax", .{
        .zeropage = Instruction.init_single(0xA7, 2, 3),
        .zeropage_y = Instruction.init_single(0xB7, 2, 4),
        .absolute = Instruction.init_single(0xAF, 3, 4),
        .absolute_y = Instruction.init_single(0xBF, 3, 4.1),
        .indirect_x = Instruction.init_single(0xA3, 2, 6),
        .indirect_y = Instruction.init_single(0xB3, 2, 5.1),
    }) },

    .{ "AAX", create_instruction_set("aax", .{
        .zeropage = Instruction.init_single(0x87, 2, 3),
        .zeropage_y = Instruction.init_single(0x97, 2, 4),
        .indirect_x = Instruction.init_single(0x83, 2, 6),
        .absolute = Instruction.init_single(0x8F, 3, 4),
    }) },

    .{ "DCP", create_instruction_set("dcp", .{
        .zeropage = Instruction.init_single(0xC7, 2, 5),
        .zeropage_x = Instruction.init_single(0xD7, 2, 6),
        .absolute = Instruction.init_single(0xCF, 3, 6),
        .absolute_x = Instruction.init_single(0xDF, 3, 7),
        .absolute_y = Instruction.init_single(0xDB, 3, 7),
        .indirect_x = Instruction.init_single(0xC3, 2, 8),
        .indirect_y = Instruction.init_single(0xD3, 2, 8),
    }) },

    .{ "ISC", create_instruction_set("isc", .{
        .zeropage = Instruction.init_single(0xE7, 2, 5),
        .zeropage_x = Instruction.init_single(0xF7, 2, 6),
        .absolute = Instruction.init_single(0xEF, 3, 6),
        .absolute_x = Instruction.init_single(0xFF, 3, 7),
        .absolute_y = Instruction.init_single(0xFB, 3, 7),
        .indirect_x = Instruction.init_single(0xE3, 2, 8),
        .indirect_y = Instruction.init_single(0xF3, 2, 8),
    }) },

    .{ "SLO", create_instruction_set("slo", .{
        .zeropage = Instruction.init_single(0x07, 2, 5),
        .zeropage_x = Instruction.init_single(0x17, 2, 6),
        .absolute = Instruction.init_single(0x0F, 3, 6),
        .absolute_x = Instruction.init_single(0x1F, 3, 7),
        .absolute_y = Instruction.init_single(0x1B, 3, 7),
        .indirect_x = Instruction.init_single(0x03, 2, 8),
        .indirect_y = Instruction.init_single(0x13, 2, 8),
    }) },

    .{ "RLA", create_instruction_set("rla", .{
        .zeropage = Instruction.init_single(0x27, 2, 5),
        .zeropage_x = Instruction.init_single(0x37, 2, 6),
        .absolute = Instruction.init_single(0x2F, 3, 6),
        .absolute_x = Instruction.init_single(0x3F, 3, 7),
        .absolute_y = Instruction.init_single(0x3B, 3, 7),
        .indirect_x = Instruction.init_single(0x23, 2, 8),
        .indirect_y = Instruction.init_single(0x33, 2, 8),
    }) },

    .{ "SRE", create_instruction_set("sre", .{
        .zeropage = Instruction.init_single(0x47, 2, 5),
        .zeropage_x = Instruction.init_single(0x57, 2, 6),
        .absolute = Instruction.init_single(0x4F, 3, 6),
        .absolute_x = Instruction.init_single(0x5F, 3, 7),
        .absolute_y = Instruction.init_single(0x5B, 3, 7),
        .indirect_x = Instruction.init_single(0x43, 2, 8),
        .indirect_y = Instruction.init_single(0x53, 2, 8),
    }) },

    .{ "RRA", create_instruction_set("rra", .{
        .zeropage = Instruction.init_single(0x67, 2, 5),
        .zeropage_x = Instruction.init_single(0x77, 2, 6),
        .absolute = Instruction.init_single(0x6F, 3, 6),
        .absolute_x = Instruction.init_single(0x7F, 3, 7),
        .absolute_y = Instruction.init_single(0x7B, 3, 7),
        .indirect_x = Instruction.init_single(0x63, 2, 8),
        .indirect_y = Instruction.init_single(0x73, 2, 8),
    }) },

    .{ "ARR", create_instruction_set("arr", .{
        .immediate = Instruction.init_single(0x6B, 2, 2),
    }) },

    .{ "ASR", create_instruction_set("asr", .{
        .immediate = Instruction.init_single(0x4B, 2, 2),
    }) },

    .{ "ATX", create_instruction_set("atx", .{
        .immediate = Instruction.init_single(0xAB, 2, 2),
    }) },

    .{ "AAC", create_instruction_set("aac", .{
        .immediate = Instruction.init_multiple(&AacImmediateBytecodes, 2, 2),
    }) },

    .{ "AXA", create_instruction_set("axa", .{
        .absolute_y = Instruction.init_single(0x9F, 3, 5),
        .indirect_y = Instruction.init_single(0x93, 2, 6),
    }) },

    .{ "AXS", create_instruction_set("axs", .{
        .immediate = Instruction.init_single(0xCB, 2, 2),
    }) },

    .{ "LAR", create_instruction_set("lar", .{
        .absolute_y = Instruction.init_single(0xBB, 3, 4.1),
    }) },

    .{ "SXA", create_instruction_set("sxa", .{
        .absolute_y = Instruction.init_single(0x9E, 3, 5),
    }) },

    .{ "SYA", create_instruction_set("sya", .{
        .absolute_x = Instruction.init_single(0x9C, 3, 5),
    }) },

    .{ "XAA", create_instruction_set("xaa", .{
        .immediate = Instruction.init_single(0x8B, 2, 2),
    }) },

    .{ "XAS", create_instruction_set("xas", .{
        .absolute_y = Instruction.init_single(0x9B, 3, 5),
    }) },
});

// Usage example
test "instruction set usage" {
    const allocator = std.testing.allocator;
    _ = allocator; // autofix

    // Get ADC instruction
    if (Instructions.get("ADC")) |adc_set| {
        std.debug.print("Instruction: {s}\n", .{adc_set.name});

        // Get immediate mode
        if (adc_set.modes.get(.immediate)) |immd| {
            if (immd) |immediate_instr| {
                std.debug.print("Immediate ADC: 0x{X}, size: {}, cycles: {d:.1}\n", .{
                    switch (immediate_instr.bytecode) {
                        .single => |b| b,
                        .multiple => |bs| bs[0],
                    },
                    immediate_instr.size_bytes,
                    immediate_instr.get_cycles(),
                });
            }
        }
    }
}

// Compile-time bytecode dictionary generation
const BYTECODE_DICT: [256]?NamedInstruction = blk: {
    @setEvalBranchQuota(10000); // Increase compile-time evaluation limit

    var instructions: [256]?NamedInstruction = [_]?NamedInstruction{null} ** 256;

    // Get all instruction names as a comptime array
    const instruction_names = Instructions.keys();

    // Iterate through all instructions at compile time
    for (instruction_names) |instr_name| {
        const instr_set = Instructions.get(instr_name).?;

        // Iterate through all addressing modes
        for (std.enums.values(AddressMode)) |mode| {
            if (instr_set.modes.get(mode)) |instr| {
                if (instr) |i| {
                    switch (i.bytecode) {
                        .single => |bytecode| {
                            instructions[bytecode] = NamedInstruction{
                                .name = instr_set.name,
                                .bytecode = bytecode,
                                .mode = mode,
                                .size_bytes = i.size_bytes,
                                .cycles_tenths = i.cycles_tenths,
                                .function = MOS6502.byte_codes.get(i.name) orelse unreachable,
                            };
                        },
                        .multiple => |bytecodes| {
                            for (bytecodes) |bytecode| {
                                instructions[bytecode] = NamedInstruction{
                                    .name = instr_set.name,
                                    .bytecode = bytecode,
                                    .mode = mode,
                                    .size_bytes = i.size_bytes,
                                    .cycles_tenths = i.cycles_tenths,
                                };
                            }
                        },
                    }
                }
            }
        }
    }

    break :blk instructions;
};

// Test and demonstration
test "compile-time bytecode dictionary" {
    // The dictionary is fully populated at compile time
    const adc_immediate = MOS6502.instructions[0x69].?;

    std.debug.print("ADC Immediate: {s}, cycles: {d:.1}, size: {}\n", .{
        adc_immediate.name,
        adc_immediate.get_cycles(),
        adc_immediate.size_bytes,
    });

    // Test execution
    var cpu = MOS6502{};
    cpu.execute_instruction(0x69); // Execute ADC immediate

    // Verify all slots are properly filled
    var filled_count: usize = 0;
    for (BYTECODE_DICT) |maybe_instr| {
        if (maybe_instr != null) filled_count += 1;
    }
    std.debug.print("Total instructions populated: {}\n", .{filled_count});
}
