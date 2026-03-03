const s = @import("game.zig");
const hotReload = @import("config").hotReload;
const rd = if (hotReload) @import("hotreload.zig") else undefined;
const gameboy = @import("gb");
const std = @import("std");

var run: *const fn (*s) callconv(.c) void =
    if (hotReload) rd.runStub else s.run;

pub fn main() !void {
    // const screenWidth = 1024;
    // const screenHeight = 768;

    if (hotReload) {
        try rd.createLibraryDir();
        try rd.reloadCode(false, &run);
    }
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    const app = try s.init(
        alloc,
    );
    defer app.deinit();

    while (!s.shouldClose()) {
        if (hotReload) {
            rd.tryToReload(&run);
        }
        run(app);

        // updateAndRender(&uiState);
    }
}
