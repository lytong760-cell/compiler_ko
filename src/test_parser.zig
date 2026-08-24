const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

test "parser printf" {
    const source = "[ <printf>^(sum) ]";
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

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = pr.parse() catch |err| {
        std.debug.print("Parser error at pos {}: {any}\n", .{pr.pos, err});
        std.debug.print("Current token: {any}\n", .{pr.current()});
        return;
    };

    std.debug.print("Parsed {} statements\n", .{program.len});
}
