const std = @import("std");

/// Runs the native `mod_check` helper, which performs the dlopen/dlsym work so
/// that no Zig code in this file needs to link libdl.
fn runCheck(lib: []const u8, check: []const u8, extra: ?[]const u8) !void {
    var argv: [4][]const u8 = undefined;
    var n: usize = 0;
    argv[n] = "mod_check";
    n += 1;
    argv[n] = lib;
    n += 1;
    argv[n] = check;
    n += 1;
    if (extra) |e| {
        argv[n] = e;
        n += 1;
    }

    const result = try std.process.run(std.testing.allocator, std.testing.io, .{
        .argv = argv[0..n],
    });
    defer std.testing.allocator.free(result.stdout);
    defer std.testing.allocator.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("\ncheck {s} on {s} failed (exit {d})\nstderr: {s}\nstdout: {s}\n", .{ check, lib, code, result.stderr, result.stdout });
                return error.ModuleCheckFailed;
            }
        },
        else => return error.ModuleCheckFailed,
    }
}

test "ko_os: ko_file_exists true on existing file" {
    try runCheck("zig-out/lib/libko_os.so", "file_exists_true", null);
}

test "ko_os: ko_file_exists false on missing file" {
    try runCheck("zig-out/lib/libko_os.so", "file_exists_false", null);
}

test "ko_os: ko_file_size matches real file" {
    try runCheck("zig-out/lib/libko_os.so", "file_size", null);
}

test "ko_os: ko_exec rejects shell injection payload" {
    try runCheck("zig-out/lib/libko_os.so", "exec_rejects_injection", null);
    std.Io.Dir.cwd().access(std.testing.io, "/tmp/ko_should_not_exist", .{}) catch |e| switch (e) {
        error.FileNotFound => {},
        else => return error.UnexpectedFileState,
    };
}

test "ko_os: ko_exec runs a plain command" {
    try runCheck("zig-out/lib/libko_os.so", "exec_simple", null);
}

test "ko_random: same seed reproduces same sequence" {
    try runCheck("zig-out/lib/libko_random.so", "random_reproducible", null);
}

test "ko_random: different seed gives different sequence" {
    try runCheck("zig-out/lib/libko_random.so", "random_differs", null);
}

test "ko_random: float stays within [0,1)" {
    try runCheck("zig-out/lib/libko_random.so", "random_float_range", null);
}

test "ko_loop: ko_loop_engine_create is exported" {
    try runCheck("zig-out/lib/libko_loop.so", "symbol", "ko_loop_engine_create");
}

test "ko_loop: ko_loop_optimize_while is exported" {
    try runCheck("zig-out/lib/libko_loop.so", "symbol", "ko_loop_optimize_while");
}

test "ko_loop: ko_loop_execute_while_loop is exported" {
    try runCheck("zig-out/lib/libko_loop.so", "symbol", "ko_loop_execute_while_loop");
}