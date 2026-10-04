const std = @import("std");

type MyFnType = ?(*const fn ([*:0]const u8) callconv(.c) c_int);

fn showType(comptime T: type) void {
    std.debug.print("T type: {s}\n", .{@typeName(T)});
}

fn main() !void {
    const lib = try std.DynLib.open("zig-out/lib/libko_os.so");
    defer lib.close();

    const my_fn = lib.lookup(MyFnType, "ko_file_exists") orelse return error.SymbolNotFound;
    std.debug.print("my_fn type: {s}\n", .{@typeName(@TypeOf(my_fn))});
    showType(MyFnType);
}
