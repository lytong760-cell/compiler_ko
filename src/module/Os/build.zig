const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const enable = b.option(bool, "enable-os", "Enable Os module") orelse true;
    _ = enable;

    const mod_root = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    mod_root.addIncludePath(b.path("."));
    mod_root.addCSourceFiles(.{
        .files = &.{"Os.c"},
        .flags = &.{ "-std=gnu11", "-fPIC", "-D_GNU_SOURCE" },
    });
    const lib = b.addLibrary(.{
        .name = "ko_os",
        .linkage = .dynamic,
        .root_module = mod_root,
    });
    b.installArtifact(lib);
}