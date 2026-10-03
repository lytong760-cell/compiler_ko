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

const KoFileExistsFn = *const fn ([*:0]const u8) callconv(.c) c_int;
const KoValidateUrlFn = *const fn ([*:0]const u8) callconv(.c) ?*const [*:0]const u8;

test "call ko_file_exists with build.zig" {
    const ko_file_exists = load(KoFileExistsFn, "ko_file_exists") catch return error.CouldNotLoadLibrary;
    const path: [*:0]const u8 = "build.zig";
    const result = ko_file_exists(path);
    try std.testing.expectEqual(@as(c_int, 1), result);
}

test "load ko_validate_url as function with C string param and return" {
    const ko_validate_url = load(KoValidateUrlFn, "ko_validate_url") catch return error.CouldNotLoadLibrary;
    const result = ko_validate_url("https://example.com");
    try std.testing.expect(result == null);
}

test "load ko_validate_url accepts example.com" {
    const ko_validate_url = load(KoValidateUrlFn, "ko_validate_url") catch return error.CouldNotLoadLibrary;
    const result = ko_validate_url("://example.com");
    try std.testing.expect(result == null);
}
