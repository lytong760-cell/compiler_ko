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
        sigil: void,
        dollar: void,
        lt: void,
        gt: void,
        caret: void,
        amp_amp: void,
        pipe_pipe: void,
        at: void,
        bang: void,
        colon: void,
        comma: void,
        dot: void,
        plus: void,
        minus: void,
        star: void,
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

    pub fn next(self: *Lexer) ?Token {
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
                while (self.pos < self.source.len and self.source[self.pos] != '|') : (self.pos += 1) {}
                if (self.pos < self.source.len) self.pos += 1;
                continue;
            }

            if (c == '\"') {
                var end = self.pos;
                while (end < self.source.len and self.source[end] != '\"') : (end += 1) {}
                const str = self.source[self.pos..end];
                self.pos = end + 1;
                self.col = end + 1;
                return Token{ .string_lit = str };
            }

            if (c == '\'') {
                var end = self.pos;
                while (end < self.source.len and self.source[end] != '\'') : (end += 1) {}
                const str = self.source[self.pos..end];
                self.pos = end + 1;
                self.col = end + 1;
                return Token{ .string_lit = str };
            }

            if (c == '`') {
                var end = self.pos;
                while (end < self.source.len and self.source[end] != '`') : (end += 1) {}
                const str = self.source[self.pos..end];
                self.pos = end + 1;
                self.col = end + 1;
                if (std.mem.eql(u8, str, "True")) return Token.bool_true;
                if (std.mem.eql(u8, str, "False")) return Token.bool_false;
                return Token{ .identifier = str };
            }

            if (c == '[') return Token.l_bracket;
            if (c == ']') return Token.r_bracket;
            if (c == '(') return Token.l_paren;
            if (c == ')') return Token.r_paren;
            if (c == '{') return Token.l_brace;
            if (c == '}') return Token.r_brace;
            if (c == '~') return Token.sigil;
            if (c == '$') return Token.dollar;
            if (c == '<') return Token.lt;
            if (c == '>') return Token.gt;
            if (c == '^') return Token.caret;
            if (c == '+') return Token.plus;
            if (c == '-') return Token.minus;
            if (c == '*') return Token.star;
            if (c == '/') return Token.slash;
            if (c == '%') {
                if (self.pos < self.source.len and self.source[self.pos] == '%') {
                    self.pos += 1;
                    self.col += 1;
                    return Token.pipe_pipe;
                }
                return Token.percent;
            }
            if (c == '&') {
                if (self.pos < self.source.len and self.source[self.pos] == '&') {
                    self.pos += 1;
                    self.col += 1;
                    return Token.amp_amp;
                }
                continue;
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
                self.pos = end;
                self.col = end + 1;
                if (has_dot) {
                    return Token{ .freal_lit = std.fmt.parseFloat(f64, num_str) catch unreachable };
                } else {
                    return Token{ .int_lit = std.fmt.parseInt(i64, num_str, 10) catch unreachable };
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
                if (std.mem.eql(u8, word, "Import")) return Token{ .keyword = .import_kw };
                if (std.mem.eql(u8, word, "Loop")) return Token{ .keyword = .loop_kw };
                if (std.mem.eql(u8, word, "if")) return Token{ .keyword = .if_kw };
                if (std.mem.eql(u8, word, "elif")) return Token{ .keyword = .elif_kw };
                if (std.mem.eql(u8, word, "else")) return Token{ .keyword = .else_kw };
                if (std.mem.eql(u8, word, "return")) return Token{ .keyword = .return_kw };
                if (std.mem.eql(u8, word, "for")) return Token{ .keyword = .for_kw };
                if (std.mem.eql(u8, word, "while")) return Token{ .keyword = .while_kw };
                if (std.mem.eql(u8, word, "private")) return Token{ .keyword = .private_kw };
                if (std.mem.eql(u8, word, "class")) return Token{ .keyword = .class_kw };
                if (std.mem.eql(u8, word, "int")) return Token{ .keyword = .int_kw };
                if (std.mem.eql(u8, word, "freal")) return Token{ .keyword = .freal_kw };
                if (std.mem.eql(u8, word, "string")) return Token{ .keyword = .string_kw };
                if (std.mem.eql(u8, word, "booling")) return Token{ .keyword = .booling_kw };
                if (std.mem.eql(u8, word, "byte")) return Token{ .keyword = .byte_kw };
                if (std.mem.eql(u8, word, "bytes")) return Token{ .keyword = .bytes_kw };
                if (std.mem.eql(u8, word, "catch")) return Token{ .keyword = .catch_kw };
                if (std.mem.eql(u8, word, "now")) return Token{ .keyword = .now_kw };
                if (std.mem.eql(u8, word, "input")) return Token{ .keyword = .input_kw };
                if (std.mem.eql(u8, word, "memory")) return Token{ .keyword = .memory_kw };
                if (std.mem.eql(u8, word, "encode")) return Token{ .keyword = .encode_kw };
                if (std.mem.eql(u8, word, "len")) return Token{ .keyword = .len_kw };
                if (std.mem.eql(u8, word, "printf")) return Token{ .keyword = .printf_kw };
                if (std.mem.eql(u8, word, "Execute")) return Token{ .keyword = .execute_kw };

                return Token{ .identifier = word };
            }

            if (c == '\\') {
                const start = self.pos - 1;
                if (std.mem.startsWith(u8, self.source[start..], "\\True\\")) {
                    self.pos = start + 6;
                    return Token.bool_true;
                }
                if (std.mem.startsWith(u8, self.source[start..], "\\False\\")) {
                    self.pos = start + 7;
                    return Token.bool_false;
                }
            }

            continue;
        }
        return Token.eof;
    }

    pub fn tokenize(self: *Lexer, allocator: std.mem.Allocator) ![]Token {
        var tokens = std.ArrayList(Token).init(allocator);
        defer tokens.deinit();

        while (true) {
            const tok = self.next() orelse Token.eof;
            if (tok == Token.eof) break;
            try tokens.append(tok);
        }
        try tokens.append(Token.eof);
        return tokens.toOwnedSlice();
    }
};
