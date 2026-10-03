const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable = b.option(bool, "enable-os", "Enable Os module") orelse true;
    _ = enable;

    const module = b.createModule(.{
        .root_source_file = null,
        .target = target,
        .optimize = optimize,
    });
    module.addCSourceFiles(.{
        .files = &.{ "Os.c" },
        .flags = &.{ "-fPIC" },
    });

    const lib = b.addLibrary(.{
        .name = "Os",
        .root_module = module,
        .linkage = .dynamic,
    });

    lib.linkLibC();
    b.installArtifact(lib);
}