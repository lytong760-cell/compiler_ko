const std = @import("std");
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const value_mod = @import("value.zig");

pub const Parser = struct {
    tokens: []lexer.Token,
    positions: []lexer.Position,
    pos: usize,
    arena: *std.heap.ArenaAllocator,
    allocator: std.mem.Allocator,
    errors: []ParseError = &.{},

    pub const Position = lexer.Position;
    pub const Span = struct {
        start: lexer.Position,
        end: lexer.Position,
        // aliases for convenience
        begin: lexer.Position = .{ .line = 1, .col = 1, .column = 1, .offset = 0 },
        finish: lexer.Position = .{ .line = 1, .col = 1, .column = 1, .offset = 0 },
    };
    pub const Error = ParseError;
    pub const Range = Span;
    pub const SourceSpan = Span;
    pub const ParseError = struct {
        span: Span,
        message: []const u8 = "",
        hint: []const u8 = "",
        err: anyerror = error.UnexpectedToken,
        line: usize = 0,
        col: usize = 0,
        column: usize = 0,
        file: []const u8 = "",
        pub fn print(self: ParseError, writer: anytype) void {
            writer.print("error: {s} at {d}:{d}..{d}:{d}\n", .{
                self.message, self.span.start.line, self.span.start.col, self.span.end.line, self.span.end.col,
            }) catch {};
        }
        pub fn format(self: ParseError, writer: anytype) !void {
            try writer.print("error: {s} at {d}:{d}..{d}:{d}", .{
                self.message, self.span.start.line, self.span.start.col, self.span.end.line, self.span.end.col,
            });
        }
        pub fn write(self: ParseError, writer: anytype) !void {
            try writer.print("error: {s} at {d}:{d}..{d}:{d}\n", .{
                self.message, self.span.start.line, self.span.start.col, self.span.end.line, self.span.end.col,
            });
        }
    };
    pub const Diagnostic = ParseError;
    pub const DiagnosticReport = ParseError;
    pub const DiagnosticEntry = ParseError;

    pub fn init(allocator: std.mem.Allocator, arena: *std.heap.ArenaAllocator, tokens: []lexer.Token, positions: []lexer.Position) Parser {
        _ = allocator;
        return .{
            .tokens = tokens,
            .positions = positions,
            .pos = 0,
            .arena = arena,
            .allocator = arena.allocator(),
            .errors = &.{},
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

    pub fn regionRoleName(self: *Parser) ?[]const u8 {
        return switch (self.current()) {
            .identifier => |id| id,
            .keyword => |kw| switch (kw) {
                .private_kw => "private",
                else => null,
            },
            else => null,
        };
    }

    pub fn isAtEnd(self: *Parser) bool {
        return self.current() == lexer.Token.eof;
    }

    pub fn currentSpan(self: *Parser) Span {
        const idx = if (self.pos < self.positions.len) self.pos else if (self.positions.len > 0) self.positions.len - 1 else 0;
        const start = if (self.positions.len > 0) self.positions[idx] else lexer.Position{ .line = 1, .col = 1, .column = 1, .offset = 0 };
        const end_idx = if (idx + 1 < self.positions.len) idx + 1 else idx;
        const end = if (self.positions.len > 0) self.positions[end_idx] else start;
        var sp = Span{ .start = start, .end = end };
        sp.begin = start;
        sp.finish = end;
        return sp;
    }

    pub fn printErrors(self: *Parser, writer: anytype) void {
        printDiagnosticSlice(writer, self.errors);
    }
    pub fn printDiagnostics(self: *Parser, writer: anytype) void {
        printDiagnosticSlice(writer, self.errors);
    }
    pub fn printDiagnosticReport(self: *Parser, writer: anytype) void {
        printDiagnosticSlice(writer, self.errors);
    }
    pub fn printErrorsWithSpan(self: *Parser, writer: anytype) void {
        printDiagnosticSlice(writer, self.errors);
    }
    pub fn reportErrors(self: *Parser, writer: anytype) void {
        printDiagnosticSlice(writer, self.errors);
    }
    pub fn printParseErrors(self: *Parser, writer: anytype) void {
        printDiagnosticSlice(writer, self.errors);
    }
    pub fn printDiagnostic(self: *Parser, writer: anytype) void {
        printDiagnosticSlice(writer, self.errors);
    }
    pub fn printErrorsWithSource(self: *Parser, writer: anytype, source: []const u8) void {
        printDiagnosticSliceWithSource(writer, self.errors, source);
    }
    pub fn printDiagnosticsWithSource(self: *Parser, writer: anytype, source: []const u8) void {
        printDiagnosticSliceWithSource(writer, self.errors, source);
    }
    pub fn printDiagnosticReportWithSource(self: *Parser, writer: anytype, source: []const u8) void {
        printDiagnosticSliceWithSource(writer, self.errors, source);
    }
    pub fn printErrorsWithSpanAndSource(self: *Parser, writer: anytype, source: []const u8) void {
        printDiagnosticSliceWithSource(writer, self.errors, source);
    }

    pub fn parse(self: *Parser) anyerror![]ast.Statement {
        var stmts = std.array_list.Managed(ast.Statement).init(self.allocator);
        defer stmts.deinit();
        var errs = std.array_list.Managed(ParseError).init(self.allocator);
        defer errs.deinit();

        while (!self.isAtEnd()) {
            const stmt = self.parseStatement() catch |err| {
                const sp = self.currentSpan();
                try errs.append(ParseError{
                    .span = sp,
                    .message = @errorName(err),
                    .err = err,
                    .line = sp.start.line,
                    .col = sp.start.col,
                    .column = sp.start.col,
                });
                if (err == error.InvalidRegionRole) {
                    self.errors = try errs.toOwnedSlice();
                    return err;
                }
                self.synchronize();
                continue;
            };
            try stmts.append(stmt);
        }

        self.errors = try errs.toOwnedSlice();
        return try stmts.toOwnedSlice();
    }

    pub fn synchronize(self: *Parser) void {
        if (!self.isAtEnd()) _ = self.advance();
        while (!self.isAtEnd() and self.current() != .r_bracket) {
            if (isStatementStart(self.current())) break;
            _ = self.advance();
        }
    }

    pub fn isStatementStart(tok: lexer.Token) bool {
        if (tok == .priority_lit) return true;
        if (tok == .keyword) return true;
        if (tok == .identifier) return true;
        if (tok == .sigil) return true;
        if (tok == .dollar) return true;
        if (tok == .l_brace) return true;
        if (tok == .l_bracket) return true;
        if (tok == .bold_lit) return true;
        if (tok == .lt) return true;
        return false;
    }

    pub fn parseStatement(self: *Parser) anyerror!ast.Statement {
        const tok = self.current();

        if (tok == .priority_lit) {
            const priority = tok.priority_lit;
            _ = self.advance();
            const stmt = try self.parseStatement();
            const stmt_ptr = try self.allocator.create(ast.Statement);
            stmt_ptr.* = stmt;
            return ast.Statement{ .priority_stmt = .{
                .priority = priority,
                .stmt = stmt_ptr,
                .allocator = self.allocator,
            } };
        }

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

        if (tok == .sigil) {
            if (self.peek(1) == .identifier and self.peek(2) == .sigil) {
                return try self.parseClassInstantiation();
            }
            return try self.parseExprStatement();
        }

        if (tok == .dollar) {
            return try self.parseExprStatement();
        }

        if (tok == .l_brace) {
            return try self.parseExprStatement();
        }

        if (tok == .l_bracket) {
            return try self.parseBlockStatement();
        }

        if (tok == .bold_lit) {
            const word = tok.bold_lit;
            if (std.mem.eql(u8, word, "Loop")) {
                return try self.parseLoopStmt();
            }
            if (std.mem.eql(u8, word, "Import")) {
                return try self.parseImportStmt();
            }
            return error.UnexpectedToken;
        }

        return error.UnexpectedToken;
    }

    pub fn parseClassInstantiation(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        const name_tok = self.current();
        if (name_tok != .identifier) return error.ExpectedIdentifier;
        const name = name_tok.identifier;
        _ = self.advance();
        _ = self.advance();
        const instance_tok = self.current();
        if (instance_tok != .identifier) return error.ExpectedIdentifier;
        const instance_name = instance_tok.identifier;
        _ = self.advance();
        const ci = try self.allocator.create(ast.ClassInstantiation);
        ci.* = ast.ClassInstantiation{
            .class_name = name,
            .instance_name = instance_name,
            .allocator = self.allocator,
        };
        return ast.Statement{ .class_instantiation = ci.* };
    }

    pub fn parseBlock(self: *Parser) ![]ast.Statement {
        try self.expectLBracket();
        var body = std.array_list.Managed(ast.Statement).init(self.allocator);
        while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
            const stmt = try self.parseStatement();
            try body.append(stmt);
        }
        try self.expectRBracket();
        const slice = try body.toOwnedSlice();
        std.sort.block(ast.Statement, slice, {}, struct {
            fn less(_: void, a: ast.Statement, b: ast.Statement) bool {
                const pa = if (a == .priority_stmt) a.priority_stmt.priority else 0;
                const pb = if (b == .priority_stmt) b.priority_stmt.priority else 0;
                if (pa != pb) return pa < pb;
                return false;
            }
        }.less);
        return slice;
    }

    pub fn parseBlockStatement(self: *Parser) anyerror!ast.Statement {
        return ast.Statement{ .block = ast.BlockStmt{ .body = try self.parseBlock(), .allocator = self.allocator } };
    }


    pub fn parseVarDecl(self: *Parser) anyerror!ast.Statement {
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

        const vd = ast.VarDecl{
            .type_name = type_name,
            .value_expr = value_expr,
            .name = name,
        };
        return ast.Statement{ .var_decl = vd };
    }

    pub fn parseImportStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const module_expr = try self.parseExpression();
        try self.expectRParen();

        if (self.current() == .at) {
            _ = self.advance();
            const role = self.regionRoleName() orelse return error.InvalidRegionRole;
            if (!isKnownRegionRole(role)) return error.InvalidRegionRole;
            _ = self.advance();

            if (self.current() == .percent) {
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

    pub fn parseFuncDecl(self: *Parser) anyerror!ast.Statement {
        const name_tok = self.current();
        const name = name_tok.identifier;
        _ = self.advance();
        try self.expectLParen();
        var params = std.array_list.Managed(value_mod.Param).init(self.allocator);
        while (!(self.current() == .r_paren) and !self.isAtEnd()) {
            if (self.current() == .comma) {
                _ = self.advance();
                continue;
            }
            if (self.current() == .keyword) {
                const type_name = lexer.Token.keywordText(self.current().keyword);
                _ = self.advance();
                try self.expectSigil();
                const param_tok = self.current();
                if (param_tok != .identifier) return error.ExpectedIdentifier;
                _ = self.advance();
                try params.append(value_mod.Param{ .type_name = type_name, .name = param_tok.identifier });
                continue;
            }
            if (self.current() == .identifier) {
                const param_tok = self.current();
                _ = self.advance();
                try params.append(value_mod.Param{ .type_name = "", .name = param_tok.identifier });
                continue;
            }
            return error.ExpectedIdentifier;
        }
        try self.expectRParen();
        try self.expectLBracket();
        var body = std.array_list.Managed(ast.Statement).init(self.allocator);
        var catch_stmts = std.array_list.Managed(ast.CatchStmt).init(self.allocator);
        while (!(self.current() == .r_bracket) and !self.isAtEnd()) {
            if (self.current() == .keyword and self.current().keyword == .catch_kw) {
                const cs_stmt = try self.parseCatchStmt();
                switch (cs_stmt) {
                    .catch_stmt => |cs| try catch_stmts.append(cs.*),
                    else => unreachable,
                }
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

    pub fn parseLoopStmt(self: *Parser) anyerror!ast.Statement {
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
            var init_assign: ?*ast.Assignment = null;
            var step: ?*ast.Expr = null;
            var loop_var_name: []const u8 = "";
            const cond = if (self.current() == .sigil) blk: {
                _ = self.advance();
                const var_tok = self.current();
                if (var_tok != .identifier) return error.ExpectedIdentifier;
                const var_name = var_tok.identifier;
                loop_var_name = var_name;
                _ = self.advance();
                try self.expectEquals();
                const init_expr = try self.parseExpression();
                var step_expr: ?*ast.Expr = null;
                if (self.current() == .l_paren) {
                    _ = self.advance();
                    const s_expr = try self.parseExpression();
                    step_expr = s_expr;
                    try self.expectRParen();
                }
                const cond_tok = self.current();
                _ = self.advance();
                const limit_expr = try self.parseExpression();
                const var_ident = try self.allocator.create(ast.Expr);
                var_ident.* = .{ .identifier = var_name };
                const op: ast.BinaryExpr.Op = switch (cond_tok) {
                    .amp_equals => .lte,
                    .lt => .lt,
                    else => .lte,
                };
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = ast.BinaryExpr{
                    .op = op,
                    .left = var_ident,
                    .right = limit_expr,
                };
                const cond_expr = try self.allocator.create(ast.Expr);
                cond_expr.* = .{ .binary = bin };
                const target = try self.allocator.create(ast.Expr);
                target.* = .{ .identifier = var_name };
                const assign = try self.allocator.create(ast.Assignment);
                assign.* = ast.Assignment{
                    .target = target,
                    .value_expr = init_expr,
                };
                init_assign = assign;
                step = step_expr;
                break :blk cond_expr;
            } else blk: {
                const c = try self.parseExpression();
                break :blk c;
            };
            try self.expectRParen();
            const body = try self.parseBlock();

            const kind: ast.ControlFlow.Kind = if (std.mem.eql(u8, tag, "for")) .for_loop else .while_loop;
            return try self.makeLoopStmt(kind, cond, body, init_assign, step, loop_var_name);
        }

        if (self.current() == .l_bracket) {
            _ = self.advance();
            const body = try self.parseBlock();

            const true_lit = try self.allocator.create(ast.Literal);
            true_lit.* = ast.Literal{ .kind = .bool_true, .int_value = 0, .freal_value = 0, .raw = "", .dict_entries = &.{}, .allocator = self.allocator };
            const true_expr = try self.allocator.create(ast.Expr);
            true_expr.* = .{ .literal = true_lit.* };

            const cf = try self.allocator.create(ast.ControlFlow);
            cf.* = ast.ControlFlow{
                .kind = .while_loop,
                .condition = true_expr,
                .body = body,
                .init = null,
                .step = null,
                .loop_var = "",
                .elifs = &[_]ast.Elif{},
                .else_body = &[_]ast.Statement{},
                .allocator = self.allocator,
            };
            return ast.Statement{ .control_flow = cf };
        }

        return error.UnexpectedToken;
    }

    pub fn parseIfStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLT();
        _ = self.advance();
        try self.expectGT();
        try self.expectLParen();
        const cond = try self.parseExpression();
        try self.expectRParen();
        const body = try self.parseBlock();
        return try self.makeIfStmt(cond, body);
    }

    pub fn parseElifStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLT();
        _ = self.advance();
        try self.expectGT();
        try self.expectLParen();
        const cond = try self.parseExpression();
        try self.expectRParen();
        const body = try self.parseBlock();
        return try self.makeElifStmt(cond, body);
    }

    pub fn parseElseStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        const body = try self.parseBlock();
        return try self.makeElseStmt(body);
    }

    pub fn parseReturnStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();

        return try self.makeReturnStmt(expr);
    }

    pub fn parseCatchStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const err_type = try self.parseErrorType();
        try self.expectRParen();
        const body = try self.parseBlock();
        return try self.makeCatchStmt(err_type, body);
    }

    pub fn parseErrorType(self: *Parser) ![]const u8 {
        const tok = self.current();
        if (tok == .identifier) {
            const name = tok.identifier;
            _ = self.advance();
            return name;
        }
        return error.ExpectedIdentifier;
    }

    pub fn parseClassDecl(self: *Parser) anyerror!ast.Statement {
        const name_tok = self.current();
        if (name_tok != .identifier) return error.ExpectedIdentifier;
        const name = name_tok.identifier;
        _ = self.advance();

        if (self.current() == .bang) {
            _ = self.advance();
            if (self.current() == .keyword and self.current().keyword == .class_kw) {
                _ = self.advance();
            }
        } else if (self.current() == .at) {
            _ = self.advance();
            if (self.current() == .keyword and self.current().keyword == .class_kw) {
                _ = self.advance();
            }
        }

        try self.expectLBracket();
        var private_body = std.array_list.Managed(ast.Statement).init(self.allocator);
        var public_body = std.array_list.Managed(ast.Statement).init(self.allocator);
        var region_depth: usize = 0;
        var private_open_count: usize = 0;
        var region_stack = std.array_list.Managed(bool).init(self.allocator);

        while (!self.isAtEnd()) {
            if (self.current() == .r_bracket and region_depth == 0) break;

            if (self.current() == .at) {
                _ = self.advance();
                const role = self.regionRoleName() orelse return error.InvalidRegionRole;
                if (!isKnownRegionRole(role)) return error.InvalidRegionRole;
                _ = self.advance();
                try self.expectLBracket();
                const is_private = std.mem.eql(u8, role, "private");
                try region_stack.append(is_private);
                region_depth += 1;
                if (is_private) private_open_count += 1;
                continue;
            }

            if (self.current() == .r_bracket and region_depth > 0) {
                const was_private = if (region_stack.items.len > 0) (region_stack.pop() orelse false) else false;
                if (was_private) {
                    if (private_open_count > 0) private_open_count -= 1;
                }
                region_depth -= 1;
                _ = self.advance();
                continue;
            }

            if (self.current() == .l_bracket and region_depth > 0) {
                region_depth += 1;
                try region_stack.append(false);
            }

            const stmt = try self.parseStatement();
            if (private_open_count > 0) {
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

    pub fn parseNowStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();
        try self.expectGT();
        const target = try self.parseExpression();

        return try self.makeNowStmt(expr, target);
    }

    pub fn parseMemoryOpStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        if (self.current() == .identifier and std.mem.eql(u8, self.current().identifier, "dete")) {
            _ = self.advance();
            try self.expectLParen();
            const expr = try self.parseExpression();
            try self.expectRParen();

            return try self.makeMemoryOp(.dete, expr);
        }
        if (self.current() == .caret) {
            _ = self.advance();
            try self.expectLParen();
            const expr = try self.parseExpression();
            try self.expectRParen();

            return try self.makeMemoryOp(.address, expr);
        }
        return error.UnexpectedToken;
    }

    pub fn parseEncodingOpStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLT();
        const tag = try self.parseSystemTagName();
        try self.expectGT();
        try self.expectCaret();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();

        return try self.makeEncodeOp(tag, expr);
    }

    pub fn parseLenOpStmt(self: *Parser) anyerror!ast.Statement {
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
    pub fn parseInputStmt(self: *Parser) anyerror!ast.Statement {
        _ = self.advance();
        try self.expectLParen();
        const target_expr = try self.parseExpression();
        try self.expectRParen();

        if (self.current() == .equals) {
            _ = self.advance();
            const value_expr = try self.parseExpression();
            const ie = try self.allocator.create(ast.InputExpr);
            ie.* = ast.InputExpr{ .target = value_expr, .target_name = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .input_expr = ie };
            return ast.Statement{ .expr = e };
        }
        if (self.current() == .amp_equals) {
            _ = self.advance();
            var target_name: []const u8 = "";
            if (self.current() == .identifier) {
                target_name = self.current().identifier;
                _ = self.advance();
            } else if (self.current() == .keyword) {
                _ = self.advance();
                try self.expectLParen();
                _ = try self.parseExpression();
                try self.expectRParen();
                try self.expectSigil();
                if (self.current() == .identifier) {
                    target_name = self.current().identifier;
                    _ = self.advance();
                }
            }

            const ie = try self.allocator.create(ast.InputExpr);
            ie.* = ast.InputExpr{ .target = null, .target_name = target_name };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .input_expr = ie };
            return ast.Statement{ .expr = e };
        }

        const ie = try self.allocator.create(ast.InputExpr);
        const assignable = target_expr.* == .identifier;
        ie.* = ast.InputExpr{ .target = if (assignable) target_expr else null, .target_name = "" };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .input_expr = ie };
        return ast.Statement{ .expr = e };
    }

    pub fn parsePrintfStmt(self: *Parser) anyerror!ast.Statement {
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

    pub fn parseSystemTagStmt(self: *Parser) anyerror!ast.Statement {
        try self.expectLT();
        const tag = try self.parseSystemTagName();
        
        var encoding_type: []const u8 = "";
        if (std.mem.eql(u8, tag, "encode")) {
            if (self.current() == .l_paren) {
                _ = self.advance();
                const enc_expr = try self.parseExpression();
                switch (enc_expr.*) {
                    .literal => |lit| {
                        if (lit.kind == .string) {
                            encoding_type = lit.raw;
                        }
                    },
                    .identifier => |name| {
                        encoding_type = name;
                    },
                    else => {},
                }
                try self.expectRParen();
            }
        }
        
        try self.expectGT();
        
        if (std.mem.eql(u8, tag, "if")) {
            try self.expectLParen();
            const cond = try self.parseExpression();
            try self.expectRParen();
            const body = try self.parseBlock();
            return try self.makeIfStmt(cond, body);
        } else if (std.mem.eql(u8, tag, "elif")) {
            try self.expectLParen();
            const cond = try self.parseExpression();
            try self.expectRParen();
            const body = try self.parseBlock();
            return try self.makeElifStmt(cond, body);
        } else if (std.mem.eql(u8, tag, "else")) {
            const body = try self.parseBlock();
            return try self.makeElseStmt(body);
        } else if (std.mem.eql(u8, tag, "catch")) {
            try self.expectLParen();
            const err_type = try self.parseErrorType();
            try self.expectRParen();
            const body = try self.parseBlock();
            return try self.makeCatchStmt(err_type, body);
        } else if (std.mem.eql(u8, tag, "return")) {
            try self.expectLParen();
            const expr = try self.parseExpression();
            try self.expectRParen();
            return try self.makeReturnStmt(expr);
        } else if (std.mem.eql(u8, tag, "now")) {
            try self.expectLParen();
            const expr = try self.parseExpression();
            try self.expectRParen();
            try self.expectGT();
            const target = try self.parseExpression();
            return try self.makeNowStmt(expr, target);
        } else if (std.mem.eql(u8, tag, "memory")) {
            if (self.current() == .caret) {
                _ = self.advance();
                const expr = try self.parseExpression();
                return try self.makeMemoryOp(.address, expr);
            }
            if (self.current() == .identifier and std.mem.eql(u8, self.current().identifier, "dete")) {
                _ = self.advance();
                try self.expectLParen();
                const expr = try self.parseExpression();
                try self.expectRParen();
                return try self.makeMemoryOp(.dete, expr);
            }
            return error.UnexpectedToken;
        } else if (std.mem.eql(u8, tag, "input")) {
            try self.expectLParen();
            const target_expr = try self.parseExpression();
            try self.expectRParen();
            if (self.current() == .amp_equals) {
                _ = self.advance();
                
                var target_name: []const u8 = "";
                if (self.current() == .identifier) {
                    target_name = self.current().identifier;
                    _ = self.advance();
                } else if (self.current() == .keyword) {
                    _ = self.advance();
                    try self.expectLParen();
                    _ = try self.parseExpression();
                    try self.expectRParen();
                    try self.expectSigil();
                    if (self.current() == .identifier) {
                        target_name = self.current().identifier;
                        _ = self.advance();
                    }
                }
                
                const ie = try self.allocator.create(ast.InputExpr);
                ie.* = ast.InputExpr{ .target = null, .target_name = target_name };
                const e = try self.allocator.create(ast.Expr);
                e.* = .{ .input_expr = ie };
                return ast.Statement{ .expr = e };
            }
            const ie = try self.allocator.create(ast.InputExpr);
            const assignable = target_expr.* == .identifier;
            ie.* = ast.InputExpr{ .target = if (assignable) target_expr else null, .target_name = "" };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .input_expr = ie };
            return ast.Statement{ .expr = e };
        } else if (std.mem.eql(u8, tag, "encode")) {
            try self.expectCaret();
            try self.expectLParen();
            const expr = try self.parseExpression();
            try self.expectRParen();
            return try self.makeEncodeOp(encoding_type, expr);
        } else if (self.current() == .caret) {
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
        } else if (std.mem.eql(u8, tag, "for") or std.mem.eql(u8, tag, "while")) {
            try self.expectLParen();
            var init_assign: ?*ast.Assignment = null;
            var step: ?*ast.Expr = null;
            var loop_var_name: []const u8 = "";
            const cond = if (self.current() == .sigil) blk: {
                _ = self.advance();
                const var_tok = self.current();
                if (var_tok != .identifier) return error.ExpectedIdentifier;
                const var_name = var_tok.identifier;
                loop_var_name = var_name;
                _ = self.advance();
                try self.expectEquals();
                const init_expr = try self.parseExpression();
                var step_expr: ?*ast.Expr = null;
                if (self.current() == .l_paren) {
                    _ = self.advance();
                    const s_expr = try self.parseExpression();
                    step_expr = s_expr;
                    try self.expectRParen();
                }
                const cond_tok = self.current();
                _ = self.advance();
                const limit_expr = try self.parseExpression();
                const var_ident = try self.allocator.create(ast.Expr);
                var_ident.* = .{ .identifier = var_name };
                const op: ast.BinaryExpr.Op = switch (cond_tok) {
                    .amp_equals => .lte,
                    .lt => .lt,
                    else => .lte,
                };
                const bin = try self.allocator.create(ast.BinaryExpr);
                bin.* = ast.BinaryExpr{
                    .op = op,
                    .left = var_ident,
                    .right = limit_expr,
                };
                const cond_expr = try self.allocator.create(ast.Expr);
                cond_expr.* = .{ .binary = bin };
                const target = try self.allocator.create(ast.Expr);
                target.* = .{ .identifier = var_name };
                const assign = try self.allocator.create(ast.Assignment);
                assign.* = ast.Assignment{
                    .target = target,
                    .value_expr = init_expr,
                };
                init_assign = assign;
                step = step_expr;
                break :blk cond_expr;
            } else blk: {
                const c = try self.parseExpression();
                break :blk c;
            };
            try self.expectRParen();
            const body = try self.parseBlock();

            const kind: ast.ControlFlow.Kind = if (std.mem.eql(u8, tag, "for")) .for_loop else .while_loop;
            return try self.makeLoopStmt(kind, cond, body, init_assign, step, loop_var_name);
        } else if (self.current() == .l_paren) {
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

    pub fn parseSystemTagName(self: *Parser) ![]const u8 {
        return @import("parser_expr.zig").parseSystemTagName(self);
    }

    pub fn parseExprStatement(self: *Parser) anyerror!ast.Statement {
        const expr = try self.parseExpression();
        return ast.Statement{ .expr = expr };
    }

    pub fn parseExpression(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseExpression(self);
    }

    pub fn parseOrExpr(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseOrExpr(self);
    }

    pub fn parseAndExpr(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseAndExpr(self);
    }

    pub fn parseEqualityExpr(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseEqualityExpr(self);
    }

    pub fn isSystemTagOpener(self: *Parser) bool {
        if (self.current() != .lt) return false;
        const peek1 = self.peek(1);
        if (peek1 != .identifier and peek1 != .keyword) return false;
        if (self.peek(2) == .gt) return true;
        var i: usize = 2;
        var paren_depth: i32 = 0;
        while (i < 32) {
            const tok = self.peek(i);
            if (tok == .l_paren) { paren_depth += 1; }
            else if (tok == .r_paren) {
                paren_depth -= 1;
                if (paren_depth == 0) {
                    return self.peek(i + 1) == .gt;
                }
            }
            i += 1;
        }
        return false;
    }

    pub fn parseRelationalExpr(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseRelationalExpr(self);
    }

    pub fn parseAdditiveExpr(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseAdditiveExpr(self);
    }

    pub fn parseMultiplicativeExpr(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseMultiplicativeExpr(self);
    }

    pub fn parseUnaryExpr(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseUnaryExpr(self);
    }

    pub fn parsePrimaryExpr(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parsePrimaryExpr(self);
    }

    pub fn parseSystemTagExpr(self: *Parser) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseSystemTagExpr(self);
    }

    pub fn parseIndexAccessSuffix(self: *Parser, object_name: []const u8) anyerror!*ast.Expr {
        return @import("parser_expr.zig").parseIndexAccessSuffix(self, object_name);
    }

    pub fn makeIfStmt(self: *Parser, cond: *ast.Expr, body: []ast.Statement) !ast.Statement {
        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = .if_stmt,
            .condition = cond,
            .body = body,
            .init = null,
            .step = null,
            .loop_var = "",
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf };
    }

    pub fn makeElifStmt(self: *Parser, cond: *ast.Expr, body: []ast.Statement) !ast.Statement {
        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = .elif_stmt,
            .condition = cond,
            .body = body,
            .init = null,
            .step = null,
            .loop_var = "",
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf };
    }

    pub fn makeElseStmt(self: *Parser, body: []ast.Statement) !ast.Statement {
        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = .else_stmt,
            .condition = null,
            .body = body,
            .init = null,
            .step = null,
            .loop_var = "",
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf };
    }

    pub fn makeReturnStmt(self: *Parser, expr: *ast.Expr) !ast.Statement {
        const rs = try self.allocator.create(ast.ReturnStmt);
        rs.* = ast.ReturnStmt{ .expr = expr };
        return ast.Statement{ .return_stmt = rs };
    }

    pub fn makeCatchStmt(self: *Parser, err_type: []const u8, body: []ast.Statement) !ast.Statement {
        const cs = try self.allocator.create(ast.CatchStmt);
        cs.* = ast.CatchStmt{
            .error_type = err_type,
            .body = body,
            .allocator = self.allocator,
        };
        return ast.Statement{ .catch_stmt = cs };
    }

    pub fn makeNowStmt(self: *Parser, expr: *ast.Expr, target: *ast.Expr) !ast.Statement {
        const ne = try self.allocator.create(ast.NowExpr);
        ne.* = ast.NowExpr{ .expr = expr, .target = target };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .now_expr = ne };
        return ast.Statement{ .expr = e };
    }

    pub fn makeLoopStmt(self: *Parser, kind: ast.ControlFlow.Kind, cond: *ast.Expr, body: []ast.Statement, init_assign: ?*ast.Assignment, step: ?*ast.Expr, loop_var_name: []const u8) !ast.Statement {
        const cf = try self.allocator.create(ast.ControlFlow);
        cf.* = ast.ControlFlow{
            .kind = kind,
            .condition = cond,
            .body = body,
            .init = init_assign,
            .step = step,
            .loop_var = loop_var_name,
            .elifs = &[_]ast.Elif{},
            .else_body = &[_]ast.Statement{},
            .allocator = self.allocator,
        };
        return ast.Statement{ .control_flow = cf };
    }

    pub fn makeMemoryOp(self: *Parser, kind: ast.MemoryOp.Kind, expr: *ast.Expr) !ast.Statement {
        const mo = try self.allocator.create(ast.MemoryOp);
        mo.* = ast.MemoryOp{ .kind = kind, .expr = expr };
        return ast.Statement{ .memory_op = mo };
    }

    pub fn makeEncodeOp(self: *Parser, encoding_type: []const u8, expr: *ast.Expr) !ast.Statement {
        const eo = try self.allocator.create(ast.EncodingOp);
        eo.* = ast.EncodingOp{ .encoding_type = encoding_type, .expr = expr };
        return ast.Statement{ .encoding_op = eo };
    }

    pub fn expectLParen(self: *Parser) !void {
        if (self.current() != .l_paren) return error.ExpectedLParen;
        _ = self.advance();
    }

    pub fn expectRParen(self: *Parser) !void {
        if (self.current() != .r_paren) return error.ExpectedRParen;
        _ = self.advance();
    }

    pub fn expectLBracket(self: *Parser) !void {
        if (self.current() != .l_bracket) return error.ExpectedLBracket;
        _ = self.advance();
    }

    pub fn expectRBracket(self: *Parser) !void {
        if (self.current() != .r_bracket) return error.ExpectedRBracket;
        _ = self.advance();
    }

    pub fn expectGT(self: *Parser) !void {
        if (self.current() != .gt) return error.UnexpectedToken;
        _ = self.advance();
    }

    pub fn expectLT(self: *Parser) !void {
        if (self.current() != .lt) return error.UnexpectedToken;
        _ = self.advance();
    }

    pub fn expectRBBrace(self: *Parser) !void {
        if (self.current() != .r_brace) return error.UnexpectedToken;
        _ = self.advance();
    }

    pub fn expectCaret(self: *Parser) !void {
        if (self.current() != .caret) return error.UnexpectedToken;
        _ = self.advance();
    }

    pub fn expectSigil(self: *Parser) !void {
        if (self.current() != .sigil) return error.UnexpectedToken;
        _ = self.advance();
    }

    pub fn expectEquals(self: *Parser) !void {
        if (self.current() != .equals) return error.UnexpectedToken;
        _ = self.advance();
    }
};

