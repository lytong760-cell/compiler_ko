const std = @import("std");

    pub const Token = union(enum) {
        eof,
        identifier: []const u8,
        int_lit: i64,
        freal_lit: f64,
        string_lit: []const u8,
        bool_true,
        bool_false,
        byte_lit: u8,
        bytes_lit: []const u8,
        l_bracket: void,
        r_bracket: void,
        l_paren: void,
        r_paren: void,
        l_brace: void,
        r_brace: void,
        priority_lit: i64,
        sigil: void,
        dollar: void,
        lt: void,
        gt: void,
        caret: void,
        amp_amp: void,
        logical_or: void,
        at: void,
        bang: void,
        colon: void,
        comma: void,
        dot: void,
        plus: void,
        minus: void,
        star: void,
        bold_lit: []const u8,
        slash: void,
        percent: void,
        equals: void,
        amp_equals: void,
        keyword: Keyword,

    pub const Keyword = enum {
        import_kw,
        loop_kw,
        if_kw,
        elif_kw,
        else_kw,
        return_kw,
        for_kw,
        while_kw,
        private_kw,
        class_kw,
        int_kw,
        freal_kw,
        string_kw,
        booling_kw,
        byte_kw,
        bytes_kw,
        true_kw,
        false_kw,
        catch_kw,
        now_kw,
        input_kw,
        memory_kw,
        encode_kw,
        len_kw,
        printf_kw,
        execute_kw,
    };

    pub fn keywordText(kw: Keyword) []const u8 {
        return switch (kw) {
            .import_kw => "Import",
            .loop_kw => "Loop",
            .if_kw => "if",
            .elif_kw => "elif",
            .else_kw => "else",
            .return_kw => "return",
            .for_kw => "for",
            .while_kw => "while",
            .private_kw => "private",
            .class_kw => "class",
            .int_kw => "int",
            .freal_kw => "freal",
            .string_kw => "string",
            .booling_kw => "booling",
            .byte_kw => "byte",
            .bytes_kw => "bytes",
            .true_kw => "True",
            .false_kw => "False",
            .catch_kw => "catch",
            .now_kw => "now",
            .input_kw => "input",
            .memory_kw => "memory",
            .encode_kw => "encode",
            .len_kw => "len",
            .printf_kw => "printf",
            .execute_kw => "Execute",
        };
    }
};

const KeywordMap = std.StaticStringMap(Token.Keyword).initComptime(&.{
    .{ "Import", .import_kw },
    .{ "Loop", .loop_kw },
    .{ "if", .if_kw },
    .{ "elif", .elif_kw },
    .{ "else", .else_kw },
    .{ "return", .return_kw },
    .{ "for", .for_kw },
    .{ "while", .while_kw },
    .{ "private", .private_kw },
    .{ "class", .class_kw },
    .{ "int", .int_kw },
    .{ "freal", .freal_kw },
    .{ "string", .string_kw },
    .{ "booling", .booling_kw },
    .{ "byte", .byte_kw },
    .{ "bytes", .bytes_kw },
    .{ "True", .true_kw },
    .{ "False", .false_kw },
    .{ "catch", .catch_kw },
    .{ "now", .now_kw },
    .{ "input", .input_kw },
    .{ "memory", .memory_kw },
    .{ "encode", .encode_kw },
    .{ "len", .len_kw },
    .{ "printf", .printf_kw },
    .{ "Execute", .execute_kw },
});

