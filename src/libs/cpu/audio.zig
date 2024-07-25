const std = @import("std");

const APU = @This();

const Sweep = struct {
    period: u4,
    negative: bool,
    shift: u3,
    timer: u64 = 0,
    shadow: u16 = 0,
    enabled: bool = false,
    pub fn read(in: u8) Sweep {
        return .{
            .period = in & 0x07,
            .negative = in & 0x08 == 1,
            .shift = (in >> 4) & 0x07,
        };
    }
    pub fn sample(self: *Sweep, dt: 64) f32 {
        _ = dt; // autofix
        if (self.timer > 0) {
            self.timer -= 1;
        }
        if (self.timer == 0) {
            self.timer = if (self.period > 0) self.period else 8;
        }
        if (self.enabled and self.period > 0) {
            const new = self.freq();
            if (new <= 0x7FF and self.shift > 0) {
                self.shadow = new;
                _ = self.freq(); //overflow check
                return new;
            }
        }
        return 0;
    }
    pub fn freq(self: *Sweep) f32 {
        var new = self.shadow >> self.shift;
        new = if (self.negative)
            self.shadow - new
        else
            self.shadow + new;

        if (new > 0x7FF) self.enabled = false;
        return new;
    }
};

const DutyCycle = enum(u2) {
    _12_5 = 0,
    _25 = 1,
    _50 = 2,
    _75 = 3,

    pub fn toCycles(self: DutyCycle, dt: u64) u8 {
        const bits = switch (self) {
            ._12_5 => 0b00000001,
            ._25 => 0b00000011,
            ._50 => 0b00001111,
            ._75 => 0b11111100,
        };
        return bits[dt % 8];
    }
};

const Duty = struct {
    duty: DutyCycle,
    len_load: u6,
    pub fn read(in: u8) Duty {
        return .{
            .duty = in & 0xC0,
            .len_load = in & 0x3F,
        };
    }
};

const Envelope = struct {
    initial_vol: u4,
    add_mode: bool,
    period: u8,
    timer: u64 = 0,
    current_vol: u4 = 0,
    pub fn read(in: u8) Envelope {
        return .{
            .initial_vol = in & 0xF0,
            .add_mode = in & 0x08 == 1,
            .period = in & 0x07,
        };
    }
    pub fn sample(self: Envelope, dt: u64) f32 {
        _ = dt; // autofix
        if (self.period != 0) {
            if (self.timer > 0) self.timer -= 1;

            if (self.timer == 0) {
                self.timer = self.period;
                if ((self.current_vol < 0xF and self.add_mode) or (self.current_vol > 0 and !self.add_mode)) {
                    self.current_vol += if (self.add_mode) 1 else -1;
                }
            }
        }
        return 0;
    }
};

const FrequencyLSB = u8;
const FrequencyMSB = u4;
const Frequency = struct {
    lsb: FrequencyLSB,
    msb: FrequencyMSB,

    pub fn toInt(self: Frequency) u16 {
        return (self.msb << 8) | self.lsb;
    }
};
const Trigger = struct {
    trigger: bool,
    len_enable: bool,
    freq_msb: FrequencyMSB,
    pub fn read(in: u8) Trigger {
        return .{
            .trigger = in & 0x80 == 1,
            .len_enable = in & 0x40 == 1,
            .freq_msb = in & 0x07,
        };
    }
};
const DAC = struct {
    power: bool,
    pub fn read(in: u8) DAC {
        return .{
            .power = in & 0x80 == 1,
        };
    }
};
const VolCode = struct {
    code: u2,
    pub fn read(in: u8) VolCode {
        return .{
            .code = in & 0x60,
        };
    }
};
const NoiseConfig = struct {
    clock_shift: u4,
    width_mode: bool,
    div_code: u3,
    pub fn read(in: u8) NoiseConfig {
        return .{
            .clock_shift = in & 0x07,
            .width_mode = in & 0x08 == 1,
            .div_code = (in >> 4) & 0x07,
        };
    }
};

const Square = struct {
    sweep: ?Sweep,
    duty: Duty,
    envelope: Envelope,
    frequency: Frequency,
    freq_timer: u64,

    pub fn sample(self: *Square, dt: u64) f32 {
        self.timer -= 1;
        if (self.timer == 0) {
            self.timer = (2048 - self.frequency.toInt()) * 4;
        }
        if (self.sweep) |s| {
            self.freq_timer -= 1;
            if (self.freq_timer == 0) {
                self.freq_timer = s.sample(dt);
            }
        }
        return (self.duty.duty.toCycles(dt) * self.envelope.sample(dt)) / 7.5 - 1.0;
    }
};
const Wave = struct {
    dac: DAC,
    len_load: u8,
    volume: VolCode,
    frequency: Frequency,
    table: [32]u4,

    pub fn sample(self: Wave, dt: u64) f32 {
        return @floatFromInt(self.shift(dt));
    }
    fn shift(self: Wave, idx: usize) u4 {
        const i = idx % 32;
        return switch (self.volume.code) {
            0 => self.table[i] >> 4,
            1 => self.table[i],
            2 => self.table[i] >> 1,
            3 => self.table[i] >> 2,
        };
    }
};
const Noise = struct {
    len_load: u8,
    envelope: Envelope,
    noise: NoiseConfig,
    pub fn sample(self: Noise, dt: u64) f32 {
        _ = dt; // autofix
        _ = self; // autofix
        return 0;
    }
};
const Channel = struct {
    timer: u6 = 0,
    conf: ChannelConf,
    on: bool = false,
    trigger: Trigger,

    pub fn shouldTurnOff(self: Channel) bool {
        return self.trigger.len_enable and self.timer == 0;
    }
    pub fn sample(self: *Channel, dt: u64) f32 {
        if (self.shouldTurnOff()) {
            self.on = false;
        }
        if (!self.on) {
            return 0;
        }
        return self.conf.sample(dt);
    }
};
const ChannelConf = union(enum) {
    square: Square,
    wave: Wave,
    noise: Noise,

    pub fn sample(self: *ChannelConf, dt: u64) f32 {
        switch (self) {
            else => |c| return c.sample(dt),
        }
    }
};

