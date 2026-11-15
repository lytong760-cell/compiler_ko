const std = @import("std");
const ast = @import("ast.zig");
const value_mod = @import("value.zig");

pub const BinaryOp = ast.BinaryExpr.Op;
pub const UnaryOp = ast.UnaryExpr.Op;

pub fn applyBinary(op: BinaryOp, left: value_mod.Value, right: value_mod.Value, allocator: std.mem.Allocator) !value_mod.Value {
    return switch (op) {
        .add => try left.add(right, allocator),
        .sub => try left.sub(right),
        .mul => try left.mul(right),
        .div => try left.div(right),
        .rem => try left.rem(right),
        .logical_and => value_mod.Value{ .booling = (try left.toBool()) and (try right.toBool()) },
        .logical_or => value_mod.Value{ .booling = (try left.toBool()) or (try right.toBool()) },
        .eq => value_mod.Value{ .booling = try left.equals(right) },
        .neq => value_mod.Value{ .booling = !(try left.equals(right)) },
        .lt => value_mod.Value{ .booling = try left.less(right) },
        .gt => value_mod.Value{ .booling = try left.greater(right) },
        .lte => value_mod.Value{ .booling = try left.lessOrEqual(right) },
        .gte => value_mod.Value{ .booling = try left.greaterOrEqual(right) },
    };
}

pub fn applyUnary(op: UnaryOp, val: value_mod.Value) !value_mod.Value {
    return switch (op) {
        .neg => switch (val) {
            .int => |i| value_mod.Value{ .int = -i },
            .freal => |f| value_mod.Value{ .freal = -f },
            else => error.TypeError,
        },
        .not => value_mod.Value{ .booling = !(try val.toBool()) },
    };
}

pub fn binaryToOpcode(op: BinaryOp) u8 {
    return switch (op) {
        .add => 0,
        .sub => 1,
        .mul => 2,
        .div => 3,
        .rem => 4,
        .logical_and => 5,
        .logical_or => 6,
        .eq => 7,
        .neq => 8,
        .lt => 9,
        .gt => 10,
        .lte => 11,
        .gte => 12,
    };
}

pub fn binaryFromOpcode(code: u8) !BinaryOp {
    return switch (code) {
        0 => .add,
        1 => .sub,
        2 => .mul,
        3 => .div,
        4 => .rem,
        5 => .logical_and,
        6 => .logical_or,
        7 => .eq,
        8 => .neq,
        9 => .lt,
        10 => .gt,
        11 => .lte,
        12 => .gte,
        else => error.TypeError,
    };
}

pub fn unaryToOpcode(op: UnaryOp) u8 {
    return switch (op) {
        .neg => 0,
        .not => 1,
    };
}

pub fn unaryFromOpcode(code: u8) !UnaryOp {
    return switch (code) {
        0 => .neg,
        1 => .not,
        else => error.TypeError,
    };
}

pub fn applyBinaryOpcode(code: u8, left: value_mod.Value, right: value_mod.Value, allocator: std.mem.Allocator) !value_mod.Value {
    const op = try binaryFromOpcode(code);
    return applyBinary(op, left, right, allocator);
}

pub fn applyUnaryOpcode(code: u8, val: value_mod.Value) !value_mod.Value {
    const op = try unaryFromOpcode(code);
    return applyUnary(op, val);
}