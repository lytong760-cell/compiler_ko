const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ko",
        .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = "src/main.zig" } },
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the compiler");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run all tests");
    const files = [_][]const u8{
        "src/test_3600.zig",
        "src/test_harness.zig",
        "src/test_lexer_extended.zig",
        "src/test_parser_extended.zig",
    };
    inline for (files) |file| {
        const test_exe = b.addTest(.{
            .root_source_file = .{ .src_path = .{ .owner = b, .sub_path = file } },
            .target = target,
            .optimize = optimize,
        });
        test_exe.addModule("root", exe.root_module);
        const test_run = b.addRunArtifact(test_exe);
        test_step.dependOn(&test_run.step);
    }
}
