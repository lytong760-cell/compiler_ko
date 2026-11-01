const std = @import("std");
const ast = @import("ast.zig");
const value_mod = @import("value.zig");
const bytecode = @import("bytecode.zig");
const operator = @import("operator.zig");

const EndOfInput = error.EndOfInput;

const KoLoopEngine = opaque {};
const KoLoopCreateFn = *const fn () callconv(.c) ?*KoLoopEngine;
const KoLoopDestroyFn = *const fn (?*KoLoopEngine) callconv(.c) void;
const KoLoopOptimizeForFn = *const fn (*KoLoopEngine, [*:0]const u8, i64, i64, i64, u64) callconv(.c) c_int;
const KoLoopBodyFn = *const fn (u64, ?*anyopaque) callconv(.c) void;
const KoLoopExecuteFn = *const fn (*KoLoopEngine, [*:0]const u8, KoLoopBodyFn, ?*anyopaque, u64) callconv(.c) c_int;
const KoLoopGetStatsFn = *const fn (*KoLoopEngine, ?[*]u8, usize) callconv(.c) c_int;

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
    loaded_libs: std.array_list.Managed(std.DynLib),
    loop_lib: ?std.DynLib,
    loop_lib_checked: bool,
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
            .loaded_libs = std.array_list.Managed(std.DynLib).init(allocator),
            .loop_lib = null,
            .loop_lib_checked = false,
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

    pub fn stdinReader(self: *VM) !*std.Io.Reader {
        if (self.stdin_reader) |*reader| return reader;
        if (self.stdin_file_reader == null) {
            self.stdin_file_reader = std.Io.File.stdin().reader(self.io, &self.stdin_buf);
        }
        return &self.stdin_file_reader.?.interface;
    }

