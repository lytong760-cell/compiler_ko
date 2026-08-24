const std = @import("std");
const lexer = @import("lexer.zig");

test "lexer basic" {
    const source = "[ int(10)~x ]";
    var lx = lexer.Lexer.init(source);
    var gpa = std.testing.allocator;
    const tokens = lx.tokenize(gpa) catch |err| {
        std.debug.print("Lexer error: {any}\n", .{err});
        return;
    };
    defer gpa.free(tokens);

    for (tokens) |tok| {
        switch (tok) {
            .identifier => |name| {
                std.debug.print("identifier: '{s}' len={d}\n", .{name, name.len});
            },
            else => {
                std.debug.print("{any}\n", .{tok});
            },
        }
    }
}
