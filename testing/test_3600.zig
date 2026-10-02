test "test_multi_input" {
    const gpa = std.testing.allocator;
    const source = "string(\"\")~a string(\"\")~b <input>(a) <input>(b) <printf>^(\"a={a}\\nb={b}\")";
    const input = "first line\\nsecond line\\n";
    // Lex and parse
    var lx = lexer.Lexer.init(&source);
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);
    var arena = std.heap.AreaAllocator.init(gpa);
    defer arena.deinit();
    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    };
    // Set up VM
    var out_buf: [4096]u8 = undefined;
    var out: std.Io.Writer = .fixed(&out_buf);
    var vm = try vm.VM.init(gpa, std.testing.io, "test.ko");
    defer vm.deinit();
    vm.setOutputWriter(&out);
    vm.setInputBuffer(input);
    // Execute
    try vm.execute(program);
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
    var lx = lexer.Lexer.init(&source);
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);
    var arena = std.heap.AreaAllocator.init(gpa);
    defer arena.deinit();
    var pr = parser.Parser.init(gpa, &arena, tokens);
    const program = try pr.parse();
    defer {
        for (program) |*stmt| stmt.deinit();
    };
    // We don't care about output, so we can use a sinking writer.
    var sink_buffer: [1]u8 = undefined;
    var sink: std.Io.Writer.Discarding = .init(&sink_buffer);
    var vm = try vm.VM.init(gpa, std.testing.io, "test.ko");
    defer vm.deinit();
    vm.setOutputWriter(&sink.writer);
    vm.setInputBuffer(input);
    // We expect an error
    if (vm.execute(program)) |_| {
        return error.TestExpectedError;
    }
    // Check that the error type is EOFError
    if (vm.error_type) |et| {
        if (!std.mem.eql(u8, et, "EOFError")) {
            std.debug.print("Expected error type EOFError, got {s}\\n", .{et});
            return error.TestFailed;
        }
    } else {
        std.debug.print("Expected error type to be set, got null\\n");
        return error.TestFailed;
    }
}