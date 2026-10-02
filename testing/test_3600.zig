const std = @import("std");
const lexer = @import("src").lexer;
const parser = @import("src").parser;
const vm = @import("src").vm;
const ast = @import("src").ast;

fn executeProgram(allocator: std.mem.Allocator, program: []ast.Statement, input: ?[]const u8) !void {
    var sink_buffer: [1]u8 = undefined;
    var sink: std.Io.Writer.Discarding = .init(&sink_buffer);

    var virtual_machine = try vm.VM.init(allocator, std.testing.io, "test.ko");
    defer virtual_machine.deinit();
    virtual_machine.setOutputWriter(&sink.writer);
    if (input) |buf| virtual_machine.setInputBuffer(buf);

    try virtual_machine.execute(program);
}

fn runSourceCapturing(allocator: std.mem.Allocator, source: []const u8, out_buf: []u8) ![]const u8 {
    var lx = lexer.Lexer.init(source);
    const tokens = try lx.tokenize(allocator);
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    var out: std.Io.Writer = .fixed(out_buf);
    var virtual_machine = try vm.VM.init(allocator, std.testing.io, "test.ko");
    defer virtual_machine.deinit();
    virtual_machine.setOutputWriter(&out);

    try virtual_machine.execute(program);
    return out.buffered();
}

fn expectOutput(allocator: std.mem.Allocator, source: []const u8, expected: []const u8) !void {
    var buf: [4096]u8 = undefined;
    const got = try runSourceCapturing(allocator, source, &buf);
    if (std.mem.indexOf(u8, got, expected) == null) {
        std.debug.print("\nexpected to find: {s}\nactual output: {s}\n", .{ expected, got });
        return error.TestExpectedOutput;
    }
}

fn runSource(allocator: std.mem.Allocator, source: []const u8) !void {
    var lx = lexer.Lexer.init(source);
    const tokens = try lx.tokenize(allocator);
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    try executeProgram(allocator, program, null);
}

fn runSourceWithInput(allocator: std.mem.Allocator, source: []const u8, input: []const u8) !void {
    var lx = lexer.Lexer.init(source);
    const tokens = try lx.tokenize(allocator);
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    try executeProgram(allocator, program, input);
}

test "test_0001" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(0)~x ]");
}

test "test_0002" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(1)~x ]");
}

test "test_0003" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(2)~x ]");
}

test "test_0004" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(3)~x ]");
}

test "test_0005" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(4)~x ]");
}

test "test_0006" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(5)~x ]");
}

test "test_0007" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(6)~x ]");
}

test "test_0008" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(7)~x ]");
}

test "test_0009" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(8)~x ]");
}

test "test_0010" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(9)~x ]");
}

test "test_0100" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(100)~x ]");
}

test "test_0101" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ string(\"hello\")~s ]");
}

test "test_0102" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ string(\"world\")~s ]");
}

test "test_0200" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ freal(3.14)~pi ]");
}

test "test_0201" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ freal(2.71)~e ]");
}

test "test_0300" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ booling(\\True\\)~flag ]");
}

test "test_0301" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ booling(\\False\\)~flag ]");
}

test "test_0400" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x int(20)~y ]");
}

test "test_0401" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x int(20)~y int(x + y)~sum ]");
}

test "test_0402" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x int(20)~y int(x - y)~diff ]");
}

test "test_0403" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x int(20)~y int(x * y)~prod ]");
}

test "test_0404" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(20)~x int(10)~y int(x / y)~quotient ]");
}

test "test_0405" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(20)~x int(10)~y int(x % y)~remainder ]");
}

test "test_0500" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <if>(1 == 1) [ <printf>^(\"ok\") ] ]");
}

test "test_0501" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <if>(1 == 2) [ <printf>^(\"ok\") ] <else> [ <printf>^(\"else\") ] ]");
}

test "test_0502" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <if>(1 < 2) [ <printf>^(\"lt\") ] ]");
}

