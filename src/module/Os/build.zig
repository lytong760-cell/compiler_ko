const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable = b.option(bool, "enable-os", "Enable Os module") orelse true;
    _ = enable;

    const lib = b.addLibrary(.{
        .name = "Os",
        .target = target,
        .optimize = optimize,
        .kind = .shared,
    });

    lib.addCSourceFiles(&.{ "Os.c" }, &.{ "-fPIC" });
    lib.linkLibC();

    b.installArtifact(lib);
}