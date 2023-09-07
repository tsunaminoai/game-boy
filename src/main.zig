const std = @import("std");
const CPU = @import("./libs/cpu/cpu.zig").CPU;

// raylib-zig (c) Nikolas Wipper 2023

const rl = @import("raylib");
const rlm = @import("raylib-math");

const State = struct {
    running: bool,
    clockrate_hz: u8,
};

var FONT: rl.Font = undefined;

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

    FONT = rl.loadFont("./assets/fonts/FreeSans.ttf");

    var cpu = CPU{};
    try loadProgram("rom.bin", &cpu);

    rl.setTargetFPS(targetFPS); // Set our game to run at 60 frames-per-second
    var frameCounter: i32 = 0;
    //--------------------------------------------------------------------------------------

    // Main game loop
    while (!rl.windowShouldClose()) { // Detect window close button or ESC key
        // Update
        //----------------------------------------------------------------------------------
        if (@mod(frameCounter, targetFPS) == 0) {
            if (state.running) {
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
        rl.drawTextEx(FONT, rl.textFormat("Running: %d at %d Hz", .{ state.running, state.clockrate_hz }), rl.Vector2.init(10, 10), 20, 2, rl.Color.sky_blue);

        drawCPU(&cpu, rl.Vector2.init(10, 50));
        frameCounter += 1;
    }
    //----------------------------------------------------------------------------------

}

const R = @import("libs/cpu/types.zig").RegisterName;

fn drawRegister(cpu: *CPU, register: R, position: rl.Vector2) rl.Vector2 {
    const height: i32 = 30;
    const width: i32 = 80;
    const color = rl.Color.maroon;
    const labelOffset = rlm.vector2Add(position, rlm.vector2Scale(rlm.vector2One(), 3));
    const valueOffset = rlm.vector2Add(position, rl.Vector2.init(25, 5));

    const value = cpu.ReadRegister(register);
    const regStr = register.str().ptr;

    // make box
    rl.drawRectangleLinesEx(rl.Rectangle.init(position.x, position.y, width, height), 2, color);

    // draw label
    rl.drawTextEx(FONT, rl.textFormat("%s", .{regStr}), labelOffset, 12, 2, color);

    // draw value
    rl.drawTextEx(FONT, rl.textFormat("%02x", .{value}), valueOffset, 16, 2, rl.Color.violet);

    // return how much space we took up
    return rl.Vector2.init(width, height);
}

fn drawFlags(cpu: *CPU, position: rl.Vector2) void {
    const height: i32 = 30;
    const width: i32 = 100;
    var labelOffset = rlm.vector2Add(rl.Vector2.init(5, 5), position);
    const fontSize = 18;
    const colorFalse = rl.Color.black;
    const colorTrue = rl.Color.green;
    const spacingAddition: f32 = @floatFromInt(rl.measureText("W ", fontSize));

    rl.drawRectangleLinesEx(rl.Rectangle.init(position.x, position.y, width, height), 2, rl.Color.black);
    rl.drawTextEx(FONT, "Z ", labelOffset, fontSize, 2, (if (cpu.flags.zero) colorTrue else colorFalse));
    labelOffset.x += spacingAddition;
    rl.drawTextEx(FONT, "S ", labelOffset, fontSize, 2, (if (cpu.flags.subtraction) colorTrue else colorFalse));
    labelOffset.x += spacingAddition;
    rl.drawTextEx(FONT, "H ", labelOffset, fontSize, 2, (if (cpu.flags.carry) colorTrue else colorFalse));
    labelOffset.x += spacingAddition;
    rl.drawTextEx(FONT, "C ", labelOffset, fontSize, 2, (if (cpu.flags.halfCarry) colorTrue else colorFalse));
    labelOffset.x += spacingAddition;
}

fn drawStack(cpu: *CPU, position: rl.Vector2) void {
    var stackPtrOffset: u16 = 0xFFFE;
    const SP = cpu.ReadRegister(R.SP);
    var labelOffset = position;
    const fontSize = 16;
    for (SP..stackPtrOffset) |i| {
        rl.drawTextEx(FONT, rl.textFormat("%04x: %04x", .{ stackPtrOffset - i, cpu.ReadMemory(@as(u16, @intCast(i)), 2) }), labelOffset, fontSize, 2, rl.Color.sky_blue);

        labelOffset.y += fontSize;
    }
}

fn drawCPU(cpu: *CPU, position: rl.Vector2) void {
    const fontHeight = 16;
    var currentWritingPosition = position;

    rl.drawTextEx(FONT, rl.textFormat("Ticks: %02d", .{cpu.ticks}), currentWritingPosition, fontHeight, 2, rl.Color.sky_blue);
    currentWritingPosition.y += fontHeight;
    rl.drawTextEx(FONT, rl.textFormat("PC: %02x", .{cpu.programCounter}), currentWritingPosition, fontHeight, 2, rl.Color.sky_blue);
    currentWritingPosition.y += fontHeight;
    rl.drawTextEx(FONT, rl.textFormat("Ins: %02x", .{cpu.currentIntruction}), currentWritingPosition, fontHeight, 2, rl.Color.sky_blue);
    currentWritingPosition.y += fontHeight;

    //draw registers
    inline for (@typeInfo(R).Enum.fields) |f| {
        var tmp = drawRegister(cpu, @as(R, @enumFromInt(f.value)), currentWritingPosition);
        currentWritingPosition.y += tmp.y + 5;
    }

    drawStack(cpu, currentWritingPosition);
    currentWritingPosition = position;
    currentWritingPosition.x += 100;
    drawFlags(cpu, currentWritingPosition);

    currentWritingPosition.y += 30;
    const m1 = drawMemory(cpu, currentWritingPosition, 0x0000, 0x0FFF, 128, 5, rl.Color.magenta);
    currentWritingPosition.y += m1.height + 30;
    const m2 = drawMemory(cpu, currentWritingPosition, 0x8000, 0x8FFF, 128, 5, rl.Color.lime);
    currentWritingPosition.y += m2.height + 30;
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

fn drawMemory(cpu: *CPU, position: rl.Vector2, start: u16, end: u16, perRow: u16, size: u16, color: rl.Color) rl.Rectangle {
    var tint: rl.Color = undefined;
    const sizePerBlock: f32 = @as(f32, @floatFromInt(size));
    const sizePerRow: f32 = @as(f32, @floatFromInt(perRow));
    var block = rl.Rectangle.init(position.x, position.y, sizePerBlock, sizePerBlock);
    const len = end - start;

    for (0..len) |i| {
        const addr = i + start;
        const val: u8 = @as(u8, @intCast(cpu.ReadMemory(@as(u16, @intCast(addr)), 1)));
        tint = rl.colorTint(rl.Color.init(val, val, val, 255), color);
        if (cpu.programCounter == addr) {
            tint = rl.Color.green;
        }
        //todo: figure out why theres a block on the end of the first row
        rl.drawRectangleRec(block, tint);
        block.x += sizePerBlock;
        if (i != 0 and @mod(i, perRow) == 0) {
            block.x = position.x;
            block.y += sizePerBlock;
        }
    }

    return rl.Rectangle.init(position.x, position.y, sizePerRow * sizePerBlock, @as(f32, @floatFromInt(@mod(len, perRow))) + 1.0);
}

test {
    std.testing.refAllDecls(@This());
}
