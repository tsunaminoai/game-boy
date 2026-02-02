const std = @import("std");
const rlz = @import("raylib_zig");

pub const LibName = "game-boy";
pub const LibVersion = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };
pub const ChipLibName = "gb";
pub const ChipVersion = std.SemanticVersion{ .major = 0, .minor = 1, .patch = 0 };
pub const ExeName = "game-boy";

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const game_only = b.option(
        bool,
        "game_only",
        "only build the game shared library",
    ) orelse false;

    const raylib_dep = b.dependency("raylib_zig", .{
        .target = target,
        .optimize = optimize,
        // .shared = true,
        .linux_display_backend = .X11,
    });

    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
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
    });
    chip_lib.root_module.addImport("game-boy", game_boy_module);
    b.installArtifact(chip_lib);

    const game_lib = b.addLibrary(.{
        .name = LibName,
        .root_module = b.addModule(LibName, .{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .version = LibVersion,
    });
    game_lib.linkLibrary(chip_lib);
    game_lib.root_module.addImport(ChipLibName, game_boy_module);
    game_lib.linkLibrary(raylib_artifact);
    game_lib.root_module.addImport("raylib", raylib);
    game_lib.root_module.addImport("raygui", raygui);
    b.installArtifact(game_lib);

    const exe = b.addExecutable(.{
        .name = ExeName,
        .root_module = b.addModule(ExeName, .{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    if (!game_only) {
        exe.linkLibrary(raylib_artifact);
        exe.root_module.addImport("raylib", raylib);

        const run_cmd = b.addRunArtifact(exe);
        const run_step = b.step("run", "Run " ++ ExeName);
        run_step.dependOn(&run_cmd.step);

        b.installArtifact(exe);
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

    //web exports are completely separate
    if (target.query.os_tag == .emscripten) {
        const emsdk = rlz.emsdk;
        const wasm = b.addLibrary(.{
            .name = ExeName,
            .root_module = exe.root_module,
        });

        const install_dir: std.Build.InstallDir = .{ .custom = "web" };
        const emcc_flags = emsdk.emccDefaultFlags(b.allocator, .{ .optimize = optimize });
        const emcc_settings = emsdk.emccDefaultSettings(b.allocator, .{ .optimize = optimize });

        const emcc_step = emsdk.emccStep(b, raylib_artifact, wasm, .{
            .optimize = optimize,
            .flags = emcc_flags,
            .settings = emcc_settings,
            .install_dir = install_dir,
        });
        b.getInstallStep().dependOn(emcc_step);

        const html_filename = try std.fmt.allocPrint(b.allocator, "{s}.html", .{wasm.name});
        const emrun_step = emsdk.emrunStep(
            b,
            b.getInstallPath(install_dir, html_filename),
            &.{},
        );

        emrun_step.dependOn(emcc_step);
        // run_step.dependOn(emrun_step);
    }
}
