const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

test "debug_simple" {
    const source = "[ int(10)~x ]";
    var lx = lexer.Lexer.init(source);
    const tokens = lx.tokenize(std.testing.allocator) catch |err| {
        std.debug.print("Lexer error: {any}\n", .{err});
        return;
    };
    defer std.testing.allocator.free(tokens);
    
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pr = parser.Parser.init(std.testing.allocator, &arena, tokens);
    const result = pr.parse() catch |err| {
        std.debug.print("Parse error at pos {}: {any}\n", .{pr.pos, err});
        const tok = pr.current();
        std.debug.print("Current token: {any}\n", .{tok});
        if (pr.pos > 0) {
            std.debug.print("Prev token: {any}\n", .{pr.tokens[pr.pos - 1]});
        }
        return;
    };
    std.debug.print("Parsed {} statements\n", .{result.len});
}
