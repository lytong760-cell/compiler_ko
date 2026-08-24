const std = @import("std");
const lexer = @import("lexer.zig");

test "parser basic" {
    const source = "[ int(10)~x ]";
    var lx = lexer.Lexer.init(source);
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch |err| {
        std.debug.print("Lexer error: {any}\n", .{err});
        return;
    };
    defer gpa.free(tokens);

    std.debug.print("Tokens:\n", .{});
    for (tokens, 0..) |tok, i| {
        std.debug.print("  {}: {any}\n", .{i, tok});
    }
}