test "test_0503" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <if>(2 > 1) [ <printf>^(\"gt\") ] ]");
}

test "test_0600" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(5)~x <if>(x > 0 && x < 10) [ <printf>^(\"range\") ] ]");
}

test "test_0601" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(5)~x <if>(x < 0 %% x > 10) [ <printf>^(\"out\") ] ]");
}

test "test_0700" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <catch>(`TestError`) [ <printf>^(\"caught\") ] ]");
}

test "test_0701" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <catch>(`Error`) [ int(0)~x ] ]");
}

test "test_0800" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ string(\"test\")~s int(<len>^(s))~l ]");
}

test "test_0801" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <encode(`UTF-8`)>^(\"hello\") ]");
}

test "test_0802" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <memory>^x ]");
}

test "test_0900" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <now>(20)>x ]");
}

test "test_0901" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <now>(x + 5)>x ]");
}

test "test_1000" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "MyFunc() [ <return>(42) ] [ int(~MyFunc())~r ]");
}

test "test_1001" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "Add(int~a, int~b) [ <return>(a + b) ] [ int(~Add(10, 20))~r ]");
}

test "test_1100" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "Person !class [ string(\"John\")~name ] [ ~Person~p ]");
}

test "test_1101" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "Box !class [ @private [ int(0)~value ] ] [ ~Box~b ]");
}

test "test_1200" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ byte(65)~b ]");
}

test "test_1201" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ bytes(16)~buf ]");
}

test "test_1300" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <printf>^(\"hello\") ]");
}

test "test_1301" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <printf>^(\"a\") <printf>^(\"b\") <printf>^(\"c\") ]");
}

test "test_1400" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ | comment | int(10)~x ]");
}

test "test_1401" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x | comment about x | int(20)~y ]");
}

test "test_1500" {
    // Import is not implemented at runtime
    // const gpa = std.testing.allocator;
    // try runSource(gpa, "Import($Test)@also%~t!`global`:t");
}

test "test_1501" {
    // Import is not implemented at runtime
    // const gpa = std.testing.allocator;
    // try runSource(gpa, "Import($OS)@also%~os!`global`:os");
}

test "test_1600" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <if>(x > 5) [ <if>(x < 15) [ <printf>^(\"mid\") ] ] ]");
}

test "test_1601" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(20)~x <if>(x > 5) [ <if>(x > 15) [ <printf>^(\"high\") ] <else> [ <printf>^(\"mid\") ] ] <else> [ <printf>^(\"low\") ] ]");
}

test "test_1700" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(0)~x int(0)~y int(x + y)~z ]");
}

test "test_1701" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(-10)~x int(10)~y int(x + y)~z ]");
}

test "test_1800" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(100)~x int(100)~y int(x * y)~z ]");
}

test "test_1801" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(1000)~x int(1000)~y int(x + y)~z ]");
}

test "test_1900" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ string(\"\")~s ]");
}

test "test_1901" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ string(\"a\")~s string(\"b\")~t ]");
}

test "test_2000" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(1)~a int(2)~b int(3)~c int(4)~d int(a + b + c + d)~sum ]");
}

test "test_2001" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(1)~a int(2)~b int(3)~c int(4)~d int(5)~e int(a + b + c + d + e)~sum ]");
}

test "test_2100" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <catch>(`E1`) [ ] <catch>(`E2`) [ ] <catch>(`E3`) [ ] ]");
}

test "test_2101" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x int(20)~y int(30)~z int(x + y + z)~sum ]");
}

test "test_2200" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ bytes(1)~b1 bytes(2)~b2 bytes(4)~b4 ]");
}

test "test_2201" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ byte(0)~b0 byte(255)~b255 ]");
}

test "test_2300" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ freal(0.0)~f ]");
}

test "test_2301" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ freal(1.5)~f1 freal(2.5)~f2 freal(f1 + f2)~sum ]");
}

