const Game = @import("game.zig");
const rl = @import("raylib");

const GB = @import("gb");
const Renderer = @import("renderer.zig");
const GUI = @import("gui.zig");
const Audio = @import("audio.zig");

const std = @import("std");
const GameStatePtr = *anyopaque;
pub const Config = @import("types.zig").Config;

/// Dyn lib function to init the game state.
export fn gameInit(config: Config) GameStatePtr {
    std.debug.print("Config: {any}\n", .{config});
    return Game.init(config);
}

/// Dyn lib function to reload the game state.
export fn gameReload(ptr: GameStatePtr) void {
    var state: *Game = @ptrCast(@alignCast(ptr));
    state.reload(state.config);
    state.startStop();
    std.debug.print("Reloaded the  successfully\n", .{});
    std.debug.print("With config: {any}\n", .{state.config});
}

/// Dyn lib function to tick the game state.
export fn gameTick(ptr: GameStatePtr) void {
    var state: *Game = @ptrCast(@alignCast(ptr));
    state.tick();
}

/// Dyn lib function to draw the game state.
export fn gameDraw(ptr: GameStatePtr) void {
    var state: *Game = @ptrCast(@alignCast(ptr));
    state.render();
}

/// Dyn lib function to deinit the game state.
export fn gameDeinit(ptr: GameStatePtr) void {
    var state: *Game = @ptrCast(@alignCast(ptr));
    state.deinit();
}
