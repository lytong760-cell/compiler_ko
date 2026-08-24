const std = @import("std");
const lexer = @import("lexer.zig");

pub fn main() !void {
    const source = "[ int(10)~x <printf>^(\"Hello World\\n\") ]";
    var lx = lexer.Lexer.init(source);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const tokens = lx.tokenize(allocator) catch |err| {
        std.debug.print("Lexer error: {any}\n", .{err});
        return;
    };
    defer allocator.free(tokens);

    for (tokens) |tok| {
        std.debug.print("{any}\n", .{tok});
    }
}