test "test_2400" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <if>(1 == 1) [ <if>(2 == 2) [ <if>(3 == 3) [ <printf>^(\"deep\") ] ] ] ]");
}

test "test_2401" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <if>(1 == 2) [ <printf>^(\"a\") ] <elif>(2 == 3) [ <printf>^(\"b\") ] <elif>(3 == 4) [ <printf>^(\"c\") ] <else> [ <printf>^(\"d\") ] ]");
}

test "test_2500" {
    const gpa = std.testing.allocator;
    try runSourceWithInput(gpa, "[ <input>(\"test\")&=string(\"\")~s ]", "test input\n");
}

test "test_2501" {
    const gpa = std.testing.allocator;
    try runSourceWithInput(gpa, "[ string(\"hello\")~s <input>(s) ]", "typed input\n");
}

test "test_2600" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(1000000)~big ]");
}

test "test_2601" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(-1000000)~neg ]");
}

test "test_2700" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <printf>^(\"1\") <printf>^(\"2\") <printf>^(\"3\") ]");
}

test "test_2701" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <printf>^(\"line1\\n\") <printf>^(\"line2\\n\") ]");
}

test "test_2800" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x int(20)~y int(30)~z int(40)~w int(x + y + z + w)~total ]");
}

test "test_2801" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <now>(20)>x ]");
}

test "test_2900" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "Func1() [ <return>(1) ] Func2() [ <return>(2) ] Func3() [ <return>(3) ] [ int(~Func1())~a int(~Func2())~b int(~Func3())~c ]");
}

test "test_2901" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ | a | | b | | c | int(1)~x ]");
}

test "test_3000" {
    // Import is not implemented at runtime
    // const gpa = std.testing.allocator;
    // try runSource(gpa, "Import($A)@also%~a!`global`:a");
}

test "test_3001" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(1)~x <catch>(`E1`) [ ] <catch>(`E2`) [ ] <catch>(`E3`) [ ] <catch>(`E4`) [ ] ]");
}

test "test_3100" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x int(5)~y int(3)~z int(x / y / z)~res ]");
}

test "test_3101" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x int(3)~y int(x % y)~rem ]");
}

test "test_3200" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ booling(\\True\\)~flag <if>(flag) [ <printf>^(\"true\") ] ]");
}

test "test_3201" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ booling(\\False\\)~flag <if>(flag) [ <printf>^(\"false\") ] <else> [ <printf>^(\"not false\") ] ]");
}

test "test_3300" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <encode(`UTF-8`)>^(\"hello\") ]");
}

test "test_3301" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <encode(`UTF-8`)>^(\"world\") ]");
}

test "test_3400" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ string(\"short\")~s int(<len>^(s))~l ]");
}

test "test_3401" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ bytes(0)~empty ]");
}

test "test_3500" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(255)~max_byte ]");
}

test "test_3501" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(256)~overflow ]");
}

test "test_3600_final" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(42)~answer <printf>^(\"Complete!\") ]");
}

