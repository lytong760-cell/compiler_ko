const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "ko",
        .root_module = root_module,
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
        // "testing/test_harness.zig",
        "testing/test_3600.zig",
        "testing/test_lexer_extended.zig",
        "testing/test_parser_extended.zig",
    };

    const src_module = b.createModule(.{
        .root_source_file = b.path("src/testing_imports.zig"),
        .target = target,
        .optimize = optimize,
    });

    inline for (files) |file| {
        const test_root_module = b.createModule(.{
            .root_source_file = b.path(file),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "src", .module = src_module },
            },
        });
        const test_exe = b.addTest(.{
            .root_module = test_root_module,
        });
        const test_run = b.addRunArtifact(test_exe);
        test_step.dependOn(&test_run.step);
    }

    // --- Build C modules as shared libraries ---
    // Build trực tiếp từ root build.zig thay vì addSubdirectory vì:
    // (1) src/module/*/build.zig dùng addSharedLibrary (API không tồn tại trong Zig 0.16),
    // (2) chúng có guard b.graph.root_options.path.source.path không chuẩn,
    // (3) chúng tạo step "run"/"test" trùng với root.
    // Zig 0.16 dùng b.addLibrary(.{ .linkage = .dynamic }) + b.createModule().
    const c_modules = [_]struct { name: []const u8, source: []const u8, include_dir: []const u8 }{
        .{ .name = "ko_os",      .source = "src/module/Os/Os.c",      .include_dir = "src/module/Os" },
        .{ .name = "ko_random",  .source = "src/module/Random/Random.c",  .include_dir = "src/module/Random" },
        .{ .name = "ko_website", .source = "src/module/Website/Website.c", .include_dir = "src/module/Website" },
    };

    for (c_modules) |mod| {
        const lib = b.addLibrary(.{
            .name = mod.name,
            .linkage = .dynamic,
            .root_module = b.createModule(.{
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            }),
        });
        lib.addCSourceFiles(.{
            .files = &.{mod.source},
            .flags = &.{ "-std=c11", "-fPIC", "-I" ++ mod.include_dir },
        });
        lib.linkLibC();
        b.installArtifact(lib);
    }

    const loop_lib = b.addLibrary(.{
        .name = "ko_loop",
        .linkage = .dynamic,
        .root_module = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        }),
    });
    loop_lib.addCMacro("KO_LOOP_NO_MAIN", "1");
    loop_lib.addCSourceFiles(.{
        .files = &.{"src/Loop.cpp"},
        .flags = &.{ "-std=c++17", "-fPIC" },
    });
    loop_lib.linkLibCpp();
    b.installArtifact(loop_lib);
}
