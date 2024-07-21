const std = @import("std");

var mem: [0xFFF]u8 = [_]u8{0} ** 0xFFF;

const ETI = mem[0x600..0xFFF];
const Prog = mem[0x200..0xFFF];

var Registers: [16]u8 = undefined;

const W = 64;
const H = 32;
var Display: [W * H]u1 = [_]u1{1} ** (W * H);

pub fn render() void {
    for (0..H) |y| {
        for (0..W) |x| {
            const char: u8 = if (Display[y * W + x] == 1) '#' else ' ';
            std.debug.print("{c}", .{char});
        }
        std.debug.print("\n", .{});
    }
}

var SoundReg: u8 = 0;
var DelayReg: u8 = 0;
var PC: u16 = 0;
var SP: u8 = 0;
var I: u12 = 0;

var rand: std.Random = undefined;

var Stack: [16]u16 = [_]u16{0} ** 16;
const Reg = enum(u8) { v0, v1, v2, v3, v4, v5, v6, v7, v8, v9, vA, vB, vC, vD, vE, vF };
const Timer = u8;
var SoundTimer: Timer = undefined;
var Delaytimer: Timer = undefined;

const Nib = u4;
const Op = enum(Nib) {
    Sys = 0x0,
    JumpAddr = 0x1,
    Call = 0x2,
    Se = 0x3,
    Sne = 0x4,
    SkipIfEqReg = 0x5,
    LoadImd = 0x6,
    Add = 0x7,
    ALU = 0x8,
    SkipIfNeReg = 0x9,
    LoadAddr = 0xA,
    JumpPlus = 0xB,
    Rnd = 0xC,
    Draw = 0xD,
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

    ///Return from subroutine. Set the PC to the address at the top of the
    /// stack and subtract 1 from the SP.
    pub fn ret() void {
        PC = mem[SP];
        SP -= 1;
    }
};
const AddrOp = packed struct(u16) {
    op: Op,
    addr: u12 = 0,
};
const JumpOp = packed struct {
    op: Op = .JumpAddr,
    addr: u12,
    ///Set PC to NNN.
    pub fn exec(self: JumpOp) void {
        PC = self.addr;
    }
};
const JumpPlusOp = packed struct {
    op: Op = .JumpPlus,
    addr: u12,
    ///Set PC to NNN.
    pub fn exec(self: JumpPlusOp) void {
        PC = self.addr + Registers[0x0];
    }
};
const CallOp = packed struct {
    op: Op = .Call,
    addr: u12,
    ///Call subroutine a NNN. Increment the SP and put the current PC value on
    /// the top of the stack. Then set the PC to NNN. Generally there is a limit
    /// of 16 successive calls.
    pub fn exec(self: CallOp) void {
        SP += 1;
        const stack: *[]u16 = @ptrCast(@alignCast(&mem));
        stack.*[SP / 2] = PC;
        PC = self.addr;
    }
};
const SkipOp = packed struct {
    op: Op,
    x: Nib,
    lower: packed union {
        byte: u8,
        xy: packed struct { y: Nib, arg: Nib },
    },
    /// Skip the next instruction if register VX is equal to NN.
    pub fn exec(self: SkipOp) void {
        switch (self.op) {
            .Se => {
                const rVal = Registers[self.x];
                if (rVal == self.lower.byte)
                    PC += 2;
            },
            .Sne => {
                const rVal = Registers[self.x];
                if (rVal != self.lower.byte)
                    PC += 2;
            },
            .SkipIfEqReg => {
                switch (self.lower.xy.arg) {
                    0 => {
                        if (Registers[self.x] == Registers[self.lower.xy.y])
                            PC += 2;
                    },
                    else => {
                        @panic("CHIP-8* unhandled");
                    },
                }
            },
            .SkipIfNeReg => {
                if (Registers[self.x] != Registers[self.lower.xy.y])
                    PC += 2;
            },
            else => @panic("Unexpected skip"),
        }
    }
};
const AluOp = packed struct {
    op: Op,
    x: Nib,
    y: Nib,
    arg: Nib,
    pub fn exec(self: AluOp) void {
        switch (self.arg) {
            0x0 => {
                //ld vx,vy
                Registers[self.x] = Registers[self.y];
            },
            0x1 => {
                Registers[self.x] |= Registers[self.y];
            }, //OR VX, VY
            0x2 => {
                Registers[self.x] &= Registers[self.y];
            }, //AND VX, VY
            0x3 => {
                Registers[self.x] ^= Registers[self.y];
            }, //XOR VX, VY
            0x4 => {
                const res = @addWithOverflow(Registers[self.x], Registers[self.y]);
                Registers[0xF] = res[0];
                Registers[self.x] = res[1];
            }, //ADD VX, VY
            0x5 => {
                const res = @subWithOverflow(Registers[self.x], Registers[self.y]);
                Registers[0xF] = res[0];
                Registers[self.x] = res[1];
            }, //SUB VX, VY
            0x6 => {
                Registers[0xF] = Registers[self.x] & 0xE;
                Registers[self.x] >>= 1;
            }, //SHR VX, VY
            0x7 => {
                const res = @subWithOverflow(Registers[self.y], Registers[self.x]);
                Registers[0xF] = res[0];
                Registers[self.x] = res[1];
            }, //SUBN VX, VY
            0xE => {
                Registers[0xF] = Registers[self.x] & 0x7;
                Registers[self.x] <<= 1;
            }, //SHL VX, VY
            else => {
                @panic("Undefined ALU argument");
            },
        }
    }
};
const RndOp = packed struct {
    op: Op = .Rnd,
    x: Nib,
    byte: u8,

    pub fn exec(self: RndOp) void {
        const r = rand.int(u8);
        Registers[self.x] = r & self.byte;
    }
};

