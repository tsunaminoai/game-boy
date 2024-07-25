const std = @import("std");
const rlz = @import("raylib-zig");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const game_only = b.option(
        bool,
        "game_only",
        "only build the game shared library",
    ) orelse false;

    const raylib_dep = b.dependency("raylib-zig", .{
        .target = target,
        .optimize = optimize,
        .shared = true,
    });

    const raylib = raylib_dep.module("raylib");
    const raygui = raylib_dep.module("raygui");
    const raylib_artifact = raylib_dep.artifact("raylib");

    const LibName = "gb";
    const ExeName = "game-boy";

    //web exports are completely separate
    if (target.query.os_tag == .emscripten) {
        const exe_lib = rlz.emcc.compileForEmscripten(b, ExeName, "src/main.zig", target, optimize);
        //FIXME: There is a bug in emsc for 0.13.0 https://github.com/Not-Nik/raylib-zig/issues/108 upstream

        exe_lib.linkLibrary(raylib_artifact);
        exe_lib.root_module.addImport("raylib", raylib);

        // Note that raylib itself is not actually added to the exe_lib output file, so it also needs to be linked with emscripten.
        const link_step = try rlz.emcc.linkWithEmscripten(b, &[_]*std.Build.Step.Compile{ exe_lib, raylib_artifact });

        b.getInstallStep().dependOn(&link_step.step);
        const run_step = try rlz.emcc.emscriptenRunStep(b);
        run_step.step.dependOn(&link_step.step);
        const run_option = b.step("run", "Run " ++ ExeName);
        run_option.dependOn(&run_step.step);
        return;
    }

    const game_lib = b.addSharedLibrary(.{
        .name = LibName,
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .version = .{ .major = 1, .minor = 0, .patch = 0 },
    });
    game_lib.linkLibrary(raylib_artifact);
    game_lib.root_module.addImport("raylib", raylib);
    game_lib.root_module.addImport("raygui", raygui);
    b.installArtifact(game_lib);

    if (!game_only) {
        const exe = b.addExecutable(.{
            .name = ExeName,
            .root_source_file = b.path("src/main.zig"),
            .optimize = optimize,
            .target = target,
        });

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
        .source_dir = game_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    docs.dependOn(&install_docs.step);
}