fn isKnownRegionRole(role: []const u8) bool {
    const roles = [_][]const u8{ "also", "private", "public", "loop", "girc" };
    for (roles) |r| if (std.mem.eql(u8, r, role)) return true;
    return false;
}

fn printDiagnosticSlice(writer: anytype, errors: anytype) void {
    for (errors) |err| {
        writer.print("error: {s} at {d}:{d}..{d}:{d}\n", .{
            err.message, err.span.start.line, err.span.start.col, err.span.end.line, err.span.end.col,
        }) catch {};
    }
}

fn printDiagnosticSliceWithSource(writer: anytype, errors: anytype, source: []const u8) void {
    for (errors) |err| {
        writer.print("{d}:{d}: error: {s}\n", .{
            err.span.start.line, err.span.start.col, err.message,
        }) catch {};
        // print source line if available
        if (source.len > 0) {
            var line_start: usize = 0;
            var current_line: usize = 1;
            while (current_line < err.span.start.line and line_start < source.len) {
                if (source[line_start] == '\n') current_line += 1;
                line_start += 1;
            }
            var line_end = line_start;
            while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}
            const line_text = source[line_start..line_end];
            writer.print("    {s}\n", .{line_text}) catch {};
            // caret underline
            writer.writeAll("    ") catch {};
            var i: usize = 1;
            while (i < err.span.start.col and i <= line_text.len) : (i += 1) {
                if (i - 1 < line_text.len and line_text[i - 1] == '\t') {
                    writer.writeAll("\t") catch {};
                } else {
                    writer.writeAll(" ") catch {};
                }
            }
            const span_len = if (err.span.end.line == err.span.start.line and err.span.end.col > err.span.start.col)
                err.span.end.col - err.span.start.col
            else
                1;
            var j: usize = 0;
            while (j < span_len) : (j += 1) {
                writer.writeAll("^") catch {};
            }
            writer.writeAll("\n") catch {};
        }
    }
}

