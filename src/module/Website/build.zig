const std = @import("std");

pub fn build(b: *std.Build) !void {
    const root_build = b.graph.root_options.path.source.path orelse {
        std.debug.print("Error: This module must be built from the parent project build.zig\n", .{});
        return error.ModuleMustBeBuiltFromParent;
    };
    _ = root_build;
    
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addSharedLibrary(.{
        .name = "Website",
        .root_source_file = b.path("src/module/Website/Website.c"),
        .target = target,
        .optimize = optimize,
    });

    lib.linkLibC();

    b.installArtifact(lib);

    const run_cmd = b.addRunArtifact(lib);
    const run_step = b.step("run", "Run the Website module");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run tests for Website module");
    test_step.dependOn(&run_cmd.step);
}