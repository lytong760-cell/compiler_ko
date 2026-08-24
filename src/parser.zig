const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");

pub const Parser = struct {
    tokens: []lexer.Token,
    pos: usize,
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, arena: *std.heap.ArenaAllocator, tokens: []lexer.Token) Parser {
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

    pub fn parse(self: *Parser) ![]ast.Statement {
        var stmts = std.ArrayList(ast.Statement).init(self.allocator);
        defer stmts.deinit();

        while (!self.isAtEnd()) {
            const stmt = try self.parseStatement();
            stmts.append(stmt) catch unreachable;
        }

        return stmts.toOwnedSlice();
    }

    fn parseStatement(self: *Parser) !ast.Statement {
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
                .if_kw => {
                    return try self.parseIfStmt();
                },
                .elif_kw => {
                    return try self.parseElifStmt();
                },
                .else_kw => {
                    return try self.parseElseStmt();
                },
                .return_kw => {
                    return try self.parseReturnStmt();
                },
                .catch_kw => {
                    return try self.parseCatchStmt();
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
                else => {},
            }
        }

        if (tok == .lt) {
            return try self.parseSystemTagStmt();
        }

        if (tok == .identifier or tok == .sigil or tok == .dollar or tok == .l_bracket) {
            return try self.parseExprStatement();
        }

        return error.UnexpectedToken;
    }

    fn parseVarDecl(self: *Parser) !ast.Statement {
        const type_tok = self.advance();
        const type_name = type_tok.keywordText();

        try self.expectLParen();
        const value_expr = try self.parseExpression();
        try self.expectRParen();

        if (self.current() != .sigil) return error.ExpectedSigil;
        _ = self.advance();

        const name_tok = self.current();
        if (name_tok != .identifier) return error.ExpectedIdentifier;
        const name = name_tok.identifier;
        _ = self.advance();

        const vd = try self.allocator.create(ast.VarDecl);
        vd.* = ast.VarDecl{
            .type_name = type_name,
            .value_expr = value_expr,
            .name = name,
        };
        return ast.Statement{ .var_decl = vd.* };
    }

    fn parseImportStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();

        const call = try self.allocator.create(ast.CallExpr);
        call.* = ast.CallExpr{
            .callee = "Import",
            .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
        };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .call = call.* };
        return ast.Statement{ .expr = e };
    }

    fn parseLoopStmt(self: *Parser) !ast.Statement {
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
                e.* = .{ .system_tag = ste.* };
                return ast.Statement{ .expr = e };
            }

            try self.expectLBracket();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
            while (!self.current().isRBracket() and !self.isAtEnd()) {
                try body.append(try self.parseStatement());
            }
            try self.expectRBracket();

            const cf = try self.allocator.create(ast.ControlFlow);
            cf.* = ast.ControlFlow{
                .kind = .for_loop,
                .condition = try self.allocator.create(ast.Expr),
                .body = body.toOwnedSlice(),
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
                .allocator = self.allocator,
            };
            return ast.Statement{ .control_flow = cf.* };
        }

        if (self.current() == .l_bracket) {
            _ = self.advance();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
            while (!self.current().isRBracket() and !self.isAtEnd()) {
                try body.append(try self.parseStatement());
            }
            try self.expectRBracket();

            const cf = try self.allocator.create(ast.ControlFlow);
            cf.* = ast.ControlFlow{
                .kind = .while_loop,
                .condition = try self.allocator.create(ast.Expr),
                .body = body.toOwnedSlice(),
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
                .allocator = self.allocator,
            };
            return ast.Statement{ .control_flow = cf.* };
        }

        return error.UnexpectedToken;
    }

    fn parseIfStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLT();
        _ = self.advance();
        try self.expectGT();
        try self.expectLParen();
        const cond = try self.parseExpression();
        try self.expectRParen();
        try self.expectLBracket();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.current().isRBracket() and !self.isAtEnd()) {
            try body.append(try self.parseStatement());
        }
        try self.expectRBracket();

        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = .if_stmt,
            .condition = cond,
            .body = body.toOwnedSlice(),
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf.* };
    }

    fn parseElifStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLT();
        _ = self.advance();
        try self.expectGT();
        try self.expectLParen();
        const cond = try self.parseExpression();
        try self.expectRParen();
        try self.expectLBracket();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.current().isRBracket() and !self.isAtEnd()) {
            try body.append(try self.parseStatement());
        }
        try self.expectRBracket();

        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = .elif_stmt,
            .condition = cond,
            .body = body.toOwnedSlice(),
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf.* };
    }

    fn parseElseStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLBracket();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.current().isRBracket() and !self.isAtEnd()) {
            try body.append(try self.parseStatement());
        }
        try self.expectRBracket();

        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = .else_stmt,
            .condition = try self.allocator.create(ast.Expr),
            .body = body.toOwnedSlice(),
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf.* };
    }

    fn parseReturnStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();

        const rs = try self.allocator.create(ast.ReturnStmt);
        rs.* = ast.ReturnStmt{ .expr = expr };
        return ast.Statement{ .return_stmt = rs.* };
    }

    fn parseCatchStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const err_type = try self.parseErrorType();
        try self.expectRParen();
        try self.expectLBracket();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!self.current().isRBracket() and !self.isAtEnd()) {
            try body.append(try self.parseStatement());
        }
        try self.expectRBracket();

        const cs = try self.allocator.create(ast.CatchStmt);
        cs.* = ast.CatchStmt{
            .error_type = err_type,
            .body = body.toOwnedSlice(),
            .allocator = self.allocator,
        };
        return ast.Statement{ .catch_stmt = cs.* };
    }

    fn parseErrorType(self: *Parser) ![]const u8 {
        const tok = self.current();
        if (tok == .identifier) {
            const name = tok.identifier;
            _ = self.advance();
            return name;
        }
        return error.ExpectedIdentifier;
    }

    fn parseClassDecl(self: *Parser) !ast.Statement {
        _ = self.advance();
        const name_tok = self.current();
        if (name_tok != .identifier) return error.ExpectedIdentifier;
        const name = name_tok.identifier;
        _ = self.advance();

        try self.expectLBracket();
        var private_body = std.ArrayList(ast.Statement).init(self.allocator);
        var public_body = std.ArrayList(ast.Statement).init(self.allocator);
        var in_private = false;

        while (!self.current().isRBracket() and !self.isAtEnd()) {
            if (self.current() == .at and self.peek(1) == .keyword and self.peek(1).keyword == .private_kw) {
                _ = self.advance();
                _ = self.advance();
                try self.expectLBracket();
                in_private = true;
                continue;
            }
            if (self.current().isRBracket()) break;
            const stmt = try self.parseStatement();
            if (in_private) {
                try private_body.append(stmt);
            } else {
                try public_body.append(stmt);
            }
        }
        try self.expectRBracket();

        const cd = try self.allocator.create(ast.ClassDecl);
        cd.* = ast.ClassDecl{
            .name = name,
            .private_body = private_body.toOwnedSlice(),
            .public_body = public_body.toOwnedSlice(),
            .allocator = self.allocator,
        };
        return ast.Statement{ .class_decl = cd.* };
    }

    fn parseNowStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();
        try self.expectGT();
        const target = try self.parseExpression();

        const ne = try self.allocator.create(ast.NowExpr);
        ne.* = ast.NowExpr{ .expr = expr };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .now_expr = ne.* };
        return ast.Statement{ .expr = e };
    }

    fn parseMemoryOpStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        if (self.current() == .identifier and std.mem.eql(u8, self.current().identifier, "dete")) {
            _ = self.advance();
            try self.expectLParen();
            const expr = try self.parseExpression();
            try self.expectRParen();

            const mo = try self.allocator.create(ast.MemoryOp);
            mo.* = ast.MemoryOp{
                .kind = .dete,
                .expr = expr,
            };
            return ast.Statement{ .memory_op = mo.* };
        }
        if (self.current() == .caret) {
            _ = self.advance();
            try self.expectLParen();
            const expr = try self.parseExpression();
            try self.expectRParen();

            const mo = try self.allocator.create(ast.MemoryOp);
            mo.* = ast.MemoryOp{
                .kind = .address,
                .expr = expr,
            };
            return ast.Statement{ .memory_op = mo.* };
        }
        return error.UnexpectedToken;
    }

    fn parseEncodingOpStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLT();
        const tag = try self.parseSystemTagName();
        try self.expectGT();
        try self.expectCaret();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();

        const eo = try self.allocator.create(ast.EncodingOp);
        eo.* = ast.EncodingOp{
            .encoding_type = tag,
            .expr = expr,
        };
        return ast.Statement{ .encoding_op = eo.* };
    }

    fn parseLenOpStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLT();
        _ = self.advance();
        try self.expectGT();
        try self.expectCaret();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();

        const lo = try self.allocator.create(ast.LenOp);
        lo.* = ast.LenOp{ .expr = expr };
        return ast.Statement{ .len_op = lo.* };
    }

    fn parseInputStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();

        if (self.current() == .equals) {
            _ = self.advance();
            const target = try self.parseExpression();
            const ie = try self.allocator.create(ast.InputExpr);
            ie.* = ast.InputExpr{ .target = target };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .input_expr = ie.* };
            return ast.Statement{ .expr = e };
        }

        const ie = try self.allocator.create(ast.InputExpr);
        ie.* = ast.InputExpr{ .target = null };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .input_expr = ie.* };
        return ast.Statement{ .expr = e };
    }

    fn parsePrintfStmt(self: *Parser) !ast.Statement {
        _ = self.advance();
        try self.expectCaret();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();

        const call = try self.allocator.create(ast.CallExpr);
        call.* = ast.CallExpr{
            .callee = "printf",
            .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
        };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .call = call.* };
        return ast.Statement{ .expr = e };
    }

    fn parseSystemTagStmt(self: *Parser) !ast.Statement {
        try self.expectLT();
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
            e.* = .{ .system_tag = ste.* };
            return ast.Statement{ .expr = e };
        }

        if (self.current() == .l_paren) {
            _ = self.advance();
            const expr = try self.parseExpression();
            try self.expectRParen();

            const call = try self.allocator.create(ast.CallExpr);
            call.* = ast.CallExpr{
                .callee = tag,
                .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
            };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .call = call.* };
            return ast.Statement{ .expr = e };
        }

        return error.UnexpectedToken;
    }

    fn parseSystemTagName(self: *Parser) ![]const u8 {
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

    fn parseExprStatement(self: *Parser) !ast.Statement {
        const expr = try self.parseExpression();
        return ast.Statement{ .expr = expr };
    }

    fn parseExpression(self: *Parser) !*ast.Expr {
        return try self.parseOrExpr();
    }

    fn parseOrExpr(self: *Parser) !*ast.Expr {
        var left = try self.parseAndExpr();
        while (self.current() == .pipe_pipe) {
            _ = self.advance();
            const right = try self.parseAndExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{
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
        while (self.current() == .amp_amp) {
            _ = self.advance();
            const right = try self.parseEqualityExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{
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
            if (self.current() == .equals and self.peek(1) != .equals) {
                _ = self.advance();
                const right = try self.parseRelationalExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = ast.BinaryExpr{ .op = .eq, .left = left, .right = right };
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
            if (self.current() == .lt and self.peek(1) != .equals) {
                _ = self.advance();
                const right = try self.parseAdditiveExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = ast.BinaryExpr{ .op = .lt, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin.* };
            } else if (self.current() == .gt and self.peek(1) != .equals) {
                _ = self.advance();
                const right = try self.parseAdditiveExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = ast.BinaryExpr{ .op = .gt, .left = left, .right = right };
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
        while (self.current() == .plus or self.current() == .minus) {
            const op_tok = self.advance();
            const right = try self.parseMultiplicativeExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{
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
        while (self.current() == .star or self.current() == .slash or self.current() == .percent) {
            const op_tok = self.advance();
            const right = try self.parseUnaryExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{
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
        if (self.current() == .minus) {
            _ = self.advance();
            const expr = try self.parseUnaryExpr();
            const unary = try self.allocator.create(ast.UnaryExpr);
            unary.* = ast.UnaryExpr{ .op = .neg, .expr = expr };
            return try self.allocator.create(ast.Expr);
        }
        return try self.parsePrimaryExpr();
    }

    fn parsePrimaryExpr(self: *Parser) !*ast.Expr {
        const tok = self.current();

        if (tok == .int_lit) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .int, .raw = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .freal_lit) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .freal, .raw = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .string_lit) {
            const str = tok.string_lit;
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .string, .raw = str };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .bool_true) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .bool_true, .raw = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .bool_false) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .bool_false, .raw = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .identifier) {
            const name = tok.identifier;
            _ = self.advance();
            if (self.current() == .l_paren) {
                _ = self.advance();
                var args = std.ArrayList(ast.Expr).init(self.allocator);
                while (!self.current().isRParen() and !self.isAtEnd()) {
                    try args.append(try self.parseExpression());
                    if (self.current() == .comma) _ = self.advance();
                }
                try self.expectRParen();

                const call = try self.allocator.create(ast.CallExpr);
                call.* = ast.CallExpr{
                    .callee = name,
                    .args = args.toOwnedSlice(),
                };
                const e = try self.allocator.create(ast.Expr);
                e.* = .{ .call = call.* };
                return e;
            }
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .identifier = name };
            return e;
        }

        if (tok == .sigil) {
            _ = self.advance();
            const name_tok = self.current();
            if (name_tok != .identifier) return error.ExpectedIdentifier;
            const name = name_tok.identifier;
            _ = self.advance();
            if (self.current() == .l_paren) {
                _ = self.advance();
                var args = std.ArrayList(ast.Expr).init(self.allocator);
                while (!self.current().isRParen() and !self.isAtEnd()) {
                    try args.append(try self.parseExpression());
                    if (self.current() == .comma) _ = self.advance();
                }
                try self.expectRParen();

                const call = try self.allocator.create(ast.CallExpr);
                call.* = ast.CallExpr{
                    .callee = name,
                    .args = args.toOwnedSlice(),
                };
                const e = try self.allocator.create(ast.Expr);
                e.* = .{ .call = call.* };
                return e;
            }
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .identifier = name };
            return e;
        }

        if (tok == .dollar) {
            _ = self.advance();
            const name_tok = self.current();
            if (name_tok != .identifier) return error.ExpectedIdentifier;
            const name = name_tok.identifier;
            _ = self.advance();
            if (self.current() == .sigil) {
                _ = self.advance();
                const method = self.current().identifier;
                _ = self.advance();
                if (self.current() == .l_paren) {
                    _ = self.advance();
                    var args = std.ArrayList(ast.Expr).init(self.allocator);
                    while (!self.current().isRParen() and !self.isAtEnd()) {
                        try args.append(try self.parseExpression());
                        if (self.current() == .comma) _ = self.advance();
                    }
                    try self.expectRParen();

                    const call = try self.allocator.create(ast.CallExpr);
                    call.* = ast.CallExpr{
                        .callee = method,
                        .args = args.toOwnedSlice(),
                    };
                    const member = try self.allocator.create(ast.MemberAccess);
                    member.* = ast.MemberAccess{
                        .object = try self.allocator.create(ast.Expr),
                        .member = method,
                    };
                    member.object.* = .{ .identifier = name };
                    const e = try self.allocator.create(ast.Expr);
                    e.* = .{ .member_access = member.* };
                    return e;
                }
            }
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .identifier = name };
            return e;
        }

        if (tok == .l_paren) {
            _ = self.advance();
            const expr = try self.parseExpression();
            try self.expectRParen();
            return expr;
        }

        if (tok == .l_brace) {
            _ = self.advance();
            var items = std.ArrayList(ast.Expr).init(self.allocator);
            while (!self.current().isRBBrace() and !self.isAtEnd()) {
                try items.append(try self.parseExpression());
                if (self.current() == .comma) _ = self.advance();
            }
            try self.expectRBBrace();

            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .dict, .raw = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .lt) {
            return try self.parseSystemTagExpr();
        }

        return error.UnexpectedToken;
    }

    fn parseSystemTagExpr(self: *Parser) !*ast.Expr {
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
            e.* = .{ .system_tag = ste.* };
            return e;
        }

        if (self.current() == .l_paren) {
            _ = self.advance();
            const expr = try self.parseExpression();
            try self.expectRParen();

            const call = try self.allocator.create(ast.CallExpr);
            call.* = ast.CallExpr{
                .callee = tag,
                .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
            };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .call = call.* };
            return e;
        }

        return error.UnexpectedToken;
    }

    fn expectLParen(self: *Parser) !void {
        if (self.current() != .l_paren) return error.ExpectedLParen;
        _ = self.advance();
    }

    fn expectRParen(self: *Parser) !void {
        if (self.current() != .r_paren) return error.ExpectedRParen;
        _ = self.advance();
    }

    fn expectLBracket(self: *Parser) !void {
        if (self.current() != .l_bracket) return error.ExpectedLBracket;
        _ = self.advance();
    }

    fn expectRBracket(self: *Parser) !void {
        if (self.current() != .r_bracket) return error.ExpectedRBracket;
        _ = self.advance();
    }

    fn expectGT(self: *Parser) !void {
        if (self.current() != .gt) return error.UnexpectedToken;
        _ = self.advance();
    }

    fn expectLT(self: *Parser) !void {
        if (self.current() != .lt) return error.UnexpectedToken;
        _ = self.advance();
    }

    fn expectCaret(self: *Parser) !void {
        if (self.current() != .caret) return error.UnexpectedToken;
        _ = self.advance();
    }
};
