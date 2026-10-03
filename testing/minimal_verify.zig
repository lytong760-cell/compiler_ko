const std = @import("std");

const dl = @cImport({
    @cInclude("dlfcn.h");
});
const dlopen = @as(*const fn ([*:0]const u8, i32) callconv(.c) ?*anyopaque, @ptrCast(&dl.dlopen));
const dlsym = @as(*const fn (?*anyopaque, [*:0]const u8) callconv(.c) ?*anyopaque, @ptrCast(&dl.dlsym));
const dlclose = @as(*const fn (?*anyopaque) callconv(.c) i32, @ptrCast(&dl.dlclose));
const RTLD_LAZY: i32 = 1;

fn closeLib(handle: ?*anyopaque) void {
    _ = dlclose(handle);
}

fn load(t: type, sym: [*:0]const u8) !t {
    const handle = dlopen("zig-out/lib/libko_os.so", RTLD_LAZY) orelse return error.CouldNotLoadLibrary;
    defer closeLib(handle);
    const sym_val = dlsym(handle, sym);
    if (sym_val == null) return error.SymbolNotFound;
    return @ptrCast(sym_val.?);
}

test "call ko_get_cwd (no args, returns string)" {
    const KoGetCwdFn = *const fn () callconv(.c) ?[*:0]const u8;
    const ko_get_cwd = load(KoGetCwdFn, "ko_get_cwd") catch return error.CouldNotLoadLibrary;
    const cwd = ko_get_cwd();
    // result is null or a C string; just confirm the call didn't crash
    _ = cwd;
}

test "call ko_get_env with string arg" {
    const KoGetEnvFn = *const fn ([*:0]const u8) callconv(.c) ?[*:0]const u8;
    const ko_get_env = load(KoGetEnvFn, "ko_get_env") catch return error.CouldNotLoadLibrary;
    const result = ko_get_env("HOME");
    _ = result;
}