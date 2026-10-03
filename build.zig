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
        const mod_module = b.createModule(.{
            .root_source_file = b.path(mod.source),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        mod_module.addIncludePath(b.path(mod.include_dir));
        const lib = b.addLibrary(.{
            .name = mod.name,
            .root_module = mod_module,
            .linkage = .dynamic,
        });
        b.installArtifact(lib);
    }

    // --- Build Loop.cpp as shared library ---
    // Loop.cpp có extern "C" (dòng 278) và main() được bảo vệ #ifndef KO_LOOP_NO_MAIN.
    // Định nghĩa KO_LOOP_NO_MAIN để loại bỏ main(), build .so với symbol ko_loop_*.
    const loop_module = b.createModule(.{
        .root_source_file = b.path("src/Loop.cpp"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    loop_module.addCMacro("KO_LOOP_NO_MAIN", "1");
    const loop_lib = b.addLibrary(.{
        .name = "ko_loop",
        .root_module = loop_module,
        .linkage = .dynamic,
    });
    b.installArtifact(loop_lib);
}
