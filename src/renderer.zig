const std = @import("std");
const GB = @import("root").GB;
const Game = @import("game.zig");
const rl = @import("raylib");
const GUI = @import("gui.zig");

const Renderer = @This();

/// The screen buffer used for rendering.
screen_buffer: []rl.Color = undefined,

/// The allocator used for memory allocation.
alloc: std.mem.Allocator = undefined,

/// A pointer to the game state.
state: *Game,

/// A pointer to the GUI.
gui: *GUI = undefined,

/// Initializes a new Renderer instance.
///
/// This function takes an allocator and a pointer to a Game struct as parameters.
/// It creates a new Renderer instance using the allocator and initializes its fields.
/// The `gui` field is initialized by calling the `init` function of the GUI module.
///
/// This function can return an error if memory allocation fails.
pub fn init(allocator: std.mem.Allocator, state: *Game) !*Renderer {
    const self = try allocator.create(Renderer);
    errdefer allocator.destroy(self);
    self.* =
        Renderer{
        .alloc = allocator,
        .state = state,
        .gui = try GUI.init(allocator, state),
    };

    return self;
}
pub fn deinit(self: *Renderer) void {
    _ = self; // autofix

}

/// Renders the game state.
pub fn render(self: *Renderer) void {
    self.gui.render();

    const block_size = 5;
    const rom_dev = self.state.chip.rom0.device();
    for (rom_dev.data.?, 0..) |color, i| {
        const x = 100 + block_size * i % 256;
        const y = 150 + block_size * i / 256;
        rl.drawRectangle(
            @intCast(x),
            @intCast(y),
            block_size,
            block_size,
            rl.Color.init(color, color, color, 255),
        );
    }
    rl.drawText(rl.textFormat("%d bytes", .{rom_dev.data.?.len}), 10, 10, 20, rl.Color.red);
}