pub fn readInputLine(self: *VM) ![]const u8 {
    const reader = try self.stdinReader();
    const result = reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
        error.EndOfStream => return reader.buffered(),
        else => return err,
    };
    if (result.len > 0 and result[result.len - 1] == '\n') return result[0 .. result.len - 1];
    return result;
}

    pub fn stdoutWriter(self: *VM) *std.Io.Writer {
        if (self.output_writer) |writer| return writer;
        if (self.stdout_writer == null) {
            self.stdout_writer = std.Io.File.stdout().writer(self.io, &self.stdout_buf);
        }
        return &self.stdout_writer.?.interface;
    }

    pub fn appendValueToString(self: *VM, out: *std.array_list.Managed(u8), val: value_mod.Value) !void {
        return @import("vm_value_ops.zig").appendValueToString(self, out, val);
    }

    pub fn deinit(self: *VM) void {
        for (self.loaded_libs.items) |*lib| lib.close();
        self.loaded_libs.deinit();
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

    pub fn getProcessName(self: *VM) []const u8 {
        if (std.mem.eql(u8, self.current_function, "main")) {
            return std.fmt.allocPrint(self.allocator, "{s}:main", .{self.file_path}) catch self.file_path;
        }
        return std.fmt.allocPrint(self.allocator, "{s}:main-{s}", .{ self.file_path, self.current_function }) catch self.file_path;
    }

    pub fn exposeProcess(self: *VM) void {
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

        const Entry = struct { priority: i64, index: usize, stmt: *ast.Statement };
        var entries = std.array_list.Managed(Entry).init(self.allocator);
        defer entries.deinit();
        for (program, 0..) |*stmt, idx| {
            const prio: i64 = if (stmt.* == .priority_stmt) stmt.priority_stmt.priority else 0;
            try entries.append(.{ .priority = prio, .index = idx, .stmt = stmt });
        }
        var i: usize = 1;
        while (i < entries.items.len) : (i += 1) {
            var j = i;
            while (j > 0 and entries.items[j - 1].priority > entries.items[j].priority) {
                const tmp = entries.items[j];
                entries.items[j] = entries.items[j - 1];
                entries.items[j - 1] = tmp;
                j -= 1;
            }
        }

        for (entries.items) |e| {
            if (self.has_returned) break;
            if (self.has_error) {
                self.dispatchCatchBlocks(program, e.index) catch |err| std.debug.print("dispatchCatchBlocks: {any}\n", .{err});
                continue;
            }
            self.executeStatement(e.stmt) catch |err| {
                self.raiseError(VM.zigErrorToKoType(err), @errorName(err));
            };
        }
        if (self.has_error) {
            if (self.error_type) |et| {
                if (std.mem.eql(u8, et, "InputError")) return error.EndOfInput;
            }
            return error.RuntimeError;
        }
    }

    pub fn dispatchCatchBlocks(self: *VM, program: []ast.Statement, current_idx: usize) !void {
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

    pub fn executeStatement(self: *VM, stmt: *const ast.Statement) anyerror!void {
        if (self.has_returned or self.has_error) return;

        switch (stmt.*) {
            .var_decl => |*v| {
                var val = try self.evaluateExpression(v.value_expr);
                 var final_val = if (std.mem.eql(u8, v.type_name, "bytes")) blk: {
                    defer val.deinit(self.allocator);
                    var buf: []u8 = undefined;
                    switch (val) {
                        .int => |i| {
                            if (i < 0) {
                                self.raiseError("TypeError", "Cannot cast negative value to bytes");
                                break :blk value_mod.Value{ .null = {} };
                            }
                            buf = try self.allocator.alloc(u8, @intCast(i));
                            @memset(buf, 0);
                        },
                        .string => |s| {
                            buf = try self.allocator.dupe(u8, s);
                        },
                        else => |other| {
                            var aw: std.Io.Writer.Allocating = .init(self.allocator);
                            errdefer aw.deinit();
                            try other.print(&aw.writer);
                            const s = try aw.toOwnedSlice();
                            defer self.allocator.free(s);
                            buf = try self.allocator.dupe(u8, s);
                        },
                    }
                    break :blk value_mod.Value{ .bytes = buf };
                } else val;
                 if (self.current_scope.variables.get(v.name)) |existing| {
                    if (existing == .none) {
                        self.raiseError("TypeError", "Cannot reassign none value");
                        final_val.deinit(self.allocator);
                        return;
                    }
                    const gop = try self.current_scope.variables.getOrPut(v.name);
                    gop.value_ptr.*.deinit(self.allocator);
                    gop.value_ptr.* = final_val;
                } else if (self.global_scope.variables.get(v.name)) |existing| {
                    if (existing == .none) {
                        self.raiseError("TypeError", "Cannot reassign none value");
                        final_val.deinit(self.allocator);
                        return;
                    }
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
                        self.dispatchLoop();
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
                        self.dispatchLoop();
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

    pub fn executeBlock(self: *VM, body: []ast.Statement) !void {
        const Entry = struct { priority: i64, stmt: *ast.Statement };
        var entries = std.array_list.Managed(Entry).init(self.allocator);
        defer entries.deinit();
        for (body) |*s| {
            const prio: i64 = if (s.* == .priority_stmt) s.priority_stmt.priority else 0;
            try entries.append(.{ .priority = prio, .stmt = s });
        }
        var i: usize = 1;
        while (i < entries.items.len) : (i += 1) {
            var j = i;
            while (j > 0 and entries.items[j - 1].priority > entries.items[j].priority) {
                const tmp = entries.items[j];
                entries.items[j] = entries.items[j - 1];
                entries.items[j - 1] = tmp;
                j -= 1;
            }
        }
        for (entries.items) |e| {
            if (self.has_returned) break;
            try self.executeStatement(e.stmt);
        }
    }

    pub fn executeStatementInScope(self: *VM, stmt: *const ast.Statement, scope: *value_mod.Scope) anyerror!void {
        const prev_scope = self.current_scope;
        self.current_scope = scope;
        defer self.current_scope = prev_scope;
        try self.executeStatement(stmt);
    }

    pub fn assignValue(self: *VM, target: *ast.Expr, val: value_mod.Value) !void {
        switch (target.*) {
            .identifier => |name| {
                if (self.current_scope.variables.get(name)) |existing| {
                    if (existing == .none) {
                        self.raiseError("TypeError", "Cannot reassign none value");
                        var v = val;
                        v.deinit(self.allocator);
                        return;
                    }
                    const gop = try self.current_scope.variables.getOrPut(name);
                    gop.value_ptr.*.deinit(self.allocator);
                    gop.value_ptr.* = val;
                } else if (self.global_scope.variables.get(name)) |existing| {
                    if (existing == .none) {
                        self.raiseError("TypeError", "Cannot reassign none value");
                        var v = val;
                        v.deinit(self.allocator);
                        return;
                    }
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
                                if (try d.fetchPut(key_copy, val)) |old_entry| {
                                    self.allocator.free(old_entry.key);
                                    var old_val = old_entry.value;
                                    old_val.deinit(self.allocator);
                                }
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

    pub fn zigErrorToKoType(err: anyerror) []const u8 {
        return @import("vm_value_ops.zig").zigErrorToKoType(err);
    }

    pub fn raiseError(self: *VM, err_type: []const u8, message: []const u8) void {
        self.has_error = true;
        self.error_type = err_type;
        _ = message;
    }

    pub fn evaluateExpression(self: *VM, expr: *ast.Expr) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateExpression(self, expr);
    }

    pub fn unescape(self: *VM, raw: []const u8) ![]u8 {
        return @import("vm_value_ops.zig").unescape(self, raw);
    }

    pub fn evaluateLiteral(self: *VM, lit: ast.Literal) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateLiteral(self, lit);
    }

    pub fn evaluateIdentifier(self: *VM, name: []const u8) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateIdentifier(self, name);
    }

    pub fn evaluateBinary(self: *VM, bin: *ast.BinaryExpr) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateBinary(self, bin);
    }

    pub fn printInterpolated(self: *VM, s: []const u8) !void {
        return @import("vm_value_ops.zig").printInterpolated(self, s);
    }

    pub fn evaluateUnary(self: *VM, unary: *ast.UnaryExpr) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateUnary(self, unary);
    }

    pub fn instantiateClassByName(self: *VM, name: []const u8) !value_mod.Value {
        return @import("vm_value_ops.zig").instantiateClassByName(self, name);
    }

    pub fn callUserFunction(self: *VM, func: *value_mod.Function, args: []ast.Expr) anyerror!value_mod.Value {
        return @import("vm_value_ops.zig").callUserFunction(self, func, args);
    }

    pub fn callUserFunctionValues(self: *VM, func: *value_mod.Function, args: []const value_mod.Value) anyerror!value_mod.Value {
        return @import("vm_value_ops.zig").callUserFunctionValues(self, func, args);
    }

    pub fn evaluateCall(self: *VM, call: *const ast.CallExpr) anyerror!value_mod.Value {
        return @import("vm_value_ops.zig").evaluateCall(self, call);
    }

    pub fn evaluateMemberAccess(self: *VM, ma: *ast.MemberAccess) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateMemberAccess(self, ma);
    }

    pub fn evaluateIndexAccess(self: *VM, ia: *ast.IndexAccess) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateIndexAccess(self, ia);
    }

    pub fn dispatchLoop(self: *VM) void {
        if (!self.loop_lib_checked) {
            self.loop_lib_checked = true;
            const candidates = [_][]const u8{
                "zig-out/lib/libko_loop.so",
                "./libs/libko_loop.so",
                "./libko_loop.so",
                "/usr/lib/libko_loop.so",
                "/usr/local/lib/libko_loop.so",
            };
            for (candidates) |path| {
                const lib = std.DynLib.open(path) catch continue;
                self.loop_lib = lib;
                break;
            }
        }

        const writer = self.stdoutWriter();
        if (self.loop_lib) |*lib| {
            const create_fn = lib.lookup(KoLoopCreateFn, "ko_loop_engine_create");
            const destroy_fn = lib.lookup(KoLoopDestroyFn, "ko_loop_engine_destroy");
            if (create_fn == null or destroy_fn == null) {
                writer.print("Warning: libko_loop not available; continuing\n", .{}) catch {};
                writer.flush() catch {};
                return;
            }
            const eng = create_fn.?() orelse {
                writer.print("Warning: libko_loop not available; continuing\n", .{}) catch {};
                writer.flush() catch {};
                return;
            };
            if (lib.lookup(KoLoopOptimizeForFn, "ko_loop_optimize_for")) |opt_fn| {
                _ = opt_fn(eng, "ko_loop", 0, 4, 1, 4);
            }
            if (lib.lookup(KoLoopExecuteFn, "ko_loop_execute_optimized_loop")) |exec_fn| {
                const body_fn = struct {
                    fn f(_: u64, _: ?*anyopaque) callconv(.c) void {}
                }.f;
                _ = exec_fn(eng, "ko_loop", body_fn, null, 4);
            }
            if (lib.lookup(KoLoopGetStatsFn, "ko_loop_get_stats")) |stats_fn| {
                var buf: [256]u8 = undefined;
                _ = stats_fn(eng, &buf, buf.len);
            }
            destroy_fn.?(eng);
        } else {
            writer.print("Warning: libko_loop not available; continuing\n", .{}) catch {};
            writer.flush() catch {};
        }
    }

    pub fn evaluateSystemTag(self: *VM, st: *ast.SystemTagExpr) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateSystemTag(self, st);
    }

pub fn evaluateInput(self: *VM, ie: *ast.InputExpr) !value_mod.Value {
    return @import("vm_value_ops.zig").evaluateInput(self, ie);
}

    pub fn evaluateNow(self: *VM, ne: *ast.NowExpr) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateNow(self, ne);
    }

    pub fn executeChunk(self: *VM, chunk: *bytecode.Chunk) !void {
        self.exposeProcess();
        if (chunk.functions.items.len == 0) return;
        const main_fn = &chunk.functions.items[0];
        try self.runFunction(main_fn, chunk);
    }

    pub fn runFunction(self: *VM, func: *bytecode.Function, chunk: *bytecode.Chunk) !void {
        var stack: [1024]value_mod.Value = undefined;
        var sp: usize = 0;
        var ip: usize = 0;

        while (ip < func.instructions.items.len) {
            const inst = func.instructions.items[ip];
            ip += 1;

            switch (inst) {
                .load_const => |idx| {
                    if (sp >= stack.len) return error.StackOverflow;
                    const val = chunk.constants.items[idx];
                    stack[sp] = val;
                    sp += 1;
                },
                .load_var => |idx| {
                    if (sp >= stack.len) return error.StackOverflow;
                    const name = chunk.constants.items[idx].string;
                    const val = self.current_scope.variables.get(name) orelse value_mod.Value{ .null = {} };
                    stack[sp] = try val.clone(self.allocator);
                    sp += 1;
                },
                .store_var => |idx| {
                    if (sp == 0) return error.StackUnderflow;
                    const name = chunk.constants.items[idx].string;
                    const val = stack[sp - 1];
                    const owned = try self.allocator.dupe(u8, name);
                    const cloned = try val.clone(self.allocator);
                    if (try self.current_scope.variables.fetchPut(owned, cloned)) |old_entry| {
                        self.allocator.free(old_entry.key);
                        var old_val = old_entry.value;
                        old_val.deinit(self.allocator);
                    }
                    sp -= 1;
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
                    if (self.current_scope.classes.get(callee_name) != null or self.global_scope.classes.get(callee_name) != null) {
                        const instance_val = try self.instantiateClassByName(callee_name);
                        sp -= arg_count;
                        stack[sp] = instance_val;
                        sp += 1;
                    } else {
                        const result = try self.callBuiltin(callee_name, args);
                        sp -= arg_count;
                        stack[sp] = result;
                        sp += 1;
                    }
                },
                .call_method => |arg_count| {
                    const ac = @as(usize, arg_count);
                    if (sp < 2 + ac) return error.StackUnderflow;
                    const args = stack[sp - ac .. sp];
                    const method_val = stack[sp - ac - 1];
                    const target_val = stack[sp - ac - 2];
                    const method_name = switch (method_val) {
                        .string => |s| s,
                        else => {
                            self.raiseError("TypeError", "Method name must be string");
                            return error.RuntimeError;
                        },
                    };
                    var method_func: ?*value_mod.Function = null;
                    switch (target_val) {
                        .class_instance => |ci| {
                            if (ci.methods.get(method_name)) |f| {
                                method_func = f;
                            } else {
                                self.raiseError("MemberError", "Method not found");
                                return error.RuntimeError;
                            }
                        },
                        .function => |f| method_func = f,
                        else => {
                            self.raiseError("CallError", "Cannot call method on non-object");
                            return error.RuntimeError;
                        },
                    }
                    if (method_func) |f| {
                        const result = try self.callUserFunctionValues(f, args);
                        sp -= ac + 2;
                        stack[sp] = result;
                        sp += 1;
                    }
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
                .make_dict => {
                    const d = try self.allocator.create(std.StringHashMap(value_mod.Value));
                    d.* = std.StringHashMap(value_mod.Value).init(self.allocator);
                    stack[sp] = value_mod.Value{ .dict = d };
                    sp += 1;
                },
                .dict_set => {
                    if (sp < 3) return error.StackUnderflow;
                    const value = stack[sp - 1];
                    const key_val = stack[sp - 2];
                    const dict_val = stack[sp - 3];
                    const key_str = switch (key_val) {
                        .string => |s| s,
                        else => return error.TypeError,
                    };
                    sp -= 3;
                    const d = dict_val.dict;
                    const duped_key = try self.allocator.dupe(u8, key_str);
                    if (try d.fetchPut(duped_key, value)) |old| {
                        self.allocator.free(old.key);
                        var v = old.value;
                        v.deinit(self.allocator);
                    }
                    var kv = key_val;
                    kv.deinit(self.allocator);
                    stack[sp] = dict_val;
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

    pub fn binaryOp(self: *VM, op: u8, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
        return @import("vm_value_ops.zig").binaryOp(self, op, lhs, rhs);
    }

    pub fn evaluateUnaryOp(self: *VM, op: u8, val: value_mod.Value) !value_mod.Value {
        return @import("vm_value_ops.zig").evaluateUnaryOp(self, op, val);
    }

    pub fn callBuiltin(self: *VM, name: []const u8, args: []value_mod.Value) !value_mod.Value {
        return @import("vm_value_ops.zig").callBuiltin(self, name, args);
    }

};
