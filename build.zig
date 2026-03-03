const std = @import("std");
const rlz = @import("raylib-zig");

pub const LibName = "game-boy";
pub const LibVersion = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };
pub const ChipLibName = "gb";
pub const ChipVersion = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };
pub const ExeName = "game-boy";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const hotReload = if (target.query.os_tag == .emscripten) false else b.option(bool, "hotReload", "Build the game as a dll to allow for automatic hot-reload of code") orelse true;
    var options = b.addOptions();
    options.addOption(bool, "hotReload", hotReload);

    var raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
    });
    const raylib = raylib_dep.module("raylib");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const game_boy_module = b.addModule(ChipLibName, .{
        .root_source_file = b.path("src/libs/game-boy.zig"),
        .target = target,
        .optimize = optimize,
    });

    const chip_lib = b.addLibrary(.{
        .name = ChipLibName,
        .root_module = game_boy_module,
        .version = ChipVersion,
        .linkage = .dynamic,
    });
    chip_lib.root_module.addImport("game-boy", game_boy_module);
    b.installArtifact(chip_lib);
    // Raylib for native builds
    const raylib_dyn = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        .linkage = .dynamic,
    });

    const raylib_d = raylib_dyn.module("raylib"); // main raylib module
    const raygui = raylib_dyn.module("raygui"); // raygui module
    const raylib_lib = raylib_dyn.artifact("raylib"); // raylib C library
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("gb", game_boy_module);
    exe_mod.addOptions("config", options);

    exe_mod.addImport("raylib", raylib_d);

    const exe = b.addExecutable(.{
        .name = "cribbage",
        .root_module = exe_mod,
    });
    exe.linkLibrary(raylib_lib);
    exe.root_module.addImport("raygui", raygui);
    b.installArtifact(exe);

    if (hotReload) {
        const lib = b.addLibrary(.{
            .name = "cribbage",
            .linkage = .dynamic,
            .root_module = b.addModule(
                "state",
                .{
                    .root_source_file = b.path("src/game.zig"),
                    .target = target,
                    .optimize = optimize,
                },
            ),
        });

        b.installArtifact(lib);
        lib.linkLibrary(raylib_artifact);
        lib.root_module.addImport("gb", game_boy_module);
        lib.root_module.addImport("raylib", raylib);
        lib.root_module.addImport("raygui", raygui);
    }

    // build docs
    const docs = b.step("docs", "Build documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = chip_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs.dependOn(&install_docs.step);

    //Chip tests
    const chip_test = b.addTest(.{
        .name = "chip",
        .root_module = game_boy_module,
    });
    const chip_test_step = b.step("test_chip", "Run chip tests");
    chip_test_step.dependOn(&chip_test.step);

    const tests_step = b.step("test", "Run all tests");
    tests_step.dependOn(chip_test_step);
}
