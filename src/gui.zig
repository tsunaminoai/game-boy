const std = @import("std");
const Game = @import("game.zig");
const rl = @import("raylib");
const gui = @import("raygui");
const APU = @import("gb").Device.Audio;
const CPU = @import("gb").Device.CPU;

const GUI = @This();

state: *Game = undefined,
picker_edit: bool = false,
picker_active: i32 = 0,
rom_list: ?[][]u8 = null,

var alloc: std.mem.Allocator = undefined;
var mem = [_]u8{0} ** 0x30;
var registers = APU.SoundRegisters.init(&mem);
var gba: APU = undefined;

/// Initializes a new GUI instance.
///
/// This function takes an allocator and a pointer to a `Game` struct.
/// It returns a pointer to the newly created `GUI` instance.
/// This function can return an error if the allocation of the `GUI` instance fails.
pub fn init(a: std.mem.Allocator, game: *Game) !*GUI {
    alloc = a;
    const self = try alloc.create(GUI);
    errdefer self.deinit();
    gba = APU.init(registers);
    self.* = .{
        .state = game,
        .rom_list = try romList(alloc),
    };
    gui.guiLoadStyle("style_bluish.rgs");
    return self;
}

pub fn deinit(self: *GUI) void {
    if (self.rom_list) |list| alloc.free(list);
    alloc.destroy(self);
}

/// Draws the GUI for the game.
pub fn render(self: *GUI) void {
    _ = gui.guiPanel(
        rl.Rectangle.init(5, 5, 1190, 100),
        "Controls",
    );

    if (0 != gui.guiLabelButton(
        rl.Rectangle.init(10, 35, 50, 20),
        if (self.state.audio.muted) "#122#Mute" else "#122#Unmute",
    )) {
        self.state.audio.mute();
    }
    self.filePicker(
        rl.Rectangle.init(10, 60, 200, 20),
        "Load ROM",
    );
    self.joyPad(
        rl.Rectangle.init(210, 35, 100, 100),
    );
    self.regsiters(
        rl.Rectangle.init(400, 35, 200, 100),
        "Registers",
    );

    if (0 != gui.guiLabelButton(
        rl.Rectangle.init(600, 35, 35, 12),
        if (self.state.running) "#132#Stop" else "#131#Start",
    ))
        self.state.startStop();

    self.flags(
        rl.Rectangle.init(600, 80, 100, 12),
        "Flags",
    );
    // self.audio(
    //     rl.Rectangle.init(self.state.screen.x + 10, 110, 380, 600),
    //     "Audio",
    // );
}

fn regsiters(self: *GUI, bounds: rl.Rectangle, label: []const u8) void {
    _ = label; // autofix
    const reg_size = rl.Vector2.init(60, 12);
    inline for (std.meta.fields(CPU.RegisterID), 0..) |r, i| {
        const l = rl.Rectangle.init(
            bounds.x + reg_size.x * @as(f32, @floatFromInt(i % 3)),
            bounds.y + reg_size.y * @as(f32, @floatFromInt(i / 3)),
            reg_size.x,
            reg_size.y,
        );
        const reg_label = if (r.value < @intFromEnum(CPU.RegisterID.A)) r.name[0..2] else " " ++ r.name[0..2];
        const reg_fmt = if ((r.value < @intFromEnum(CPU.RegisterID.A))) "%s: %04X" else "%s: %02X";
        _ = gui.guiLabel(l, rl.textFormat(
            reg_fmt,
            .{
                reg_label,
                self.state.chip.cpu.readReg(@enumFromInt(r.value)),
            },
        ));
    }
}

fn flags(self: *GUI, bounds: rl.Rectangle, label: []const u8) void {
    _ = label; // autofix
    const flag_size = rl.Vector2.init(60, 12);

    inline for (std.meta.fields(CPU.Flags), 0..) |f, i| {
        const icon = if (@field(self.state.chip.cpu.flags, f.name)) "#212#" else "#213#";
        const fb = rl.Rectangle.init(
            bounds.x + flag_size.x * @as(f32, @floatFromInt(i)),
            bounds.y,
            flag_size.x,
            flag_size.y,
        );

        _ = gui.guiLabel(fb, icon ++ f.name);
    }
}