// Polymorphic module-level helpers: accept writer/errors in either order.
pub fn printErrors(a: anytype, b: anytype) void {
    const AIsWriter = comptime isWriterType(@TypeOf(a));
    if (AIsWriter) {
        printDiagnosticSlice(a, b);
    } else {
        printDiagnosticSlice(b, a);
    }
}
pub fn printDiagnostics(a: anytype, b: anytype) void {
    printErrors(a, b);
}
pub fn printDiagnosticReport(a: anytype, b: anytype) void {
    printErrors(a, b);
}
pub fn printErrorsWithSpan(a: anytype, b: anytype) void {
    printErrors(a, b);
}
pub fn printErrorWithSpan(a: anytype, b: anytype) void {
    printErrors(a, b);
}
pub fn printDiagnostic(a: anytype, b: anytype) void {
    printErrors(a, b);
}
pub fn reportErrors(a: anytype, b: anytype) void {
    printErrors(a, b);
}
pub fn printParseErrors(a: anytype, b: anytype) void {
    printErrors(a, b);
}
pub fn printDiagnosticEntry(a: anytype, b: anytype) void {
    printErrors(a, b);
}

// Three-argument variants (writer, errors, source) in any order.
fn isWriterType(comptime T: type) bool {
    const U = if (@typeInfo(T) == .pointer) @typeInfo(T).pointer.child else T;
    return @hasDecl(U, "writeAll");
}
fn isSourceSlice(comptime T: type) bool {
    const ti = @typeInfo(T);
    if (ti != .pointer) return false;
    return ti.pointer.child == u8;
}

