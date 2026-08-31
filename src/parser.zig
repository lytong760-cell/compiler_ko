const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const value_mod = @import("value.zig");

pub const Parser = struct {
    tokens: []lexer.Token,
    pos: usize,
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, arena: *std.heap.ArenaAllocator, tokens: []lexer.Token) Parser {
        _ = allocator;
        return .{
            .tokens = tokens,
            .pos = 0,
            .arena = arena,
            .allocator = arena.allocator(),
        };
    }

    pub fn current(self: *Parser) lexer.Token {
        if (self.pos < self.tokens.len) return self.tokens[self.pos];
        return lexer.Token.eof;
    }

    pub fn advance(self: *Parser) lexer.Token {
        const tok = self.current();
        self.pos += 1;
        return tok;
    }

    pub fn peek(self: *Parser, offset: usize) lexer.Token {
        const idx = self.pos + offset;
        if (idx < self.tokens.len) return self.tokens[idx];
        return lexer.Token.eof;
    }

    pub fn isAtEnd(self: *Parser) bool {
        return self.current() == lexer.Token.eof;
    }

    pub fn parse(self: *Parser) anyerror![]ast.Statement {
        var stmts = std.ArrayList(ast.Statement).init(self.allocator);
        defer stmts.deinit();

        while (!self.isAtEnd()) {
            const stmt = try self.parseStatement();
            stmts.append(stmt) catch unreachable;
        }

        return try stmts.toOwnedSlice();
    }

    fn parseStatement(self: *Parser) anyerror!ast.Statement {
        const tok = self.current();

        if (tok == .keyword) {
            switch (tok.keyword) {
                .int_kw, .freal_kw, .string_kw, .booling_kw, .byte_kw, .bytes_kw => {
                    return try self.parseVarDecl();
                },
                .import_kw => {
                    return try self.parseImportStmt();
                },
                .loop_kw => {
                    return try self.parseLoopStmt();
                },
                .return_kw => {
                    return try self.parseReturnStmt();
                },
                .class_kw => {
                    return try self.parseClassDecl();
                },
                .now_kw => {
                    return try self.parseNowStmt();
                },
                .memory_kw => {
                    return try self.parseMemoryOpStmt();
                },
                .encode_kw => {
                    return try self.parseEncodingOpStmt();
                },
                .len_kw => {
                    return try self.parseLenOpStmt();
                },
                .input_kw => {
                    return try self.parseInputStmt();
                },
                .printf_kw => {
                    return try self.parsePrintfStmt();
                },
                .catch_kw => {
                    return try self.parseCatchStmt();
                },
                else => {},
            }
        }

        if (tok == .lt) {
            return try self.parseSystemTagStmt();
        }

        if (tok == .identifier) {
            if (self.peek(1) == .bang and self.peek(2) == .keyword and self.peek(2).keyword == .class_kw) {
                return try self.parseClassDecl();
            }
            if (self.peek(1) == .l_paren) {
                var depth: usize = 1;
                var i: usize = 2;
                while (self.pos + i < self.tokens.len and depth > 0) {
                    switch (self.tokens[self.pos + i]) {
                        .l_paren => depth += 1,
                        .r_paren => depth -= 1,
                        else => {},
                    }
                    i += 1;
                }
                if (self.pos + i < self.tokens.len and self.tokens[self.pos + i] == .l_bracket) {
                    return try self.parseFuncDecl();
                }
            }
            return try self.parseExprStatement();
        }

        if (tok == .sigil or tok == .dollar) {
            return try self.parseExprStatement();
        }

        if (tok == .l_bracket) {
             return try self.parseBlockStatement();
        }

        return error.UnexpectedToken;
    }

    fn parseBlockStatement(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
            const stmt = try self.parseStatement();
            try body.append(stmt);
        }
        try self.expectRBracket();
        return ast.Statement{ .block = ast.BlockStmt{ .body = try body.toOwnedSlice(), .allocator = self.allocator } };
    }

    fn parseLoopStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();

        if (self.current() == .lt) {
            _ = self.advance();
            const tag = try self.parseSystemTagName();
            try self.expectGT();

            if (self.current() == .caret) {
                _ = self.advance();
                try self.expectLParen();
                const expr = try self.parseExpression();
                try self.expectRParen();

                const ste = try self.allocator.create(ast.SystemTagExpr);
                ste.* = ast.SystemTagExpr{
                    .tag = tag,
                    .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
                };
                const e = try self.allocator.create(ast.Expr);
                e.* = .{ .system_tag = ste };
                return ast.Statement{ .expr = e };
            }

            try self.expectLParen();
            var init: ?*ast.Assignment = null;
            var step: ?*ast.Expr = null;
            var cond = try self.parseExpression();
            try self.expectRParen();
            try self.expectLBracket();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
                while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
                const stmt = try self.parseStatement();
                    try body.append(stmt);
            }
            try self.expectRBracket();

            const kind: ast.ControlFlow.Kind = if (std.mem.eql(u8, tag, "for")) .for_loop else .while_loop;
            const cf = try self.allocator.create(ast.ControlFlow);
            cf.* = ast.ControlFlow{
                .kind = kind,
                .condition = cond,
                .body = try body.toOwnedSlice(),
                .init = init,
                .step = step,
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
                .allocator = self.allocator,
            };
            return ast.Statement{ .control_flow = cf };
        }

        if (self.current() == .l_bracket) {
            _ = self.advance();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
                while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
                const stmt = try self.parseStatement();
                    try body.append(stmt);
            }
            try self.expectRBracket();

            const cf = try self.allocator.create(ast.ControlFlow);
            cf.* = ast.ControlFlow{
                .kind = .while_loop,
                .condition = try self.allocator.create(ast.Expr),
                .body = try body.toOwnedSlice(),
                .init = null,
                .step = null,
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
                .allocator = self.allocator,
            };
            return ast.Statement{ .control_flow = cf };
        }

        return error.UnexpectedToken;
    }