/// Displays a file picker GUI element.
///
/// This function takes a GUI object, bounds for the file picker, and a label for the file picker.
/// It retrieves a list of files using `getFileList` and displays them in a dropdown box.
/// The selected file is loaded into the CHIP-8 emulator using `loadRomFromPath`.
///
/// Parameters:
/// - `self`: A pointer to the GUI object.
/// - `bounds`: The bounds of the file picker.
/// - `label`: The label for the file picker.
fn filePicker(
    self: *GUI,
    bounds: rl.Rectangle,
    label: []const u8,
) void {
    _ = label; // autofix
    const files = self.getFileList(alloc) catch |e| blk: {
        std.log.err("Error getting list\n{}\n", .{e});
        break :blk "Error getting list";
    };
    defer alloc.free(files);
    errdefer alloc.free(files);
    const current = self.picker_active;
    _ = current; // autofix

    // try writer.flush();
    if (0 != gui.guiDropdownBox(
        rl.Rectangle.init(bounds.x, bounds.y, bounds.width - 15, bounds.height),
        @ptrCast(files),
        &self.picker_active,
        self.picker_edit,
    )) self.picker_edit = !self.picker_edit;

    if (0 != gui.guiLabelButton(
        rl.Rectangle.init(bounds.x + bounds.width - 15, bounds.y, 15, bounds.height),
        "#211#",
    )) {
        if (self.rom_list) |list| {
            alloc.free(list);
            self.rom_list = romList(alloc) catch |e| blk: {
                std.log.err("Could not load rom list.\n{}\n", .{e});
                break :blk null;
            };
        }
    }

    // if (current != self.picker_active) {
    //     self.state.chip.loadRomFromPath(self.rom_list[@intCast(self.picker_active)]) catch |e| {
    //         std.log.err("Could not load ROM '{s}': {}s\n", .{ self.rom_list[@intCast(self.picker_active)], e });
    //     };
    // }
}

/// Retrieves a list of file names from the GUI's `rom_list` and returns it as a null-terminated string.
/// The caller is responsible for freeing the memory.
fn getFileList(self: *GUI, allocator: std.mem.Allocator) ![]u8 {
    const strInsert = "{s};";
    var string = std.ArrayList(u8).init(allocator);
    var buf: [1024]u8 = undefined;
    @memset(&buf, 0);
    if (self.rom_list) |list| {
        for (list) |rom| {
            const name = try std.fmt.bufPrint(&buf, strInsert, .{rom});
            try string.appendSlice(name);
        }
    }
    return try string.toOwnedSlice();
}

/// Converts an enum value to the specified type.
///
/// This function is used to convert an enum value to the specified type. It can only be used with enums.
/// If the type is not supported, a compile error will be thrown.
///
/// - Parameters:
///   - as: The type to convert the enum value to.
///   - self: The enum value to be converted.
///
/// - Returns: The converted value of the specified type.
inline fn enumAs(
    as: type,
    self: anytype,
) as {
    if (@typeInfo(@TypeOf(self)) != .Enum) @compileError("enumAs can only be used with enums");

    return switch (@typeInfo(as)) {
        .Int => @as(as, @intFromEnum(self)),
        .Float => @as(as, @floatFromInt(@intFromEnum(self))),
        else => @compileError("Unsupported type for gState"),
    };
}

/// Retrieves a list of ROM files with the ".ch8" extension in the current directory. Caller must free the memory.
///
/// This function uses the provided allocator `a` to allocate memory for the list.
/// It opens the current directory and iterates over its entries, filtering out non-file entries.
/// For each file entry with the ".ch8" extension, it appends the entry name to the list.
/// The resulting list of ROM file names is returned as a slice of owned memory.
fn romList(a: std.mem.Allocator) ![][]u8 {
    var cwd = try std.fs.cwd().openDir(
        "./",
        std.fs.Dir.OpenDirOptions{ .iterate = true },
    );
    var it = cwd.iterate();
    var list = std.ArrayList([]u8).init(a);
    errdefer list.deinit();
    while (try it.next()) |entry| {
        if (entry.kind != .file) {
            continue;
        }
        if (std.mem.endsWith(u8, entry.name, ".bin")) {
            std.debug.print("{s}\n", .{entry.name});
            const name = entry.name;
            const n = try alloc.dupe(u8, name);
            try list.append(n);
        }
    }
    return list.toOwnedSlice();
}

