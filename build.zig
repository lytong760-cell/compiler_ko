const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ko",
        .root_module = b.createModule(.{
            .source_file = .{ .path = "src/main.zig" },
        }),
        .target = target,
        .optimize = optimize,
    });

    exe.addModule("ko", b.createModule(.{
        .source_file = .{ .path = "src/ko.zig" },
    }));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the compiler");
    run_step.dependOn(&run_cmd.step);
}
