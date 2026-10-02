const std = @import("std");
const lexer = @import("src").lexer;
const parser = @import("src").parser;
const vm = @import("src").vm;
const ast = @import("src").ast;

test "test_multi_input" {
    const gpa = std.testing.allocator;
    const source = "string(\"\")~a string(\"\")~b <input>(a) <input>(b) <printf>^(\"a={a}\\nb={b}\")";
    const input = "first line\\nsecond line\\n";
    // Lex and parse
    var lx = lexer.Lexer.init(source);
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);
    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }
    // Set up VM
    var out_buf: [4096]u8 = undefined;
    var out: std.Io.Writer = .fixed(&out_buf);
    var virtual_machine = try vm.VM.init(gpa, std.testing.io, "test.ko");
    defer virtual_machine.deinit();
    virtual_machine.setOutputWriter(&out);
    virtual_machine.setInputBuffer(input);
    // Execute
    try virtual_machine.execute(program);
    const got = out.buffered();
    const expected = "a=first line\\nb=second line";
    if (!std.mem.eql(u8, got, expected)) {
        std.debug.print("Expected: {s}\\nGot: {s}\\n", .{expected, got});
        return error.TestFailed;
    }
}

test "test_eof_error" {
    const gpa = std.testing.allocator;
    const source = "string(\"\")~a string(\"\")~b <input>(a) <input>(b)";
    const input = "first line\\n";
    // Lex and parse
    var lx = lexer.Lexer.init(source);
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);
    var arena = std.heap.AreaAllocator.init(gpa);
    defer arena.deinit();
    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    }
    // We don't care about output, so we can use a sinking writer.
    var sink_buffer: [1]u8 = undefined;
    var sink: std.Io.Writer.Discarding = .init(&sink_buffer);
    var virtual_machine = try vm.VM.init(gpa, std.testing.io, "test.ko");
    defer virtual_machine.deinit();
    virtual_machine.setOutputWriter(&sink.writer);
    virtual_machine.setInputBuffer(input);
    // We expect an error
    if (virtual_machine.execute(program)) |_| {
        return error.TestExpectedError;
    }
    // Check that the error type is EOFError
    if (virtual_machine.error_type) |et| {
        if (!std.mem.eql(u8, et, "EOFError")) {
            std.debug.print("Expected error type EOFError, got {s}\\n", .{et});
            return error.TestFailed;
        }
    } else {
        std.debug.print("Expected error type to be set, got null\\n");
        return error.TestFailed;
    }
}