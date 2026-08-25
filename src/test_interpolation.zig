const std = @import("std");
const vm = @import("vm.zig");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");

fn runSource(allocator: std.mem.Allocator, source: []const u8) !void {
    var lx = lexer.Lexer.init(source);
    const tokens = try lx.tokenize(allocator);
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    const program = try pr.parse();

    var virtual_machine = try vm.VM.init(allocator);
    defer virtual_machine.deinit();

    try virtual_machine.execute(program);
}

test "printf interpolation test" {
    const gpa = std.testing.allocator;
    try runSource(gpa, "[ int(42)~x <printf>^(\"Value: {x}\\n\") ]");
}
