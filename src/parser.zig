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
            if (self.peek(1) == .at and self.peek(2) == .keyword and self.peek(2).keyword == .class_kw) {
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
        const block = try self.allocator.create(ast.BlockStmt);
        block.* = ast.BlockStmt{
            .body = try body.toOwnedSlice(),
            .allocator = self.allocator,
        };
        return ast.Statement{ .block = block.* };
    }


    fn parseVarDecl(self: *Parser) anyerror!ast.Statement {
        const type_tok = self.advance();
        const type_name = lexer.Token.keywordText(type_tok.keyword);

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

    fn parseImportStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const module_expr = try self.parseExpression();
        try self.expectRParen();

        if (self.current() == .at) {
            _ = self.advance();
            if (self.current() == .identifier) {
                _ = self.advance();
            }
            try self.expectSigil();
            if (self.current() == .identifier) {
                _ = self.advance();
            }
            if (self.current() == .bang) {
                _ = self.advance();
                if (self.current() == .identifier) {
                    _ = self.advance();
                }
            }
            if (self.current() == .colon) {
                _ = self.advance();
                if (self.current() == .identifier) {
                    _ = self.advance();
                }
            }
        }

        const call = try self.allocator.create(ast.CallExpr);
        call.* = ast.CallExpr{
            .callee = "Import",
            .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{module_expr.*}),
        };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .call = call };
        return ast.Statement{ .expr = e };
    }

    fn parseFuncDecl(self: *Parser) anyerror!ast.Statement {
        const name_tok = self.current();
        const name = name_tok.identifier;
        _ = self.advance();
        try self.expectLParen();
        var params = std.ArrayList(value_mod.Param).init(self.allocator);
        while (!(self.current() == .r_paren) and !self.isAtEnd()) {
            const type_tok = self.current();
            if (type_tok == .keyword) {
                const type_name = lexer.Token.keywordText(type_tok.keyword);
                _ = self.advance();
                try self.expectSigil();
                const param_tok = self.current();
                if (param_tok != .identifier) return error.ExpectedIdentifier;
                const param_name = param_tok.identifier;
                _ = self.advance();
                try params.append(value_mod.Param{ .type_name = type_name, .name = param_name });
            }
            if (self.current() == .comma) _ = self.advance();
        }
        try self.expectRParen();
        try self.expectLBracket();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        var catch_stmts = std.ArrayList(ast.CatchStmt).init(self.allocator);
        while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
            if (self.current() == .keyword and self.current().keyword == .catch_kw) {
                const cs = try self.parseCatchStmt();
                try catch_stmts.append(cs);
            } else {
                const stmt = try self.parseStatement();
                try body.append(stmt);
            }
        }
        try self.expectRBracket();

        const func = try self.allocator.create(ast.FuncDecl);
        func.* = ast.FuncDecl{
            .name = name,
            .params = try params.toOwnedSlice(),
            .body = try body.toOwnedSlice(),
            .catch_stmts = try catch_stmts.toOwnedSlice(),
            .allocator = self.allocator,
        };
        return ast.Statement{ .func_decl = func };
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

            try self.expectLBracket();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
                while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
                const stmt = try self.parseStatement();
                    try body.append(stmt);
            }
            try self.expectRBracket();

            const cf = try self.allocator.create(ast.ControlFlow);
            cf.* = ast.ControlFlow{
                .kind = .for_loop,
                .condition = try self.allocator.create(ast.Expr),
                .body = try body.toOwnedSlice(),
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
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
                .allocator = self.allocator,
            };
            return ast.Statement{ .control_flow = cf };
        }

        return error.UnexpectedToken;
    }

    fn parseIfStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLT();
        _ = self.advance();
        try self.expectGT();
        try self.expectLParen();
        const cond = try self.parseExpression();
        try self.expectRParen();
        try self.expectLBracket();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
            const stmt = try self.parseStatement();
                    try body.append(stmt);
        }
        try self.expectRBracket();

        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = .if_stmt,
            .condition = cond,
            .body = try body.toOwnedSlice(),
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf };
    }

    fn parseElifStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLT();
        _ = self.advance();
        try self.expectGT();
        try self.expectLParen();
        const cond = try self.parseExpression();
        try self.expectRParen();
        try self.expectLBracket();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
            const stmt = try self.parseStatement();
                    try body.append(stmt);
        }
        try self.expectRBracket();

        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = .elif_stmt,
            .condition = cond,
            .body = try body.toOwnedSlice(),
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf };
    }

    fn parseElseStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLBracket();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
            const stmt = try self.parseStatement();
                    try body.append(stmt);
        }
        try self.expectRBracket();

        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = .else_stmt,
            .condition = try self.allocator.create(ast.Expr),
            .body = try body.toOwnedSlice(),
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf };
    }

    fn parseReturnStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();

        const rs = try self.allocator.create(ast.ReturnStmt);
        rs.* = ast.ReturnStmt{ .expr = expr };
        return ast.Statement{ .return_stmt = rs };
    }

    fn parseCatchStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const err_type = try self.parseErrorType();
        try self.expectRParen();
        try self.expectLBracket();
        var body = std.ArrayList(ast.Statement).init(self.allocator);
        while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
            const stmt = try self.parseStatement();
                    try body.append(stmt);
        }
        try self.expectRBracket();

        const cs = try self.allocator.create(ast.CatchStmt);
        cs.* = ast.CatchStmt{
            .error_type = err_type,
            .body = try body.toOwnedSlice(),
            .allocator = self.allocator,
        };
        return ast.Statement{ .catch_stmt = cs };
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

    fn parseClassDecl(self: *Parser) anyerror!ast.Statement {
        const name_tok = self.current();
        if (name_tok != .identifier) return error.ExpectedIdentifier;
        const name = name_tok.identifier;
        _ = self.advance();

        if (self.current() == .at) {
            _ = self.advance();
            if (self.current() == .keyword and self.current().keyword == .class_kw) {
                _ = self.advance();
            }
        }

        try self.expectLBracket();
        var private_body = std.ArrayList(ast.Statement).init(self.allocator);
        var public_body = std.ArrayList(ast.Statement).init(self.allocator);
        var in_private = false;

        while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
            if (self.current() == .at and self.peek(1) == .keyword and self.peek(1).keyword == .private_kw) {
                _ = self.advance();
                _ = self.advance();
                try self.expectLBracket();
                in_private = true;
                continue;
            }
            if (self.current() == .r_bracket) break;
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
            .private_body = try private_body.toOwnedSlice(),
                .public_body = try public_body.toOwnedSlice(),
            .allocator = self.allocator,
        };
        return ast.Statement{ .class_decl = cd };
    }

    fn parseNowStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        _ = try self.parseExpression();
        try self.expectRParen();
        try self.expectGT();
        const target = try self.parseExpression();

        const ne = try self.allocator.create(ast.NowExpr);
        ne.* = ast.NowExpr{ .expr = target };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .now_expr = ne };
        return ast.Statement{ .expr = e };
    }

    fn parseMemoryOpStmt(self: *Parser) anyerror!ast.Statement {
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
            return ast.Statement{ .memory_op = mo };
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
            return ast.Statement{ .memory_op = mo };
        }
        return error.UnexpectedToken;
    }

    fn parseEncodingOpStmt(self: *Parser) anyerror!ast.Statement {
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
        return ast.Statement{ .encoding_op = eo };
    }

    fn parseLenOpStmt(self: *Parser) anyerror!ast.Statement {
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
        return ast.Statement{ .len_op = lo };
    }

    fn parseInputStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        _ = try self.parseExpression();
        try self.expectRParen();

        if (self.current() == .equals) {
            _ = self.advance();
            const target = try self.parseExpression();
            const ie = try self.allocator.create(ast.InputExpr);
            ie.* = ast.InputExpr{ .target = target };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .input_expr = ie };
            return ast.Statement{ .expr = e };
        }

        const ie = try self.allocator.create(ast.InputExpr);
        ie.* = ast.InputExpr{ .target = null };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .input_expr = ie };
        return ast.Statement{ .expr = e };
    }

    fn parsePrintfStmt(self: *Parser) anyerror!ast.Statement {
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
        e.* = .{ .call = call };
        return ast.Statement{ .expr = e };
    }

    fn parseSystemTagStmt(self: *Parser) anyerror!ast.Statement {
        try self.expectLT();
        const tag = try self.parseSystemTagName();
        
        if (std.mem.eql(u8, tag, "if")) {
            try self.expectGT();
            try self.expectLParen();
            const cond = try self.parseExpression();
            try self.expectRParen();
            try self.expectLBracket();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
            while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
                const stmt = try self.parseStatement();
                try body.append(stmt);
            }
            try self.expectRBracket();
            const cf = try self.allocator.create(ast.ControlFlow);
            cf.* = ast.ControlFlow{
                .kind = .if_stmt,
                .condition = cond,
                .body = try body.toOwnedSlice(),
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
                .allocator = self.allocator,
            };
            return ast.Statement{ .control_flow = cf };
        }
        
        if (std.mem.eql(u8, tag, "elif")) {
            try self.expectGT();
            try self.expectLParen();
            const cond = try self.parseExpression();
            try self.expectRParen();
            try self.expectLBracket();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
            while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
                const stmt = try self.parseStatement();
                try body.append(stmt);
            }
            try self.expectRBracket();
            const cf = try self.allocator.create(ast.ControlFlow);
            cf.* = ast.ControlFlow{
                .kind = .elif_stmt,
                .condition = cond,
                .body = try body.toOwnedSlice(),
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
                .allocator = self.allocator,
            };
            return ast.Statement{ .control_flow = cf };
        }
        
        if (std.mem.eql(u8, tag, "else")) {
            try self.expectGT();
            try self.expectLBracket();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
            while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
                const stmt = try self.parseStatement();
                try body.append(stmt);
            }
            try self.expectRBracket();
            const cf = try self.allocator.create(ast.ControlFlow);
            cf.* = ast.ControlFlow{
                .kind = .else_stmt,
                .condition = try self.allocator.create(ast.Expr),
                .body = try body.toOwnedSlice(),
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
                .allocator = self.allocator,
            };
            return ast.Statement{ .control_flow = cf };
        }
        
        if (std.mem.eql(u8, tag, "catch")) {
            try self.expectGT();
            try self.expectLParen();
            const err_type = try self.parseErrorType();
            try self.expectRParen();
            try self.expectLBracket();
            var body = std.ArrayList(ast.Statement).init(self.allocator);
            while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
                const stmt = try self.parseStatement();
                try body.append(stmt);
            }
            try self.expectRBracket();
            const cs = try self.allocator.create(ast.CatchStmt);
            cs.* = ast.CatchStmt{
                .error_type = err_type,
                .body = try body.toOwnedSlice(),
                .allocator = self.allocator,
            };
            return ast.Statement{ .catch_stmt = cs };
        }
        
        if (std.mem.eql(u8, tag, "now")) {
            try self.expectLParen();
            _ = try self.parseExpression();
            try self.expectRParen();
            try self.expectGT();
            const target = try self.parseExpression();
            const ne = try self.allocator.create(ast.NowExpr);
            ne.* = ast.NowExpr{ .expr = target };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .now_expr = ne };
            return ast.Statement{ .expr = e };
        }
        
        if (std.mem.eql(u8, tag, "memory")) {
            if (self.current() == .caret) {
                _ = self.advance();
                const expr = try self.parseExpression();
                const mo = try self.allocator.create(ast.MemoryOp);
                mo.* = ast.MemoryOp{
                    .kind = .address,
                    .expr = expr,
                };
                return ast.Statement{ .memory_op = mo };
            }
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
                return ast.Statement{ .memory_op = mo };
            }
            return error.UnexpectedToken;
        }
        
        if (std.mem.eql(u8, tag, "encode")) {
            var encoding_type: []const u8 = "";
            if (self.current() == .l_paren) {
                _ = self.advance();
                const enc_expr = try self.parseExpression();
                if (enc_expr.* == .literal and enc_expr.literal.kind == .string) {
                    encoding_type = enc_expr.literal.raw;
                }
                try self.expectRParen();
            }
            try self.expectGT();
            try self.expectCaret();
            try self.expectLParen();
            const expr = try self.parseExpression();
            try self.expectRParen();
            const eo = try self.allocator.create(ast.EncodingOp);
            eo.* = ast.EncodingOp{
                .encoding_type = encoding_type,
                .expr = expr,
            };
            return ast.Statement{ .encoding_op = eo };
        }

        if (self.current() == .caret) {
            _ = self.advance();
            if (self.current() == .l_paren) {
                _ = self.advance();
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
            const expr = try self.parseExpression();
            const ste = try self.allocator.create(ast.SystemTagExpr);
            ste.* = ast.SystemTagExpr{
                .tag = tag,
                .args = try self.allocator.dupe(ast.Expr, &[_]ast.Expr{expr.*}),
            };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .system_tag = ste };
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
            e.* = .{ .call = call };
            return ast.Statement{ .expr = e };
        }

        return error.UnexpectedToken;
    }

    fn parseSystemTagName(self: *Parser) ![]const u8 {
        const tok = self.current();
        if (tok == .keyword) {
            const name = lexer.Token.keywordText(tok.keyword);
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

    fn parseExprStatement(self: *Parser) anyerror!ast.Statement {
        const expr = try self.parseExpression();
        return ast.Statement{ .expr = expr };
    }

    fn parseExpression(self: *Parser) anyerror!*ast.Expr {
        return try self.parseOrExpr();
    }

    fn parseOrExpr(self: *Parser) anyerror!*ast.Expr {
        var left = try self.parseAndExpr();
        while (self.current() == .pipe_pipe) {
            _ = self.advance();
            const right = try self.parseAndExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{
                .op = .logical_or,
                .left = left,
                .right = right,
            };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin };
        }
        return left;
    }

    fn parseAndExpr(self: *Parser) anyerror!*ast.Expr {
        var left = try self.parseEqualityExpr();
        while (self.current() == .amp_amp) {
            _ = self.advance();
            const right = try self.parseEqualityExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{
                .op = .logical_and,
                .left = left,
                .right = right,
            };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin };
        }
        return left;
    }

    fn parseEqualityExpr(self: *Parser) anyerror!*ast.Expr {
        var left = try self.parseRelationalExpr();
        while (true) {
            if (self.current() == .equals and self.peek(1) != .equals) {
                _ = self.advance();
                const right = try self.parseRelationalExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = ast.BinaryExpr{ .op = .eq, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseRelationalExpr(self: *Parser) anyerror!*ast.Expr {
        var left = try self.parseAdditiveExpr();
        while (true) {
            if (self.current() == .lt and self.peek(1) != .equals) {
                _ = self.advance();
                const right = try self.parseAdditiveExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = ast.BinaryExpr{ .op = .lt, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin };
            } else if (self.current() == .gt and self.peek(1) != .equals) {
                _ = self.advance();
                const right = try self.parseAdditiveExpr();
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = ast.BinaryExpr{ .op = .gt, .left = left, .right = right };
                left = try self.allocator.create(ast.Expr);
                left.* = .{ .binary = bin };
            } else {
                break;
            }
        }
        return left;
    }

    fn parseAdditiveExpr(self: *Parser) anyerror!*ast.Expr {
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
            left.* = .{ .binary = bin };
        }
        return left;
    }

    fn parseMultiplicativeExpr(self: *Parser) anyerror!*ast.Expr {
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
            left.* = .{ .binary = bin };
        }
        return left;
    }

    fn parseUnaryExpr(self: *Parser) anyerror!*ast.Expr {
        if (self.current() == .minus) {
            _ = self.advance();
            const expr = try self.parseUnaryExpr();
            const unary = try self.allocator.create(ast.UnaryExpr);
            unary.* = ast.UnaryExpr{ .op = .neg, .expr = expr };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .unary = unary };
            return e;
        }
        return try self.parsePrimaryExpr();
    }

    fn parsePrimaryExpr(self: *Parser) anyerror!*ast.Expr {
        const tok = self.current();

        if (tok == .int_lit) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .int, .int_value = tok.int_lit, .freal_value = 0, .raw = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .freal_lit) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .freal, .int_value = 0, .freal_value = tok.freal_lit, .raw = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .string_lit) {
            const str = tok.string_lit;
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .string, .int_value = 0, .freal_value = 0, .raw = str };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .bool_true) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .bool_true, .int_value = 0, .freal_value = 0, .raw = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .bool_false) {
            _ = self.advance();
            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .bool_false, .int_value = 0, .freal_value = 0, .raw = "" };
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
                while (!(self.current() == .r_paren) and !self.isAtEnd()) {
                    const expr = try self.parseExpression();
                    try args.append(expr.*);
                    if (self.current() == .comma) _ = self.advance();
                }
                try self.expectRParen();

                const call = try self.allocator.create(ast.CallExpr);
                call.* = ast.CallExpr{
                    .callee = name,
                    .args = try args.toOwnedSlice(),
                };
                const e = try self.allocator.create(ast.Expr);
                e.* = .{ .call = call };
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
                while (!(self.current() == .r_paren) and !self.isAtEnd()) {
                    const expr = try self.parseExpression();
                    try args.append(expr.*);
                    if (self.current() == .comma) _ = self.advance();
                }
                try self.expectRParen();

                const call = try self.allocator.create(ast.CallExpr);
                call.* = ast.CallExpr{
                    .callee = name,
                    .args = try args.toOwnedSlice(),
                };
                const e = try self.allocator.create(ast.Expr);
                e.* = .{ .call = call };
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
                    while (!(self.current() == .r_paren) and !self.isAtEnd()) {
                        const expr = try self.parseExpression();
                        try args.append(expr.*);
                        if (self.current() == .comma) _ = self.advance();
                    }
                    try self.expectRParen();

                     const call = try self.allocator.create(ast.CallExpr);
                     call.* = ast.CallExpr{
                         .callee = method,
                         .args = try args.toOwnedSlice(),
                     };
                    const member = try self.allocator.create(ast.MemberAccess);
                    member.* = ast.MemberAccess{
                        .object = try self.allocator.create(ast.Expr),
                        .member = method,
                    };
                    member.object.* = .{ .identifier = name };
                    const e = try self.allocator.create(ast.Expr);
                    e.* = .{ .member_access = member };
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
                while (!(self.current() == .r_brace) and !self.isAtEnd()) {
                const expr = try self.parseExpression();
                try items.append(expr.*);
                if (self.current() == .comma) _ = self.advance();
            }
            try self.expectRBBrace();

            const lit = try self.allocator.create(ast.Literal);
            lit.* = ast.Literal{ .kind = .dict, .int_value = 0, .freal_value = 0, .raw = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .literal = lit.* };
            return e;
        }

        if (tok == .lt) {
            return try self.parseSystemTagExpr();
        }

        return error.UnexpectedToken;
    }

    fn parseSystemTagExpr(self: *Parser) anyerror!*ast.Expr {
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
            e.* = .{ .call = call };
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

    fn expectRBBrace(self: *Parser) !void {
        if (self.current() != .r_brace) return error.UnexpectedToken;
        _ = self.advance();
    }

    fn expectCaret(self: *Parser) !void {
        if (self.current() != .caret) return error.UnexpectedToken;
        _ = self.advance();
    }

    fn expectSigil(self: *Parser) !void {
        if (self.current() != .sigil) return error.UnexpectedToken;
        _ = self.advance();
    }
};
