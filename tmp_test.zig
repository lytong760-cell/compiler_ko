const std = @import("std");
const src = @import("src/testing_imports.zig");

test "import_check" {
    _ = src.lexer;
    _ = src.parser;
    _ = src.vm;
}
