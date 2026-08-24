const std = @import("std");
const ast = @import("ast.zig");

pub const Parser = struct {
    tokens: []Token,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, tokens: []Token) Parser {
        return .{
            .tokens = tokens,
            .pos = 0,
            .allocator = allocator,
        };
    }

    pub fn current(self: *Parser) Token {
        if (self.pos < self.tokens.len) return self.tokens[self.pos];
        return Token.eof;
    }

    pub fn advance(self: *Parser) Token {
        const tok = self.current();
        self.pos += 1;
        return tok;
    }

    pub fn expect(self: *Parser, expected: Token) !void {
        const tok = self.current();
        if (!tokensEqual(tok, expected)) {
            return error.UnexpectedToken;
        }
        self.pos += 1;
    }

    pub fn match(self: *Parser, comptime expected: Token) bool {
        const tok = self.current();
        return tokensEqual(tok, expected);
    }

    pub fn parse(self: *Parser) ![]ast.Statement {
        var stmts = std.ArrayList(ast.Statement).init(self.allocator);
        defer stmts.deinit();

        while (!self.match(Token.eof)) {
            const stmt = try self.parseStatement();
            try stmts.append(stmt);
        }

        return stmts.toOwnedSlice();
    }

    fn tokensEqual(a: Token, b: Token) bool {
        _ = a;
        _ = b;
        return false;
    }

    fn parseStatement(self: *Parser) !ast.Statement {
        const tok = self.current();

        if (tok == .keyword) {
            switch (tok.keyword) {
                .int_kw, .freal_kw, .string_kw, .booling_kw, .byte_kw, .bytes_kw => {
                    return try self.parseVarDecl();
                },
                .import_kw => {
                    _ = self.advance();
                    return try self.parseImport();
                },
                .loop_kw => {
                    return try self.parseLoop();
                },
                .if_kw => {
                    return try self.parseIf();
                },
                .elif_kw => {
                    return try self.parseElif();
                },
                .else_kw => {
                    return try self.parseElse();
                },
                .return_kw => {
                    return try self.parseReturn();
                },
                .catch_kw => {
                    return try self.parseCatch();
                },
                .class_kw => {
                    return try self.parseClassDecl();
                },
                .now_kw => {
                    return try self.parseNow();
                },
                .memory_kw => {
                    return try self.parseMemoryOp();
                },
                .encode_kw => {
                    return try self.parseEncodingOp();
                },
                .len_kw => {
                    return try self.parseLenOp();
                },
                .input_kw => {
                    return try self.parseInput();
                },
                .printf_kw => {
                    return try self.parsePrintf();
                },
                else => {},
            }
        }

        if (tok == .lt) {
            return try self.parseSystemTagStmt();
        }

        if (tok == .at) {
            return try self.parseAtStatement();
        }

        if (tok == .identifier or tok == .sigil or tok == .dollar) {
            return try self.parseExprStatement();
        }

        if (tok == .l_bracket) {
            return try self.parseBlockStatement();
        }

        return error.UnexpectedToken;
    }

    fn parseVarDecl(self: *Parser) !ast.Statement {
        const type_tok = self.advance();
        const type_name = switch (type_tok.keyword) {
            .int_kw => "int",
            .freal_kw => "freal",
            .string_kw => "string",
            .booling_kw => "booling",
            .byte_kw => "byte",
            .bytes_kw => "bytes",
            else => unreachable,
        };

        try self.expect(Token.l_paren);
        const value_expr = try self.parseExpression();
        try self.expect(Token.r_paren);

        const sigil_tok = self.current();
        if (sigil_tok != .sigil) return error.ExpectedSigil;
        _ = self.advance();

        const name_tok = self.current();
        if (name_tok != .identifier) return error.ExpectedIdentifier;
        const name = name_tok.identifier;
        _ = self.advance();

        return ast.Statement{ .var_decl = ast.VarDecl{
            .type_name = name,
            .value_expr = value_expr,
            .sigil = true,
            .name = name,
        } };
    }

    fn parseImport(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.l_paren);
        const expr = try self.parseExpression();
        try self.expect(Token.r_paren);
        return ast.Statement{ .expr = ast.Expr{ .call = ast.CallExpr{
            .callee = "Import",
            .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
        } } };
    }

    fn parseLoop(self: *Parser) !ast.Statement {
        _ = self.advance();

        if (self.match(Token.lt)) {
            _ = self.advance();
            const tag = try self.parseSystemTag();
            try self.expect(Token.gt);

            if (self.match(Token.caret)) {
                _ = self.advance();
                try self.expect(Token.l_paren);
                const expr = try self.parseExpression();
                try self.expect(Token.r_paren);
                return ast.Statement{ .expr = ast.Expr{ .system_tag = ast.SystemTagExpr{
                    .tag = tag,
                    .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
                } } };
            }

            try self.expect(Token.l_bracket);
            var body = std.ArrayList(ast.Statement).init(self.allocator);
            while (!self.match(Token.r_bracket) and !self.match(Token.eof)) {
                try body.append(try self.parseStatement());
            }
            try self.expect(Token.r_bracket);

            return ast.Statement{ .control_flow = ast.ControlFlow{
                .kind = .loop_for,
                .condition = try self.allocator.create(ast.Expr),
                .body = body.toOwnedSlice(),
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
            } };
        }

        if (self.match(Token.l_bracket)) {
            _ = self.advance();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
            while (!self.match(Token.r_bracket) and !self.match(Token.eof)) {
                try body.append(try self.parseStatement());
            }
            try self.expect(Token.r_bracket);
            return ast.Statement{ .control_flow = ast.ControlFlow{
                .kind = .while_loop,
                .condition = try self.allocator.create(ast.Expr),
                .body = body.toOwnedSlice(),
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
            } };
        }

        return error.UnexpectedToken;
    }

    fn parseIf(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.lt);
        _ = self.advance();
        try self.expect(Token.gt);
        try self.expect(Token.l_paren);
        const cond = try self.parseExpression();
        try self.expect(Token.r_paren);
        try self.expect(Token.l_bracket);
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.match(Token.r_bracket) and !self.match(Token.eof)) {
            try body.append(try self.parseStatement());
        }
        try self.expect(Token.r_bracket);

        return ast.Statement{ .control_flow = ast.ControlFlow{
            .kind = .if_stmt,
            .condition = cond,
            .body = body.toOwnedSlice(),
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
        } };
    }

    fn parseElif(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.lt);
        _ = self.advance();
        try self.expect(Token.gt);
        try self.expect(Token.l_paren);
        const cond = try self.parseExpression();
        try self.expect(Token.r_paren);
        try self.expect(Token.l_bracket);
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.match(Token.r_bracket) and !self.match(Token.eof)) {
            try body.append(try self.parseStatement());
        }
        try self.expect(Token.r_bracket);

        return ast.Statement{ .control_flow = ast.ControlFlow{
            .kind = .elif_stmt,
            .condition = cond,
            .body = body.toOwnedSlice(),
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
        } };
    }

    fn parseElse(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.l_bracket);
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.match(Token.r_bracket) and !self.match(Token.eof)) {
            try body.append(try self.parseStatement());
        }
        try self.expect(Token.r_bracket);

        return ast.Statement{ .control_flow = ast.ControlFlow{
            .kind = .else_stmt,
            .condition = try self.allocator.create(ast.Expr),
            .body = body.toOwnedSlice(),
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
        } };
    }

    fn parseReturn(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.l_paren);
        const expr = try self.parseExpression();
        try self.expect(Token.r_paren);
        return ast.Statement{ .return_stmt = ast.ReturnStmt{ .expr = expr } };
    }

    fn parseCatch(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.l_paren);
        const err_type = try self.parseErrorType();
        try self.expect(Token.r_paren);
        try self.expect(Token.l_bracket);
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.match(Token.r_bracket) and !self.match(Token.eof)) {
            try body.append(try self.parseStatement());
        }
        try self.expect(Token.r_bracket);

        return ast.Statement{ .catch_stmt = ast.CatchStmt{
            .error_type = err_type,
            .body = body.toOwnedSlice(),
        } };
    }

    fn parseErrorType(self: *Parser) ![]const u8 {
        const tok = self.current();
        if (tok == .backtick or tok == .identifier) {
            const name = tok.identifier;
            _ = self.advance();
            return name;
        }
        return error.UnexpectedToken;
    }

    fn parseClassDecl(self: *Parser) !ast.Statement {
        _ = self.advance();
        const name_tok = self.current();
        if (name_tok != .identifier) return error.ExpectedIdentifier;
        const name = name_tok.identifier;
        _ = self.advance();

        try self.expect(Token.l_bracket);
        var private_body = std.ArrayList(ast.Statement).init(self.allocator);
        var public_body = std.ArrayList(ast.Statement).init(self.allocator);
        var current_private = true;

        while (!self.match(Token.r_bracket) and !self.match(Token.eof)) {
            if (self.match(Token.at) and self.peekKeyword(.private_kw)) {
                _ = self.advance();
                _ = self.advance();
                try self.expect(Token.l_bracket);
                current_private = true;
                continue;
            }
            if (self.match(Token.r_bracket)) break;
            const stmt = try self.parseStatement();
            if (current_private) {
                try private_body.append(stmt);
            } else {
                try public_body.append(stmt);
            }
        }
        try self.expect(Token.r_bracket);

        return ast.Statement{ .class_decl = ast.ClassDecl{
            .name = name,
            .private_body = private_body.toOwnedSlice(),
            .public_body = public_body.toOwnedSlice(),
        } };
    }

    fn peekKeyword(self: *Parser, kw: Token.Keyword) bool {
        if (self.pos + 1 >= self.tokens.len) return false;
        const next = self.tokens[self.pos + 1];
        return next == .keyword and next.keyword == kw;
    }

    fn parseNow(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.l_paren);
        const expr = try self.parseExpression();
        try self.expect(Token.r_paren);
        try self.expect(Token.gt);
        const target = try self.parseExpression();
        return ast.Statement{ .expr = ast.Expr{ .now_expr = ast.NowExpr{ .expr = expr } } };
    }

    fn parseMemoryOp(self: *Parser) !ast.Statement {
        _ = self.advance();
        if (self.match(Token.identifier) and std.mem.eql(u8, self.current().identifier, "dete")) {
            _ = self.advance();
            try self.expect(Token.l_paren);
            const expr = try self.parseExpression();
            try self.expect(Token.r_paren);
            return ast.Statement{ .memory_op = ast.MemoryOp{
                .kind = .dete,
                .expr = expr,
            } };
        }
        if (self.match(Token.caret)) {
            _ = self.advance();
            try self.expect(Token.l_paren);
            const expr = try self.parseExpression();
            try self.expect(Token.r_paren);
            return ast.Statement{ .memory_op = ast.MemoryOp{
                .kind = .address,
                .expr = expr,
            } };
        }
        return error.UnexpectedToken;
    }

    fn parseEncodingOp(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.lt);
        const tag = try self.parseSystemTag();
        try self.expect(Token.gt);
        try self.expect(Token.caret);
        try self.expect(Token.l_paren);
        const expr = try self.parseExpression();
        try self.expect(Token.r_paren);
        return ast.Statement{ .encoding_op = ast.EncodingOp{
            .encoding_type = tag,
            .expr = expr,
        } };
    }

    fn parseLenOp(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.lt);
        _ = self.advance();
        try self.expect(Token.gt);
        try self.expect(Token.caret);
        try self.expect(Token.l_paren);
        const expr = try self.parseExpression();
        try self.expect(Token.r_paren);
        return ast.Statement{ .len_op = ast.LenOp{ .expr = expr } };
    }

    fn parseInput(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.l_paren);
        const expr = try self.parseExpression();
        try self.expect(Token.r_paren);
        if (self.match(Token.equals)) {
            _ = self.advance();
            const target = try self.parseExpression();
            return ast.Statement{ .expr = ast.Expr{ .input_expr = ast.InputExpr{ .target = target } } };
        }
        return ast.Statement{ .expr = ast.Expr{ .input_expr = ast.InputExpr{ .target = null } } };
    }

    fn parsePrintf(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expect(Token.caret);
        try self.expect(Token.l_paren);
        const expr = try self.parseExpression();
        try self.expect(Token.r_paren);
        return ast.Statement{ .expr = ast.Expr{ .call = ast.CallExpr{
            .callee = "printf",
            .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
        } } };
    }

    fn parseSystemTagStmt(self: *Parser) !ast.Statement {
        try self.expect(Token.lt);
        const tag = try self.parseSystemTag();
        try self.expect(Token.gt);

        if (self.match(Token.caret)) {
            _ = self.advance();
            try self.expect(Token.l_paren);
            const expr = try self.parseExpression();
            try self.expect(Token.r_paren);
            return ast.Statement{ .expr = ast.Expr{ .system_tag = ast.SystemTagExpr{
                .tag = tag,
                .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
            } } };
        }

        if (self.match(Token.l_paren)) {
            _ = self.advance();
            const expr = try self.parseExpression();
            try self.expect(Token.r_paren);
            return ast.Statement{ .expr = ast.Expr{ .call = ast.CallExpr{
                .callee = tag,
                .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
            } } };
        }

        return error.UnexpectedToken;
    }

    fn parseAtStatement(self: *Parser) !ast.Statement {
        _ = self.advance();
        const keyword = self.current().keyword;
        if (keyword == .loop_kw) {
            return try self.parseLoop();
        }
        return error.UnexpectedToken;
    }

    fn parseSystemTag(self: *Parser) ![]const u8 {
        const tok = self.current();
        if (tok == .keyword) {
            const name = tok.keywordText();
            _ = self.advance();
            return name;
        }
        if (tok == .identifier) {
            const name = tok.identifier;
            _ = self.advance();
            return name;
        }
        return error.UnexpectedToken;
    }

    fn parseBlockStatement(self: *Parser) !ast.Statement {
        _ = self.advance();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.match(Token.r_bracket) and !self.match(Token.eof)) {
            try body.append(try self.parseStatement());
        }
        try self.expect(Token.r_bracket);
        return ast.Statement{ .expr = ast.Expr{ .literal = ast.Literal{ .kind = .null, .value = "" } } };
    }

    fn parseExprStatement(self: *Parser) !ast.Statement {
        const expr = try self.parseExpression();
        return ast.Statement{ .expr = expr.* };
    }

    fn parseExpression(self: *Parser) !*ast.Expr {
        const expr = try self.parseOrExpr();
        return expr;
    }

    fn parseOrExpr(self: *Parser) !*ast.Expr {
        var left = try self.parseAndExpr();
        while (self.match(Token.pipe_pipe)) {
            _ = self.advance();
            const right = try self.parseAndExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = .{
                .op = .or,
                .left = left,
                .right = right,
            };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin.* };
        }
        return left;
    }

    fn parseAndExpr(self: *Parser) !*ast.Expr {
        var left = try self.parseEqualityExpr();
        while (self.match(Token.amp_amp)) {
            _ = self.advance();
            const right = try self.parseEqualityExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = .{
                .op = .and,
                .left = left,
                .right = right,
            };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin.* };
        }
        return left;
    }

    fn parseEqualityExpr(self: *Parser) !*ast.Expr {
        var left = try self.parseRelationalExpr();
        while (true) {
            if (self.match(Token.equals)) {
                _ = self.advance();
                const right = try self.parseRelationalExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = .{ .op = .eq, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin.* };
            } else if (self.match(Token.neq)) {
                _ = self.advance();
                const right = try self.parseRelationalExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = .{ .op = .neq, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin.* };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseRelationalExpr(self: *Parser) !*ast.Expr {
        var left = try self.parseAdditiveExpr();
        while (true) {
            if (self.match(Token.lt)) {
                _ = self.advance();
                const right = try self.parseAdditiveExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = .{ .op = .lt, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin.* };
            } else if (self.match(Token.gt)) {
                _ = self.advance();
                const right = try self.parseAdditiveExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = .{ .op = .gt, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin.* };
            } else if (self.match(Token.lte)) {
                _ = self.advance();
                const right = try self.parseAdditiveExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = .{ .op = .lte, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin.* };
            } else if (self.match(Token.gte)) {
                _ = self.advance();
                const right = try self.parseAdditiveExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = .{ .op = .gte, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin.* };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseAdditiveExpr(self: *Parser) !*ast.Expr {
        var left = try self.parseMultiplicativeExpr();
        while (self.match(Token.plus) or self.match(Token.minus)) {
            const op_tok = self.advance();
            const right = try self.parseMultiplicativeExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = .{
                .op = switch (op_tok) {
                    .plus => .add,
                    .minus => .sub,
                    else => unreachable,
                },
                .left = left,
                .right = right,
            };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin.* };
        }
        return left;
    }

    fn parseMultiplicativeExpr(self: *Parser) !*ast.Expr {
        var left = try self.parseUnaryExpr();
        while (self.match(Token.star) or self.match(Token.slash) or self.match(Token.percent)) {
            const op_tok = self.advance();
            const right = try self.parseUnaryExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = .{
                .op = switch (op_tok) {
                    .star => .mul,
                    .slash => .div,
                    .percent => .rem,
                    else => unreachable,
                },
                .left = left,
                .right = right,
            };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin.* };
        }
        return left;
    }

    fn parseUnaryExpr(self: *Parser) !*ast.Expr {
        if (self.match(Token.minus)) {
            _ = self.advance();
            const expr = try self.parseUnaryExpr();
            const unary = try self.allocator.create(ast.UnaryExpr);
            unary.* = .{ .op = .neg, .expr = expr };
            return try self.allocator.create(ast.Expr);
        }
        return try self.parsePrimaryExpr();
    }

    fn parsePrimaryExpr(self: *Parser) !*ast.Expr {
        const tok = self.current();

        if (tok == .int_lit) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = .{ .kind = .int, .value = "" };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .freal_lit) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = .{ .kind = .freal, .value = "" };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .string_lit) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = .{ .kind = .string, .value = tok.string_lit };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .bool_true) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = .{ .kind = .bool_true, .value = "" };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .bool_false) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = .{ .kind = .bool_false, .value = "" };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .identifier) {
            const name = tok.identifier;
            _ = self.advance();
            if (self.match(Token.l_paren)) {
                _ = self.advance();
                var args = std.ArrayList(ast.Expr).init(self.allocator);
                while (!self.match(Token.r_paren) and !self.match(Token.eof)) {
                    try args.append(try self.parseExpression());
                    if (self.match(Token.comma)) _ = self.advance();
                }
                try self.expect(Token.r_paren);
                const call = try self.allocator.create(ast.CallExpr);
                call.* = .{
                    .callee = name,
                    .args = args.toOwnedSlice(),
                };
                return try self.allocator.create(ast.Expr);
            }
            const ident = try self.allocator.create(ast.Identifier);
            ident.* = .{ .name = name };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .sigil) {
            _ = self.advance();
            const name_tok = self.current();
            if (name_tok != .identifier) return error.ExpectedIdentifier;
            const name = name_tok.identifier;
            _ = self.advance();
            if (self.match(Token.l_paren)) {
                _ = self.advance();
                var args = std.ArrayList(ast.Expr).init(self.allocator);
                while (!self.match(Token.r_paren) and !self.match(Token.eof)) {
                    try args.append(try self.parseExpression());
                    if (self.match(Token.comma)) _ = self.advance();
                }
                try self.expect(Token.r_paren);
                const call = try self.allocator.create(ast.CallExpr);
                call.* = .{
                    .callee = name,
                    .args = args.toOwnedSlice(),
                };
                return try self.allocator.create(ast.Expr);
            }
            const ident = try self.allocator.create(ast.Identifier);
            ident.* = .{ .name = name };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .dollar) {
            _ = self.advance();
            const name_tok = self.current();
            if (name_tok != .identifier) return error.ExpectedIdentifier;
            const name = name_tok.identifier;
            _ = self.advance();
            if (self.match(Token.sigil)) {
                _ = self.advance();
                const method = self.current().identifier;
                _ = self.advance();
                if (self.match(Token.l_paren)) {
                    _ = self.advance();
                    var args = std.ArrayList(ast.Expr).init(self.allocator);
                    while (!self.match(Token.r_paren) and !self.match(Token.eof)) {
                        try args.append(try self.parseExpression());
                        if (self.match(Token.comma)) _ = self.advance();
                    }
                    try self.expect(Token.r_paren);
                    const call = try self.allocator.create(ast.CallExpr);
                    call.* = .{
                        .callee = method,
                        .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{}),
                    };
                    const member = try self.allocator.create(ast.MemberAccess);
                    member.* = .{
                        .object = try self.allocator.create(ast.Expr),
                        .member = method,
                    };
                    member.object.* = .{ .identifier = ast.Identifier{ .name = name } };
                    return try self.allocator.create(ast.Expr);
                }
            }
            const ident = try self.allocator.create(ast.Identifier);
            ident.* = .{ .name = name };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .l_paren) {
            _ = self.advance();
            var items = std.ArrayList(ast.Expr).init(self.allocator);
            while (!self.match(Token.r_paren) and !self.match(Token.eof)) {
                try items.append(try self.parseExpression());
                if (self.match(Token.comma)) _ = self.advance();
            }
            try self.expect(Token.r_paren);
            const tuple = try self.allocator.create(ast.Literal);
            tuple.* = .{ .kind = .tuple, .value = "" };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .l_brace) {
            _ = self.advance();
            var dict = std.ArrayList(ast.Expr).init(self.allocator);
            while (!self.match(Token.r_brace) and !self.match(Token.eof)) {
                try dict.append(try self.parseExpression());
                if (self.match(Token.comma)) _ = self.advance();
            }
            try self.expect(Token.r_brace);
            const d = try self.allocator.create(ast.Literal);
            d.* = .{ .kind = .bytes_lit, .value = "" };
            return try self.allocator.create(ast.Expr);
        }

        if (tok == .lt) {
            return try self.parseSystemTagExpr();
        }

        return error.UnexpectedToken;
    }

    fn parseSystemTagExpr(self: *Parser) !*ast.Expr {
        _ = self.advance();
        const tag = try self.parseSystemTag();
        try self.expect(Token.gt);

        if (self.match(Token.caret)) {
            _ = self.advance();
            try self.expect(Token.l_paren);
            const expr = try self.parseExpression();
            try self.expect(Token.r_paren);
            const ste = try self.allocator.create(ast.SystemTagExpr);
            ste.* = .{
                .tag = tag,
                .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
            };
            return try self.allocator.create(ast.Expr);
        }

        if (self.match(Token.l_paren)) {
            _ = self.advance();
            const expr = try self.parseExpression();
            try self.expect(Token.r_paren);
            const call = try self.allocator.create(ast.CallExpr);
            call.* = .{
                .callee = tag,
                .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
            };
            return try self.allocator.create(ast.Expr);
        }

        return error.UnexpectedToken;
    }
};
