test "test_multi_input" {
    const gpa = std.testing.allocator;
    const source = [&]u8]{ string("")~a string("")~b <input>(a) <input>(b) <printf>^("a={a}\\nb={b}") };
    const input = "first line\\nsecond line\\n";
    // Lex and parse
    var lx = lexer.Lexer.init(&source);
    const tokens = try lx.tokenize(gpa);
    defer gpa.free(tokens);
    var arena = std.heap.ArenaAllocator.init(gpa);
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