pub fn printErrorsWithSource(a: anytype, b: anytype, c: anytype) void {
    // identify writer and source
    // We'll handle by trying each.
    if (comptime (isWriterType(@TypeOf(a)) and isSourceSlice(@TypeOf(c)))) {
        printDiagnosticSliceWithSource(a, b, c);
    } else if (comptime (isWriterType(@TypeOf(a)) and isSourceSlice(@TypeOf(b)))) {
        printDiagnosticSliceWithSource(a, c, b);
    } else if (comptime (isWriterType(@TypeOf(b)) and isSourceSlice(@TypeOf(a)))) {
        printDiagnosticSliceWithSource(b, c, a);
    } else if (comptime (isWriterType(@TypeOf(b)) and isSourceSlice(@TypeOf(c)))) {
        printDiagnosticSliceWithSource(b, a, c);
    } else if (comptime (isWriterType(@TypeOf(c)) and isSourceSlice(@TypeOf(a)))) {
        printDiagnosticSliceWithSource(c, b, a);
    } else if (comptime (isWriterType(@TypeOf(c)) and isSourceSlice(@TypeOf(b)))) {
        printDiagnosticSliceWithSource(c, a, b);
    } else {
        // fallback: assume a=writer,b=errors,c=source
        printDiagnosticSliceWithSource(a, b, c);
    }
}
pub fn printErrorsWithSpanAndSource(a: anytype, b: anytype, c: anytype) void {
    printErrorsWithSource(a, b, c);
}
pub fn printErrorsWithSpanSource(a: anytype, b: anytype, c: anytype) void {
    printErrorsWithSource(a, b, c);
}
pub fn printDiagnosticsWithSource(a: anytype, b: anytype, c: anytype) void {
    printErrorsWithSource(a, b, c);
}
pub fn printDiagnosticReportWithSource(a: anytype, b: anytype, c: anytype) void {
    printErrorsWithSource(a, b, c);
}

// Single diagnostic helpers
pub fn printDiagnosticOne(writer: anytype, err: anytype) void {
    err.print(writer);
}
pub fn printError(writer: anytype, err: anytype) void {
    err.print(writer);
}