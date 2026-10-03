const std = @import("std");

const dl = @cImport({
    @cInclude("dlfcn.h");
});

const dlopen = @as(*const fn (path: [*:0]const u8, mode: i32) callconv(.c) ?*anyopaque, @ptrCast(&dl.dlopen));
const dlsym = @as(*const fn (handle: ?*anyopaque, sym: [*:0]const u8) callconv(.c) ?*anyopaque, @ptrCast(&dl.dlsym));
const dlclose = @as(*const fn (handle: ?*anyopaque) callconv(.c) i32, @ptrCast(&dl.dlclose));
const RTLD_LAZY: i32 = 1;

const Error = error{
    CouldNotLoadLibrary,
    SymbolNotFound,
    ReproducibilityFailed,
    FloatRangeFailed,
};

const KoFileExistsFn = *const fn (*const u8) callconv(.c) c_int;
const KoRandomSeedFn = *const fn (i64) callconv(.c) void;
const KoRandomIntFn = *const fn () callconv(.c) i64;
const KoRandomFloatFn = *const fn () callconv(.c) f64;
const KoRandomBytesFn = *const fn (i64, [*]u8) callconv(.c) void;
const KoValidateUrlFn = *const fn (*const u8) callconv(.c) ?*const u8;
const KoUrlEncodeFn = *const fn (*const u8) callconv(.c) ?*const u8;

const KoLib = struct {
    fn close(self: *KoLib, allocator: Allocator) void {
        self.lib.close();
        allocator.free(self.path);
    }

    lib: dynamic_library.DynLib,
    path: []const u8,
};

fn loadKoLib(allocator: Allocator, lib_dir: []const u8, lib_name: []const u8) Error!KoLib {
    const path = try std.fs.path.join(allocator, &.{ lib_dir, lib_name });
    const lib = dynamic_library.DynLib.open(path) catch return error.CouldNotLoadLibrary;
    return KoLib{ .path = path, .lib = lib };
}

fn resolveHelper(allocator: Allocator, lib_dir: []const u8, lib_name: []const u8, t: type, sym_name: [:0]const u8) !?t {
    var lib = try loadKoLib(allocator, lib_dir, lib_name);
    defer lib.close(allocator);
    const sym = lib.lib.lookup(t, sym_name);
    return sym;
}

fn resolveOrFail(allocator: Allocator, lib_dir: []const u8, lib_name: []const u8, t: type, sym_name: [:0]const u8) !t {
    const result = resolveHelper(allocator, lib_dir, lib_name, t, sym_name) catch |err| return err;
    if (result) |v| return v;
    return error.SymbolNotFound;
}

test "ko_os: resolve trailing symbol ko_set_cwd" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fn_ptr = try resolveOrFail(a, "zig-out/lib", "libko_os.so", KoFileExistsFn, "ko_set_cwd");
    try std.testing.expect(fn_ptr != null);
}

test "ko_random: resolve trailing symbol ko_random_bytes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fn_ptr = try resolveOrFail(a, "zig-out/lib", "libko_random.so", KoRandomBytesFn, "ko_random_bytes");
    try std.testing.expect(fn_ptr != null);
}

test "ko_website: resolve trailing symbol ko_validate_url" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fn_ptr = try resolveOrFail(a, "zig-out/lib", "libko_website.so", KoValidateUrlFn, "ko_validate_url");
    try std.testing.expect(fn_ptr != null);
}

test "ko_loop: resolve trailing symbol ko_loop_reset_registers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const fn_ptr = try resolveOrFail(a, "zig-out/lib", "libko_loop.so", *const fn (i32) callconv(.c) void, "ko_loop_reset_registers");
    try std.testing.expect(fn_ptr != null);
}

test "ko_os: resolve all 9 ko_* symbols" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const lib_dir = "zig-out/lib";
    const names = [_][]const u8{ "ko_get_env", "ko_set_env", "ko_list_dir", "ko_file_exists", "ko_file_size", "ko_exec", "ko_exit", "ko_get_cwd", "ko_set_cwd" };
    const FnT = *const fn (*const u8) callconv(.c) ?*anyopaque;

    for (names) |name| {
        const path = try std.fs.path.join(a, &.{ lib_dir, "libko_os.so" });
        defer a.free(path);
        const lib = dynamic_library.DynLib.open(path) catch return error.CouldNotLoadLibrary;
        const sym = lib.lookup(FnT, name);
        try std.testing.expect(sym != null, "symbol '{s}' is NULL", .{name});
        lib.close();
    }
}

test "ko_os: ko_file_exists(true) on existing file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_file_exists = try resolveOrFail(a, "zig-out/lib", "libko_os.so", KoFileExistsFn, "ko_file_exists");
    const result = ko_file_exists("examples/simple.ko");
    try std.testing.expectEqual(@as(c_int, 1), result);
}

test "ko_os: ko_file_exists(false) on non-existing file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_file_exists = try resolveOrFail(a, "zig-out/lib", "libko_os.so", KoFileExistsFn, "ko_file_exists");
    const result = ko_file_exists("nope");
    try std.testing.expectEqual(@as(c_int, 0), result);
}

test "ko_os: ko_file_size matches stat for existing file" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_file_size = try resolveOrFail(a, "zig-out/lib", "libko_os.so", *const fn (*const u8) callconv(.c) i64, "ko_file_size");
    const size = ko_file_size("examples/simple.ko");
    try std.testing.expect(size >= 0);

    const path = try std.fs.path.join(a, &.{ "examples", "simple.ko" });
    defer a.free(path);
    const Dir = std.Io.Dir;
    const stat = Dir.cwd().stat(path) catch return error.OsFileNotFound;
    try std.testing.expectEqual(@as(i64, stat.size), size);
}

