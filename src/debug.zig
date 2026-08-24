const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

test "debug_backslash" {
    const source = "\\[ int(10)~x ]";
    std.debug.print("Source: '{s}'\n", .{source});
    var lx = lexer.Lexer.init(source);
    const tokens = lx.tokenize(std.testing.allocator) catch |err| {
        std.debug.print("Lexer error: {any}\n", .{err});
        return;
    };
    defer std.testing.allocator.free(tokens);
    
    std.debug.print("Tokens:\n", .{});
    for (tokens, 0..) |tok, i| {
        std.debug.print("  {}: {any}\n", .{i, tok});
    }
}
