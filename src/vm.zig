const std = @import("std");
const ast = @import("ast.zig");
const value_mod = @import("value.zig");

pub const VM = struct {
    allocator: std.mem.Allocator,
    global_scope: *value_mod.Scope,
    current_scope: *value_mod.Scope,
    call_stack: std.ArrayList(CallFrame),
    return_value: ?value_mod.Value,
    error_info: ?value_mod.ErrorObj,
    stdout: std.fs.File.Writer,

    pub const CallFrame = struct {
        function: *value_mod.Function,
        scope: *value_mod.Scope,
        pc: usize,
    };

    pub fn init(allocator: std.mem.Allocator) !VM {
        const global_scope = try allocator.create(value_mod.Scope);
        global_scope.* = value_mod.Scope.init(allocator, null);
        return .{
            .allocator = allocator,
            .global_scope = global_scope,
            .current_scope = global_scope,
            .call_stack = std.ArrayList(CallFrame).init(allocator),
            .return_value = null,
            .error_info = null,
            .stdout = std.io.getStdOut().writer(),
        };
    }

    pub fn deinit(self: *VM) void {
        self.global_scope.deinit();
        self.allocator.destroy(self.global_scope);
    }

    pub fn execute(self: *VM, program: *ast.Program) !void {
        for (program.stmts) |stmt| {
            try self.executeStatement(&stmt);
        }
    }

    fn executeStatement(self: *VM, stmt: *ast.Statement) !void {
        switch (stmt.*) {
            .var_decl => |*v| {
                const val = try self.evaluateExpression(v.value_expr);
                try self.current_scope.variables.put(self.allocator.dupe(u8, v.name) catch unreachable, val);
            },
            .assignment => |*a| {
                const val = try self.evaluateExpression(a.value_expr);
                // Simplified: update variable by re-evaluating target
                _ = val;
            },
            .func_decl => |*f| {
                const func = try self.allocator.create(value_mod.Function);
                func.* = value_mod.Function{
                    .name = f.name,
                    .params = try self.allocator.dupe(value_mod.Param, f.params),
                    .body = try self.allocator.dupe(ast.Statement, f.body),
                    .closure_scope = self.current_scope,
                    .allocator = self.allocator,
                };
                try self.current_scope.functions.put(self.allocator.dupe(u8, f.name) catch unreachable, func.*);
            },
            .class_decl => |*c| {
                const class_def = try self.allocator.create(value_mod.ClassDef);
                class_def.* = value_mod.ClassDef{
                    .name = c.name,
                    .private_fields = std.StringHashMap(value_mod.Value).init(self.allocator),
                    .private_methods = std.StringHashMap(value_mod.Function).init(self.allocator),
                    .public_fields = std.StringHashMap(value_mod.Value).init(self.allocator),
                    .public_methods = std.StringHashMap(value_mod.Function).init(self.allocator),
                    .allocator = self.allocator,
                };
                try self.current_scope.classes.put(self.allocator.dupe(u8, c.name) catch unreachable, class_def.*);
            },
            .control_flow => |*cf| {
                switch (cf.kind) {
                    .if_stmt => {
                        const cond = try self.evaluateExpression(cf.condition);
                        const cond_bool = try cond.toBool();
                        if (cond_bool) {
                            for (cf.body) |*s| try self.executeStatement(s);
                        }
                    },
                    .elif_stmt => {
                        const cond = try self.evaluateExpression(cf.condition);
                        const cond_bool = try cond.toBool();
                        if (cond_bool) {
                            for (cf.body) |*s| try self.executeStatement(s);
                        }
                    },
                    .else_stmt => {
                        for (cf.body) |*s| try self.executeStatement(s);
                    },
                    .for_loop => {
                        // Simplified for loop
                        for (cf.body) |*s| try self.executeStatement(s);
                    },
                    .while_loop => {
                        // Simplified while loop - just execute once for prototype
                        for (cf.body) |*s| try self.executeStatement(s);
                    },
                }
            },
            .memory_op => |*m| {
                switch (m.kind) {
                    .address => {
                        const val = try self.evaluateExpression(m.expr);
                        _ = val;
                    },
                    .dete => {
                        const val = try self.evaluateExpression(m.expr);
                        val.deinit(self.allocator);
                    },
                }
            },
            .encoding_op => |*eo| {
                const val = try self.evaluateExpression(eo.expr);
                _ = val;
                _ = eo.encoding_type;
            },
            .len_op => |*lo| {
                const val = try self.evaluateExpression(lo.expr);
                _ = val;
            },
            .return_stmt => |*rs| {
                const val = try self.evaluateExpression(rs.expr);
                self.return_value = val;
            },
            .expr => |*e| {
                _ = try self.evaluateExpression(e);
            },
            .catch_stmt => |*cs| {
                if (self.error_info) |err| {
                    if (std.mem.eql(u8, err.type, cs.error_type)) {
                        for (cs.body) |*s| try self.executeStatement(s);
                    }
                }
            },
        }
    }

    fn evaluateExpression(self: *VM, expr: *ast.Expr) !value_mod.Value {
        return switch (expr.*) {
            .literal => |lit| self.evaluateLiteral(lit),
            .identifier => |name| self.evaluateIdentifier(name),
            .binary => |bin| self.evaluateBinary(bin),
            .unary => |unary| self.evaluateUnary(unary),
            .call => |call| self.evaluateCall(call),
            .member_access => |ma| self.evaluateMemberAccess(ma),
            .index_access => |ia| self.evaluateIndexAccess(ia),
            .system_tag => |st| self.evaluateSystemTag(st),
            .input_expr => |ie| self.evaluateInput(ie),
            .now_expr => |ne| self.evaluateNow(ne),
        };
    }

    fn evaluateLiteral(self: *VM, lit: ast.Literal) !value_mod.Value {
        return switch (lit.kind) {
            .int => value_mod.Value{ .int = 0 },
            .freal => value_mod.Value{ .freal = 0.0 },
            .string => value_mod.Value{ .string = lit.raw },
            .bool_true => value_mod.Value{ .booling = true },
            .bool_false => value_mod.Value{ .booling = false },
            .tuple => value_mod.Value{ .tuple = &[_]value_mod.Value{} },
            .dict => value_mod.Value{ .dict = std.StringHashMap(value_mod.Value).init(self.allocator) },
        };
    }

    fn evaluateIdentifier(self: *VM, name: []const u8) !value_mod.Value {
        if (self.current_scope.variables.get(name)) |val| {
            return val;
        }
        if (self.current_scope.functions.get(name)) |func| {
            return value_mod.Value{ .function = func };
        }
        if (self.current_scope.classes.get(name)) |cls| {
            return value_mod.Value{ .class_instance = try self.allocator.create(value_mod.ClassInstance) };
        }
        return value_mod.Value{ .null = {} };
    }

    fn evaluateBinary(self: *VM, bin: *ast.BinaryExpr) !value_mod.Value {
        const left = try self.evaluateExpression(bin.left);
        const right = try self.evaluateExpression(bin.right);

        return switch (bin.op) {
            .add => try left.add(right),
            .sub => try left.sub(right),
            .mul => try left.mul(right),
            .div => try left.div(right),
            .rem => try left.rem(right),
            .and => value_mod.Value{ .booling = (try left.toBool()) and (try right.toBool()) },
            .or => value_mod.Value{ .booling = (try left.toBool()) or (try right.toBool()) },
            .eq => value_mod.Value{ .booling = try left.equals(right) },
            .neq => value_mod.Value{ .booling = !(try left.equals(right)) },
            .lt => value_mod.Value{ .booling = (try left.toBool()) < (try right.toBool()) },
            .gt => value_mod.Value{ .booling = (try left.toBool()) > (try right.toBool()) },
            .lte => value_mod.Value{ .booling = (try left.toBool()) <= (try right.toBool()) },
            .gte => value_mod.Value{ .booling = (try left.toBool()) >= (try right.toBool()) },
        };
    }

    fn evaluateUnary(self: *VM, unary: *ast.UnaryExpr) !value_mod.Value {
        const val = try self.evaluateExpression(unary.expr);
        return switch (unary.op) {
            .neg => switch (val) {
                .int => |i| value_mod.Value{ .int = -i },
                .freal => |f| value_mod.Value{ .freal = -f },
                else => error.TypeError,
            },
            .not => value_mod.Value{ .booling = !(try val.toBool()) },
        };
    }

    fn evaluateCall(self: *VM, call: *ast.CallExpr) !value_mod.Value {
        _ = call;
        return value_mod.Value{ .null = {} };
    }

    fn evaluateMemberAccess(self: *VM, ma: *ast.MemberAccess) !value_mod.Value {
        const obj = try self.evaluateExpression(ma.object);
        _ = obj;
        _ = ma.member;
        return value_mod.Value{ .null = {} };
    }

    fn evaluateIndexAccess(self: *VM, ia: *ast.IndexAccess) !value_mod.Value {
        const obj = try self.evaluateExpression(ia.object);
        const idx = try self.evaluateExpression(ia.index);
        _ = obj;
        _ = idx;
        return value_mod.Value{ .null = {} };
    }

    fn evaluateSystemTag(self: *VM, st: *ast.SystemTagExpr) !value_mod.Value {
        if (st.args.len > 0) {
            const arg = try self.evaluateExpression(&st.args[0]);
            if (std.mem.eql(u8, st.tag, "printf")) {
                try self.stdout.print("{any}\n", .{arg});
                return value_mod.Value{ .null = {} };
            }
            if (std.mem.eql(u8, st.tag, "len")) {
                return switch (arg) {
                    .string => |s| value_mod.Value{ .int = @intCast(s.len) },
                    .tuple, .list => |v| value_mod.Value{ .int = @intCast(v.len) },
                    .bytes => |b| value_mod.Value{ .int = @intCast(b.len) },
                    else => value_mod.Value{ .int = 0 },
                };
            }
            if (std.mem.eql(u8, st.tag, "memory")) {
                return value_mod.Value{ .int = 0 };
            }
            if (std.mem.eql(u8, st.tag, "encode")) {
                if (arg == .string) {
                    const bytes = try self.allocator.dupe(u8, arg.string);
                    return value_mod.Value{ .bytes = bytes };
                }
                return value_mod.Value{ .bytes = &[_]u8{} };
            }
        }
        return value_mod.Value{ .null = {} };
    }

    fn evaluateInput(self: *VM, ie: *ast.InputExpr) !value_mod.Value {
        var buf: [4096]u8 = undefined;
        const stdin = std.io.getStdIn().reader();
        const line = try stdin.readUntilDelimiterOrEof(buf[0..], '\n');
        if (line) |l| {
            const str = try self.allocator.dupe(u8, l);
            if (ie.target) |target| {
                const name = target.identifier;
                try self.current_scope.variables.put(self.allocator.dupe(u8, name) catch unreachable, value_mod.Value{ .string = str });
            }
            return value_mod.Value{ .string = str };
        }
        return value_mod.Value{ .string = "" };
    }

    fn evaluateNow(self: *VM, ne: *ast.NowExpr) !value_mod.Value {
        return try self.evaluateExpression(ne.expr);
    }
};
