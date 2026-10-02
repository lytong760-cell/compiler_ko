const std = @import("std");
const lexer = @import("src").lexer;
const parser = @import("src").parser;
const vm = @import("src").vm;
const ast = @import("src").ast";

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

    var sink_buffer: [1]u8 = undefined;
    var sink: std.Io.Writer.Discarding = .init(&sink_buffer);

    var virtual_machine = try vm.VM.init(allocator, std.testing.io, "test.ko");
    defer virtual_machine.deinit();
    virtual_machine.setOutputWriter(&sink.writer);

    try virtual_machine.execute(program);
}

test "debug_input" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ <input>(\"a\")&=string(\"\")~s <printf>^(\"got {a}\") ]");
}
