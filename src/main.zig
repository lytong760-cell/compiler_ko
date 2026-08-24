const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const vm = @import("vm.zig");
const ast = @import("ast.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try std.io.getStdOut().writer().print("Usage: ko <file.ko>\n", .{});
        return;
    }

    const file_path = args[1];
    const source = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| {
        try std.io.getStdErr().writer().print("Error reading file: {any}\n", .{err});
        return;
    };
    defer allocator.free(source);

    var lx = lexer.Lexer.init(source);
    const tokens = lx.tokenize(allocator) catch |err| {
        try std.io.getStdErr().writer().print("Lexer error: {any}\n", .{err});
        return;
    };
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    const program = pr.parse() catch |err| {
        try std.io.getStdErr().writer().print("Parser error: {any}\n", .{err});
        return;
    };
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    var virtual_machine = try vm.VM.init(allocator);
    defer virtual_machine.deinit();

    virtual_machine.execute(program) catch |err| {
        try std.io.getStdErr().writer().print("Runtime error: {any}\n", .{err});
        return;
    };
}
