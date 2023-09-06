const std = @import("std");
const CPU = @import("./libs/cpu/cpu.zig").CPU;

// raylib-zig (c) Nikolas Wipper 2023

const rl = @import("raylib");

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 800;
    const screenHeight = 450;

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    var cpu = CPU{};
    try loadProgram("rom.bin", &cpu);

    rl.setTargetFPS(1); // Set our game to run at 60 frames-per-second
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        cpu.Tick();
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.dark_gray);

        rl.drawText(rl.textFormat("PC: %02x", .{ cpu.programCounter }), 200, 160, 40, rl.Color.blue);
        //----------------------------------------------------------------------------------
    }
}

fn loadProgram(path: []const u8, cpu: *CPU) !void {
    std.debug.print("Loading '{s}'", .{path});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const data = try std.fs.cwd().readFileAlloc(allocator, path, 64000);
    defer allocator.free(data);

    var i: u16 = 0;
    while (i < data.len) : (i += 1) {
        cpu.WriteMemory(i, @as(u16, data[i]), 1);
    }
}

test {
    std.testing.refAllDecls(@This());
}
