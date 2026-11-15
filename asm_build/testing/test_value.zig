const std = @import("std");
const value_mod = @import("src").value;
const Value = value_mod.Value;

test "value: int add overflow" {
    const v1 = Value{ .int = 9223372036854775807 };
    const v2 = Value{ .int = 1 };
    try std.testing.expectError(error.OverflowError, v1.add(v2, std.testing.allocator));
}

test "value: int add" {
    const v1 = Value{ .int = 2 };
    const v2 = Value{ .int = 3 };
    const r = try v1.add(v2, std.testing.allocator);
    defer {
        var rv = r;
        rv.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(i64, 5), r.int);
}

test "value: freal add" {
    const v1 = Value{ .freal = 1.5 };
    const v2 = Value{ .freal = 2.5 };
    const r = try v1.add(v2, std.testing.allocator);
    defer {
        var rv = r;
        rv.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(f64, 4.0), r.freal);
}

test "value: mixed add type error" {
    const v1 = Value{ .int = 1 };
    const v2 = Value{ .freal = 2.0 };
    try std.testing.expectError(error.TypeError, v1.add(v2, std.testing.allocator));
}

test "value: sub overflow" {
    const v1 = Value{ .int = -9223372036854775808 };
    const v2 = Value{ .int = 1 };
    try std.testing.expectError(error.OverflowError, v1.sub(v2));
}

test "value: mul overflow" {
    const v1 = Value{ .int = 9223372036854775807 };
    const v2 = Value{ .int = 2 };
    try std.testing.expectError(error.OverflowError, v1.mul(v2));
}

test "value: div by zero" {
    const v1 = Value{ .int = 10 };
    const v2 = Value{ .int = 0 };
    try std.testing.expectError(error.DivideByZero, v1.div(v2));
}

test "value: rem" {
    const v1 = Value{ .int = 10 };
    const v2 = Value{ .int = 3 };
    const r = try v1.rem(v2);
    defer {
        var rv = r;
        rv.deinit(std.testing.allocator);
    }
    try std.testing.expectEqual(@as(i64, 1), r.int);
}

test "value: rem type error" {
    const v1 = Value{ .freal = 10.0 };
    const v2 = Value{ .int = 3 };
    try std.testing.expectError(error.TypeError, v1.rem(v2));
}

test "value: string concat" {
    const alloc = std.testing.allocator;
    const v1 = Value{ .string = try alloc.dupe(u8, "ab") };
    const v2 = Value{ .string = try alloc.dupe(u8, "cd") };
    const r = try v1.add(v2, alloc);
    defer {
        var rv = r;
        rv.deinit(alloc);
        var a = v1;
        a.deinit(alloc);
        var b = v2;
        b.deinit(alloc);
    }
    try std.testing.expectEqualStrings("abcd", r.string);
}

test "value: list concat" {
    const alloc = std.testing.allocator;
    var items1 = [_]Value{Value{ .int = 1 }};
    var items2 = [_]Value{Value{ .int = 2 }};
    const v1 = Value{ .list = try alloc.dupe(Value, &items1) };
    const v2 = Value{ .list = try alloc.dupe(Value, &items2) };
    const r = try v1.add(v2, alloc);
    defer {
        var rv = r;
        rv.deinit(alloc);
        var a = v1;
        a.deinit(alloc);
        var b = v2;
        b.deinit(alloc);
    }
    try std.testing.expectEqual(@as(usize, 2), r.list.len);
    try std.testing.expectEqual(@as(i64, 1), r.list[0].int);
    try std.testing.expectEqual(@as(i64, 2), r.list[1].int);
}

test "value: equals strict" {
    const a = Value{ .int = 1 };
    const b = Value{ .freal = 1.0 };
    try std.testing.expectError(error.TypeError, a.equals(b));
    const c = Value{ .int = 1 };
    const d = Value{ .int = 1 };
    try std.testing.expect(try c.equals(d));
    const e = Value{ .freal = 2.0 };
    const f = Value{ .freal = 2.0 };
    try std.testing.expect(try e.equals(f));
}

test "value: less int" {
    const a = Value{ .int = 1 };
    const b = Value{ .int = 2 };
    try std.testing.expect(try a.less(b));
    try std.testing.expect(!(try b.less(a)));
}

test "value: greater freal" {
    const a = Value{ .freal = 3.0 };
    const b = Value{ .freal = 2.0 };
    try std.testing.expect(try a.greater(b));
}

test "value: lessOrEqual string" {
    const a = Value{ .string = "abc" };
    const b = Value{ .string = "abd" };
    try std.testing.expect(try a.lessOrEqual(b));
    try std.testing.expect(try a.lessOrEqual(a));
}

test "value: greaterOrEqual" {
    const a = Value{ .int = 5 };
    const b = Value{ .int = 5 };
    try std.testing.expect(try a.greaterOrEqual(b));
}

test "value: mixed comparison type error" {
    const a = Value{ .int = 1 };
    const b = Value{ .freal = 2.0 };
    try std.testing.expectError(error.TypeError, a.less(b));
    try std.testing.expectError(error.TypeError, a.greater(b));
    try std.testing.expectError(error.TypeError, a.lessOrEqual(b));
    try std.testing.expectError(error.TypeError, a.greaterOrEqual(b));
}
