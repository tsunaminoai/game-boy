const s = @import("game.zig");
const std = @import("std");
const builtIn = @import("builtin");

const run_t = @TypeOf(&runStub);
pub fn runStub(_: *s) callconv(.c) void {}

var curr_lib: std.DynLib = undefined;

var oldModificationTime: i128 = 0;

const LIB_SRC_DIR = "zig-out/lib/";
const EXE_SRC_DIR = "zig-out/bin/";
const LIB_DEST_DIR = "libs/";
const LIB_NAME = if (builtIn.target.os.tag == .windows) "gameboy.dll" else "libgameboy.so";
const LIB_SRC = if (builtIn.target.os.tag == .windows) EXE_SRC_DIR ++ LIB_NAME else LIB_SRC_DIR ++ LIB_NAME;

const CopyFile = struct { src: []const u8, dst: []const u8 };
const FILES_TO_COPY = if (builtIn.target.os.tag == .windows)
    [_]CopyFile{
        .{ .src = EXE_SRC_DIR ++ "gameboy.pdb", .dst = LIB_DEST_DIR ++ "gameboy.pdb" },
        .{ .src = LIB_SRC, .dst = LIB_DEST_DIR ++ LIB_NAME },
        .{ .src = LIB_SRC_DIR ++ "gameboy.lib", .dst = LIB_DEST_DIR ++ "gameboy.lib" },
    }
else
    [_]CopyFile{
        .{ .src = LIB_SRC, .dst = LIB_DEST_DIR ++ LIB_NAME },
    };

pub fn tryToReload(run: *run_t) void {
    const stat = std.fs.Dir.statFile(std.fs.cwd(), LIB_SRC) catch return;
    if (stat.mtime > oldModificationTime) {
        reloadCode(true, run) catch unreachable;
        oldModificationTime = stat.mtime;
    }
}

pub fn reloadCode(closeDll: bool, run: *run_t) !void {
    if (closeDll) curr_lib.close();

    for (FILES_TO_COPY) |paths| {
        std.fs.Dir.copyFile(std.fs.cwd(), paths.src, std.fs.cwd(), paths.dst, .{}) catch |err| {
            std.debug.print("****Could not copy {s} to {s}\n", .{ paths.src, paths.dst });
            return err;
        };
    }
    const out_path = LIB_DEST_DIR ++ LIB_NAME;

    curr_lib = try std.DynLib.open(out_path);
    std.debug.print("***reloaded dll: {s}\n", .{out_path});
    if (curr_lib.lookup(run_t, "run")) |cl| {
        run.* = cl;
    } else {
        std.debug.print("****Could not open DLL: {s}\n", .{out_path});
        return error.CouldNotOpenDLL;
    }
}

pub fn createLibraryDir() !void {
    var file = std.fs.cwd().openDir(LIB_DEST_DIR, .{});
    if (file) |*f| {
        f.close();
    } else |_| {
        try std.fs.Dir.makeDir(std.fs.cwd(), LIB_DEST_DIR);
    }
}