pub const Lexer = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    col: usize,

    pub fn init(source: []const u8) Lexer {
        return .{
            .source = source,
            .pos = 0,
            .line = 1,
            .col = 1,
        };
    }

    pub fn next(self: *Lexer) !?Token {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            self.pos += 1;
            self.col += 1;

            if (c == '\n') {
                self.line += 1;
                self.col = 1;
                continue;
            }

            if (std.ascii.isWhitespace(c)) continue;

            if (c == '|') {
                while (self.pos < self.source.len and self.source[self.pos] != '|') {
                    if (self.source[self.pos] == '\n') {
                        self.line += 1;
                        self.col = 1;
                    } else {
                        self.col += 1;
                    }
                    self.pos += 1;
                }
                if (self.pos < self.source.len) {
                    self.pos += 1;
                    self.col += 1;
                }
                continue;
            }

            if (c == '"') {
                var end = self.pos;
                while (end < self.source.len) {
                    if (self.source[end] == '"') break;
                    if (self.source[end] == '\\' and end + 1 < self.source.len) {
                        end += 2;
                    } else {
                        end += 1;
                    }
                }
                const str = self.source[self.pos..end];
                self.col += (end - self.pos + 2);
                self.pos = end + 1;
                return Token{ .string_lit = str };
            }

            if (c == '\'') {
                var end = self.pos;
                while (end < self.source.len) {
                    if (self.source[end] == '\'') break;
                    if (self.source[end] == '\\' and end + 1 < self.source.len) {
                        end += 2;
                    } else {
                        end += 1;
                    }
                }
                const str = self.source[self.pos..end];
                self.col += (end - self.pos + 2);
                self.pos = end + 1;
                return Token{ .string_lit = str };
            }

            if (c == '`') {
                var end = self.pos;
                while (end < self.source.len and self.source[end] != '`') : (end += 1) {}
                const str = self.source[self.pos..end];
                self.col += (end - self.pos + 2);
                self.pos = end + 1;
                if (std.mem.eql(u8, str, "True")) return Token.bool_true;
                if (std.mem.eql(u8, str, "False")) return Token.bool_false;
                return Token{ .identifier = str };
            }

            if (c == '[') return Token.l_bracket;
            if (c == ']') return Token.r_bracket;
            if (c == '(') return Token.l_paren;
            if (c == ')') return Token.r_paren;
            if (c == '{') {
                if (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
                    const start = self.pos;
                    var end = self.pos;
                    while (end < self.source.len and std.ascii.isDigit(self.source[end])) : (end += 1) {}
                    if (end < self.source.len and self.source[end] == '}') {
                        const num_str = self.source[start..end];
                        const num = std.fmt.parseInt(i64, num_str, 10) catch unreachable;
                        self.pos = end + 1;
                        self.col += (end - start + 2);
                        return Token{ .priority_lit = num };
                    }
                }
                return Token.l_brace;
            }
            if (c == '}') return Token.r_brace;
            if (c == '~') return Token.sigil;
            if (c == '$') return Token.dollar;
            if (c == '<') return Token.lt;
            if (c == '>') return Token.gt;
            if (c == '^') return Token.caret;
            if (c == '+') return Token.plus;
            if (c == '-') return Token.minus;
            if (c == '*') {
                if (self.pos < self.source.len and self.source[self.pos] == '*') {
                    self.pos += 1;
                    self.col += 1;
                    const start = self.pos;
                    while (self.pos < self.source.len) {
                        if (self.source[self.pos] == '*' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '*') {
                            break;
                        }
                        self.pos += 1;
                        self.col += 1;
                    }
                    if (self.pos >= self.source.len) {
                        return error.UnterminatedBoldLiteral;
                    }
                    const word = self.source[start..self.pos];
                    if (!std.mem.eql(u8, word, "Loop") and !std.mem.eql(u8, word, "Import")) {
                        return error.UnexpectedToken;
                    }
                    self.pos += 2;
                    self.col += 2;
                    return Token{ .bold_lit = word };
                }
                return Token.star;
            }
            if (c == '/') return Token.slash;
            if (c == '%') {
                if (self.pos < self.source.len and self.source[self.pos] == '%') {
                    self.pos += 1;
                    self.col += 1;
                    return Token.logical_or;
                }
                return Token.percent;
            }
            if (c == '&') {
                if (self.pos < self.source.len and self.source[self.pos] == '&') {
                    self.pos += 1;
                    self.col += 1;
                    return Token.amp_amp;
                }
                if (self.pos < self.source.len and self.source[self.pos] == '=') {
                    self.pos += 1;
                    self.col += 1;
                    return Token.amp_equals;
                }
                return error.UnexpectedToken;
            }
            if (c == '@') return Token.at;
            if (c == '!') return Token.bang;
            if (c == ':') return Token.colon;
            if (c == ',') return Token.comma;
            if (c == '.') return Token.dot;
            if (c == '=') return Token.equals;

            if (std.ascii.isDigit(c)) {
                var end = self.pos - 1;
                var has_dot = false;
                while (end < self.source.len) {
                    const ch = self.source[end];
                    if (std.ascii.isDigit(ch)) {
                        end += 1;
                    } else if (ch == '.' and !has_dot) {
                        has_dot = true;
                        end += 1;
                    } else {
                        break;
                    }
                }
                const num_str = self.source[self.pos - 1 .. end];
                const num_len = end - self.pos + 1;
                self.pos = end;
                self.col += num_len;
                if (has_dot) {
                    return Token{ .freal_lit = std.fmt.parseFloat(f64, num_str) catch unreachable };
                } else {
                    return Token{ .int_lit = std.fmt.parseInt(i64, num_str, 10) catch |err| {
                        if (err == error.Overflow) return error.NumberOverflow;
                        return err;
                    } };
                }
            }

            if (std.ascii.isAlphabetic(c) or c == '_') {
                var end = self.pos - 1;
                while (end < self.source.len and (std.ascii.isAlphanumeric(self.source[end]) or self.source[end] == '_')) : (end += 1) {}
                const word = self.source[self.pos - 1 .. end];
                self.pos = end;
                self.col = end + 1;

                if (std.mem.eql(u8, word, "True")) return Token.bool_true;
                if (std.mem.eql(u8, word, "False")) return Token.bool_false;
                if (KeywordMap.get(word)) |kw| {
                    return Token{ .keyword = kw };
                }

                return Token{ .identifier = word };
            }

            if (c == '\\') {
                const start = self.pos - 1;
                if (std.mem.startsWith(u8, self.source[start..], "\\True\\")) {
                    self.pos = start + 6;
                    self.col += 6;
                    return Token.bool_true;
                }
                if (std.mem.startsWith(u8, self.source[start..], "\\False\\")) {
                    self.pos = start + 7;
                    self.col += 7;
                    return Token.bool_false;
                }
                return error.UnexpectedToken;
            }

            continue;
        }
        return Token.eof;
    }

    pub fn tokenize(self: *Lexer, allocator: std.mem.Allocator) ![]Token {
        var tokens = std.array_list.Managed(Token).init(allocator);
        defer tokens.deinit();

        while (true) {
            const tok = (try self.next()) orelse Token.eof;
            if (tok == Token.eof) break;
            try tokens.append(tok);
        }
        try tokens.append(Token.eof);
        return tokens.toOwnedSlice();
    }
};
