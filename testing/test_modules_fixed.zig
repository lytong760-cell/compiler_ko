//!/usr/bin/env zig

const std = @import("std");

fn runCheckSymbols(lib_path: [:0]const u8, sym_name: [:0]const u8) !void {
    const check_exe = "zig-out/bin/check_symbols";
    var args = std.ArrayList([]const u8).init(std.testing.allocator);
    defer args.deinit();
    try args.append(check_exe);
    try args.append(lib_path);
    try args.append(sym_name);

    const result = std.process.Child.run(.{
        .argv = args.items,
        .stderr = .Ignore,
        .stdout = .Ignore,
    }) catch |err| {
        std.debug.print("Failed to run check_symbols: {}\n", .{err});
        return error.CouldNotExecuteCheck;
    };

    if (result.term != .Exited) {
        return error.CouldNotExecuteCheck;
    }

    if (result.term.Exited != 0) {
        return error.SymbolNotFound;
    }
}

fn lookup(comptime T: type, lib_path: [:0]const u8, sym_name: [:0]const u8) !T {
    try runCheckSymbols(lib_path, sym_name);
    
    const lib = try std.DynLib.open(lib_path);
    defer lib.close();

    const func_ptr = lib.lookup(T, sym_name) orelse return error.SymbolNotFound;
    return @ptrCast(func_ptr);
}

test "ko_os: ko_file_exists(true) on existing file" {
    const ko_file_exists = try lookup(?*const fn ([*:0]const u8) callconv(.c) c_int, "zig-out/lib/libko_os.so", "ko_file_exists");
    const result = ko_file_exists.?("examples/simple.ko");
    try std.testing.expectEqual(@as(c_int, 1), result);
}

test "ko_os: ko_file_exists(false) on non-existing file" {
    const ko_file_exists = try lookup(?*const fn ([*:0]const u8) callconv(.c) c_int, "zig-out/lib/libko_os.so", "ko_file_exists");
    const result = ko_file_exists.?("nope");
    try std.testing.expectEqual(@as(c_int, 0), result);
}

test "ko_os: ko_file_size matches stat for existing file" {
    const ko_file_size = try lookup(?*const fn ([*:0]const u8) callconv(.c) i64, "zig-out/lib/libko_os.so", "ko_file_size");
    const size = ko_file_size.?("examples/simple.ko");
    try std.testing.expect(size >= 0);

    const stat = std.Io.Dir.cwd().statFile(std.testing.io, "examples/simple.ko", .{}) catch return error.OsFileNotFound;
    try std.testing.expectEqual(@as(i64, @intCast(stat.size)), size);
}

test "ko_random: reproducibility via seed" {
    const ko_random_seed = try lookup(?*const fn (i64) callconv(.c) void, "zig-out/lib/libko_random.so", "ko_random_seed");
    const ko_random_int = try lookup(?*const fn () callconv(.c) i64, "zig-out/lib/libko_random.so", "ko_random_int");

    ko_random_seed.?(12345);
    const a1 = ko_random_int.?();
    const a2 = ko_random_int.?();

    ko_random_seed.?(12345);
    const b1 = ko_random_int.?();
    const b2 = ko_random_int.?();

    try std.testing.expectEqual(a1, b1);
    try std.testing.expectEqual(a2, b2);
}

test "ko_random: seed uniqueness produces different sequences" {
    const ko_random_seed = try lookup(?*const fn (i64) callconv(.c) void, "zig-out/lib/libko_random.so", "ko_random_seed");
    const ko_random_int = try lookup(?*const fn () callconv(.c) i64, "zig-out/lib/libko_random.so", "ko_random_int");

    ko_random_seed.?(0);
    const x1 = ko_random_int.?();
    ko_random_seed.?(1);
    const x2 = ko_random_int.?();
    try std.testing.expect(x1 != x2);
}

test "ko_random: ko_random_float in [0, 1)" {
    const ko_random_seed = try lookup(?*const fn (i64) callconv(.c) void, "zig-out/lib/libko_random.so", "ko_random_seed");
    const ko_random_float = try lookup(?*const fn () callconv(.c) f64, "zig-out/lib/libko_random.so", "ko_random_float");

    ko_random_seed.?(42);
    for (0..100) |_| {
        const f = ko_random_float.?();
        try std.testing.expect(f >= 0.0);
        try std.testing.expect(f < 1.0);
    }
}

test "ko_random: ko_random_bytes fills buffer" {
    const ko_random_seed = try lookup(?*const fn (i64) callconv(.c) void, "zig-out/lib/libko_random.so", "ko_random_seed");
    const ko_random_bytes = try lookup(?*const fn (i64, [*]u8) callconv(.c) void, "zig-out/lib/libko_random.so", "ko_random_bytes");

    const len: i64 = 64;
    const buf = std.testing.allocator.alloc(u8, @intCast(len)) catch return error.NoMemory;
    defer std.testing.allocator.free(buf);
    ko_random_seed.?(999);
    ko_random_bytes.?(len, buf.ptr);

    var all_zero = true;
    for (buf) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero);
}

test "ko_website: ko_validate_url rejects dangerous URL" {
    const ko_validate_url = try lookup(?*const fn ([*:0]const u8) callconv(.c) ?*const u8, "zig-out/lib/libko_website.so", "ko_validate_url");
    const result = ko_validate_url.?("file:///etc/passwd");
    try std.testing.expect(result != null);
}

test "ko_website: ko_validate_url accepts safe URL" {
    const ko_validate_url = try lookup(?*const fn ([*:0]const u8) callconv(.c) ?*const u8, "zig-out/lib/libko_website.so", "ko_validate_url");
    const result = ko_validate_url.?("https://example.com/path");
    try std.testing.expect(result == null);
}

test "ko_website: ko_url_encode returns non-null" {
    const ko_url_encode = try lookup(?*const fn ([*:0]const u8) callconv(.c) ?*const u8, "zig-out/lib/libko_website.so", "ko_url_encode");
    const result = ko_url_encode.?("hello world");
    try std.testing.expect(result != null);
}

test "ko_loop: resolve ko_loop_optimize_for" {
    const f = try lookup(?*const fn (?*anyopaque, [*:0]const u8, i64, i64, i64, u64) callconv(.c) c_int, "zig-out/lib/libko_loop.so", "ko_loop_optimize_for");
    try std.testing.expect(f != null);
}
