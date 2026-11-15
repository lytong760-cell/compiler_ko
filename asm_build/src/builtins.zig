const std = @import("std");

pub fn registerBuiltins(scope: *std.StringHashMap(std.fn(void) anyerror!void)) void {
    _ = scope;
}
