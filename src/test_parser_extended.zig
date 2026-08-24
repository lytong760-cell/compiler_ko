const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

fn parseSource(allocator: std.mem.Allocator, source: []const u8) !void {
    var lx = lexer.Lexer.init(source);
    const tokens = lx.tokenize(allocator) catch |err| {
        std.debug.print("Lexer error: {any}\n", .{err});
        return;
    };
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    _ = pr.parse() catch |err| {
        std.debug.print("Parser error: {any}\n", .{err});
        return;
    };
}

test "parser_test_0001" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ ]");
}

test "parser_test_0002" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x ]");
}

test "parser_test_0003" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x int(20)~y ]");
}

test "parser_test_0004" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x int(x + 5)~y ]");
}

test "parser_test_0005" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x int(x - 5)~y ]");
}

test "parser_test_0006" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x int(x * 2)~y ]");
}

test "parser_test_0007" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x int(x / 2)~y ]");
}

test "parser_test_0008" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x int(x % 3)~y ]");
}

test "parser_test_0009" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <if>(1 == 1) [ ] ]");
}

test "parser_test_0010" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <if>(1 == 1) [ ] <else> [ ] ]");
}

test "parser_test_0011" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <if>(1 == 1) [ ] <elif>(2 == 2) [ ] ]");
}

test "parser_test_0012" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <printf>^(\"hello\") ]");
}

test "parser_test_0013" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <printf>^(x) ]");
}

test "parser_test_0014" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <len>^(s) ]");
}

test "parser_test_0015" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <memory>^x ]");
}

test "parser_test_0016" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <memory>dete(x) ]");
}

test "parser_test_0017" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <catch>(`Error`) [ ] ]");
}

test "parser_test_0018" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <now>(10)>x ]");
}

test "parser_test_0019" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <input>(\"prompt\")&=x ]");
}

test "parser_test_0020" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ string(\"hello\")~s ]");
}

test "parser_test_0021" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ booling(\\True\\)~f ]");
}

test "parser_test_0022" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ byte(65)~b ]");
}

test "parser_test_0023" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ bytes(16)~buf ]");
}

test "parser_test_0024" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x <if>(x > 0) [ <printf>^(\"positive\") ] ]");
}

test "parser_test_0025" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x <if>(x > 0) [ <printf>^(\"pos\") ] <else> [ <printf>^(\"nonpos\") ] ]");
}

test "parser_test_0026" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "func() [ <return>(42) ]");
}

test "parser_test_0027" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "func(int~a, int~b) [ <return>(a + b) ]");
}

test "parser_test_0028" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "Box !class [ int(0)~x ] ]");
}

test "parser_test_0029" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "Box !class [ @private [ int(0)~x ] ] ]");
}

test "parser_test_0030" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(10)~x int(20)~y int(x + y)~z int(z * 2)~w ]");
}

test "parser_test_0031" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <if>(1 < 2) [ <if>(3 > 2) [ <printf>^(\"ok\") ] ] ]");
}

test "parser_test_0032" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <catch>(`E1`) [ ] <catch>(`E2`) [ ] ]");
}

test "parser_test_0033" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "Import($Random)@also%~r!`global`:r");
}

test "parser_test_0034" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <printf>^(\"a\") <printf>^(\"b\") <printf>^(\"c\") ]");
}

test "parser_test_0035" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(0)~x ]");
}

test "parser_test_0036" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ int(1)~x int(2)~y int(3)~z ]");
}

test "parser_test_0037" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <if>(x == y) [ ] ]");
}

test "parser_test_0038" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <if>(x != y) [ ] ]");
}

test "parser_test_0039" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <if>(x >= y) [ ] ]");
}

test "parser_test_0040" {
    const gpa = std.testing.allocator;
    try parseSource(gpa, "[ <if>(x <= y) [ ] ]");
}
