const std = @import("std");
const value = @import("value.zig");

pub const Statement = union(enum) {
    var_decl: VarDecl,
    assignment: Assignment,
    func_decl: *FuncDecl,
    class_decl: *ClassDecl,
    control_flow: *ControlFlow,
    memory_op: *MemoryOp,
    encoding_op: *EncodingOp,
    len_op: *LenOp,
    return_stmt: *ReturnStmt,
    expr: *Expr,
    catch_stmt: *CatchStmt,
    block: BlockStmt,

    pub fn deinit(self: *Statement) void {
        switch (self.*) {
            .var_decl => |*v| v.deinit(),
            .assignment => |*a| a.deinit(),
            .func_decl => |f| f.deinit(),
            .class_decl => |c| c.deinit(),
            .control_flow => |c| c.deinit(),
            .memory_op => |m| m.deinit(),
            .encoding_op => |e| e.deinit(),
            .len_op => |l| l.deinit(),
            .return_stmt => |r| r.deinit(),
            .expr => |e| e.deinit(),
            .catch_stmt => |c| c.deinit(),
            .block => |b| b.deinit(),
        }
    }
};

pub const BlockStmt = struct {
    body: []Statement,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *BlockStmt) void {
        for (self.body) |*stmt| stmt.deinit();
        self.allocator.free(self.body);
    }
};

pub const VarDecl = struct {
    type_name: []const u8,
    value_expr: *Expr,
    name: []const u8,

    pub fn deinit(self: *VarDecl) void {
        self.value_expr.deinit();
    }
};

pub const Assignment = struct {
    target: *Expr,
    value_expr: *Expr,

    pub fn deinit(self: *Assignment) void {
        self.target.deinit();
        self.value_expr.deinit();
    }
};

pub const FuncDecl = struct {
    name: []const u8,
    params: []value.Param,
    body: []Statement,
    catch_stmts: []CatchStmt,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *FuncDecl) void {
        for (self.body) |*stmt| stmt.deinit();
        for (self.catch_stmts) |*c| c.deinit();
        self.allocator.free(self.params);
        self.allocator.free(self.body);
        self.allocator.free(self.catch_stmts);
    }
};

pub const ClassDecl = struct {
    name: []const u8,
    private_body: []Statement,
    public_body: []Statement,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ClassDecl) void {
        for (self.private_body) |*stmt| stmt.deinit();
        for (self.public_body) |*stmt| stmt.deinit();
        self.allocator.free(self.private_body);
        self.allocator.free(self.public_body);
    }
};

pub const ControlFlow = struct {
    kind: Kind,
    condition: *Expr,
    body: []Statement,
    elifs: []Elif,
    else_body: []Statement,
    allocator: std.mem.Allocator,

    pub const Kind = enum { if_stmt, elif_stmt, else_stmt, for_loop, while_loop };

    pub fn deinit(self: *ControlFlow) void {
        self.condition.deinit();
        for (self.body) |*stmt| stmt.deinit();
        for (self.elifs) |*e| e.deinit();
        for (self.else_body) |*stmt| stmt.deinit();
        self.allocator.free(self.body);
        self.allocator.free(self.elifs);
        self.allocator.free(self.else_body);
    }
};

pub const Elif = struct {
    condition: *Expr,
    body: []Statement,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Elif) void {
        self.condition.deinit();
        for (self.body) |*stmt| stmt.deinit();
        self.allocator.free(self.body);
    }
};

pub const MemoryOp = struct {
    kind: Kind,
    expr: *Expr,

    pub const Kind = enum { address, dete };

    pub fn deinit(self: *MemoryOp) void {
        self.expr.deinit();
    }
};

pub const EncodingOp = struct {
    encoding_type: []const u8,
    expr: *Expr,

    pub fn deinit(self: *EncodingOp) void {
        self.expr.deinit();
    }
};

pub const LenOp = struct {
    expr: *Expr,

    pub fn deinit(self: *LenOp) void {
        self.expr.deinit();
    }
};

pub const ReturnStmt = struct {
    expr: *Expr,

    pub fn deinit(self: *ReturnStmt) void {
        self.expr.deinit();
    }
};

pub const CatchStmt = struct {
    error_type: []const u8,
    body: []Statement,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *CatchStmt) void {
        for (self.body) |*stmt| stmt.deinit();
        self.allocator.free(self.body);
    }
};

pub const Expr = union(enum) {
    literal: Literal,
    identifier: []const u8,
    binary: *BinaryExpr,
    unary: *UnaryExpr,
    call: *CallExpr,
    member_access: *MemberAccess,
    index_access: *IndexAccess,
    system_tag: *SystemTagExpr,
    input_expr: *InputExpr,
    now_expr: *NowExpr,

    pub fn deinit(self: *Expr) void {
        switch (self.*) {
            .binary => |b| b.deinit(),
            .unary => |u| u.deinit(),
            .call => |c| c.deinit(),
            .member_access => |m| m.deinit(),
            .index_access => |i| i.deinit(),
            .system_tag => |s| s.deinit(),
            .input_expr => |i| i.deinit(),
            .now_expr => |n| n.deinit(),
            else => {},
        }
    }
};

pub const Literal = struct {
    kind: Kind,
    raw: []const u8,

    pub const Kind = enum { int, freal, string, bool_true, bool_false, tuple, dict };
};

pub const BinaryExpr = struct {
    op: Op,
    left: *Expr,
    right: *Expr,

    pub const Op = enum { add, sub, mul, div, rem, logical_and, logical_or, eq, neq, lt, gt, lte, gte };

    pub fn deinit(self: *BinaryExpr) void {
        self.left.deinit();
        self.right.deinit();
    }
};

pub const UnaryExpr = struct {
    op: Op,
    expr: *Expr,

    pub const Op = enum { neg, not };

    pub fn deinit(self: *UnaryExpr) void {
        self.expr.deinit();
    }
};

pub const CallExpr = struct {
    callee: []const u8,
    args: []Expr,

    pub fn deinit(self: *CallExpr) void {
        for (self.args) |*arg| arg.deinit();
    }
};

pub const MemberAccess = struct {
    object: *Expr,
    member: []const u8,

    pub fn deinit(self: *MemberAccess) void {
        self.object.deinit();
    }
};

pub const IndexAccess = struct {
    object: *Expr,
    index: *Expr,

    pub fn deinit(self: *IndexAccess) void {
        self.object.deinit();
        self.index.deinit();
    }
};

pub const SystemTagExpr = struct {
    tag: []const u8,
    args: []Expr,

    pub fn deinit(self: *SystemTagExpr) void {
        for (self.args) |*arg| arg.deinit();
    }
};

pub const InputExpr = struct {
    target: ?*Expr,

    pub fn deinit(self: *InputExpr) void {
        if (self.target) |t| t.deinit();
    }
};

pub const NowExpr = struct {
    expr: *Expr,

    pub fn deinit(self: *NowExpr) void {
        self.expr.deinit();
    }
};