test "test_nested_if_else_001" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <if>(x > 5) [ <if>(x > 15) [ <printf>^(\"big\") ] <else> [ <printf>^(\"medium\") ] ] <else> [ <printf>^(\"small\") ] ]");
}

test "test_nested_if_else_002" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <if>(x > 5) [ <if>(x > 15) [ <printf>^(\"big\") ] <elif>(x > 5) [ <printf>^(\"medium\") ] <else> [ <printf>^(\"small\") ] ] <else> [ <printf>^(\"tiny\") ] ]");
}

test "test_nested_if_else_003" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <if>(x > 20) [ <if>(x > 15) [ <printf>^(\"big\") ] <else> [ <printf>^(\"medium\") ] ] <else> [ <printf>^(\"small\") ] ]");
}

test "test_nested_if_else_004" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(10)~x <if>(x > 5) [ <if>(x > 15) [ <printf>^(\"big\") ] <else> [ <printf>^(\"medium\") ] ] <else> [ <printf>^(\"small\") ] ]");
}

test "test_nested_if_else_005" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <if>(1 == 1) [ <if>(1 == 1) [ <printf>^(\"a\") ] ] ]");
}

test "test_nested_if_else_006" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <if>(1 == 1) [ <if>(1 == 1) [ <printf>^(\"a\") ] <else> [ <printf>^(\"b\") ] ] ]");
}

test "test_input_target_expr" {
    const gpa = std.testing.allocator;
    try runSourceWithInput(gpa, "[ string(\"\")~s <input>(s) ]", "target expr input\n");
}

test "test_priority_order" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ {1}<printf>^(\"1\") {0}<printf>^(\"0\") ]");
}

test "test_process_manager_function" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "Func() [ <return>(1) ] [ int(~Func())~r ]");
}

test "test_method_call_args_preserved" {
    const gpa = std.testing.allocator;
    var lx = lexer.Lexer.init("$inst~meth(1, 2)");
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    try std.testing.expectEqual(program.len, 1);

    const call_expr = blk: {
        switch (program[0]) {
            .expr => |e| break :blk e,
            else => return error.TestExpectedExpr,
        }
    };

    const call = blk: {
        switch (call_expr.*) {
            .call => |c| break :blk c,
            else => return error.TestExpectedCall,
        }
    };

    try std.testing.expectEqualStrings(call.callee, "meth");
    try std.testing.expect(call.target != null);
    try std.testing.expectEqual(call.args.len, 2);

    if (call.target) |target_expr| {
        const ma = blk: {
            switch (target_expr.*) {
                .member_access => |m| break :blk m,
                else => return error.TestExpectedMemberAccess,
            }
        };
        try std.testing.expectEqualStrings(ma.member, "meth");
        switch (ma.object.*) {
            .identifier => |name| {
                try std.testing.expectEqualStrings(name, "inst");
            },
            else => return error.TestExpectedIdentifier,
        }
    }

    switch (call.args[0]) {
        .literal => |lit| {
            try std.testing.expectEqual(lit.kind, ast.Literal.Kind.int);
            try std.testing.expectEqual(lit.int_value, 1);
        },
        else => return error.TestExpectedLiteral,
    }
    switch (call.args[1]) {
        .literal => |lit| {
            try std.testing.expectEqual(lit.kind, ast.Literal.Kind.int);
            try std.testing.expectEqual(lit.int_value, 2);
        },
        else => return error.TestExpectedLiteral,
    }
}

test "test_method_call_three_args" {
    const gpa = std.testing.allocator;
    var lx = lexer.Lexer.init("$inst~meth(10, 20, 30)");
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    try std.testing.expectEqual(program.len, 1);

    const call = blk: {
        switch (program[0]) {
            .expr => |e| switch (e.*) {
                .call => |c| break :blk c,
                else => return error.TestExpectedCall,
            },
            else => return error.TestExpectedExpr,
        }
    };

    try std.testing.expectEqualStrings(call.callee, "meth");
    try std.testing.expect(call.target != null);
    try std.testing.expectEqual(call.args.len, 3);

    const expected = [_]i64{ 10, 20, 30 };
    for (call.args, 0..) |arg, i| {
        switch (arg) {
            .literal => |lit| {
                try std.testing.expectEqual(lit.kind, ast.Literal.Kind.int);
                try std.testing.expectEqual(lit.int_value, expected[i]);
            },
            else => return error.TestExpectedLiteral,
        }
    }
}

test "test_sigil_call_has_no_target" {
    const gpa = std.testing.allocator;
    var lx = lexer.Lexer.init("~f(1, 2)");
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    try std.testing.expectEqual(program.len, 1);

    const call = blk: {
        switch (program[0]) {
            .expr => |e| switch (e.*) {
                .call => |c| break :blk c,
                else => return error.TestExpectedCall,
            },
            else => return error.TestExpectedExpr,
        }
    };

    try std.testing.expectEqualStrings(call.callee, "f");
    try std.testing.expect(call.target == null);
    try std.testing.expectEqual(call.args.len, 2);
}

test "test_plain_call_has_no_target" {
    const gpa = std.testing.allocator;
    var lx = lexer.Lexer.init("f(1, 2)");
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    try std.testing.expectEqual(program.len, 1);

    const call = blk: {
        switch (program[0]) {
            .expr => |e| switch (e.*) {
                .call => |c| break :blk c,
                else => return error.TestExpectedCall,
            },
            else => return error.TestExpectedExpr,
        }
    };

    try std.testing.expectEqualStrings(call.callee, "f");
    try std.testing.expect(call.target == null);
    try std.testing.expectEqual(call.args.len, 2);
}

test "test_class_member_access_parse_only" {
    const gpa = std.testing.allocator;
    var lx = lexer.Lexer.init("Greeter !class [ string(\"hi\")~greeting ] [ ~Greeter~g ] [ $g~greeting ]");
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();

    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    try std.testing.expectEqual(program.len, 3);
    const member_access = blk: {
        const block_stmt = switch (program[2]) {
            .block => |b| b,
            else => return error.TestExpectedBlock,
        };
        try std.testing.expectEqual(block_stmt.body.len, 1);
        const expr_stmt = switch (block_stmt.body[0]) {
            .expr => |e| e,
            else => return error.TestExpectedExpr,
        };
        switch (expr_stmt.*) {
            .member_access => |ma| break :blk ma,
            else => return error.TestExpectedMemberAccess,
        }
    };

    const obj = blk: {
        switch (member_access.object.*) {
            .identifier => |name| break :blk name,
            else => return error.TestExpectedIdentifier,
        }
    };
    try std.testing.expectEqualStrings(obj, "g");
    try std.testing.expectEqualStrings(member_access.member, "greeting");
}

test "format_int_interpolation" {
    const gpa = std.testing.allocator;
    try expectOutput(gpa, "[ int(30)~n <printf>^(\"Sum: {n}\") ]", "Sum: 30");
}

test "format_int_printf_tag" {
    const gpa = std.testing.allocator;
    try expectOutput(gpa, "[ int(42)~n <printf>^(n) ]", "42");
}

test "format_string_interpolation" {
    const gpa = std.testing.allocator;
    try expectOutput(gpa, "[ string(\"abc\")~s <printf>^(\"v={s}\") ]", "v=abc");
}

test "format_freal_interpolation" {
    const gpa = std.testing.allocator;
    try expectOutput(gpa, "[ freal(2)~f <printf>^(\"f={f}\") ]", "f=2");
}

test "format_booling_interpolation" {
    const gpa = std.testing.allocator;
    try expectOutput(gpa, "[ booling(\\True\\)~b <printf>^(\"b={b}\") ]", "b=True");
}

test "format_no_raw_tagged_union" {
    const gpa = std.testing.allocator;
    var buf: [4096]u8 = undefined;
    const got = try runSourceCapturing(gpa, "[ int(30)~n <printf>^(\"Sum: {n}\") ]", &buf);
    if (std.mem.indexOf(u8, got, ".{") != null or std.mem.indexOf(u8, got, ".int") != null) {
        std.debug.print("\nraw union leaked into output: {s}\n", .{got});
        return error.TestRawUnionLeaked;
    }
}

test "func_decl_with_untyped_params_parses" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "Show(x, y) [ <return>(1) ]");
}

test "func_decl_with_typed_params_parses" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "Add(int~a, int~b) [ <return>(a) ]");
}

test "method_call_receives_arguments_at_runtime" {
    const gpa = std.testing.allocator;
    try expectOutput(
        gpa,
        "G !class [ string(\"\")~a Show(x, y) [ <printf>^(\"got {x} {y}\") ] ] ~G~g $g~Show(11, 22)",
        "got 11 22",
    );
}
