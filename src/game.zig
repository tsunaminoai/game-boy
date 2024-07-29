const std = @import("std");
const rl = @import("raylib");
const GameStatePtr = *anyopaque;
const Config = @import("types.zig").Config;
const Renderer = @import("renderer.zig");
const GB = @import("gb");
const Audio = @import("audio.zig");

const Game = @This();

const ROM = "test_opcode.ch8";

screen: rl.Vector2,
scale: rl.Vector2 = rl.Vector2.init(1, 1),
shift: rl.Vector2 = rl.Vector2.init(0, 0),
target_frame_rate: f32 = 60.0,
delta_time: f64 = 0.0,
running: bool = false,
fps_capped: bool = false,
debug: bool = false,
config: Config = Config{},
renderer: *Renderer = undefined,
chip: GB.Device.CPU,
clock_hz: f32 = 0,
audio: Audio,

alloc: std.mem.Allocator,
var frame_start: f64 = 0;

/// Initializes the game with the given configuration and returns a pointer to the game state.
///
/// # Parameters
/// - `config`: The configuration for the game.
///
/// # Returns
/// A pointer to the game state.
pub fn init(config: Config) GameStatePtr {
    std.debug.print("Starting game with config: {any}\n", .{config});
    var alloc = std.heap.c_allocator;

    var self = alloc.create(Game) catch @panic("Failed to allocate Game");
    self.reload(Config{});

    const chip = GB.init(0xFFFF) catch @panic("Failed to initialize CPU");

    self.chip = chip;
    self.init_renderer() catch @panic("Failed to initialize renderer");
    self.audio = Audio.init(self);
    var thread = std.Thread.spawn(
        .{},
        Audio.processor,
        .{&self.audio},
    ) catch @panic("Failed to spawn audio processor");
    thread.detach();

    // self.startStop();
    return self;
}

pub fn init_renderer(self: *Game) !void {
    self.renderer = try Renderer.init(self.alloc, self);
}

/// Handles the events for the game.
pub fn handleEvents(self: *Game) void {
    if (rl.getMouseWheelMove() > 0) {
        self.scale = self.scale.addValue(0.01);
    } else if (rl.getMouseWheelMove() < 0) {
        // Zoom out
        self.scale = self.scale.subtractValue(0.01);
    }
    if (rl.isMouseButtonDown(.mouse_button_left)) {
        const pos = rl.getMouseDelta().multiply(self.scale).scale(5);
        self.shift = self.shift.add(pos);
    }

    switch (rl.getKeyPressed()) {
        // .key_d => self.debug = !self.debug,
        .key_s => std.debug.print("State: {any}\n", .{self}),
        .key_p => self.running = !self.running,
        .key_q => rl.closeWindow(),
        else => |k| {
            _ = k; // autofix
            // self.chip.keyPress(@truncate(@as(u16, @intCast(@intFromEnum(k)))));
        },
    }
}

/// Updates the game state.
pub fn tick(self: *Game) void {
    self.handleEvents();
    const denom = 1.0 / self.target_frame_rate;
    const ticks_per_frame = self.clock_hz / denom;
    if (self.running) {
        for (@as(usize, @intFromFloat(if (ticks_per_frame > 1.0) ticks_per_frame else 1.0))) |_|
            // self.chip.tick();
            _ = 1;
    }
}

/// Starts the game.
pub fn startStop(self: *Game) void {
    self.running = !self.running;
}

/// Deinitializes the game.
pub fn deinit(self: *Game) void {
    _ = self; // autofix
    // self.chip.deinit();

}

/// Reloads the game with the given configuration.
pub fn reload(self: *Game, config: Config) void {
    self.* = Game{
        .screen = .{
            .x = config.width,
            .y = config.height,
        },
        .chip = undefined,
        .target_frame_rate = 1.0 / (config.target_fps),
        .alloc = std.heap.c_allocator,
        .audio = Audio.init(self),
        .config = config,
    };
    var bus = GB.Device.Bus.init(0xFFFF) catch @panic("Failed to initialize bus");
    self.chip = GB.Device.CPU.init(&bus) catch @panic("Failed to initialize CPU");
    self.init_renderer() catch @panic("Failed to initialize renderer");
}

/// Starts the frame.
pub fn frameStart(_: *Game) void {
    frame_start = rl.getTime();
}

/// Ends the frame.
pub fn frameEnd(self: *Game) void {
    self.delta_time = (rl.getTime() - frame_start);
}

/// Main rendering function.
pub fn render(self: *Game) void {
    self.frameStart();
    self.renderer.render();
    if (self.debug) self.debugDraw();
    self.frameEnd();
    if (self.delta_time < self.target_frame_rate) {
        rl.waitTime((self.target_frame_rate - self.delta_time));
        self.delta_time = self.target_frame_rate;
    }
}

/// Draws some debug information.
fn debugDraw(self: *Game) void {
    var buffer: [128:0]u8 = undefined;
    _ = std.fmt.bufPrint(
        &buffer,
        "Target FPS: {d:0.1}\n\t({d:0.0},{d:0.0})\x00",
        .{
            self.config.target_fps,
            self.config.width,
            self.config.height,
        },
    ) catch unreachable;
    rl.drawFPS(@intFromFloat(self.config.width - 75), 10);
    rl.drawText(&buffer, @intFromFloat(self.config.width - 75), 30, 10, rl.Color.white);
}
