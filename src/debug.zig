const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

test "debug" {
    const source = "[ <catch>(`TestError`) [ <printf>^(\"caught\") ] ]";
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
    
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pr = parser.Parser.init(std.testing.allocator, &arena, tokens);
    const program = pr.parse() catch |err| {
        std.debug.print("Parse error: {any}\n", .{err});
        return;
    };
    std.debug.print("Parsed {} statements\n", .{program.len});
}
