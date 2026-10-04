const std = @import("std");

fn lookup(comptime T: type, lib_path: [:0]const u8, sym_name: [:0]const u8) !T {
    const lib = try std.DynLib.open(lib_path);
    defer lib.close();

    const func_ptr = lib.lookup(T, sym_name) orelse return error.SymbolNotFound;
    return func_ptr;
}