const AddOp = packed struct {
    op: Op = .Add,
    x: Nib,
    byte: u8,

    pub fn exec(self: AddOp) void {
        Registers[self.x] = self.byte;
    }
};
const DrawOp = packed struct {
    op: Op = .Draw,
    x: Nib,
    y: Nib,
    sprite_bytes: Nib,

    pub fn exec(self: DrawOp) void {
        // Display N-byte sprite starting at memory location I at (VX, VY).
        // Each set bit of xored with what's already drawn. VF is set to 1
        // if a collision occurs. 0 otherwise.
        var set: u8 = 0;
        const sprite = mem[I .. I + self.sprite_bytes];
        for (0..self.sprite_bytes) |i| {
            const loc = (self.y + i) * W + self.x;
            var current_pix = Display[loc .. loc + 8];
            const cur_val = std.mem.bytesToValue(u8, current_pix);
            const new_pix = cur_val ^ sprite[i];
            if (new_pix != cur_val)
                set = 1;
            const pixel_row = @as(*u8, @ptrCast(current_pix[0..8]));
            pixel_row.* = new_pix;
        }
        Registers[0xF] = set;
    }
};

const LdOp = packed struct {
    op: Op,
    rest: packed union {
        addr: u12,
        lower: packed struct {
            x: Nib,
            imd: u8,
        },
    },
    pub fn exec(self: LdOp) void {
        switch (self.op) {
            .LoadImd => {
                Registers[self.rest.lower.x] = self.rest.lower.imd;
            },
            .LoadAddr => {
                I = self.rest.addr;
            },
            else => @panic("Unexpected load op"),
        }
    }
};
const DelayOp = packed struct {
    op: Op = .Delay,
    x: Nib,
    cmd: enum(u8) {
        regFromTimer = 0x07,
        keyStore = 0x0A,
        timerFromReg = 0x15,
        soundFromReg = 0x18,
        addI = 0x1E,
        loadFont = 0x29,
        bcd = 0x33,
        memFromReg = 0x55,
        regFromMem = 0x65,
    },

    pub fn exec(self: DelayOp) void {
        switch (self.cmd) {
            .regFromTimer => {
                Registers[self.x] = Delaytimer;
            },
            .keyStore => {
                // wait for key and then store in Registers[self.x]
            },
            .timerFromReg => {
                Delaytimer = Registers[self.x];
            },
            .soundFromReg => {
                SoundTimer = Registers[self.x];
            },
            .addI => {
                I += Registers[self.x];
            },
            .loadFont => {
                // Set I to the address of the CHIP-8 8x5 font sprite representing the value in VX.
            },
            .bcd => {
                // Convert that word to BCD and store the 3 digits at memory location I through I+2.
                // I does not change.
            },
            .memFromReg => {
                // Store registers V0 through VX in memory starting at location I.
                // I does not change.
                for (0..self.x) |i|
                    mem[I + i] = Registers[i];
            },
            .regFromMem => {
                // Copy values from memory location I through I + X into registers V0 through VX.
                // I does not change.
                for (0..self.x) |i|
                    Registers[i] = mem[I + i];
            },
        }
    }
};
const Inst = packed union {
    sys: SysOp,
    jump: JumpOp,
    call: CallOp,
    skip: SkipOp,
    rnd: RndOp,
    alu: AluOp,
    jumpPlus: JumpPlusOp,
    add: AddOp,
    draw: DrawOp,
    load: LdOp,
    delay: DelayOp,
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
        .JumpAddr => {
            const i = std.mem.bytesAsValue(JumpOp, cur);
            i.exec();
        },
        .Call => {
            const i = std.mem.bytesAsValue(CallOp, cur);
            i.exec();
        },
        .Se, .Sne, .SkipIfEqReg, .SkipIfNeReg => {
            const i = std.mem.bytesAsValue(SkipOp, cur);
            i.exec();
        },
        .LoadImd, .LoadAddr => {
            const i = std.mem.bytesAsValue(LdOp, cur);
            i.exec();
        },
        .Add => {
            const i = std.mem.bytesAsValue(AddOp, cur);
            i.exec();
        },
        .ALU => {
            const i = std.mem.bytesAsValue(AluOp, cur);
            i.exec();
        },
        .JumpPlus => {
            const i = std.mem.bytesAsValue(JumpPlusOp, cur);
            i.exec();
        },
        .Rnd => {
            const i = std.mem.bytesAsValue(RndOp, cur);
            i.exec();
        },
        .Draw => {
            const i = std.mem.bytesAsValue(DrawOp, cur);
            i.exec();
        },
        .SkipKey => {},
        .Delay => {
            const i = std.mem.bytesAsValue(DelayOp, cur);
            i.exec();
        },
    }
    PC += 2;
}

pub fn init() C8 {
    var r = std.rand.DefaultPrng.init(@intCast(std.time.microTimestamp()));
    rand = r.random();
    return C8{};
}
test {
    @memcpy(mem[0..2], &[_]u8{ 0x00, 0xE0 });
    var c = C8.init();
    std.debug.print("{any}\n", .{c});
    c.tick();
    render();
}
