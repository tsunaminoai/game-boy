const std = @import("std");
const CPU = @import("./libs/cpu/cpu.zig").CPU;

// raylib-zig (c) Nikolas Wipper 2023

const rl = @import("raylib");
const rlm = @import("raylib-math");

const State = struct {
    running: bool,
    clockrate_hz: u8,
};

pub fn main() anyerror!void {
    // Initialization
    //--------------------------------------------------------------------------------------
    const screenWidth = 1200;
    const screenHeight = 900;
    const targetFPS = 60;

    var state = State{
        .running = false,
        .clockrate_hz = 1,
    };

    rl.initWindow(screenWidth, screenHeight, "raylib-zig [core] example - basic window");
    defer rl.closeWindow(); // Close window and OpenGL context

    var cpu = CPU{};
    try loadProgram("rom.bin", &cpu);

    rl.setTargetFPS(targetFPS); // Set our game to run at 60 frames-per-second
    var frameCounter: i32 = 0;
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        if (state.running) {
            if (@mod(frameCounter, targetFPS) == 0) {
                cpu.Tick();
            }
        }
        if (rl.isKeyPressed(rl.KeyboardKey.key_s)) {
            state.running = !state.running;
        }
        //----------------------------------------------------------------------------------

        // Draw
        //----------------------------------------------------------------------------------
        rl.beginDrawing();
        defer rl.endDrawing();

        rl.clearBackground(rl.Color.white);
        rl.drawText(rl.textFormat("Running: %04d", .{state.running}), 10, 0, 20, rl.Color.sky_blue);

        drawCPU(&cpu, rl.Vector2.init(10, 10));
        frameCounter += 1;
    }
    //----------------------------------------------------------------------------------

}

const R = @import("libs/cpu/types.zig").RegisterName;

fn drawRegister(cpu: *CPU, register: R, position: rl.Vector2) rl.Vector2 {
    const height: i32 = 30;
    const width: i32 = 50;
    const color = rl.Color.maroon;
    const labelOffset = rlm.vector2Add(position, rlm.vector2Scale(rlm.vector2One(), 3));
    const valueOffset = rlm.vector2Add(position, rl.Vector2.init(25, 5));

    const value = cpu.ReadRegister(register);
    const regStr = register.str().ptr;

    // make box
    rl.drawRectangleLinesEx(rl.Rectangle.init(position.x, position.y, width, height), 2, color);

    // draw label
    rl.drawTextEx(rl.getFontDefault(), rl.textFormat("%s", .{regStr}), labelOffset, 12, 2, color);

    // draw value
    rl.drawTextEx(rl.getFontDefault(), rl.textFormat("%02x", .{value}), valueOffset, 14, 2, rl.Color.violet);

    // return how much space we took up
    return rl.Vector2.init(width, height);
}

fn drawCPU(cpu: *CPU, position: rl.Vector2) void {
    const fontHeight = 15;
    const font = rl.getFontDefault();
    var currentWritingPosition = position;

    currentWritingPosition.y += fontHeight;
    rl.drawTextEx(font, rl.textFormat("PC: %02x", .{cpu.programCounter}), currentWritingPosition, fontHeight, 2, rl.Color.sky_blue);
    currentWritingPosition.y += fontHeight;

    //draw registers
    inline for (@typeInfo(R).Enum.fields) |f| {
        var tmp = drawRegister(cpu, @as(R, @enumFromInt(f.value)), currentWritingPosition);
        currentWritingPosition.y += tmp.y;
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
