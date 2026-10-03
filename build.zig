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

    // Collect library artifacts so the test step can depend on them.
    var libs = std.ArrayList(*std.Build.Step.Compile).init(b.allocator);
    defer libs.deinit();

    // --- Build C modules as shared libraries ---
    const c_modules = [_]struct { name: []const u8, source: []const u8, include_dir: []const u8 }{
        .{ .name = "ko_os",      .source = "src/module/Os/Os.c",      .include_dir = "src/module/Os" },
        .{ .name = "ko_random",  .source = "src/module/Random/Random.c",  .include_dir = "src/module/Random" },
        .{ .name = "ko_website", .source = "src/module/Website/Website.c", .include_dir = "src/module/Website" },
    };

    for (c_modules) |mod| {
        const mod_root = b.createModule(.{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        mod_root.addIncludePath(b.path(mod.include_dir));
        mod_root.addCSourceFiles(.{
            .files = &.{mod.source},
            .flags = &.{ "-std=gnu11", "-fPIC", "-D_GNU_SOURCE" },
        });
        const lib = b.addLibrary(.{
            .name = mod.name,
            .linkage = .dynamic,
            .root_module = mod_root,
        });
        b.installArtifact(lib);
        _ = libs.append(lib) catch @panic("oom");
    }

    const loop_root = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .link_libcpp = true,
    });
    loop_root.addCMacro("KO_LOOP_NO_MAIN", "1");
    loop_root.addCSourceFiles(.{
        .files = &.{"src/Loop.cpp"},
        .flags = &.{ "-std=c++17", "-fPIC" },
    });
    const loop_lib = b.addLibrary(.{
        .name = "ko_loop",
        .linkage = .dynamic,
        .root_module = loop_root,
    });
    b.installArtifact(loop_lib);
    _ = libs.append(loop_lib) catch @panic("oom");

    const test_step = b.step("test", "Run all tests");
    const files = [_][]const u8{
        // "testing/test_harness.zig",
        "testing/test_3600.zig",
        "testing/test_lexer_extended.zig",
        "testing/test_parser_extended.zig",
        "testing/test_modules.zig",
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
        // Libraries must be built (and installed to zig-out/lib) before the test runs.
        for (libs.items) |lib| {
            test_run.step.dependOn(&lib.step);
        }
        test_step.dependOn(&test_run.step);
    }
}
