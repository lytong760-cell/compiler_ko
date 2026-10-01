const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const src_module = b.createModule(.{
        .root_source_file = b.path("src/testing_imports.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_root_module = b.createModule(.{
        .root_source_file = b.path("testing/test_lexer_extended.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "src", .module = src_module },
        },
    });
    const test_exe = b.addTest(.{
        .root_module = test_root_module,
    });
    b.installArtifact(test_exe);
}
