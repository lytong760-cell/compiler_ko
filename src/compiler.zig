const std = @import("std");
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");
const lexer = @import("lexer.zig");
const value_mod = @import("value.zig");

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    chunk: *bytecode.Chunk,
    current_function: *bytecode.Function,

    pub fn init(allocator: std.mem.Allocator, chunk: *bytecode.Chunk, name: []const u8, arity: u32) !Compiler {
        var functions = std.array_list.Managed(bytecode.Function).init(allocator);
        errdefer functions.deinit();

        var instructions = std.array_list.Managed(bytecode.Instruction).init(allocator);
        errdefer instructions.deinit();

        const duped = try allocator.dupe(u8, name);
        const func = try allocator.create(bytecode.Function);
        func.* = .{
            .name = duped,
            .instructions = instructions,
            .arity = arity,
        };

        return .{
            .allocator = allocator,
            .chunk = chunk,
            .current_function = func,
        };
    }

    pub fn deinit(self: *Compiler) void {
        // Note: current_function is owned by chunk after append
        self.allocator.destroy(self.current_function);
    }

    pub fn compileProgram(self: *Compiler, program: []const ast.Statement) !void {
        for (program) |stmt| {
            try self.compileStatement(&stmt);
        }
        try self.emit(.{ .ret = {} });
    }

    fn compileStatement(self: *Compiler, stmt: *const ast.Statement) anyerror!void {
        switch (stmt.*) {
            .expr => |e| try self.compileExpression(e),
            .var_decl => |v| try self.compileVarDecl(&v),
            .assignment => |a| try self.compileAssignment(&a),
            .return_stmt => |r| try self.compileReturn(r),
            .catch_stmt => |c| try self.compileCatch(c),
            .func_decl => |f| try self.compileFuncDecl(f),
            .block => |b| {
                for (b.body) |s| {
                    try self.compileStatement(&s);
                }
            },
            else => {},
        }
    }

    fn compileExpression(self: *Compiler, expr: *const ast.Expr) !void {
        switch (expr.*) {
            .literal => |lit| try self.emitLiteral(lit),
            .identifier => |name| {
                const duped = try self.allocator.dupe(u8, name);
                const idx = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = duped });
                try self.emit(.{ .load_var = @intCast(idx) });
            },
            .binary => |b| {
                try self.compileExpression(b.left);
                try self.compileExpression(b.right);
                const op: u8 = switch (b.op) {
                    .add => 0, .sub => 1, .mul => 2, .div => 3,
                    .rem => 4, .logical_and => 5, .logical_or => 6,
                    .eq => 7, .neq => 8, .lt => 9, .gt => 10, .lte => 11, .gte => 12,
                };
                try self.emit(.{ .binary = op });
            },
            .unary => |u| {
                try self.compileExpression(u.expr);
                const op: u8 = switch (u.op) {
                    .neg => 0, .not => 1,
                };
                try self.emit(.{ .unary = op });
            },
            .call => |c| {
                for (c.args) |arg| {
                    try self.compileExpression(&arg);
                }
                const callee_duped = try self.allocator.dupe(u8, c.callee);
                const idx = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = callee_duped });
                try self.emit(.{ .call = @intCast(idx + c.args.len) });
            },
            .system_tag => |st| {
                if (std.mem.eql(u8, st.tag, "printf")) {
                    for (st.args) |arg| {
                        try self.compileExpression(&arg);
                    }
                    try self.emit(.{ .print = {} });
                } else if (std.mem.eql(u8, st.tag, "input")) {
                    try self.emit(.{ .input = {} });
                } else if (std.mem.eql(u8, st.tag, "now")) {
                    try self.emit(.{ .now = {} });
                } else if (std.mem.eql(u8, st.tag, "len")) {
                    try self.compileExpression(&st.args[0]);
                    try self.emit(.{ .len = {} });
                } else if (std.mem.eql(u8, st.tag, "memory")) {
                    try self.emit(.{ .memory = {} });
                } else if (std.mem.eql(u8, st.tag, "encode")) {
                    try self.compileExpression(&st.args[0]);
                    try self.emit(.{ .encode = {} });
                }
            },
            else => {},
        }
    }

    fn compileVarDecl(self: *Compiler, v: *const ast.VarDecl) !void {
        try self.compileExpression(v.value_expr);
        const name_duped = try self.allocator.dupe(u8, v.name);
        const idx = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = name_duped });
        try self.emit(.{ .store_var = @intCast(idx) });
    }

    fn compileAssignment(self: *Compiler, a: *const ast.Assignment) !void {
        try self.compileExpression(a.value_expr);
        if (a.target.* == .identifier) {
            const target_duped = try self.allocator.dupe(u8, a.target.*.identifier);
            const idx = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = target_duped });
            try self.emit(.{ .store_var = @intCast(idx) });
        }
    }

    fn compileReturn(self: *Compiler, r: *const ast.ReturnStmt) !void {
        try self.compileExpression(r.expr);
        try self.emit(.{ .ret = {} });
    }

    fn compileCatch(self: *Compiler, c: *const ast.CatchStmt) anyerror!void {
        const catch_start = self.current_function.instructions.items.len;
        try self.emit(.{ .catch_start = 0 });
        for (c.body) |stmt| {
            try self.compileStatement(&stmt);
        }
        try self.emit(.{ .catch_end = {} });
        self.current_function.instructions.items[catch_start].catch_start = @intCast(self.current_function.instructions.items.len);
    }

    fn compileFuncDecl(self: *Compiler, f: *const ast.FuncDecl) !void {
        const func_name_duped = try self.allocator.dupe(u8, f.name);
        const idx = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = func_name_duped });
        try self.emit(.{ .load_var = @intCast(idx) });
    }

    fn emitLiteral(self: *Compiler, lit: ast.Literal) !void {
        const val = switch (lit.kind) {
            .int => value_mod.Value{ .int = lit.int_value },
            .freal => value_mod.Value{ .freal = lit.freal_value },
            .string => blk: {
                const duped = try self.allocator.dupe(u8, lit.raw);
                break :blk value_mod.Value{ .string = duped };
            },
            .bool_true => value_mod.Value{ .booling = true },
            .bool_false => value_mod.Value{ .booling = false },
            .tuple => value_mod.Value{ .null = {} },
            .dict => value_mod.Value{ .null = {} },
        };
        const idx = self.chunk.constants.items.len; try self.chunk.constants.append(val);
        try self.emit(.{ .load_const = @intCast(idx) });
    }

    fn emit(self: *Compiler, inst: bytecode.Instruction) !void {
        try self.current_function.instructions.append(inst);
    }
};
