const std = @import("std");

var mem: [0xFFF]u8 = [_]u8{0} ** 0xFFF;

const ETI = mem[0x600..0xFFF];
const Prog = mem[0x200..0xFFF];

var Registers: [16]u8 = undefined;

var SoundReg: u8 = 0;
var DelayReg: u8 = 0;
var PC: u16 = 0;
var SP: u8 = 0;

var Stack: [16]u16 = undefined;
const Reg = enum(u8) { v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, vA, vB, vC, vD, vE, vF };
const Timer = struct {};
var SoundTimer: Timer = undefined;
var Delaytimer: Timer = undefined;

const Nib = u4;
const Op = enum(Nib) {
    Sys = 0x0,
    JumpAddr = 0x1,
    Call = 0x2,
    Se = 0x3,
    Sne = 0x4,
    SkipIfEqByte = 0x5,
    ALU = 0x8,
    SkipIfNeReg = 0x9,
    LdAddr = 0xA,
    JumpPlus = 0xB,
    Rnd = 0xC,
    Disp = 0xD,
    SkipKey = 0xE,
    Delay = 0xF,
};
const XY = struct { x: Nib, y: Nib };

const SysOp = packed struct(u16) {
    op: Op,
    _pad: Nib,
    inst: Cmd,
    const Cmd = enum(u8) {
        Cls = 0xE0,
        Ret = 0xEE,
        _,
    };
};
const AddrOp = packed struct(u16) {
    op: Op,
    addr: u12 = 0,
};
const JumpOp = packed struct {
    op: Op = .JumpAddr,
    addr: u12,
};
const CallOp = packed struct {
    op: Op = .Call,
    add: u12,
};
const SkipOp = packed struct {
    op: Op,
    x: Nib,
    lower: packed union {
        byte: u8,
        xy: packed struct { y: Nib, arg: Nib },
    },
};
const AluOp = packed struct {
    op: Op,
    x: Nib,
    y: Nib,
    arg: Nib,
};
const RndOp = packed struct {
    op: Op = .Rnd,
    x: Nib,
    byte: u8,
};
const DrawOp = packed struct {
    op: Op = .Draw,
    x: Nib,
    y: Nib,
    sprite: Nib,
};
const Inst = packed union {
    sys: SysOp,
    jump: JumpOp,
    call: CallOp,
    skip: SkipOp,
    rnd: RndOp,
};

const C8 = @This();
const RawInst = packed union {
    op: Op,
    _: u12,
};
pub fn tick(_: *C8) void {
    const cur = mem[PC .. PC + 2];
    const inst = std.mem.bytesAsValue(RawInst, cur);
    std.debug.print("{any}\n", .{inst.op});
    switch (inst.op) {
        .Sys => {
            const i = std.mem.bytesAsValue(SysOp, cur);
            std.debug.print("{any}\n", .{i.inst});
            switch (i.inst) {
                .Cls => {},
                .Ret => {},
                else => @panic("Invalid Sys Call"),
            }
        },
        else => |o| {
            std.debug.print("Undefined: {any}\n", .{o});
            @panic("Undefined OpCode");
        },
    }
    PC += 2;
}

pub fn init() C8 {
    return C8{};
}
test {
    @memcpy(mem[0..2], &[_]u8{ 0x00, 0xE0 });
    var c = C8.init();
    std.debug.print("{any}\n", .{c});
    c.tick();
}
