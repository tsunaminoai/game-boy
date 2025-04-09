const std = @import("std");
const rl = @import("raylib");
const Config = @import("types.zig").Config;
const LibName = "libgame-boy.dylib";

var alloc: std.mem.Allocator = std.heap.c_allocator;

var config = Config{
    .width = 1200,
    .height = 800,
    .target_fps = 60,
};
pub fn main() !void {
    loadGameDll() catch @panic("Failed to load " ++ LibName);

    rl.initWindow(
        @intFromFloat(config.width),
        @intFromFloat(config.height),
        "Raylib With Hot Reloading",
    );
    rl.setTargetFPS(@intFromFloat(config.target_fps));
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    alloc = gpa.allocator();

    const state = gameInit(
        config,
    );

    while (!rl.windowShouldClose()) {
        if (rl.isKeyPressed(.backspace)) {
            try reload(state);
        }
        gameTick(state);

        rl.beginDrawing();

        rl.clearBackground(rl.Color.black);

        gameDraw(state);

        rl.endDrawing();
    }
}

/// Reloads the game state and recompiles the game DLL.
///
/// This function is responsible for reloading the game state, recompiling the game DLL, and loading the updated DLL.
/// It first calculates the center of the screen using the `config.width` and `config.height` variables.
/// Then, it displays the message "RELOADING" at the calculated center position using the specified font size.
/// After that, it clears the background with a black color and begins drawing.
///
/// Next, it attempts to unload the current game DLL using the `unloadGameDll` function.
/// Then, it tries to recompile the game DLL using the `recompileGameDll` function, passing the `alloc` allocator.
/// Finally, it loads the updated game DLL using the `loadGameDll` function and calls the `gameReload` function
/// to reload the game state with the updated configuration.
fn reload(state: GameStatePtr) !void {
    const center = rl.Vector2{
        .x = config.width / 2,
        .y = config.height / 2,
    };
    const message = "RELOADING";
    const font_size = 20;
    const message_size = rl.measureText(message, font_size);
    rl.beginDrawing();
    rl.clearBackground(rl.Color.black);

    rl.drawText(
        "RELOADING",
        @as(i32, @intFromFloat(center.x)) - @divTrunc(message_size, 2),
        @as(i32, @intFromFloat(center.y)) - @divTrunc(font_size, 2),
        20,
        rl.Color.red,
    );
    rl.endDrawing();
    try unloadGameDll();
    try recompileGameDll(alloc);
    try loadGameDll();
    gameReload(state, config);
}

/// Loads the game dynamic library.
///
/// This function opens the game dynamic library and initializes function pointers
/// to the required game functions. It returns an error if the library is already loaded,
/// if the library fails to open, or if any of the required functions cannot be found.
///
/// # Errors
///
/// - `error.AlreadyLoaded`: If the game dynamic library is already loaded.
/// - `error.OpenFail`: If the game dynamic library fails to open.
/// - `error.LookupFail`: If any of the required game functions cannot be found.
fn loadGameDll() !void {
    if (game_dynamic_lib != null) return error.AlreadyLoaded;

    // TODO: platform specific
    var dyn_lib = std.DynLib.open("zig-out/lib/" ++ LibName) catch {
        return error.OpenFail;
    };

    game_dynamic_lib = dyn_lib;
    gameInit = dyn_lib.lookup(@TypeOf(gameInit), "gameInit") orelse return error.LookupFail;
    gameReload = dyn_lib.lookup(@TypeOf(gameReload), "gameReload") orelse return error.LookupFail;
    gameTick = dyn_lib.lookup(@TypeOf(gameTick), "gameTick") orelse return error.LookupFail;
    gameDraw = dyn_lib.lookup(@TypeOf(gameDraw), "gameDraw") orelse return error.LookupFail;
    gameDeinit = dyn_lib.lookup(@TypeOf(gameDraw), "gameDeinit") orelse return error.LookupFail;
    std.debug.print("Loaded {s}\n", .{LibName});
}

/// Unloads the game dynamic library.
///
/// This function unloads the game dynamic library by calling the `gameDeinit` function
/// to perform any necessary cleanup, closing the library, and setting the `game_dynamic_lib`
/// variable to `null`.
///
/// Returns an error if the game dynamic library is already unloaded.
fn unloadGameDll() !void {
    if (game_dynamic_lib) |*dyn_lib| {
        gameDeinit(dyn_lib);
        dyn_lib.close();
        game_dynamic_lib = null;
    } else {
        return error.AlreadyUnloaded;
    }
}

/// Recompiles the game DLL using the Zig build process.
///
/// This function takes an allocator as a parameter and recompiles the game DLL by invoking the Zig build process.
/// It sets the `-Dgame_only=true` flag to ensure that only the game code is compiled.
/// After spawning the build process, it waits for the compilation to complete.
/// If the compilation fails, it returns an error.
fn recompileGameDll(allocator: std.mem.Allocator) !void {
    const process_args = [_][]const u8{
        "zig",
        "build",
        "-Dgame_only=true", // This '=true' is important!
    };
    var build_process = std.process.Child.init(&process_args, allocator);
    try build_process.spawn();

    // wait() returns a tagged union. If the compilations fails that union
    // will be in the state .{ .Exited = 2 }
    const term = try build_process.wait();
    switch (term) {
        .Exited => |exited| {
            if (exited == 2) return error.RecompileFail;
        },
        else => return,
    }
}

/// Represents a dynamic library that contains the game logic.
var game_dynamic_lib: ?std.DynLib = null;

/// Pointer to the game initialization function.
const GameStatePtr = *anyopaque;
var gameInit: *const fn (Config) GameStatePtr = undefined;

/// Pointer to the game reload function.
var gameReload: *const fn (GameStatePtr, Config) void = undefined;

/// Pointer to the game tick function.
var gameTick: *const fn (GameStatePtr) void = undefined;

/// Pointer to the game draw function.
var gameDraw: *const fn (GameStatePtr) void = undefined;

/// Pointer to the game deinitialization function.
var gameDeinit: *const fn (GameStatePtr) void = undefined;
