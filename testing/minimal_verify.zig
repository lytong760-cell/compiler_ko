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

test "dlopen works" {
    const handle = dlopen("zig-out/lib/libko_os.so", RTLD_LAZY) orelse return error.CouldNotLoadLibrary;
    defer closeLib(handle);
}

test "dlsym resolves ko_file_exists" {
    const handle = dlopen("zig-out/lib/libko_os.so", RTLD_LAZY) orelse return error.CouldNotLoadLibrary;
    defer closeLib(handle);
    const sym = dlsym(handle, "ko_file_exists");
    if (sym == null) return error.SymbolNotFound;
    const addr = @intFromPtr(@as(*anyopaque, @ptrCast(sym.?)));
    try std.testing.expect(addr > 0);
}

test "call ko_list_dir (args unused, returns -1)" {
    const KoListDirFn = *const fn (*const u8, ***u8, *usize) callconv(.c) c_int;
    const ko_list_dir = load(KoListDirFn, "ko_list_dir") catch return error.CouldNotLoadLibrary;
    const path: [*:0]const u8 = "zig-out/lib";
    const entries: ***u8 = @ptrCast(@as(?*anyopaque, null) orelse unreachable);
    var count: usize = 0;
    const result = ko_list_dir(path, entries, @as(*usize, @ptrCast(&count)));
    try std.testing.expectEqual(@as(c_int, -1), result);
}

test "call ko_get_env returns string or null" {
    const KoGetEnvFn = *const fn ([*:0]const u8) callconv(.c) ?[*:0]const u8;
    const ko_get_env = load(KoGetEnvFn, "ko_get_env") catch return error.CouldNotLoadLibrary;
    const path: [*:0]const u8 = "HOME";
    const result = ko_get_env(path);
    // result is either null (HOME unset) or a C string
    _ = result;
}