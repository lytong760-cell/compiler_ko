const std = @import("std");
const ast = @import("ast.zig");
const value_mod = @import("value.zig");
const bytecode = @import("bytecode.zig");

const EndOfInput = error.EndOfInput;

pub const VM = struct {
    allocator: std.mem.Allocator,
    global_scope: *value_mod.Scope,
    current_scope: *value_mod.Scope,
    io: std.Io,
    stdout_buf: [4096]u8,
    stdout_writer: ?std.Io.File.Writer,
    output_writer: ?*std.Io.Writer,
    return_value: ?value_mod.Value,
    has_returned: bool,
    error_type: ?[]const u8,
    has_error: bool,
    skip_elif_else: bool,
    file_path: []const u8,
    current_function: []const u8,
    stdin_buf: [4096]u8,
    stdin_file_reader: ?std.Io.File.Reader,
    stdin_reader: ?std.Io.Reader,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8) !VM {
        const global_scope = try allocator.create(value_mod.Scope);
        global_scope.* = value_mod.Scope.init(allocator, null);
        const duped = try allocator.dupe(u8, file_path);
        return .{
            .allocator = allocator,
            .global_scope = global_scope,
            .current_scope = global_scope,
            .io = io,
            .stdout_buf = undefined,
            .stdout_writer = null,
            .output_writer = null,
            .return_value = null,
            .has_returned = false,
            .error_type = null,
            .has_error = false,
            .skip_elif_else = false,
            .file_path = duped,
            .current_function = "main",
            .stdin_buf = undefined,
            .stdin_file_reader = null,
            .stdin_reader = null,
        };
    }

    /// Replace the source `<input>` reads from. Tests use this to stay hermetic;
    /// the default remains the real process stdin.
    pub fn setInputBuffer(self: *VM, buffer: []const u8) void {
        self.stdin_reader = std.Io.Reader.fixed(buffer);
    }

    /// Redirect everything the VM writes. Under `zig build test` the real stdout is
    /// the test-runner protocol channel, so program output must not go there.
    pub fn setOutputWriter(self: *VM, writer: *std.Io.Writer) void {
        self.output_writer = writer;
    }

    fn stdinReader(self: *VM) !*std.Io.Reader {
        if (self.stdin_reader) |*reader| return reader;
        if (self.stdin_file_reader == null) {
            self.stdin_file_reader = std.Io.File.stdin().reader(self.io, &self.stdin_buf);
        }
        return &self.stdin_file_reader.?.interface;
    }

fn readInputLine(self: *VM) ![]const u8 {
    const reader = try self.stdinReader();
    const result = try reader.takeDelimiterInclusive('\n');
    return result[0 .. result.len - 1];
}

