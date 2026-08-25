const std = @import("std");
const ast = @import("ast.zig");
const value_mod = @import("value.zig");

pub const VM = struct {
    allocator: std.mem.Allocator,
    global_scope: *value_mod.Scope,
    current_scope: *value_mod.Scope,
    stdout: std.fs.File.Writer,
    return_value: ?value_mod.Value,
    has_returned: bool,
    error_type: ?[]const u8,
    has_error: bool,

    pub fn init(allocator: std.mem.Allocator) !VM {
        const global_scope = try allocator.create(value_mod.Scope);
        global_scope.* = value_mod.Scope.init(allocator, null);
        return .{
            .allocator = allocator,
            .global_scope = global_scope,
            .current_scope = global_scope,
            .stdout = std.io.getStdOut().writer(),
            .return_value = null,
            .has_returned = false,
            .error_type = null,
            .has_error = false,
        };
    }

    pub fn deinit(self: *VM) void {
        self.global_scope.deinit();
        self.allocator.destroy(self.global_scope);
    }

    pub fn execute(self: *VM, program: []ast.Statement) !void {
        for (program) |*stmt| try self.executeStatement(stmt);
    }

    fn executeStatement(self: *VM, stmt: *const ast.Statement) !void {
        if (self.has_returned or self.has_error) return;

        switch (stmt.*) {
            .var_decl => |*v| {
                const val = try self.evaluateExpression(v.value_expr);
                const name_copy = self.allocator.dupe(u8, v.name) catch unreachable;
                try self.current_scope.variables.put(name_copy, val);
            },
            .assignment => |*a| {
                const val = try self.evaluateExpression(a.value_expr);
                try self.assignValue(a.target, val);
            },
            .func_decl => |f| {
                const func = try self.allocator.create(value_mod.Function);
                const name_copy = try self.allocator.dupe(u8, f.name);
                func.* = value_mod.Function{
                    .name = name_copy,
                    .params = try self.allocator.dupe(value_mod.Param, f.params),
                    .body_ptr = @ptrCast(f.body.ptr),
                    .body_len = f.body.len,
                    .closure_scope = self.current_scope,
                    .allocator = self.allocator,
                };
                try self.current_scope.functions.put(name_copy, func);
            },
            .class_decl => |c| {
                const class_def = try self.allocator.create(value_mod.ClassDef);
                class_def.* = value_mod.ClassDef{
                    .name = c.name,
                    .private_fields = std.StringHashMap(value_mod.Value).init(self.allocator),
                    .private_methods = std.StringHashMap(*value_mod.Function).init(self.allocator),
                    .public_fields = std.StringHashMap(value_mod.Value).init(self.allocator),
                    .public_methods = std.StringHashMap(*value_mod.Function).init(self.allocator),
                    .allocator = self.allocator,
                };
                const name_copy = self.allocator.dupe(u8, c.name) catch unreachable;
                try self.current_scope.classes.put(name_copy, class_def);

                var private_scope = try self.allocator.create(value_mod.Scope);
                private_scope.* = value_mod.Scope.init(self.allocator, self.current_scope);
                for (c.private_body) |*priv_stmt| {
                    try self.executeStatementInScope(priv_stmt, private_scope);
                }

                var piter = private_scope.variables.iterator();
                while (piter.next()) |entry| {
                    try class_def.private_fields.put(try self.allocator.dupe(u8, entry.key_ptr.*), entry.value_ptr.*);
                }
                var miter = private_scope.functions.iterator();
                while (miter.next()) |entry| {
                    try class_def.private_methods.put(try self.allocator.dupe(u8, entry.key_ptr.*), entry.value_ptr.*);
                }
                private_scope.deinit();
                self.allocator.destroy(private_scope);

                var public_scope = try self.allocator.create(value_mod.Scope);
                public_scope.* = value_mod.Scope.init(self.allocator, self.current_scope);
                for (c.public_body) |*pub_stmt| {
                    try self.executeStatementInScope(pub_stmt, public_scope);
                }

                var ppiter = public_scope.variables.iterator();
                while (ppiter.next()) |entry| {
                    try class_def.public_fields.put(try self.allocator.dupe(u8, entry.key_ptr.*), entry.value_ptr.*);
                }
                var pmiter = public_scope.functions.iterator();
                while (pmiter.next()) |entry| {
                    try class_def.public_methods.put(try self.allocator.dupe(u8, entry.key_ptr.*), entry.value_ptr.*);
                }
                public_scope.deinit();
                self.allocator.destroy(public_scope);
            },
            .control_flow => |cf| {
                switch (cf.kind) {
                    .if_stmt => {
                        const cond = try self.evaluateExpression(cf.condition);
                        if (try cond.toBool()) {
                            for (cf.body) |s| try self.executeStatement(&s);
                        }
                    },
                    .elif_stmt => {
                        const cond = try self.evaluateExpression(cf.condition);
                        if (try cond.toBool()) {
                            for (cf.body) |s| try self.executeStatement(&s);
                        }
                    },
                    .else_stmt => {
                        for (cf.body) |s| try self.executeStatement(&s);
                    },
                    .for_loop => {
                        var cond_val = try self.evaluateExpression(cf.condition);
                        while (try cond_val.toBool() and !self.has_returned and !self.has_error) {
                            for (cf.body) |s| try self.executeStatement(&s);
                            if (self.has_returned or self.has_error) break;
                            cond_val = try self.evaluateExpression(cf.condition);
                        }
                    },
                    .while_loop => {
                        var cond_val = try self.evaluateExpression(cf.condition);
                        while (try cond_val.toBool() and !self.has_returned and !self.has_error) {
                            for (cf.body) |s| try self.executeStatement(&s);
                            if (self.has_returned or self.has_error) break;
                            cond_val = try self.evaluateExpression(cf.condition);
                        }
                    },
                }
            },
            .memory_op => |m| {
                switch (m.kind) {
                    .address => {
                        const val = try self.evaluateExpression(m.expr);
                        _ = val;
                    },
                    .dete => {
                        var val = try self.evaluateExpression(m.expr);
                        val.deinit(self.allocator);
                    },
                }
            },
            .encoding_op => |eo| {
                const val = try self.evaluateExpression(eo.expr);
                _ = val;
                _ = eo.encoding_type;
            },
            .len_op => |lo| {
                const val = try self.evaluateExpression(lo.expr);
                _ = val;
            },
            .return_stmt => |rs| {
                const val = try self.evaluateExpression(rs.expr);
                self.return_value = val;
                self.has_returned = true;
            },
            .block => |b| {
                for (b.body) |s| try self.executeStatement(&s);
            },
            .expr => |e| {
                _ = try self.evaluateExpression(e);
            },
            .catch_stmt => |cs| {
                if (self.has_error) {
                    if (self.error_type) |err_type| {
                        if (std.mem.eql(u8, err_type, cs.error_type)) {
                            self.has_error = false;
                            self.error_type = null;
                            for (cs.body) |s| try self.executeStatement(&s);
                        }
                    }
                }
            },
        }
    }

    fn executeStatementInScope(self: *VM, stmt: *const ast.Statement, scope: *value_mod.Scope) !void {
        const prev_scope = self.current_scope;
        self.current_scope = scope;
        defer self.current_scope = prev_scope;
        try self.executeStatement(stmt);
    }

    fn assignValue(self: *VM, target: *ast.Expr, val: value_mod.Value) !void {
        switch (target.*) {
            .identifier => |name| {
                if (self.current_scope.variables.get(name)) |_| {
                    const name_copy = self.allocator.dupe(u8, name) catch unreachable;
                    try self.current_scope.variables.put(name_copy, val);
                } else if (self.global_scope.variables.get(name)) |_| {
                    const name_copy = self.allocator.dupe(u8, name) catch unreachable;
                    try self.global_scope.variables.put(name_copy, val);
                } else {
                    self.raiseError("AssignmentError", "Undefined variable");
                }
            },
            .member_access => |ma| {
                const obj = try self.evaluateExpression(ma.object);
                switch (obj) {
                    .class_instance => |ci| {
                        if (ci.fields.get(ma.member)) |_| {
                            const key_copy = self.allocator.dupe(u8, ma.member) catch unreachable;
                            try ci.fields.put(key_copy, val);
                        } else if (ci.methods.get(ma.member)) |_| {
                            self.raiseError("AssignmentError", "Cannot assign to method");
                        } else {
                            self.raiseError("AssignmentError", "Member not found");
                        }
                    },
                    else => self.raiseError("AssignmentError", "Not a class instance"),
                }
            },
            .index_access => |ia| {
                const obj = try self.evaluateExpression(ia.object);
                const idx = try self.evaluateExpression(ia.index);
                switch (obj) {
                    .tuple, .list => |arr| {
                        if (idx == .int) |i| {
                            const idx_usize: usize = @intCast(i);
                            if (idx_usize < arr.len) {
                                arr[idx_usize].deinit(self.allocator);
                                arr[idx_usize] = val;
                            } else {
                                self.raiseError("IndexError", "Index out of bounds");
                            }
                        } else {
                            self.raiseError("TypeError", "Index must be integer");
                        }
                    },
                    .dict => |d| {
                        if (idx == .string) {
                            const key = idx.string;
                            const key_copy = self.allocator.dupe(u8, key) catch unreachable;
                            try d.put(key_copy, val);
                        } else {
                            self.raiseError("TypeError", "Dict key must be string");
                        }
                    },
                    else => self.raiseError("TypeError", "Cannot index this type"),
                }
            },
            else => self.raiseError("SyntaxError", "Invalid assignment target"),
        }
    }

    fn raiseError(self: *VM, err_type: []const u8, message: []const u8) void {
        self.has_error = true;
        self.error_type = self.allocator.dupe(u8, err_type) catch unreachable;
        _ = message;
    }

    fn evaluateExpression(self: *VM, expr: *ast.Expr) !value_mod.Value {
        if (self.has_returned or self.has_error) return value_mod.Value{ .null = {} };

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
            .int => value_mod.Value{ .int = lit.int_value },
            .freal => value_mod.Value{ .freal = lit.freal_value },
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
        if (self.current_scope.classes.get(name)) |class_def| {
            return value_mod.Value{ .class_instance = class_def };
        }
        if (self.global_scope.variables.get(name)) |val| {
            return val;
        }
        if (self.global_scope.functions.get(name)) |func| {
            return value_mod.Value{ .function = func };
        }
        if (self.global_scope.classes.get(name)) |class_def| {
            return value_mod.Value{ .class_instance = class_def };
        }
        return error.UndefinedVariable;
    }

    fn evaluateBinary(self: *VM, bin: *ast.BinaryExpr) !value_mod.Value {
        const left = try self.evaluateExpression(bin.left);
        const right = try self.evaluateExpression(bin.right);

        return switch (bin.op) {
            .add => try left.add(right, self.allocator),
            .sub => try left.sub(right),
            .mul => try left.mul(right),
            .div => try left.div(right),
            .rem => try left.rem(right),
            .logical_and => value_mod.Value{ .booling = (try left.toBool()) and (try right.toBool()) },
            .logical_or => value_mod.Value{ .booling = (try left.toBool()) or (try right.toBool()) },
            .eq => value_mod.Value{ .booling = try left.equals(right) },
            .neq => value_mod.Value{ .booling = !(try left.equals(right)) },
            .lt => try compareLess(left, right),
            .gt => try compareGreater(left, right),
            .lte => try compareLessOrEqual(left, right),
            .gte => try compareGreaterOrEqual(left, right),
        };
    }

    fn compareLess(left: value_mod.Value, right: value_mod.Value) !value_mod.Value {
        return switch (left) {
            .int => |a| switch (right) {
                .int => |b| value_mod.Value{ .booling = a < b },
                .freal => |b| value_mod.Value{ .booling = @as(f64, @floatFromInt(a)) < b },
                else => error.TypeError,
            },
            .freal => |a| switch (right) {
                .freal => |b| value_mod.Value{ .booling = a < b },
                .int => |b| value_mod.Value{ .booling = a < @as(f64, @floatFromInt(b)) },
                else => error.TypeError,
            },
            .string => |a| switch (right) {
                .string => |b| value_mod.Value{ .booling = std.mem.order(u8, a, b) == .lt },
                else => error.TypeError,
            },
            else => error.TypeError,
        };
    }

    fn compareGreater(left: value_mod.Value, right: value_mod.Value) !value_mod.Value {
        return switch (left) {
            .int => |a| switch (right) {
                .int => |b| value_mod.Value{ .booling = a > b },
                .freal => |b| value_mod.Value{ .booling = @as(f64, @floatFromInt(a)) > b },
                else => error.TypeError,
            },
            .freal => |a| switch (right) {
                .freal => |b| value_mod.Value{ .booling = a > b },
                .int => |b| value_mod.Value{ .booling = a > @as(f64, @floatFromInt(b)) },
                else => error.TypeError,
            },
            .string => |a| switch (right) {
                .string => |b| value_mod.Value{ .booling = std.mem.order(u8, a, b) == .gt },
                else => error.TypeError,
            },
            else => error.TypeError,
        };
    }

    fn compareLessOrEqual(left: value_mod.Value, right: value_mod.Value) !value_mod.Value {
        return switch (left) {
            .int => |a| switch (right) {
                .int => |b| value_mod.Value{ .booling = a <= b },
                .freal => |b| value_mod.Value{ .booling = @as(f64, @floatFromInt(a)) <= b },
                else => error.TypeError,
            },
            .freal => |a| switch (right) {
                .freal => |b| value_mod.Value{ .booling = a <= b },
                .int => |b| value_mod.Value{ .booling = a <= @as(f64, @floatFromInt(b)) },
                else => error.TypeError,
            },
            .string => |a| switch (right) {
                .string => |b| value_mod.Value{ .booling = std.mem.order(u8, a, b) != .gt },
                else => error.TypeError,
            },
            else => error.TypeError,
        };
    }

    fn compareGreaterOrEqual(left: value_mod.Value, right: value_mod.Value) !value_mod.Value {
        return switch (left) {
            .int => |a| switch (right) {
                .int => |b| value_mod.Value{ .booling = a >= b },
                .freal => |b| value_mod.Value{ .booling = @as(f64, @floatFromInt(a)) >= b },
                else => error.TypeError,
            },
            .freal => |a| switch (right) {
                .freal => |b| value_mod.Value{ .booling = a >= b },
                .int => |b| value_mod.Value{ .booling = a >= @as(f64, @floatFromInt(b)) },
                else => error.TypeError,
            },
            .string => |a| switch (right) {
                .string => |b| value_mod.Value{ .booling = std.mem.order(u8, a, b) != .lt },
                else => error.TypeError,
            },
            else => error.TypeError,
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

    fn evaluateCall(self: *VM, call: *const ast.CallExpr) anyerror!value_mod.Value {
        if (std.mem.eql(u8, call.callee, "Import")) {
            for (call.args) |arg| {
                _ = try self.evaluateExpression(@constCast(&arg));
            }
            return value_mod.Value{ .null = {} };
        }
        if (std.mem.eql(u8, call.callee, "printf")) {
            for (call.args) |arg| {
                const val = try self.evaluateExpression(@constCast(&arg));
                if (val == .string) {
                    var out = std.ArrayList(u8).init(self.allocator);
                    var i: usize = 0;
                    while (i < val.string.len) {
                        if (val.string[i] == '\\' and i + 1 < val.string.len and val.string[i + 1] == 'n') {
                            try out.append('\n');
                            i += 2;
                        } else {
                            try out.append(val.string[i]);
                            i += 1;
                        }
                    }
                    try self.stdout.print("{s}", .{out.items});
                    out.deinit();
                } else {
                    try self.stdout.print("{any}\n", .{val});
                }
            }
            return value_mod.Value{ .null = {} };
        }

        const callee_val = try self.evaluateIdentifier(call.callee);
        switch (callee_val) {
            .function => |func| {
                if (call.args.len != func.params.len) {
                    self.raiseError("ArgumentError", "Argument count mismatch");
                    return error.RuntimeError;
                }

                var new_scope = try self.allocator.create(value_mod.Scope);
                new_scope.* = value_mod.Scope.init(self.allocator, func.closure_scope);

                for (call.args, func.params) |arg_expr, param| {
                    const arg_val = try self.evaluateExpression(@constCast(&arg_expr));
                    const param_name = self.allocator.dupe(u8, param.name) catch unreachable;
                    try new_scope.variables.put(param_name, arg_val);
                }

                const prev_scope = self.current_scope;
                self.current_scope = new_scope;
                self.has_returned = false;
                self.return_value = null;
                self.has_error = false;
                self.error_type = null;

                var body_stmts: []ast.Statement = undefined;
                body_stmts.ptr = @ptrCast(@alignCast(func.body_ptr));
                body_stmts.len = func.body_len;

                for (body_stmts) |*body_stmt| {
                    try self.executeStatement(body_stmt);
                    if (self.has_returned or self.has_error) break;
                }

                const ret = self.return_value orelse value_mod.Value{ .null = {} };

                new_scope.deinit();
                self.allocator.destroy(new_scope);
                self.current_scope = prev_scope;
                self.has_returned = false;
                self.return_value = null;

                return ret;
            },
            .class_instance => |class_def| {
                const instance = try self.allocator.create(value_mod.ClassInstance);
                instance.* = value_mod.ClassInstance{
                    .class_name = try self.allocator.dupe(u8, class_def.name),
                    .fields = std.StringHashMap(value_mod.Value).init(self.allocator),
                    .methods = std.StringHashMap(*value_mod.Function).init(self.allocator),
                    .allocator = self.allocator,
                };

                var piter = class_def.public_fields.iterator();
                while (piter.next()) |entry| {
                    const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                    try instance.fields.put(key_copy, entry.value_ptr.*);
                }
                var miter = class_def.public_methods.iterator();
                while (miter.next()) |entry| {
                    const method_copy = entry.value_ptr.*;
                    const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                    try instance.methods.put(key_copy, method_copy);
                }

                return value_mod.Value{ .class_instance = instance };
            },
            else => {
                self.raiseError("CallError", "Cannot call non-function");
                return error.RuntimeError;
            },
        }
    }

    fn evaluateMemberAccess(self: *VM, ma: *ast.MemberAccess) !value_mod.Value {
        const obj = try self.evaluateExpression(ma.object);
        switch (obj) {
            .class_instance => |ci| {
                if (ci.fields.get(ma.member)) |val| {
                    return val;
                }
                if (ci.methods.get(ma.member)) |func| {
                    return value_mod.Value{ .function = func };
                }
                self.raiseError("MemberError", "Member not found");
                return error.RuntimeError;
            },
            .dict => |d| {
                if (d.get(ma.member)) |val| {
                    return val;
                }
                self.raiseError("KeyError", "Key not found");
                return error.RuntimeError;
            },
            else => {
                self.raiseError("TypeError", "Cannot access member of this type");
                return error.RuntimeError;
            },
        }
    }

    fn evaluateIndexAccess(self: *VM, ia: *ast.IndexAccess) !value_mod.Value {
        const obj = try self.evaluateExpression(ia.object);
        const idx = try self.evaluateExpression(ia.index);

        switch (obj) {
            .tuple, .list => |arr| {
                if (idx == .int) {
                    const i = idx.int;
                    const idx_usize: usize = @intCast(i);
                    if (idx_usize < arr.len) {
                        return arr[idx_usize];
                    }
                    self.raiseError("IndexError", "Index out of bounds");
                    return error.RuntimeError;
                }
                self.raiseError("TypeError", "Index must be integer");
                return error.RuntimeError;
            },
            .dict => |d| {
                if (idx == .string) {
                    const key = idx.string;
                    if (d.get(key)) |val| {
                        return val;
                    }
                    self.raiseError("KeyError", "Key not found");
                    return error.RuntimeError;
                }
                self.raiseError("TypeError", "Dict key must be string");
                return error.RuntimeError;
            },
            .string => |s| {
                if (idx == .int) {
                    const i = idx.int;
                    const idx_usize: usize = @intCast(i);
                    if (idx_usize < s.len) {
                        const ch = s[idx_usize..idx_usize + 1];
                        return value_mod.Value{ .string = ch };
                    }
                    self.raiseError("IndexError", "Index out of bounds");
                    return error.RuntimeError;
                }
                self.raiseError("TypeError", "Index must be integer");
                return error.RuntimeError;
            },
            else => {
                self.raiseError("TypeError", "Cannot index this type");
                return error.RuntimeError;
            },
        }
    }

    fn evaluateSystemTag(self: *VM, st: *ast.SystemTagExpr) !value_mod.Value {
        if (st.args.len > 0) {
            const arg = try self.evaluateExpression(&st.args[0]);
            if (std.mem.eql(u8, st.tag, "printf")) {
                if (arg == .string) {
                    var out = std.ArrayList(u8).init(self.allocator);
                    var i: usize = 0;
                    while (i < arg.string.len) {
                        if (arg.string[i] == '\\' and i + 1 < arg.string.len and arg.string[i + 1] == 'n') {
                            try out.append('\n');
                            i += 2;
                        } else {
                            try out.append(arg.string[i]);
                            i += 1;
                        }
                    }
                    try self.stdout.print("{s}", .{out.items});
                    out.deinit();
                } else {
                    try self.stdout.print("{any}\n", .{arg});
                }
                return value_mod.Value{ .null = {} };
            }
            if (std.mem.eql(u8, st.tag, "len")) {
                return switch (arg) {
                    .string => |s| value_mod.Value{ .int = @intCast(s.len) },
                    .tuple, .list => |v| value_mod.Value{ .int = @intCast(v.len) },
                    .bytes => |b| value_mod.Value{ .int = @intCast(b.len) },
                    .dict => |d| value_mod.Value{ .int = @intCast(d.count()) },
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
            if (ie.target_name.len > 0) {
                const name_copy = self.allocator.dupe(u8, ie.target_name) catch unreachable;
                try self.current_scope.variables.put(name_copy, value_mod.Value{ .string = str });
            }
            if (ie.target) |target_expr| {
                const target_val = try self.evaluateExpression(target_expr);
                try self.assignValue(target_expr, value_mod.Value{ .string = str });
            }
            return value_mod.Value{ .string = str };
        }
        return value_mod.Value{ .string = "" };
    }

    fn evaluateNow(self: *VM, ne: *ast.NowExpr) !value_mod.Value {
        const val = try self.evaluateExpression(ne.expr);
        try self.assignValue(ne.expr, val);
        return val;
    }
};