/// audio GUI
pub fn audio(
    self: *GUI,
    bounds: rl.Rectangle,
    label: [:0]const u8,
) void {
    _ = gui.guiPanel(
        bounds,
        label,
    );

    if (0 != gui.guiLabelButton(
        .{ .x = bounds.x + 10, .y = bounds.y + 35, .width = 50, .height = 20 },
        if (self.state.audio.muted) "#122#Mute" else "#122#Unmute",
    )) {
        self.state.audio.mute();
    }

    for (gba.channels, 0..) |ch, i| {
        const icon = switch (ch.conf) {
            .square => gui.guiIconText(122, "S"),
            .wave => gui.guiIconText(122, "W"),
            .noise => gui.guiIconText(122, "N"),
        };
        _ = icon; // autofix

        const y = bounds.y + 60 + 20 * @as(f32, @floatFromInt(i));
        _ = gui.guiLabel(
            .{ .x = bounds.x + 10, .y = y, .width = 50, .height = 20 },
            "Channel",
        );
        _ = gui.guiLabel(
            .{ .x = bounds.x + 60, .y = y, .width = 50, .height = 20 },
            rl.textFormat("#122#%d", .{i}),
        );
        _ = gui.guiLabel(
            .{ .x = bounds.x + 110, .y = y, .width = 50, .height = 20 },
            "Volume",
        );
        _ = gui.guiSliderBar(
            .{ .x = bounds.x + 160, .y = y, .width = 200, .height = 20 },
            "",
            "",
            &dummy,
            0,
            1,
        );
    }

    for (gba.channels, 0..) |ch, i| {
        _ = ch; // autofix
        const y = bounds.y + 60 * 2 + 10 + 110 * @as(f32, @floatFromInt(i));
        // osciloscope
        _ = gui.guiPanel(
            .{ .x = bounds.x + 10, .y = y + 20, .width = 350, .height = 100 },
            rl.textFormat("Channel %d", .{i}),
        );

        // draw osciloscope
        var wave_data: [350]f32 = undefined;
        @memset(&wave_data, 0);
        for (wave_data, 0..) |d, j| {
            _ = d; // autofix
            rl.drawPixel(
                @as(i32, @intFromFloat(bounds.x)) + 10 + @as(i32, @intCast(j)),
                10 + @as(i32, @intFromFloat(y)) + 20 + 50 - @as(i32, @intFromFloat(wave_data[i] * 50)),
                rl.Color.init(255, 255, 255, 255),
            );
        }
    }
}
var dummy: f32 = 0;

pub fn joyPad(self: *GUI, bound: rl.Rectangle) void {
    _ = self; // autofix
    const x = 10 + bound.x;
    const y = bound.y;
    const w = bound.width / 4;
    const h = bound.height / 4;
    const spacing = 10;
    const color = rl.Color.init(255, 255, 255, 255);
    _ = color; // autofix

    const dpad = enum {
        Up,
        Down,
        Left,
        Right,
    };
    inline for (std.meta.fields(dpad), 0..) |b, i| {
        _ = i; // autofix

        const bx = x + (w + spacing) * @as(i32, b.value);
        const by = y;

        _ = gui.guiButton(
            rl.Rectangle.init(bx, by, w, h),
            b.name,
        );
    }

    const buttons = enum {
        A,
        B,
        Start,
        Select,
    };

    inline for (std.meta.fields(buttons), 0..) |b, i| {
        _ = i; // autofix

        const bx = x + (w + spacing) * @as(i32, b.value);
        const by = y + h + spacing;

        _ = gui.guiButton(
            rl.Rectangle.init(bx, by, w, h),
            b.name,
        );
    }
}
