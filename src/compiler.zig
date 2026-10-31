const std = @import("std");
const ast = @import("ast.zig");
const bytecode = @import("bytecode.zig");
const lexer = @import("lexer.zig");
const value_mod = @import("value.zig");
const operator = @import("operator.zig");

pub const Compiler = struct {
    allocator: std.mem.Allocator,
    chunk: *bytecode.Chunk,
    current_function: *bytecode.Function,

    pub fn init(allocator: std.mem.Allocator, chunk: *bytecode.Chunk, name: []const u8, arity: u32) !Compiler {
        var instructions = std.array_list.Managed(bytecode.Instruction).init(allocator);
        errdefer instructions.deinit();

        const duped = try allocator.dupe(u8, name);
        errdefer allocator.free(duped);

        try chunk.functions.append(.{
            .name = duped,
            .instructions = instructions,
            .arity = arity,
        });

        const current = &chunk.functions.items[chunk.functions.items.len - 1];
        return .{
            .allocator = allocator,
            .chunk = chunk,
            .current_function = current,
        };
    }

    pub fn deinit(self: *Compiler) void {
        _ = self;
        // Ownership of current_function (and its name/instructions) was transferred
        // to chunk during init(); chunk.deinit() releases them. Nothing to do here.
    }

    pub fn compileProgram(self: *Compiler, program: []const ast.Statement) !void {
        for (0..program.len) |i| {
            try self.compileStatement(&program[i]);
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
                for (0..b.body.len) |i| {
                    try self.compileStatement(&b.body[i]);
                }
            },
            .control_flow => |cf| try self.compileControlFlow(cf),
            .memory_op => |m| try self.compileMemoryOp(m),
            .encoding_op => |eo| try self.compileEncodingOp(eo),
            .len_op => |lo| try self.compileLenOp(lo),
            .class_instantiation => |ci| try self.compileClassInstantiation(ci),
            .priority_stmt => |ps| try self.compileStatement(ps.stmt),
            .class_decl => {
                return error.UnsupportedBytecode;
            },
        }
    }

    fn compileControlFlow(self: *Compiler, cf: *const ast.ControlFlow) anyerror!void {
        switch (cf.kind) {
            .if_stmt => {
                try self.compileExpression(cf.condition.?);
                const else_pos = try self.emitJumpPlaceholder(.jump_if_false);
                for (0..cf.body.len) |i| try self.compileStatement(&cf.body[i]);
                const end_pos = try self.emitJumpPlaceholder(.jump);
                self.patchJump(else_pos);
                var end_positions = std.array_list.Managed(usize).init(self.allocator);
                defer end_positions.deinit();
                for (cf.elifs) |e| {
                    try self.compileExpression(e.condition);
                    const elif_false = try self.emitJumpPlaceholder(.jump_if_false);
                    for (0..e.body.len) |i| try self.compileStatement(&e.body[i]);
                    const elif_end = try self.emitJumpPlaceholder(.jump);
                    self.patchJump(elif_false);
                    try end_positions.append(elif_end);
                }
                for (0..cf.else_body.len) |i| try self.compileStatement(&cf.else_body[i]);
                self.patchJump(end_pos);
                for (end_positions.items) |p| self.patchJump(p);
            },
            .for_loop => {
                if (cf.init) |init_assign| {
                    try self.compileExpression(init_assign.value_expr);
                    const name_duped = try self.allocator.dupe(u8, cf.loop_var);
                    const idx = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = name_duped });
                    try self.emit(.{ .store_var = @intCast(idx) });
                }
                const cond_pos = self.current_function.instructions.items.len;
                if (cf.condition) |cond| {
                    try self.compileExpression(cond);
                    const exit_pos = try self.emitJumpPlaceholder(.jump_if_false);
                    for (0..cf.body.len) |i| try self.compileStatement(&cf.body[i]);
                    if (cf.step) |step| {
                        const name_duped = try self.allocator.dupe(u8, cf.loop_var);
                        const idx = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = name_duped });
                        try self.emit(.{ .load_var = @intCast(idx) });
                        try self.compileExpression(step);
                        try self.emit(.{ .binary = 0 });
                        const name_duped2 = try self.allocator.dupe(u8, cf.loop_var);
                        const idx2 = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = name_duped2 });
                        try self.emit(.{ .store_var = @intCast(idx2) });
                    } else {
                        const name_duped = try self.allocator.dupe(u8, cf.loop_var);
                        const idx = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = name_duped });
                        try self.emit(.{ .load_var = @intCast(idx) });
                        const one_idx = self.chunk.constants.items.len;
                        try self.chunk.constants.append(.{ .int = 1 });
                        try self.emit(.{ .load_const = @intCast(one_idx) });
                        try self.emit(.{ .binary = 0 });
                        const name_duped2 = try self.allocator.dupe(u8, cf.loop_var);
                        const idx2 = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = name_duped2 });
                        try self.emit(.{ .store_var = @intCast(idx2) });
                    }
                    const jump_back = @as(i32, @intCast(@as(isize, @intCast(cond_pos)) - @as(isize, @intCast(self.current_function.instructions.items.len + 1))));
                    try self.emit(.{ .jump = jump_back });
                    self.patchJump(exit_pos);
                }
            },
            .while_loop => {
                const cond_pos = self.current_function.instructions.items.len;
                if (cf.condition) |cond| {
                    try self.compileExpression(cond);
                    const exit_pos = try self.emitJumpPlaceholder(.jump_if_false);
                    for (0..cf.body.len) |i| try self.compileStatement(&cf.body[i]);
                    const jump_back = @as(i32, @intCast(@as(isize, @intCast(cond_pos)) - @as(isize, @intCast(self.current_function.instructions.items.len + 1))));
                    try self.emit(.{ .jump = jump_back });
                    self.patchJump(exit_pos);
                }
            },
            else => return error.UnsupportedBytecode,
        }
    }

    fn compileMemoryOp(self: *Compiler, m: *const ast.MemoryOp) anyerror!void {
        switch (m.kind) {
            .address => { try self.compileExpression(m.expr); try self.emit(.{ .memory = {} }); },
            .dete => { try self.compileExpression(m.expr); },
        }
    }

    fn compileEncodingOp(self: *Compiler, eo: *const ast.EncodingOp) anyerror!void {
        try self.compileExpression(eo.expr);
        try self.emit(.{ .encode = {} });
        _ = eo.encoding_type;
    }

    fn compileLenOp(self: *Compiler, lo: *const ast.LenOp) anyerror!void {
        try self.compileExpression(lo.expr);
        try self.emit(.{ .len = {} });
    }

    fn compileClassInstantiation(_: *Compiler, _: ast.ClassInstantiation) anyerror!void {
        return error.UnsupportedBytecode;
    }

    fn emitJumpPlaceholder(self: *Compiler, op: bytecode.Op) anyerror!usize {
        const pos = self.current_function.instructions.items.len;
        switch (op) {
            .jump_if_false => try self.emit(.{ .jump_if_false = 0 }),
            else => try self.emit(.{ .jump = 0 }),
        }
        return pos;
    }

    fn patchJump(self: *Compiler, pos: usize) void {
        const target = self.current_function.instructions.items.len;
        const offset = @as(i32, @intCast(@as(isize, @intCast(target)) - @as(isize, @intCast(pos + 1))));
        const inst = self.current_function.instructions.items[pos];
        switch (inst) {
            .jump => self.current_function.instructions.items[pos] = .{ .jump = offset },
            .jump_if_false => self.current_function.instructions.items[pos] = .{ .jump_if_false = offset },
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
                const op: u8 = operator.binaryToOpcode(b.op);
                try self.emit(.{ .binary = op });
            },
            .unary => |u| {
                try self.compileExpression(u.expr);
                const op: u8 = operator.unaryToOpcode(u.op);
                try self.emit(.{ .unary = op });
            },
            .call => |c| {
                for (c.args) |arg| {
                    try self.compileExpression(&arg);
                }
                const callee_duped = try self.allocator.dupe(u8, c.callee);
                const idx = self.chunk.constants.items.len; try self.chunk.constants.append(.{ .string = callee_duped });
                try self.emit(.{ .call = @intCast((idx << 16) | c.args.len) });
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
            else => return error.UnsupportedBytecode,
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
        for (0..c.body.len) |i| {
            try self.compileStatement(&c.body[i]);
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
                const unescaped = try unescapeString(self.allocator, lit.raw);
                break :blk value_mod.Value{ .string = unescaped };
            },
            .bool_true => value_mod.Value{ .booling = true },
            .bool_false => value_mod.Value{ .booling = false },
            .none => value_mod.Value{ .none = {} },
            .tuple => value_mod.Value{ .null = {} },
            .dict => return error.UnsupportedBytecode,
        };
        const idx = self.chunk.constants.items.len; try self.chunk.constants.append(val);
        try self.emit(.{ .load_const = @intCast(idx) });
    }

    fn emit(self: *Compiler, inst: bytecode.Instruction) !void {
        try self.current_function.instructions.append(inst);
    }

};

fn unescapeString(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var result = std.array_list.Managed(u8).init(allocator);
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
                '0' => try result.append(0),
                else => {
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
