const std = @import("std");
const Game = @import("game.zig");
const rl = @import("raylib");
const gui = @import("raygui");

const GUI = @This();

state: *Game = undefined,
picker_edit: bool = false,
picker_active: i32 = 0,
rom_list: [][]u8 = undefined,

var alloc: std.mem.Allocator = undefined;

/// Initializes a new GUI instance.
///
/// This function takes an allocator and a pointer to a `Game` struct.
/// It returns a pointer to the newly created `GUI` instance.
/// This function can return an error if the allocation of the `GUI` instance fails.
pub fn init(a: std.mem.Allocator, game: *Game) !*GUI {
    alloc = a;
    const self = try alloc.create(GUI);
    self.* = .{
        .state = game,
        .rom_list = try romList(alloc),
    };
    gui.guiLoadStyle("style_bluish.rgs");
    return self;
}

pub fn deinit(self: *GUI) void {
    alloc.free(self.rom_list);
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
    const files: [:0]u8 = self.getFileList(alloc) catch unreachable;
    defer alloc.free(files);
    const current = self.picker_active;
    _ = current; // autofix

    // try writer.flush();
    if (0 != gui.guiDropdownBox(
        bounds,
        files,
        &self.picker_active,
        self.picker_edit,
    )) self.picker_edit = !self.picker_edit;

    // if (current != self.picker_active) {
    //     self.state.chip.loadRomFromPath(self.rom_list[@intCast(self.picker_active)]) catch |e| {
    //         std.log.err("Could not load ROM '{s}': {}s\n", .{ self.rom_list[@intCast(self.picker_active)], e });
    //     };
    // }
}

/// Retrieves a list of file names from the GUI's `rom_list` and returns it as a null-terminated string.
/// The caller is responsible for freeing the memory.
fn getFileList(self: *GUI, allocator: std.mem.Allocator) ![:0]u8 {
    const strInsert = "{s};";
    var string = std.ArrayList(u8).init(allocator);
    var buf: [1024:0]u8 = undefined;
    for (self.rom_list) |rom| {
        const name = std.fmt.bufPrint(&buf, strInsert, .{rom}) catch unreachable;
        try string.appendSlice(name);
    }
    try string.append(0);
    return @ptrCast(try string.toOwnedSlice());
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
