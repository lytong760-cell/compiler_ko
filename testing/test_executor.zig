const std = @import("std");
const lexer = @import("src").lexer;
const parser = @import("src").parser;
const executor_mod = @import("src").executor;

const CaptureResult = struct { out: []u8, errored: bool };

/// Parse `source`, chạy qua `Executor.execute` (không qua `VM.execute`),
/// chụp stdout vào buffer, trả về (output, có_lỗi).
fn runExecutorCapture(allocator: std.mem.Allocator, source: []const u8) !CaptureResult {
    var lx = lexer.Lexer.init(source);
    const lex_result = try lx.tokenize(allocator);
    const tokens = lex_result.tokens;
    const positions = lex_result.positions;
    defer allocator.free(tokens);
    defer allocator.free(positions);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens, positions);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    var aw = std.Io.Writer.Allocating.init(allocator);
    defer aw.deinit();
    var ex = try executor_mod.Executor.init(allocator, std.testing.io, "test.ko", null);
    defer ex.deinit();
    ex.setOutputWriter(&aw.writer);
    var errored = false;
    ex.execute(program) catch |err| {
        errored = true;
        _ = @errorName(err);
    };
    try aw.writer.flush();
    const full = try aw.toOwnedSlice();
    // exposeProcess() ghi `{file_path}:main` trước mỗi dòng chương trình;
    // bỏ mọi dòng bắt đầu bằng `test.ko:` để so sánh đầu ra sạch sẽ.
    var out = std.array_list.Managed(u8).init(allocator);
    defer out.deinit();
    var i: usize = 0;
    while (i < full.len) {
        const nl = std.mem.indexOf(u8, full[i..], "\n") orelse (full.len - i);
        const line_end = i + nl;
        const line = full[i..line_end];
        if (!std.mem.startsWith(u8, line, "test.ko:")) {
            try out.appendSlice(line);
            if (line_end < full.len) try out.append('\n');
        }
        i = line_end + 1;
    }
    allocator.free(full);
    const body = try out.toOwnedSlice();
    return CaptureResult{ .out = body, .errored = errored };
}

test "executor a1 tuple" {
    const gpa = std.testing.allocator;
    const res = try runExecutorCapture(gpa, "[ (1,2,3)~t <printf>^(t) ]");
    defer gpa.free(res.out);
    try std.testing.expectEqualStrings("(1, 2, 3)\n", res.out);
    try std.testing.expect(!res.errored);
}

test "executor b1 print interpolated" {
    const gpa = std.testing.allocator;
    const res = try runExecutorCapture(gpa, "[ int(7)~x <print>^(\"x={x}\\n\") ]");
    defer gpa.free(res.out);
    try std.testing.expectEqualStrings("x=7\n", res.out);
    try std.testing.expect(!res.errored);
}

test "executor b1 printf control interpolated" {
    const gpa = std.testing.allocator;
    const res = try runExecutorCapture(gpa, "[ int(7)~x <printf>^(\"x={x}\\n\") ]");
    defer gpa.free(res.out);
    try std.testing.expectEqualStrings("x=7\n", res.out);
    try std.testing.expect(!res.errored);
}

test "executor b2 bytes len" {
    const gpa = std.testing.allocator;
    const res = try runExecutorCapture(gpa, "[ bytes(8)~b int(<len>^(b))~l <printf>^(l) ]");
    defer gpa.free(res.out);
    try std.testing.expectEqualStrings("8\n", res.out);
    try std.testing.expect(!res.errored);
}

test "executor b5 type string" {
    const gpa = std.testing.allocator;
    const res = try runExecutorCapture(gpa, "[ <printf>^(type(\"hi\")) ]");
    defer gpa.free(res.out);
    try std.testing.expectEqualStrings("string", res.out);
    try std.testing.expect(!res.errored);
}

test "executor b5 type int" {
    const gpa = std.testing.allocator;
    const res = try runExecutorCapture(gpa, "[ <printf>^(type(123)) ]");
    defer gpa.free(res.out);
    try std.testing.expectEqualStrings("int", res.out);
    try std.testing.expect(!res.errored);
}

test "executor m1 catch not run when no error" {
    const gpa = std.testing.allocator;
    const res = try runExecutorCapture(gpa, "[ int(1)~x <catch>(`Err`) [ <printf>^(\"in catch\\n\") ] <printf>^(x) ]");
    defer gpa.free(res.out);
    try std.testing.expectEqualStrings("1\n", res.out);
    try std.testing.expect(!res.errored);
}

test "executor b3 method reads field" {
    const gpa = std.testing.allocator;
    const res = try runExecutorCapture(gpa, "[ Foo !class[int(5)~x get()[<return>(x)]] ~Foo~f int($f~get())~r <printf>^(r) ]");
    defer gpa.free(res.out);
    try std.testing.expectEqualStrings("5\n", res.out);
    try std.testing.expect(!res.errored);
}

test "executor m3 unknown tag errors" {
    const gpa = std.testing.allocator;
    const res = try runExecutorCapture(gpa, "[ <foo>^(\"x\") ]");
    defer gpa.free(res.out);
    try std.testing.expect(res.errored);
}
