const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const vm = @import("vm.zig");
const ast = @import("ast.zig");

fn runSource(allocator: std.mem.Allocator, source: []const u8) !void {
    var lx = lexer.Lexer.init(source);
    const tokens = lx.tokenize(allocator) catch |err| {
        std.debug.print("Lexer error: {any}\n", .{err});
        return;
    };
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    const program = pr.parse() catch |err| {
        std.debug.print("Parser error: {any}\n", .{err});
        return;
    };

    var virtual_machine = try vm.VM.init(allocator);
    defer virtual_machine.deinit();

    virtual_machine.execute(program) catch |err| {
        std.debug.print("Runtime error: {any}\n", .{err});
        return;
    };
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
    try runSource(gpa, "[ <input>(\"test\")&=string(\"\")~s ]");
}

test "test_2501" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ string(\"hello\")~s <input>(s) ]");
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
    const gpa = std.testing.allocator;
    try runSource(gpa, "Import($A)@also%~a!`global`:a");
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