const SoundRegisters = struct {
    // square 1
    nr10: Sweep,
    nr11: Duty,
    nr12: Envelope,
    nr13: FrequencyLSB,
    nr14: Trigger,
    // square 2
    _1: u8, //not used
    nr21: Duty,
    nr22: Envelope,
    nr23: FrequencyLSB,
    nr24: Trigger,
    // wave
    nr30: DAC,
    nr31: u8, //len load (256-L)
    nr32: VolCode,
    nr33: FrequencyLSB,
    nr34: Trigger,
    // noise
    _2: u8, //not used
    nr41: u8, //len load (64-L)
    nr42: Envelope,
    nr43: NoiseConfig,
    nr44: Trigger,
    ctrl: Control,

    pub fn init(ptr: *[0x30]u8) *SoundRegisters {
        return @ptrCast(@alignCast(ptr));
    }
};

const Control = struct {
    vin_L_enable: bool = false, // never enable!
    left_vol: u3,
    vin_R_enable: bool = false, // never enable!
    right_vol: u3,
    left_enable: struct {
        square1: bool,
        square2: bool,
        wave: bool,
        noise: bool,
    },
    right_enable: struct {
        square1: bool,
        square2: bool,
        wave: bool,
        noise: bool,
    },
    power: u4,
    status: struct {
        square1: bool,
        square2: bool,
        wave: bool,
        noise: bool,
    },
    _2: u64,
    wave_table: [32]u4 align(2),
};

test {
    var data = [_]u8{0} ** 0x30;
    const s = SoundRegisters.init(&data);
    var apu = APU.init(s);
    for (0..10) |i| {
        apu.tick();
        std.debug.print("{any}\n", .{apu.sample(i)});
    }
}

registers: *SoundRegisters,
channels: [4]Channel,
master_enable: bool = false,
clock_hz: usize = 1_048_576,
sample_rate: usize = 44_100,
fs: FrameSequencer,
last_tick: u64 = 0,

pub fn init(registers: *SoundRegisters) APU {
    var self = APU{
        .registers = registers,
        .channels = undefined,
        .fs = undefined,
    };
    self.fs = FrameSequencer.init(&self);
    self.channels[0] = .{
        .conf = .{ .square = .{
            .sweep = .{ .period = 3, .negative = false, .shift = 1 },
            .duty = .{ .duty = DutyCycle._12_5, .len_load = 0 },
            .envelope = .{ .initial_vol = 10, .add_mode = false, .period = 0 },
            .frequency = .{ .lsb = 0, .msb = 0 },
            .freq_timer = 0,
        } },
        .trigger = .{
            .trigger = false,
            .len_enable = false,
            .freq_msb = 0,
        },
    };
    return self;
}

pub const Sample = struct {
    left: f32 = 0,
    right: f32 = 0,
};

pub fn tick(self: *APU) void {
    const now: u64 = @intCast(std.time.nanoTimestamp());
    if (now - self.last_tick >= self.clock_hz / self.sample_rate) {
        self.last_tick = now;
        self.fs.step();
    }
}

pub fn sample(self: *APU, dt: u64) Sample {
    var s = Sample{};

    var mix: f32 = 0;
    for (&self.channels) |*c| {
        if (c.on) {
            mix += c.sample(dt) / self.channels.len;
        }
    }

    s.left = mix * @as(f32, @floatFromInt(self.registers.ctrl.left_vol));
    s.right = mix * @as(f32, @floatFromInt(self.registers.ctrl.right_vol));
    return s;
}

pub const FrameSequencer = struct {
    idx: usize = 0,
    apu: *APU,
    pub fn init(apu: *APU) FrameSequencer {
        return .{ .apu = apu };
    }
    pub fn step(self: *FrameSequencer) void {
        self.idx += 1;
        if (self.idx == 8) {
            self.idx = 0;
        }
        if (self.idx % 2 == 0) {
            self.apu.stepLength();
        }
        if (self.idx == 7) {
            self.apu.stepVolume();
        }
    }
};

pub fn stepLength(self: *APU) void {
    for (&self.channels) |*c| {
        if (c.trigger.len_enable) {
            c.timer -= 1;
            if (c.timer == 0) {
                c.on = false;
            }
        }
    }
}

pub fn stepVolume(self: *APU) void {
    for (&self.channels) |*c| {
        if (c.trigger.len_enable) {
            c.on = false;
        }
    }
}