const InputError = error{ EndOfInput };

    fn stdoutWriter(self: *VM) *std.Io.Writer {
        if (self.output_writer) |writer| return writer;
        if (self.stdout_writer == null) {
            self.stdout_writer = std.Io.File.stdout().writer(self.io, &self.stdout_buf);
        }
        return &self.stdout_writer.?.interface;
    }

    fn appendValueToString(self: *VM, out: *std.array_list.Managed(u8), val: value_mod.Value) !void {
        var aw: std.Io.Writer.Allocating = .init(self.allocator);
        errdefer aw.deinit();
        try val.print(&aw.writer);
        const text = try aw.toOwnedSlice();
        try out.appendSlice(text);
        self.allocator.free(text);
    }

    pub fn deinit(self: *VM) void {
        self.allocator.free(self.file_path);
        var fiter = self.global_scope.functions.iterator();
        while (fiter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.global_scope.functions.deinit();

        var citer = self.global_scope.classes.iterator();
        while (citer.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.global_scope.classes.deinit();

        var viter = self.global_scope.variables.iterator();
        while (viter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.global_scope.variables.deinit();

        self.allocator.destroy(self.global_scope);
    }

    fn getProcessName(self: *VM) []const u8 {
        if (std.mem.eql(u8, self.current_function, "main")) {
            return std.fmt.allocPrint(self.allocator, "{s}:main", .{self.file_path}) catch self.file_path;
        }
        return std.fmt.allocPrint(self.allocator, "{s}:main-{s}", .{ self.file_path, self.current_function }) catch self.file_path;
    }

    fn exposeProcess(self: *VM) void {
        const name = self.getProcessName();
        const writer = self.stdoutWriter();
        writer.print("{s}\n", .{name}) catch {};
        writer.flush() catch {};
        if (!std.mem.eql(u8, name, self.file_path)) {
            self.allocator.free(name);
        }
    }

    pub fn execute(self: *VM, program: []ast.Statement) anyerror!void {
        self.current_function = "main";
        self.exposeProcess();
        for (program, 0..) |*stmt, idx| {
            if (self.has_returned) break;
            if (self.has_error) {
                self.dispatchCatchBlocks(program, idx) catch {};
                continue;
            }
            self.executeStatement(stmt) catch |err| {
                self.raiseError(VM.zigErrorToKoType(err), @errorName(err));
            };
        }
        if (self.has_error) {
            return error.RuntimeError;
        }
    }

    fn dispatchCatchBlocks(self: *VM, program: []ast.Statement, current_idx: usize) !void {
        var i: usize = 0;
        while (i < program.len) {
            if (i == current_idx) break;
            i += 1;
        }
        i += 1;
        while (i < program.len) {
            const stmt = &program[i];
            if (stmt.* == .catch_stmt) {
                try self.executeStatement(stmt);
                if (!self.has_error) break;
            }
            i += 1;
        }
    }

    fn executeStatement(self: *VM, stmt: *const ast.Statement) anyerror!void {
        if (self.has_returned or self.has_error) return;

        switch (stmt.*) {
            .var_decl => |*v| {
                var val = try self.evaluateExpression(v.value_expr);
                const final_val = if (std.mem.eql(u8, v.type_name, "bytes")) blk: {
                    defer val.deinit(self.allocator);
                    const size: usize = switch (val) {
                        .int => |i| blk2: {
                            if (i < 0) {
                                self.raiseError("TypeError", "Cannot cast negative value to bytes");
                                break :blk2 0;
                            }
                            break :blk2 @intCast(i);
                        },
                        else => 0,
                    };
                    const bytes_val = try self.allocator.alloc(u8, size);
                    @memset(bytes_val, 0);
                    break :blk value_mod.Value{ .bytes = bytes_val };
                } else val;
                if (self.current_scope.variables.get(v.name)) |_| {
                    const gop = try self.current_scope.variables.getOrPut(v.name);
                    gop.value_ptr.*.deinit(self.allocator);
                    gop.value_ptr.* = final_val;
                } else if (self.global_scope.variables.get(v.name)) |_| {
                    const gop = try self.global_scope.variables.getOrPut(v.name);
                    gop.value_ptr.*.deinit(self.allocator);
                    gop.value_ptr.* = final_val;
                } else {
                    const name_copy = try self.allocator.dupe(u8, v.name);
                    try self.current_scope.variables.put(name_copy, final_val);
                }
            },
            .assignment => |*a| {
                const val = try self.evaluateExpression(a.value_expr);
                try self.assignValue(a.target, val);
            },
            .func_decl => |f| {
                const func = try self.allocator.create(value_mod.Function);
                const name_copy = try self.allocator.dupe(u8, f.name);
                const params_copy = try self.allocator.dupe(value_mod.Param, f.params);
                const body_copy = try self.allocator.dupe(ast.Statement, f.body);
                const catch_stmts_copy = try self.allocator.dupe(ast.CatchStmt, f.catch_stmts);
                func.* = value_mod.Function{
                    .name = name_copy,
                    .params = params_copy,
                    .body_ptr = body_copy.ptr,
                    .body_len = body_copy.len,
                    .catch_stmts = catch_stmts_copy,
                    .closure_scope = self.current_scope,
                    .allocator = self.allocator,
                };
                try self.current_scope.functions.put(name_copy, func);
            },
            .class_instantiation => |ci| {
                var class_def: ?*value_mod.ClassDef = null;
                if (self.current_scope.classes.get(ci.class_name)) |cd| {
                    class_def = cd;
                } else if (self.global_scope.classes.get(ci.class_name)) |cd| {
                    class_def = cd;
                }

                if (class_def) |cd| {
                    const instance = try self.allocator.create(value_mod.ClassInstance);
                    instance.* = value_mod.ClassInstance{
                        .class_name = try self.allocator.dupe(u8, cd.name),
                        .fields = std.StringHashMap(value_mod.Value).init(self.allocator),
                        .methods = std.StringHashMap(*value_mod.Function).init(self.allocator),
                        .allocator = self.allocator,
                    };

                    var piter = cd.public_fields.iterator();
                    while (piter.next()) |entry| {
                        const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                        const cloned_val = try entry.value_ptr.*.clone(self.allocator);
                        try instance.fields.put(key_copy, cloned_val);
                    }
                    var miter = cd.public_methods.iterator();
                    while (miter.next()) |entry| {
                        const method_copy = entry.value_ptr.*;
                        const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                        try instance.methods.put(key_copy, method_copy);
                    }

                    const name_copy = try self.allocator.dupe(u8, ci.instance_name);
                    try self.current_scope.variables.put(name_copy, value_mod.Value{ .class_instance = instance });
                } else {
                    self.raiseError("ClassError", "Class not found");
                    _ = ci.class_name;
                }
            },
            .class_decl => |c| {
                const class_def = try self.allocator.create(value_mod.ClassDef);
                var private_scope = try self.allocator.create(value_mod.Scope);
                private_scope.* = value_mod.Scope.init(self.allocator, self.current_scope);
                var public_scope = try self.allocator.create(value_mod.Scope);
                public_scope.* = value_mod.Scope.init(self.allocator, self.current_scope);
                class_def.* = value_mod.ClassDef{
                    .name = c.name,
                    .private_fields = std.StringHashMap(value_mod.Value).init(self.allocator),
                    .private_methods = std.StringHashMap(*value_mod.Function).init(self.allocator),
                    .public_fields = std.StringHashMap(value_mod.Value).init(self.allocator),
                    .public_methods = std.StringHashMap(*value_mod.Function).init(self.allocator),
                    .allocator = self.allocator,
                    .private_scope = private_scope,
                    .public_scope = public_scope,
                };
                const name_copy = try self.allocator.dupe(u8, c.name);
                try self.current_scope.classes.put(name_copy, class_def);

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
                {
                    var free_iter = private_scope.variables.iterator();
                    while (free_iter.next()) |entry| {
                        self.allocator.free(entry.key_ptr.*);
                    }
                }
                private_scope.variables.clearRetainingCapacity();
                {
                    var free_iter = private_scope.functions.iterator();
                    while (free_iter.next()) |entry| {
                        self.allocator.free(entry.key_ptr.*);
                    }
                }
                private_scope.functions.clearRetainingCapacity();
                private_scope.classes.clearRetainingCapacity();

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
                {
                    var free_iter = public_scope.variables.iterator();
                    while (free_iter.next()) |entry| {
                        self.allocator.free(entry.key_ptr.*);
                    }
                }
                public_scope.variables.clearRetainingCapacity();
                {
                    var free_iter = public_scope.functions.iterator();
                    while (free_iter.next()) |entry| {
                        self.allocator.free(entry.key_ptr.*);
                    }
                }
                public_scope.functions.clearRetainingCapacity();
                public_scope.classes.clearRetainingCapacity();
            },
            .control_flow => |cf| {
                switch (cf.kind) {
                    .if_stmt => {
                        if (self.skip_elif_else) {
                            self.skip_elif_else = false;
                            return;
                        }
                        const cond = try self.evaluateExpression(cf.condition.?);
                        if (try cond.toBool()) {
                            for (cf.body) |s| try self.executeStatement(&s);
                            self.skip_elif_else = true;
                        } else {
                            self.skip_elif_else = false;
                        }
                    },
                    .elif_stmt => {
                        if (self.skip_elif_else) {
                            self.skip_elif_else = false;
                            return;
                        }
                        const cond = try self.evaluateExpression(cf.condition.?);
                        if (try cond.toBool()) {
                            for (cf.body) |s| try self.executeStatement(&s);
                            self.skip_elif_else = true;
                        } else {
                            self.skip_elif_else = false;
                        }
                    },
                    .else_stmt => {
                        if (self.skip_elif_else) {
                            self.skip_elif_else = false;
                            return;
                        }
                        for (cf.body) |s| try self.executeStatement(&s);
                        self.skip_elif_else = true;
                    },
                    .for_loop => {
                        if (cf.init) |init_assign| {
                            const val = try self.evaluateExpression(init_assign.value_expr);
                            try self.assignValue(init_assign.target, val);
                        }
                        var cond_val = try self.evaluateExpression(cf.condition.?);
                        while (try cond_val.toBool() and !self.has_returned and !self.has_error) {
                            for (cf.body) |s| try self.executeStatement(&s);
                            if (self.has_returned or self.has_error) break;
                            if (cf.step) |step_expr| {
                                const step_val = try self.evaluateExpression(step_expr);
                                const current_val = self.current_scope.variables.get(cf.loop_var) orelse cond_val;
                                const new_val = try current_val.add(step_val, self.allocator);
                                const target = try self.allocator.create(ast.Expr);
                                target.* = .{ .identifier = cf.loop_var };
                                try self.assignValue(target, new_val);
                                self.allocator.destroy(target);
                            } else {
                                const one = value_mod.Value{ .int = 1 };
                                const current_val = self.current_scope.variables.get(cf.loop_var) orelse cond_val;
                                const new_val = try current_val.add(one, self.allocator);
                                const target = try self.allocator.create(ast.Expr);
                                target.* = .{ .identifier = cf.loop_var };
                                try self.assignValue(target, new_val);
                                self.allocator.destroy(target);
                            }
                            cond_val = try self.evaluateExpression(cf.condition.?);
                        }
                    },
                    .while_loop => {
                        var cond_val = try self.evaluateExpression(cf.condition.?);
                        while (try cond_val.toBool() and !self.has_returned and !self.has_error) {
                            for (cf.body) |s| try self.executeStatement(&s);
                            if (self.has_returned or self.has_error) break;
                            cond_val = try self.evaluateExpression(cf.condition.?);
                        }
                    },
                }
            },
            .memory_op => |m| {
                switch (m.kind) {
                    .address => {
                        const val = try self.evaluateExpression(m.expr);
                        @constCast(&val).deinit(self.allocator);
                    },
                    .dete => {
                        var val = try self.evaluateExpression(m.expr);
                        val.deinit(self.allocator);
                    },
                }
            },
            .encoding_op => |eo| {
                const val = try self.evaluateExpression(eo.expr);
                @constCast(&val).deinit(self.allocator);
                _ = eo.encoding_type;
            },
            .len_op => |lo| {
                const val = try self.evaluateExpression(lo.expr);
                @constCast(&val).deinit(self.allocator);
            },
            .return_stmt => |rs| {
                const val = try self.evaluateExpression(rs.expr);
                self.return_value = val;
                self.has_returned = true;
            },
            .block => |b| {
                try self.executeBlock(b.body);
            },
            .expr => |e| {
                const val = try self.evaluateExpression(e);
                @constCast(&val).deinit(self.allocator);
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
            .priority_stmt => |ps| {
                try self.executeStatement(ps.stmt);
            },
        }
    }

    fn executeBlock(self: *VM, body: []ast.Statement) !void {
        for (body) |s| try self.executeStatement(&s);
    }

    fn executeStatementInScope(self: *VM, stmt: *const ast.Statement, scope: *value_mod.Scope) anyerror!void {
        const prev_scope = self.current_scope;
        self.current_scope = scope;
        defer self.current_scope = prev_scope;
        try self.executeStatement(stmt);
    }

fn assignValue(self: *VM, target: *ast.Expr, val: value_mod.Value) !void {
    switch (target.*) {
        .identifier => |name| {
            if (self.current_scope.variables.get(name)) |_| {
                const gop = try self.current_scope.variables.getOrPut(name);
                gop.value_ptr.*.deinit(self.allocator);
                gop.value_ptr.* = val;
            } else if (self.global_scope.variables.get(name)) |_| {
                const gop = try self.global_scope.variables.getOrPut(name);
                gop.value_ptr.*.deinit(self.allocator);
                gop.value_ptr.* = val;
            } else {
                const name_copy = try self.allocator.dupe(u8, name);
                try self.current_scope.variables.put(name_copy, val);
            }
        },
            .member_access => |ma| {
                switch (ma.object.*) {
                    .identifier => |name| {
                        var scope: ?*value_mod.Scope = self.current_scope;
                        while (scope) |s| {
                            if (s.variables.get(name)) |_| {
                                const gop = try s.variables.getOrPut(name);
                                if (gop.value_ptr.* != .class_instance) {
                                    self.raiseError("AssignmentError", "Not a class instance");
                                    return;
                                }
                                const instance = gop.value_ptr.*.class_instance;
                                if (instance.fields.get(ma.member)) |_| {
                                    const fgop = try instance.fields.getOrPut(ma.member);
                                    fgop.value_ptr.*.deinit(self.allocator);
                                    fgop.value_ptr.* = val;
                                } else if (instance.methods.get(ma.member)) |_| {
                                    self.raiseError("AssignmentError", "Cannot assign to method");
                                } else {
                                    self.raiseError("AssignmentError", "Member not found");
                                }
                                return;
                            }
                            scope = s.parent;
                        }
                        if (self.global_scope.variables.get(name)) |_| {
                            const gop = try self.global_scope.variables.getOrPut(name);
                            if (gop.value_ptr.* != .class_instance) {
                                self.raiseError("AssignmentError", "Not a class instance");
                                return;
                            }
                            const instance = gop.value_ptr.*.class_instance;
                            if (instance.fields.get(ma.member)) |_| {
                                const fgop = try instance.fields.getOrPut(ma.member);
                                fgop.value_ptr.*.deinit(self.allocator);
                                fgop.value_ptr.* = val;
                            } else if (instance.methods.get(ma.member)) |_| {
                                self.raiseError("AssignmentError", "Cannot assign to method");
                            } else {
                                self.raiseError("AssignmentError", "Member not found");
                            }
                            return;
                        }
                        self.raiseError("AssignmentError", "Variable not found");
                    },
                    else => {
                        const obj = try self.evaluateExpression(ma.object);
                        switch (obj) {
                            .class_instance => |ci| {
                                if (ci.fields.get(ma.member)) |_| {
                                    const gop = try ci.fields.getOrPut(ma.member);
                                    gop.value_ptr.*.deinit(self.allocator);
                                    gop.value_ptr.* = val;
                                } else if (ci.methods.get(ma.member)) |_| {
                                    self.raiseError("AssignmentError", "Cannot assign to method");
                                } else {
                                    self.raiseError("AssignmentError", "Member not found");
                                }
                            },
                            else => self.raiseError("AssignmentError", "Not a class instance"),
                        }
                    },
                }
            },
            .index_access => |ia| {
                const obj = try self.evaluateExpression(ia.object);
                const idx = try self.evaluateExpression(ia.index);
                switch (obj) {
                    .tuple, .list => |arr| {
                        if (idx == .int) {
                            const i = idx.int;
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
                                const key_copy = try self.allocator.dupe(u8, key);
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

fn zigErrorToKoType(err: anyerror) []const u8 {
    return switch (err) {
        error.DivideByZero => "DivideByZeroError",
        error.OverflowError => "OverflowError",
        error.TypeError => "TypeError",
        error.UndefinedVariable => "NameError",
        InputError.EndOfInput => "InputError",
        else => "RuntimeError",
    };
}

    fn raiseError(self: *VM, err_type: []const u8, message: []const u8) void {
        self.has_error = true;
        self.error_type = err_type;
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

    fn unescape(self: *VM, raw: []const u8) ![]u8 {
        var result = std.array_list.Managed(u8).init(self.allocator);
        var i: usize = 0;
        while (i < raw.len) {
            if (raw[i] == '\\' and i + 1 < raw.len) {
                const next = raw[i + 1];
                switch (next) {
                    'n' => try result.append('\n'),
                    't' => try result.append('\t'),
                    'r' => try result.append('\r'),
                    '\\' => try result.append('\\'),
                    '"' => try result.append('"'),
                    '\'' => try result.append('\''),
                    '0' => try result.append('\x00'),
                    else => {
                        // For unknown escapes, keep the backslash and the character
                        try result.append('\\');
                        try result.append(next);
                    },
                }
                i += 2;
            } else {
                try result.append(raw[i]);
                i += 1;
            }
        }
        return result.toOwnedSlice();
    }

    fn evaluateLiteral(self: *VM, lit: ast.Literal) !value_mod.Value {
        return switch (lit.kind) {
            .int => value_mod.Value{ .int = lit.int_value },
            .freal => value_mod.Value{ .freal = lit.freal_value },
            .string => blk: {
                const unescaped = try self.unescape(lit.raw);
                break :blk value_mod.Value{ .string = unescaped };
            },
            .bool_true => value_mod.Value{ .booling = true },
            .bool_false => value_mod.Value{ .booling = false },
            .tuple => value_mod.Value{ .tuple = &[_]value_mod.Value{} },
            .dict => blk: {
                const d = try self.allocator.create(std.StringHashMap(value_mod.Value));
                d.* = std.StringHashMap(value_mod.Value).init(self.allocator);
                break :blk value_mod.Value{ .dict = d };
            },
        };
    }

    fn evaluateIdentifier(self: *VM, name: []const u8) !value_mod.Value {
        var scope: ?*value_mod.Scope = self.current_scope;
        while (scope) |s| {
            if (s.variables.get(name)) |val| {
                return try val.clone(self.allocator);
            }
            if (s.functions.get(name)) |func| {
                return value_mod.Value{ .function = func };
            }
            scope = s.parent;
        }
        if (self.global_scope.variables.get(name)) |val| {
            return try val.clone(self.allocator);
        }
        if (self.global_scope.functions.get(name)) |func| {
            return value_mod.Value{ .function = func };
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

    fn printInterpolated(self: *VM, s: []const u8) !void {
        var out = std.array_list.Managed(u8).init(self.allocator);
        defer out.deinit();

        var i: usize = 0;
        while (i < s.len) {
            if (s[i] == '\\' and i + 1 < s.len and s[i + 1] == 'n') {
                try out.append('\n');
                i += 2;
            } else if (s[i] == '{') {
                if (i + 1 < s.len) {
                    var j = i + 1;
                    while (j < s.len and s[j] != '}') : (j += 1) {}
                    if (j < s.len and s[j] == '}') {
                        const var_name = s[i + 1 .. j];
                        if (self.current_scope.variables.get(var_name)) |var_val| {
                            try self.appendValueToString(&out, var_val);
                        } else if (self.global_scope.variables.get(var_name)) |var_val| {
                            try self.appendValueToString(&out, var_val);
                        } else {
                            try out.appendSlice("{");
                            try out.appendSlice(var_name);
                            try out.append('}');
                        }
                        i = j + 1;
                        continue;
                    }
                }
                try out.append(s[i]);
                i += 1;
            } else {
                try out.append(s[i]);
                i += 1;
            }
        }
        const writer = self.stdoutWriter();
        try writer.print("{s}", .{out.items});
        try writer.flush();
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
            const writer = self.stdoutWriter();
            try writer.print("Warning: Import subsystem is not yet integrated. Skipping import.\n", .{});
            try writer.flush();
            return value_mod.Value{ .null = {} };
        }
        if (std.mem.eql(u8, call.callee, "printf")) {
            for (call.args) |arg| {
                var val = try self.evaluateExpression(@constCast(&arg));
                if (val == .string) {
                    try self.printInterpolated(val.string);
                } else {
                    const writer = self.stdoutWriter();
                    try val.print(writer);
                    try writer.print("\n", .{});
                    try writer.flush();
                }
                val.deinit(self.allocator);
            }
            return value_mod.Value{ .null = {} };
        }

        const callee_val = if (call.target) |target_expr| try self.evaluateExpression(target_expr) else try self.evaluateIdentifier(call.callee);
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
                    const param_name = try self.allocator.dupe(u8, param.name);
                    try new_scope.variables.put(param_name, arg_val);
                }

                const prev_scope = self.current_scope;
                const prev_has_returned = self.has_returned;
                const prev_return_value = self.return_value;
                const prev_has_error = self.has_error;
                const prev_error_type = self.error_type;
                const prev_function = self.current_function;
                self.current_scope = new_scope;
                self.current_function = func.name;
                self.exposeProcess();
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

                if (self.has_error) {
                    for (func.catch_stmts) |*cs| {
                        if (self.error_type) |err_type| {
                            if (std.mem.eql(u8, err_type, cs.error_type)) {
                                self.has_error = false;
                                self.error_type = null;
                                for (cs.body) |s| try self.executeStatement(&s);
                                break;
                            }
                        }
                    }
                }

                const ret = self.return_value orelse value_mod.Value{ .null = {} };

                new_scope.deinit();
                self.allocator.destroy(new_scope);
                self.current_scope = prev_scope;
                self.current_function = prev_function;
                self.has_returned = prev_has_returned;
                self.return_value = prev_return_value;
                self.has_error = prev_has_error;
                self.error_type = prev_error_type;

                return ret;
            },
            else => {
                var class_def: ?*value_mod.ClassDef = null;
                if (self.current_scope.classes.get(call.callee)) |cd| {
                    class_def = cd;
                } else if (self.global_scope.classes.get(call.callee)) |cd| {
                    class_def = cd;
                }

                if (class_def) |cd| {
                    const instance = try self.allocator.create(value_mod.ClassInstance);
                    instance.* = value_mod.ClassInstance{
                        .class_name = try self.allocator.dupe(u8, cd.name),
                        .fields = std.StringHashMap(value_mod.Value).init(self.allocator),
                        .methods = std.StringHashMap(*value_mod.Function).init(self.allocator),
                        .allocator = self.allocator,
                    };

                    var piter = cd.public_fields.iterator();
                    while (piter.next()) |entry| {
                        const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                        const cloned_val = try entry.value_ptr.*.clone(self.allocator);
                        try instance.fields.put(key_copy, cloned_val);
                    }
                    var miter = cd.public_methods.iterator();
                    while (miter.next()) |entry| {
                        const method_copy = entry.value_ptr.*;
                        const key_copy = try self.allocator.dupe(u8, entry.key_ptr.*);
                        try instance.methods.put(key_copy, method_copy);
                    }

                    return value_mod.Value{ .class_instance = instance };
                }

                self.raiseError("CallError", "Cannot call non-function");
                return error.RuntimeError;
            },
        }
    }

    fn evaluateMemberAccess(self: *VM, ma: *ast.MemberAccess) !value_mod.Value {
        const owned = ma.object.* == .identifier;
        const obj = try self.evaluateExpression(ma.object);
        switch (obj) {
            .class_instance => |ci| {
                if (ci.fields.get(ma.member)) |val| {
                    const cloned = try val.clone(self.allocator);
                    if (owned) @constCast(&obj).deinit(self.allocator);
                    return cloned;
                }
                if (ci.methods.get(ma.member)) |func| {
                    if (owned) @constCast(&obj).deinit(self.allocator);
                    return value_mod.Value{ .function = func };
                }
                if (owned) @constCast(&obj).deinit(self.allocator);
                self.raiseError("MemberError", "Member not found");
                return error.RuntimeError;
            },
            .dict => |d| {
                if (d.get(ma.member)) |val| {
                    const cloned = try val.clone(self.allocator);
                    if (owned) @constCast(&obj).deinit(self.allocator);
                    return cloned;
                }
                if (owned) @constCast(&obj).deinit(self.allocator);
                self.raiseError("KeyError", "Key not found");
                return error.RuntimeError;
            },
            else => {
                if (owned) @constCast(&obj).deinit(self.allocator);
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
                        return try arr[idx_usize].clone(self.allocator);
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
                        return try val.clone(self.allocator);
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
                        const ch = try self.allocator.dupe(u8, s[idx_usize..idx_usize + 1]);
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
                    try self.printInterpolated(arg.string);
                } else {
                    const writer = self.stdoutWriter();
                    try arg.print(writer);
                    try writer.print("\n", .{});
                    try writer.flush();
                }
                @constCast(&arg).deinit(self.allocator);
                return value_mod.Value{ .null = {} };
            }
            if (std.mem.eql(u8, st.tag, "len")) {
                const result = switch (arg) {
                    .string => |s| value_mod.Value{ .int = @intCast(s.len) },
                    .tuple, .list => |v| value_mod.Value{ .int = @intCast(v.len) },
                    .bytes => |b| value_mod.Value{ .int = @intCast(b.len) },
                    .dict => |d| value_mod.Value{ .int = @intCast(d.count()) },
                    else => value_mod.Value{ .int = 0 },
                };
                @constCast(&arg).deinit(self.allocator);
                return result;
            }
            if (std.mem.eql(u8, st.tag, "memory")) {
                @constCast(&arg).deinit(self.allocator);
                return value_mod.Value{ .int = 0 };
            }
            if (std.mem.eql(u8, st.tag, "encode")) {
                if (arg == .string) {
                    const bytes = try self.allocator.dupe(u8, arg.string);
                    @constCast(&arg).deinit(self.allocator);
                    return value_mod.Value{ .bytes = bytes };
                }
                @constCast(&arg).deinit(self.allocator);
                return value_mod.Value{ .bytes = &[_]u8{} };
            }
        }
        return value_mod.Value{ .null = {} };
    }

fn evaluateInput(self: *VM, ie: *ast.InputExpr) !value_mod.Value {
    const line = self.readInputLine() catch |err| switch (err) {
        error.EndOfStream => return error.EndOfInput,
        else => |e| return e,
    };
    if (ie.target_name.len > 0) {
        const name_copy = try self.allocator.dupe(u8, ie.target_name);
        const owned = try self.allocator.dupe(u8, line);
        try self.current_scope.variables.put(name_copy, value_mod.Value{ .string = owned });
    }
    if (ie.target) |target_expr| {
        const owned = try self.allocator.dupe(u8, line);
        try self.assignValue(target_expr, value_mod.Value{ .string = owned });
    }
    return value_mod.Value{ .string = try self.allocator.dupe(u8, line) };
}

    fn evaluateNow(self: *VM, ne: *ast.NowExpr) !value_mod.Value {
        const val = try self.evaluateExpression(ne.expr);
        errdefer @constCast(&val).deinit(self.allocator);
        try self.assignValue(ne.target, val);
        return val;
    }

    pub fn executeChunk(self: *VM, chunk: *bytecode.Chunk) !void {
        self.exposeProcess();
        if (chunk.functions.items.len == 0) return;
        const main_fn = &chunk.functions.items[0];
        try self.runFunction(main_fn, chunk);
    }

    fn runFunction(self: *VM, func: *bytecode.Function, chunk: *bytecode.Chunk) !void {
        var stack: [1024]value_mod.Value = undefined;
        var sp: usize = 0;
        var ip: usize = 0;

        while (ip < func.instructions.items.len) {
            const inst = func.instructions.items[ip];
            ip += 1;

            switch (inst) {
                .load_const => |idx| {
                    const val = chunk.constants.items[idx];
                    stack[sp] = val;
                    sp += 1;
                },
                .load_var => |idx| {
                    const name = chunk.constants.items[idx].string;
                    const val = self.current_scope.variables.get(name) orelse value_mod.Value{ .null = {} };
                    stack[sp] = val;
                    sp += 1;
                },
                .store_var => |idx| {
                    const name = chunk.constants.items[idx].string;
                    const val = stack[sp - 1];
                    const owned = try self.allocator.dupe(u8, name);
                    try self.current_scope.variables.put(owned, val);
                },
                .binary => |op| {
                    const rhs = stack[sp - 1];
                    const lhs = stack[sp - 2];
                    sp -= 2;
                    const result = try self.binaryOp(op, lhs, rhs);
                    stack[sp] = result;
                    sp += 1;
                },
                .unary => |op| {
                    const val = stack[sp - 1];
                    sp -= 1;
                    const result = try self.evaluateUnaryOp(op, val);
                    stack[sp] = result;
                    sp += 1;
                },
                .call => |arity| {
                    const name_idx = @as(usize, @intCast(arity >> 16));
                    const arg_count = @as(usize, @intCast(arity & 0xFFFF));
                    const callee_name = chunk.constants.items[name_idx].string;
                    const args = stack[sp - arg_count .. sp];
                    const result = try self.callBuiltin(callee_name, args);
                    sp -= arg_count;
                    stack[sp] = result;
                    sp += 1;
                },
                .ret => {
                    return;
                },
                .print => {
                    const val = stack[sp - 1];
                    sp -= 1;
                    try val.print(self.stdoutWriter());
                    try self.stdoutWriter().print("\n", .{});
                    try self.stdoutWriter().flush();
                },
                .input => {
                    const line = try self.readInputLine();
                    const str = try self.allocator.dupe(u8, line);
                    stack[sp] = value_mod.Value{ .string = str };
                    sp += 1;
                },
                .now => {
                    const ts = std.Io.Clock.now(.real, self.io);
                    stack[sp] = value_mod.Value{ .int = @intCast(ts.nanoseconds) };
                    sp += 1;
                },
                .len => {
                    const val = stack[sp - 1];
                    sp -= 1;
                    const len: i64 = switch (val) {
                        .string => |s| @intCast(s.len),
                        .tuple => |t| @intCast(t.len),
                        .list => |l| @intCast(l.len),
                        .dict => |d| @intCast(d.count()),
                        else => 0,
                    };
                    stack[sp] = value_mod.Value{ .int = len };
                    sp += 1;
                },
                .memory => {
                    stack[sp] = value_mod.Value{ .string = try self.allocator.dupe(u8, "0x7fff") };
                    sp += 1;
                },
                .encode => {
                    const val = stack[sp - 1];
                    sp -= 1;
                    var aw: std.Io.Writer.Allocating = .init(self.allocator);
                    errdefer aw.deinit();
                    try val.print(&aw.writer);
                    const text = try aw.toOwnedSlice();
                    stack[sp] = value_mod.Value{ .string = text };
                    sp += 1;
                },
                .catch_start => {},
                .catch_end => {},
                .import => {
                    stack[sp] = value_mod.Value{ .null = {} };
                    sp += 1;
                },
                .jump => |offset| {
                    ip = @intCast(@as(isize, @intCast(ip)) + offset);
                },
                .jump_if_false => |offset| {
                    const val = stack[sp - 1];
                    sp -= 1;
                    if (!try val.toBool()) {
                        ip = @intCast(@as(isize, @intCast(ip)) + offset);
                    }
                },
            }
        }
    }

    fn binaryOp(self: *VM, op: u8, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        return switch (op) {
            0 => self.addValues(lhs, rhs),
            1 => self.subValues(lhs, rhs),
            2 => self.mulValues(lhs, rhs),
            3 => self.divValues(lhs, rhs),
            4 => self.remValues(lhs, rhs),
            5 => self.andValues(lhs, rhs),
            6 => self.orValues(lhs, rhs),
            7 => self.eqValues(lhs, rhs),
            8 => self.neqValues(lhs, rhs),
            9 => self.ltValues(lhs, rhs),
            10 => self.gtValues(lhs, rhs),
            11 => self.lteValues(lhs, rhs),
            12 => self.gteValues(lhs, rhs),
            else => error.TypeError,
        };
    }

    fn evaluateUnaryOp(_: *VM, op: u8, val: value_mod.Value) !value_mod.Value {
        return switch (op) {
            0 => switch (val) {
                .int => |i| value_mod.Value{ .int = -i },
                .freal => |f| value_mod.Value{ .freal = -f },
                else => error.TypeError,
            },
            1 => value_mod.Value{ .booling = !(try val.toBool()) },
            else => error.TypeError,
        };
    }

    fn callBuiltin(self: *VM, name: []const u8, args: []value_mod.Value) !value_mod.Value {
        if (std.mem.eql(u8, name, "printf")) {
            for (args) |arg| {
                try arg.print(self.stdoutWriter());
                try self.stdoutWriter().print(" ", .{});
            }
            try self.stdoutWriter().print("\n", .{});
            return value_mod.Value{ .null = {} };
        }
        if (std.mem.eql(u8, name, "int")) {
            return switch (args[0]) {
                .int => |v| value_mod.Value{ .int = v },
                .freal => |v| value_mod.Value{ .int = @intFromFloat(v) },
                else => error.TypeError,
            };
        }
        if (std.mem.eql(u8, name, "string")) {
            return switch (args[0]) {
                .string => |s| value_mod.Value{ .string = s },
                .int => |v| value_mod.Value{ .string = try std.fmt.allocPrint(self.allocator, "{d}", .{v}) },
                else => error.TypeError,
            };
        }
        return error.UndefinedFunction;
    }

    fn addValues(self: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        if (lhs == .int and rhs == .int) return value_mod.Value{ .int = lhs.int + rhs.int };
        if (lhs == .freal and rhs == .freal) return value_mod.Value{ .freal = lhs.freal + rhs.freal };
        if (lhs == .string and rhs == .string) {
            const result = try std.mem.concat(self.allocator, u8, &.{ lhs.string, rhs.string });
            return value_mod.Value{ .string = result };
        }
        return error.TypeError;
    }

    fn subValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        if (lhs == .int and rhs == .int) return value_mod.Value{ .int = lhs.int - rhs.int };
        if (lhs == .freal and rhs == .freal) return value_mod.Value{ .freal = lhs.freal - rhs.freal };
        return error.TypeError;
    }

    fn mulValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        if (lhs == .int and rhs == .int) return value_mod.Value{ .int = lhs.int * rhs.int };
        if (lhs == .freal and rhs == .freal) return value_mod.Value{ .freal = lhs.freal * rhs.freal };
        return error.TypeError;
    }

    fn divValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        if (lhs == .int and rhs == .int) return value_mod.Value{ .int = @divTrunc(lhs.int, rhs.int) };
        if (lhs == .freal and rhs == .freal) return value_mod.Value{ .freal = lhs.freal / rhs.freal };
        return error.TypeError;
    }

    fn remValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        if (lhs == .int and rhs == .int) return value_mod.Value{ .int = @rem(lhs.int, rhs.int) };
        return error.TypeError;
    }

    fn andValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        _ = lhs;
        _ = rhs;
        return error.TypeError;
    }

    fn orValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        _ = lhs;
        _ = rhs;
        return error.TypeError;
    }

    fn eqValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        const equal = switch (lhs) {
            .int => |li| if (rhs == .int) li == rhs.int else false,
            .freal => |lf| if (rhs == .freal) lf == rhs.freal else false,
            .string => |ls| if (rhs == .string) std.mem.eql(u8, ls, rhs.string) else false,
            .booling => |lb| if (rhs == .booling) lb == rhs.booling else false,
            .null => rhs == .null,
            else => false,
        };
        return value_mod.Value{ .booling = equal };
    }

    fn neqValues(self: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        const equal = try self.eqValues(lhs, rhs);
        return value_mod.Value{ .booling = !equal.booling };
    }

    fn ltValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        if (lhs == .int and rhs == .int) return value_mod.Value{ .booling = lhs.int < rhs.int };
        if (lhs == .freal and rhs == .freal) return value_mod.Value{ .booling = lhs.freal < rhs.freal };
        return error.TypeError;
    }

    fn gtValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        if (lhs == .int and rhs == .int) return value_mod.Value{ .booling = lhs.int > rhs.int };
        if (lhs == .freal and rhs == .freal) return value_mod.Value{ .booling = lhs.freal > rhs.freal };
        return error.TypeError;
    }

    fn lteValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        if (lhs == .int and rhs == .int) return value_mod.Value{ .booling = lhs.int <= rhs.int };
        if (lhs == .freal and rhs == .freal) return value_mod.Value{ .booling = lhs.freal <= rhs.freal };
        return error.TypeError;
    }

    fn gteValues(_: *VM, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        if (lhs == .int and rhs == .int) return value_mod.Value{ .booling = lhs.int >= rhs.int };
        if (lhs == .freal and rhs == .freal) return value_mod.Value{ .booling = lhs.freal >= rhs.freal };
        return error.TypeError;
    }
};

