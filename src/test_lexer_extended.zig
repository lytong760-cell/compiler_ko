const std = @import("std");
const lexer = @import("lexer.zig");

test "lexer_test_0001" {
    var lx = lexer.Lexer.init("int");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0002" {
    var lx = lexer.Lexer.init("freal");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0003" {
    var lx = lexer.Lexer.init("string");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0004" {
    var lx = lexer.Lexer.init("booling");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0005" {
    var lx = lexer.Lexer.init("byte");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0006" {
    var lx = lexer.Lexer.init("bytes");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0007" {
    var lx = lexer.Lexer.init("if");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0008" {
    var lx = lexer.Lexer.init("else");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0009" {
    var lx = lexer.Lexer.init("return");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0010" {
    var lx = lexer.Lexer.init("catch");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0011" {
    var lx = lexer.Lexer.init("[");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0012" {
    var lx = lexer.Lexer.init("]");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0013" {
    var lx = lexer.Lexer.init("(");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0014" {
    var lx = lexer.Lexer.init(")");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0015" {
    var lx = lexer.Lexer.init("~");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0016" {
    var lx = lexer.Lexer.init("+");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0017" {
    var lx = lexer.Lexer.init("-");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0018" {
    var lx = lexer.Lexer.init("*");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0019" {
    var lx = lexer.Lexer.init("/");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0020" {
    var lx = lexer.Lexer.init("%");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0021" {
    var lx = lexer.Lexer.init("&&");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0022" {
    var lx = lexer.Lexer.init("%%");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0023" {
    var lx = lexer.Lexer.init("<");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0024" {
    var lx = lexer.Lexer.init(">");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0025" {
    var lx = lexer.Lexer.init("^");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0026" {
    var lx = lexer.Lexer.init("=");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0027" {
    var lx = lexer.Lexer.init("x");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0028" {
    var lx = lexer.Lexer.init("_test");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0029" {
    var lx = lexer.Lexer.init("test123");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0030" {
    var lx = lexer.Lexer.init("42");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0031" {
    var lx = lexer.Lexer.init("3.14");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0032" {
    var lx = lexer.Lexer.init("\"hello\"");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0033" {
    var lx = lexer.Lexer.init("'hello'");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 2) catch unreachable;
}

test "lexer_test_0034" {
    var lx = lexer.Lexer.init("|comment|");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 1) catch unreachable;
}

test "lexer_test_0035" {
    var lx = lexer.Lexer.init("int(10)~x");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 7) catch unreachable;
}

test "lexer_test_0036" {
    var lx = lexer.Lexer.init("x + y");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 4) catch unreachable;
}

test "lexer_test_0037" {
    var lx = lexer.Lexer.init("x && y");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 4) catch unreachable;
}

test "lexer_test_0038" {
    var lx = lexer.Lexer.init("x %% y");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 4) catch unreachable;
}

test "lexer_test_0039" {
    var lx = lexer.Lexer.init("<printf>");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 4) catch unreachable;
}

test "lexer_test_0040" {
    var lx = lexer.Lexer.init("<len>");
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch unreachable;
    defer gpa.free(tokens);
    std.testing.expect(tokens.len == 4) catch unreachable;
}