test "ko_random: reproducibility via seed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_random_seed = try resolveOrFail(a, "zig-out/lib", "libko_random.so", KoRandomSeedFn, "ko_random_seed");
    const ko_random_int = try resolveOrFail(a, "zig-out/lib", "libko_random.so", KoRandomIntFn, "ko_random_int");

    ko_random_seed(12345);
    const a1 = ko_random_int();
    const a2 = ko_random_int();

    ko_random_seed(12345);
    const b1 = ko_random_int();
    const b2 = ko_random_int();

    try std.testing.expectEqual(@as(i64, a1), b1, "reproducibility: first value");
    try std.testing.expectEqual(@as(i64, a2), b2, "reproducibility: second value");
}

test "ko_random: seed uniqueness produces different sequences" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_random_seed = try resolveOrFail(a, "zig-out/lib", "libko_random.so", KoRandomSeedFn, "ko_random_seed");
    const ko_random_int = try resolveOrFail(a, "zig-out/lib", "libko_random.so", KoRandomIntFn, "ko_random_int");

    ko_random_seed(0);
    const x1 = ko_random_int();
    ko_random_seed(1);
    const x2 = ko_random_int();
    try std.testing.expect(x1 != x2, "different seeds should produce different first values");
}

test "ko_random: ko_random_float in [0, 1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_random_seed = try resolveOrFail(a, "zig-out/lib", "libko_random.so", KoRandomSeedFn, "ko_random_seed");
    const ko_random_float = try resolveOrFail(a, "zig-out/lib", "libko_random.so", KoRandomFloatFn, "ko_random_float");

    ko_random_seed(42);
    for (0..100) |_| {
        const f = ko_random_float();
        try std.testing.expect(f >= 0.0, "ko_random_float must be >= 0");
        try std.testing.expect(f < 1.0, "ko_random_float must be < 1");
    }
}

test "ko_random: ko_random_bytes fills buffer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_random_seed = try resolveOrFail(a, "zig-out/lib", "libko_random.so", KoRandomSeedFn, "ko_random_seed");
    const ko_random_bytes = try resolveOrFail(a, "zig-out/lib", "libko_random.so", KoRandomBytesFn, "ko_random_bytes");

    const len: i64 = 64;
    const buf = a.alloc(u8, len) catch return error.NoMemory;
    defer a.free(buf);
    ko_random_seed(999);
    ko_random_bytes(len, buf.ptr);

    var all_zero = true;
    for (buf) |b| {
        if (b != 0) {
            all_zero = false;
            break;
        }
    }
    try std.testing.expect(!all_zero, "ko_random_bytes should not produce all zeros");
}

test "ko_website: resolve all 7 ko_* symbols" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const lib_dir = "zig-out/lib";
    const names = [_][]const u8{ "ko_http_get", "ko_http_post", "ko_http_request", "ko_http_response_free", "ko_url_encode", "ko_url_decode", "ko_validate_url" };
    const FnT = *const fn (*const u8) callconv(.c) ?*anyopaque;

    for (names) |name| {
        const path = try std.fs.path.join(a, &.{ lib_dir, "libko_website.so" });
        defer a.free(path);
        const lib = dynamic_library.DynLib.open(path) catch return error.CouldNotLoadLibrary;
        const sym = lib.lookup(FnT, name);
        try std.testing.expect(sym != null, "symbol '{s}' is NULL", .{name});
        lib.close();
    }
}

test "ko_website: ko_validate_url rejects dangerous URL" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_validate_url = try resolveOrFail(a, "zig-out/lib", "libko_website.so", KoValidateUrlFn, "ko_validate_url");
    const result = ko_validate_url("file:///etc/passwd");
    try std.testing.expect(result != null, "file:// URLs must be rejected");
}

test "ko_website: ko_validate_url accepts safe URL" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_validate_url = try resolveOrFail(a, "zig-out/lib", "libko_website.so", KoValidateUrlFn, "ko_validate_url");
    const result = ko_validate_url("https://example.com/path");
    try std.testing.expect(result == null, "safe URLs must be accepted");
}

test "ko_website: ko_url_encode returns non-null" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const ko_url_encode = try resolveOrFail(a, "zig-out/lib", "libko_website.so", KoUrlEncodeFn, "ko_url_encode");
    const result = ko_url_encode("hello world");
    try std.testing.expect(result != null, "ko_url_encode must not return null");
}

test "ko_loop: resolve all 8 ko_loop_* symbols" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const lib_dir = "zig-out/lib";
    const names = [_][]const u8{ "ko_loop_engine_create", "ko_loop_engine_destroy", "ko_loop_execute_optimized_loop", "ko_loop_execute_while_loop", "ko_loop_get_stats", "ko_loop_optimize_for", "ko_loop_optimize_while", "ko_loop_reset_registers" };
    const FnT = *const fn (i32) callconv(.c) ?*anyopaque;

    for (names) |name| {
        const path = try std.fs.path.join(a, &.{ lib_dir, "libko_loop.so" });
        defer a.free(path);
        const lib = dynamic_library.DynLib.open(path) catch return error.CouldNotLoadLibrary;
        const sym = lib.lookup(FnT, name);
        try std.testing.expect(sym != null, "symbol '{s}' is NULL", .{name});
        lib.close();
    }
}
