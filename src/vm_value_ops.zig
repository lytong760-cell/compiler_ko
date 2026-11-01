const std = @import("std");
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const ast = @import("ast.zig");
const value_mod = @import("value.zig");
const bytecode = @import("bytecode.zig");
const operator = @import("operator.zig");

pub fn appendValueToString(self: *VM, out: *std.array_list.Managed(u8), val: value_mod.Value) !void {
    var aw: std.Io.Writer.Allocating = .init(self.allocator);
    errdefer aw.deinit();
    try val.print(&aw.writer);
    const text = try aw.toOwnedSlice();
    try out.appendSlice(text);
    self.allocator.free(text);
}

pub fn evaluateExpression(self: *VM, expr: *ast.Expr) !value_mod.Value {
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

pub fn unescape(self: *VM, raw: []const u8) ![]u8 {
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

pub fn evaluateLiteral(self: *VM, lit: ast.Literal) !value_mod.Value {
    return switch (lit.kind) {
        .int => value_mod.Value{ .int = lit.int_value },
        .freal => value_mod.Value{ .freal = lit.freal_value },
        .string => blk: {
            const unescaped = try self.unescape(lit.raw);
            break :blk value_mod.Value{ .string = unescaped };
        },
        .bool_true => value_mod.Value{ .booling = true },
        .bool_false => value_mod.Value{ .booling = false },
        .none => value_mod.Value{ .none = {} },
        .null => value_mod.Value{ .null = {} },
        .tuple => value_mod.Value{ .tuple = &[_]value_mod.Value{} },
        .dict => blk: {
            const d = try self.allocator.create(std.StringHashMap(value_mod.Value));
            d.* = std.StringHashMap(value_mod.Value).init(self.allocator);
            for (lit.dict_entries) |entry| {
                const val = try self.evaluateExpression(entry.value);
                _ = try d.put(entry.key, val);
            }
            break :blk value_mod.Value{ .dict = d };
        },
    };
}

pub fn evaluateIdentifier(self: *VM, name: []const u8) !value_mod.Value {
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

pub fn evaluateBinary(self: *VM, bin: *ast.BinaryExpr) !value_mod.Value {
    const left = try self.evaluateExpression(bin.left);
    const right = try self.evaluateExpression(bin.right);

    return try operator.applyBinary(bin.op, left, right, self.allocator);
}

pub fn printInterpolated(self: *VM, s: []const u8) !void {
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

pub fn evaluateUnary(self: *VM, unary: *ast.UnaryExpr) !value_mod.Value {
    const val = try self.evaluateExpression(unary.expr);
    return try operator.applyUnary(unary.op, val);
}

pub fn instantiateClassByName(self: *VM, name: []const u8) !value_mod.Value {
    const cd = if (self.current_scope.classes.get(name)) |c| c else if (self.global_scope.classes.get(name)) |c| c else return error.RuntimeError;
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

pub fn callUserFunction(self: *VM, func: *value_mod.Function, args: []ast.Expr) anyerror!value_mod.Value {
    if (args.len != func.params.len) {
        self.raiseError("ArgumentError", "Argument count mismatch");
        return error.RuntimeError;
    }

    var new_scope = try self.allocator.create(value_mod.Scope);
    new_scope.* = value_mod.Scope.init(self.allocator, func.closure_scope);

    for (args, func.params) |arg_expr, param| {
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
}

pub fn callUserFunctionValues(self: *VM, func: *value_mod.Function, args: []const value_mod.Value) anyerror!value_mod.Value {
    if (args.len != func.params.len) {
        self.raiseError("ArgumentError", "Argument count mismatch");
        return error.RuntimeError;
    }

    var new_scope = try self.allocator.create(value_mod.Scope);
    new_scope.* = value_mod.Scope.init(self.allocator, func.closure_scope);

    for (args, func.params) |arg_val, param| {
        const param_name = try self.allocator.dupe(u8, param.name);
        const cloned = try arg_val.clone(self.allocator);
        try new_scope.variables.put(param_name, cloned);
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
}

pub fn evaluateCall(self: *VM, call: *const ast.CallExpr) anyerror!value_mod.Value {
    if (std.mem.eql(u8, call.callee, "Loop")) {
        self.dispatchLoop();
        return value_mod.Value{ .null = {} };
    }
    if (std.mem.eql(u8, call.callee, "Import")) {
        const writer = self.stdoutWriter();

        var module_name: []const u8 = "unknown";
        var module_name_owned = false;
        if (call.args.len > 0) {
            const arg = &call.args[0];
            if (arg.* == .identifier) {
                module_name = arg.identifier;
            } else if (arg.* == .literal and arg.literal.kind == .string) {
                module_name = try self.unescape(arg.literal.raw);
                module_name_owned = true;
            } else if (arg.* == .system_tag) {
                module_name = arg.system_tag.tag;
            } else {
                const val = self.evaluateExpression(@constCast(arg)) catch null;
                if (val) |v| {
                    if (v == .string) {
                        module_name = v.string;
                        module_name_owned = true;
                    }
                }
            }
        }

        const home_ptr = std.c.getenv("HOME");
        const home = if (home_ptr) |p| std.mem.span(p) else "/root";
        // Build candidate directory list including home expansion
        var dir_list = std.array_list.Managed([]const u8).init(self.allocator);
        defer dir_list.deinit();
        try dir_list.append("./libs");
        const home_plugins = try std.fmt.allocPrint(self.allocator, "{s}/.ko/plugins", .{home});
        defer self.allocator.free(home_plugins);
        try dir_list.append(home_plugins);
        // extra fallbacks for existing build artifacts
        try dir_list.append("zig-out/lib");

        // candidate filenames
        var name_list = std.array_list.Managed([]const u8).init(self.allocator);
        defer {
            for (name_list.items) |n| self.allocator.free(n);
            name_list.deinit();
        }
        try name_list.append(try std.fmt.allocPrint(self.allocator, "{s}.so", .{module_name}));
        try name_list.append(try std.fmt.allocPrint(self.allocator, "lib{s}.so", .{module_name}));
        try name_list.append(try std.fmt.allocPrint(self.allocator, "libko_{s}.so", .{module_name}));
        // lowercase variant
        const lower = try self.allocator.alloc(u8, module_name.len);
        defer self.allocator.free(lower);
        for (module_name, 0..) |c, i| lower[i] = std.ascii.toLower(c);
        try name_list.append(try std.fmt.allocPrint(self.allocator, "{s}.so", .{lower}));
        try name_list.append(try std.fmt.allocPrint(self.allocator, "lib{s}.so", .{lower}));
        try name_list.append(try std.fmt.allocPrint(self.allocator, "libko_{s}.so", .{lower}));

        var loaded = false;
        for (dir_list.items) |dir| {
            for (name_list.items) |fname| {
                const full_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ dir, fname });
                defer self.allocator.free(full_path);

                // check existence
                const f = std.Io.Dir.cwd().openFile(self.io, full_path, .{}) catch continue;
                f.close(self.io);

                const lib = std.DynLib.open(full_path) catch continue;
                try self.loaded_libs.append(lib);
                loaded = true;

                try writer.print("Imported module {s} from {s}\n", .{ module_name, full_path });
                try writer.flush();
                break;
            }
            if (loaded) break;
        }

        if (!loaded) {
            // Attempt to load module metadata from src/module (Java Import metadata).
            var metadata_loaded = false;
            const meta_candidates = [_][]const u8{ "src/module", "./src/module" };
            for (meta_candidates) |base| {
                const meta_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}/module.json", .{ base, module_name });
                defer self.allocator.free(meta_path);
                std.Io.Dir.cwd().access(self.io, meta_path, .{}) catch continue;
                metadata_loaded = true;
                try writer.print("Imported module metadata {s} from {s}\n", .{ module_name, meta_path });
                try writer.flush();
                break;
            }
            if (!metadata_loaded) {
                try writer.print("Warning: could not load module {s}\n", .{module_name});
                try writer.flush();
            }
        }

        // Register module name in scope regardless of native load.
        const key = try self.allocator.dupe(u8, module_name);
        const marker = try std.fmt.allocPrint(self.allocator, "module:{s}", .{module_name});
        try self.current_scope.variables.put(key, value_mod.Value{ .string = marker });

        if (module_name_owned) self.allocator.free(module_name);
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
    var func: ?*value_mod.Function = null;
    switch (callee_val) {
        .function => |f| func = f,
        .class_instance => |ci| {
            if (ci.methods.get(call.callee)) |f| {
                func = f;
            } else {
                self.raiseError("MemberError", "Method not found");
                return error.RuntimeError;
            }
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
    if (func) |f| {
        return try self.callUserFunction(f, call.args);
    }
    return error.RuntimeError;
}

pub fn evaluateMemberAccess(self: *VM, ma: *ast.MemberAccess) !value_mod.Value {
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

pub fn evaluateIndexAccess(self: *VM, ia: *ast.IndexAccess) !value_mod.Value {
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

pub fn evaluateSystemTag(self: *VM, st: *ast.SystemTagExpr) !value_mod.Value {
    if (std.mem.eql(u8, st.tag, "Loop") or std.mem.eql(u8, st.tag, "loop")) {
        if (st.args.len > 0) {
            const arg = self.evaluateExpression(&st.args[0]) catch value_mod.Value{ .null = {} };
            @constCast(&arg).deinit(self.allocator);
        }
        self.dispatchLoop();
        return value_mod.Value{ .null = {} };
    }
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
        if (std.mem.eql(u8, st.tag, "type")) {
            const name = switch (arg) {
                .int => "int",
                .freal => "freal",
                .string => "string",
                .booling => "booling",
                .byte => "byte",
                .bytes => "bytes",
                .tuple => "tuple",
                .list => "list",
                .dict => "dict",
                .none => "none",
                .null => "null",
                .function => "function",
                .class_instance => "class",
                .error_obj => "error",
            };
            const duped = try self.allocator.dupe(u8, name);
            @constCast(&arg).deinit(self.allocator);
            return value_mod.Value{ .string = duped };
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

pub fn evaluateInput(self: *VM, ie: *ast.InputExpr) !value_mod.Value {
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

pub fn evaluateNow(self: *VM, ne: *ast.NowExpr) !value_mod.Value {
    const val = try self.evaluateExpression(ne.expr);
    errdefer @constCast(&val).deinit(self.allocator);
    try self.assignValue(ne.target, val);
    return val;
}

pub fn binaryOp(self: *VM, op: u8, lhs: value_mod.Value, rhs: value_mod.Value) !value_mod.Value {
    return try operator.applyBinaryOpcode(op, lhs, rhs, self.allocator);
}

pub fn evaluateUnaryOp(_: *VM, op: u8, val: value_mod.Value) !value_mod.Value {
    return try operator.applyUnaryOpcode(op, val);
}

pub fn callBuiltin(self: *VM, name: []const u8, args: []value_mod.Value) !value_mod.Value {
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

pub fn zigErrorToKoType(err: anyerror) []const u8 {
    return switch (err) {
        error.DivideByZero => "DivideByZeroError",
        error.OverflowError => "OverflowError",
        error.TypeError => "TypeError",
        error.UndefinedVariable => "NameError",
        error.EndOfInput => "InputError",
        else => "RuntimeError",
    };
}

