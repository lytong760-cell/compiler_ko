const std = @import("std");

const dl = @cImport({
    @cInclude("dlfcn.h");
});
const dlopen = @as(*const fn ([*:0]const u8, i32) callconv(.c) ?*anyopaque, @ptrCast(&dl.dlopen));
const dlsym = @as(*const fn (?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque, @ptrCast(&dl.dlsym));
const dlclose = @as(*const fn (?*anyopaque) callconv(.c) i32, @ptrCast(&dl.dlclose));

fn closeLib(handle: ?*anyopaque) void {
    _ = dlclose(handle);
}

test "A: no callconv, return ?[*:0]const u8" {
    const handle = dlopen("zig-out/lib/libko_os.so", 1) orelse return error.CouldNotLoadLibrary;
    defer closeLib(handle);
    const sym = dlsym(handle, "ko_get_cwd");
    if (sym == null) return error.SymbolNotFound;
    const fn_ptr = @as(*const fn () ?[*:0]const u8, @ptrCast(sym.?));
    const cwd = fn_ptr();
    _ = cwd;
}

test "B: with callconv(.c), return ?[*:0]const u8" {
    const handle = dlopen("zig-out/lib/libko_os.so", 1) orelse return error.CouldNotLoadLibrary;
    defer closeLib(handle);
    const sym = dlsym(handle, "ko_get_cwd");
    if (sym == null) return error.SymbolNotFound;
    const fn_ptr = @as(*const fn () callconv(.c) ?[*:0]const u8, @ptrCast(sym.?));
    const cwd = fn_ptr();
    _ = cwd;
}

test "C: callconv(.c), return ?*const u8" {
    const handle = dlopen("zig-out/lib/libko_os.so", 1) orelse return error.CouldNotLoadLibrary;
    defer closeLib(handle);
    const sym = dlsym(handle, "ko_get_cwd");
    if (sym == null) return error.SymbolNotFound;
    const fn_ptr = @as(*const fn () callconv(.c) ?*const u8, @ptrCast(sym.?));
    const cwd = fn_ptr();
    _ = cwd;
}

test "D: cimport'd dlsym directly, cast to fn pointer" {
    const handle = dlopen("zig-out/lib/libko_os.so", 1) orelse return error.CouldNotLoadLibrary;
    defer closeLib(handle);
    const sym = dl.dlsym(handle, "ko_get_cwd");
    const fn_ptr: *const fn () callconv(.c) ?[*:0]const u8 = @ptrCast(sym.?);
    const cwd = fn_ptr();
    _ = cwd;
}

fn load(t: type, sym: [*:0]const u8, handle: ?*anyopaque) !t {
    defer closeLib(handle);
    const sym_val = dlsym(handle, sym);
    if (sym_val == null) return error.SymbolNotFound;
    return @as(t, @ptrCast(sym_val.?));
}

test "E: generic load helper" {
    const KoGetCwdFn = *const fn () callconv(.c) ?[*:0]const u8;
    const handle = dlopen("zig-out/lib/libko_os.so", 1) orelse return error.CouldNotLoadLibrary;
    const ko_get_cwd = load(KoGetCwdFn, "ko_get_cwd", handle) catch return error.CouldNotLoadLibrary;
    const cwd = ko_get_cwd();
    _ = cwd;
}

test "F: generic load helper with RTLD_LAZY" {
    const RTLD_LAZY: i32 = 1;
    const KoGetEnvFn = *const fn ([*:0]const u8) callconv(.c) ?[*:0]const u8;
    const handle = dlopen("zig-out/lib/libko_os.so", RTLD_LAZY) orelse return error.CouldNotLoadLibrary;
    const ko_get_env = load(KoGetEnvFn, "ko_get_env", handle) catch return error.CouldNotLoadLibrary;
    const cwd = ko_get_env("HOME");
    _ = cwd;
}