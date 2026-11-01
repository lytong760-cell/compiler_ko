const std = @import("std");
const parser_mod = @import("parser.zig");
const Parser = parser_mod.Parser;
const ast = @import("ast.zig");
const lexer = @import("lexer.zig");
const value_mod = @import("value.zig");

pub fn parseSystemTagName(self: *Parser) ![]const u8 {
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

pub fn parseExpression(self: *Parser) anyerror!*ast.Expr {
    return try self.parseOrExpr();
}

pub fn parseOrExpr(self: *Parser) anyerror!*ast.Expr {
    var left = try self.parseAndExpr();
    while (self.current() == .logical_or) {
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

pub fn parseAndExpr(self: *Parser) anyerror!*ast.Expr {
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

pub fn parseEqualityExpr(self: *Parser) anyerror!*ast.Expr {
    var left = try self.parseRelationalExpr();
    while (true) {
        if (self.current() == .equals and self.peek(1) == .equals) {
            _ = self.advance();
            _ = self.advance();
            const right = try self.parseRelationalExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{ .op = .eq, .left = left, .right = right };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin };
        } else if (self.current() == .bang and self.peek(1) == .equals) {
            _ = self.advance();
            _ = self.advance();
            const right = try self.parseRelationalExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{ .op = .neq, .left = left, .right = right };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin };
        } else {
            break;
        }
    }
    return left;
}

pub fn parseRelationalExpr(self: *Parser) anyerror!*ast.Expr {
    var left = try self.parseAdditiveExpr();
    while (true) {
        if (self.current() == .lt and self.peek(1) == .equals) {
            _ = self.advance();
            _ = self.advance();
            const right = try self.parseAdditiveExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{ .op = .lte, .left = left, .right = right };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin };
        } else if (self.current() == .gt and self.peek(1) == .equals) {
            _ = self.advance();
            _ = self.advance();
            const right = try self.parseAdditiveExpr();
            const bin = try self.allocator.create(ast.BinaryExpr);
            bin.* = ast.BinaryExpr{ .op = .gte, .left = left, .right = right };
            left = try self.allocator.create(ast.Expr);
            left.* = .{ .binary = bin };
        } else if (self.current() == .lt and self.peek(1) != .equals and !self.isSystemTagOpener()) {
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

pub fn parseAdditiveExpr(self: *Parser) anyerror!*ast.Expr {
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

pub fn parseMultiplicativeExpr(self: *Parser) anyerror!*ast.Expr {
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

pub fn parseUnaryExpr(self: *Parser) anyerror!*ast.Expr {
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

pub fn parsePrimaryExpr(self: *Parser) anyerror!*ast.Expr {
    const tok = self.current();

    if (tok == .int_lit) {
        _ = self.advance();
        const lit = try self.allocator.create(ast.Literal);
        lit.* = ast.Literal{ .kind = .int, .int_value = tok.int_lit, .freal_value = 0, .raw = "", .dict_entries = &.{}, .allocator = self.allocator };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .literal = lit.* };
        return e;
    }

    if (tok == .freal_lit) {
        _ = self.advance();
        const lit = try self.allocator.create(ast.Literal);
        lit.* = ast.Literal{ .kind = .freal, .int_value = 0, .freal_value = tok.freal_lit, .raw = "", .dict_entries = &.{}, .allocator = self.allocator };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .literal = lit.* };
        return e;
    }

    if (tok == .string_lit) {
        const str = tok.string_lit;
        _ = self.advance();
        const lit = try self.allocator.create(ast.Literal);
        lit.* = ast.Literal{ .kind = .string, .int_value = 0, .freal_value = 0, .raw = str, .dict_entries = &.{}, .allocator = self.allocator };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .literal = lit.* };
        return e;
    }

    if (tok == .bool_true) {
        _ = self.advance();
        const lit = try self.allocator.create(ast.Literal);
        lit.* = ast.Literal{ .kind = .bool_true, .int_value = 0, .freal_value = 0, .raw = "", .dict_entries = &.{}, .allocator = self.allocator };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .literal = lit.* };
        return e;
    }

    if (tok == .bool_false) {
        _ = self.advance();
        const lit = try self.allocator.create(ast.Literal);
        lit.* = ast.Literal{ .kind = .bool_false, .int_value = 0, .freal_value = 0, .raw = "", .dict_entries = &.{}, .allocator = self.allocator };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .literal = lit.* };
        return e;
    }

    if (tok == .identifier and std.mem.eql(u8, tok.identifier, "none")) {
        _ = self.advance();
        const lit = try self.allocator.create(ast.Literal);
        lit.* = ast.Literal{ .kind = .none, .int_value = 0, .freal_value = 0, .raw = "", .dict_entries = &.{}, .allocator = self.allocator };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .literal = lit.* };
        return e;
    }

    if (tok == .identifier and std.mem.eql(u8, tok.identifier, "null")) {
        _ = self.advance();
        const lit = try self.allocator.create(ast.Literal);
        lit.* = ast.Literal{ .kind = .null, .int_value = 0, .freal_value = 0, .raw = "", .dict_entries = &.{}, .allocator = self.allocator };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .literal = lit.* };
        return e;
    }

    if (tok == .identifier) {
        const name = tok.identifier;
        _ = self.advance();
        if (self.current() == .l_paren) {
            _ = self.advance();
            var args = std.array_list.Managed(ast.Expr).init(self.allocator);
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
        if (self.current() == .l_brace) {
            const index_expr = try self.parseIndexAccessSuffix(name);
            return index_expr;
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
            var args = std.array_list.Managed(ast.Expr).init(self.allocator);
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
            const member = self.current().identifier;
            _ = self.advance();
            if (self.current() == .l_paren) {
                _ = self.advance();
                var args = std.array_list.Managed(ast.Expr).init(self.allocator);
                while (!(self.current() == .r_paren) and !self.isAtEnd()) {
                    const expr = try self.parseExpression();
                    try args.append(expr.*);
                    if (self.current() == .comma) _ = self.advance();
                }
                try self.expectRParen();

                const member_access = try self.allocator.create(ast.MemberAccess);
                member_access.* = ast.MemberAccess{
                    .object = try self.allocator.create(ast.Expr),
                    .member = member,
                };
                member_access.object.* = .{ .identifier = name };
                const target_expr = try self.allocator.create(ast.Expr);
                target_expr.* = .{ .member_access = member_access };
                const call = try self.allocator.create(ast.CallExpr);
                call.* = ast.CallExpr{
                    .callee = member,
                    .args = try args.toOwnedSlice(),
                    .target = target_expr,
                };
                const e = try self.allocator.create(ast.Expr);
                e.* = .{ .call = call };
                return e;
            }
            const member_access = try self.allocator.create(ast.MemberAccess);
            member_access.* = ast.MemberAccess{
                .object = try self.allocator.create(ast.Expr),
                .member = member,
            };
            member_access.object.* = .{ .identifier = name };
            const e = try self.allocator.create(ast.Expr);
            e.* = .{ .member_access = member_access };
            return e;
        }
        if (self.current() == .l_brace) {
            const index_expr = try self.parseIndexAccessSuffix(name);
            return index_expr;
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
        var entries = std.array_list.Managed(ast.DictEntry).init(self.allocator);
        var consumed = false;
        errdefer if (!consumed) entries.deinit();
        while (!(self.current() == .r_brace) and !self.isAtEnd()) {
            const key_expr = try self.parseExpression();
            if (self.current() != .colon) return error.ExpectedColon;
            _ = self.advance();
            const value_expr = try self.parseExpression();
            const key = switch (key_expr.*) {
                .literal => |lit| switch (lit.kind) {
                    .string => lit.raw,
                    else => return error.ExpectedDictKey,
                },
                .identifier => |name| name,
                else => return error.ExpectedDictKey,
            };
            key_expr.deinit();
            self.allocator.destroy(key_expr);
            const entry = try self.allocator.create(ast.DictEntry);
            entry.* = ast.DictEntry{
                .key = key,
                .value = value_expr,
                .allocator = self.allocator,
            };
            try entries.append(entry.*);
            if (self.current() == .comma) _ = self.advance();
        }
        try self.expectRBBrace();

        const dict_entries = entries.items;
        consumed = true;

        const lit = try self.allocator.create(ast.Literal);
        lit.* = ast.Literal{
            .kind = .dict,
            .int_value = 0,
            .freal_value = 0,
            .raw = "",
            .dict_entries = dict_entries,
            .allocator = self.allocator,
        };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .literal = lit.* };
        return e;
    }

    if (tok == .lt) {
        return try self.parseSystemTagExpr();
    }

    return error.UnexpectedToken;
}

pub fn parseSystemTagExpr(self: *Parser) anyerror!*ast.Expr {
    _ = self.advance();
    const tag = try self.parseSystemTagName();

    var args = std.array_list.Managed(ast.Expr).init(self.allocator);
    defer args.deinit();

    if (std.mem.eql(u8, tag, "encode") and self.current() == .identifier) {
        const enc_name = self.current().identifier;
        _ = self.advance();
        try self.expectGT();
        const enc_lit = try self.allocator.create(ast.Literal);
        enc_lit.* = ast.Literal{ .kind = .string, .int_value = 0, .freal_value = 0, .raw = enc_name, .dict_entries = &.{}, .allocator = self.allocator };
        try args.append(ast.Expr{ .literal = enc_lit.* });
    } else {
        try self.expectGT();
    }

    if (self.current() == .caret) {
        _ = self.advance();
        try self.expectLParen();
        const expr = try self.parseExpression();
        try self.expectRParen();
        try args.append(expr.*);
    }

    if (self.current() == .l_paren) {
        _ = self.advance();
        const expr = try self.parseExpression();
        try self.expectRParen();
        try args.append(expr.*);
    }

    if (args.items.len == 0) return error.UnexpectedToken;

    const ste = try self.allocator.create(ast.SystemTagExpr);
    ste.* = ast.SystemTagExpr{
        .tag = tag,
        .args = try args.toOwnedSlice(),
    };
    const e = try self.allocator.create(ast.Expr);
    e.* = .{ .system_tag = ste };
    return e;
}

pub fn parseIndexAccessSuffix(self: *Parser, object_name: []const u8) anyerror!*ast.Expr {
    const object = try self.allocator.create(ast.Expr);
    object.* = .{ .identifier = object_name };

    if (self.current() == .l_brace) {
        _ = self.advance();
        const index_expr = try self.parseExpression();
        try self.expectRBBrace();

        const ia = try self.allocator.create(ast.IndexAccess);
        ia.* = ast.IndexAccess{
            .object = object,
            .index = index_expr,
        };
        const e = try self.allocator.create(ast.Expr);
        e.* = .{ .index_access = ia };
        return e;
    }

    return object;
}

