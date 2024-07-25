const std = @import("std");
const rl = @import("raylib");

/// Configuration struct for the game.
pub const Config = extern struct {
    /// The width of the game window.
    width: f32 = 800,

    /// The height of the game window.
    height: f32 = 600,

    /// The target frames per second for the game.
    target_fps: f32 = 60.0,
};
