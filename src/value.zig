const std = @import("std");
const ast = @import("ast.zig");

pub const Value = union(enum) {
    null,
    int: i64,
    freal: f64,
    string: []const u8,
    booling: bool,
    byte: u8,
    bytes: []u8,
    tuple: []Value,
    list: []Value,
    dict: std.StringHashMap(Value),
    function: *Function,
    class_instance: *ClassInstance,
    error_obj: *ErrorObj,

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .bytes => allocator.free(self.bytes),
            .tuple, .list => {
                for (self.tuple) |*v| v.deinit(allocator);
                allocator.free(self.tuple);
            },
            .dict => {
                var iter = self.dict.iterator();
                while (iter.next()) |entry| {
                    allocator.free(entry.key_ptr.*);
                    entry.value_ptr.*.deinit(allocator);
                }
                self.dict.deinit();
            },
            .function => {},
            .class_instance => {
                self.class_instance.deinit();
            },
            .error_obj => {
                allocator.free(self.error_obj.code);
            },
            else => {},
        }
        self.* = .null;
    }

    pub fn format(self: Value, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try self.print(writer);
    }

    pub fn print(self: Value, writer: anytype) !void {
        switch (self) {
            .null => try writer.print("null", .{}),
            .int => |v| try writer.print("{d}", .{v}),
            .freal => |v| try writer.print("{d}", .{v}),
            .string => |v| try writer.print("{s}", .{v}),
            .booling => |v| try writer.print("{?s}", .{if (v) "True" else "False"}),
            .byte => |v| try writer.print("{b:0>8}", .{v}),
            .bytes => |v| {
                try writer.print("[", .{});
                for (v, 0..) |b, i| {
                    if (i > 0) try writer.print(", ", .{});
                    try writer.print("0x{X:0>2}", .{b});
                }
                try writer.print("]", .{});
            },
            .tuple, .list => |v| {
                try writer.print("(", .{});
                for (v, 0..) |item, i| {
                    if (i > 0) try writer.print(", ", .{});
                    try item.print(writer);
                }
                try writer.print(")", .{});
            },
            .dict => |d| {
                try writer.print("{{", .{});
                var iter = d.iterator();
                var first = true;
                while (iter.next()) |entry| {
                    if (!first) try writer.print(", ", .{});
                    try writer.print("{s}: ", .{entry.key_ptr.*});
                    try entry.value_ptr.print(writer);
                    first = false;
                }
                try writer.print("}}", .{});
            },
            .function => |f| try writer.print("<function {s}>", .{f.name}),
            .class_instance => |ci| try writer.print("<{s} instance>", .{ci.class_name}),
            .error_obj => |e| try writer.print("<Error {s}: {s}>", .{ e.type, e.code }),
        }
    }

    pub fn toBool(self: Value) !bool {
        return switch (self) {
            .booling => |b| b,
            .int => |i| i != 0,
            .freal => |f| f != 0.0,
            .string => |s| s.len > 0,
            .byte => |b| b != 0,
            .bytes => |b| b.len > 0,
            .tuple, .list => |v| v.len > 0,
            .dict => |d| d.count() > 0,
            .null => false,
            else => error.TypeError,
        };
    }

    pub fn equals(self: Value, other: Value) !bool {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| a == b,
                .freal => |b| @as(f64, @floatFromInt(a)) == b,
                else => error.TypeError,
            },
            .freal => |a| switch (other) {
                .freal => |b| a == b,
                .int => |b| a == @as(f64, @floatFromInt(b)),
                else => error.TypeError,
            },
            .string => |a| switch (other) {
                .string => |b| std.mem.eql(u8, a, b),
                else => error.TypeError,
            },
            .booling => |a| switch (other) {
                .booling => |b| a == b,
                else => error.TypeError,
            },
            .byte => |a| switch (other) {
                .byte => |b| a == b,
                else => error.TypeError,
            },
            .tuple, .list => |a| switch (other) {
                .tuple, .list => |b| {
                    if (a.len != b.len) return false;
                    for (a, b) |av, bv| {
                        if (!try av.equals(bv)) return false;
                    }
                    return true;
                },
                else => error.TypeError,
            },
            .dict => |a| switch (other) {
                .dict => |b| {
                    if (a.count() != b.count()) return false;
                    var iter = a.iterator();
                    while (iter.next()) |entry| {
                        const bv = b.get(entry.key_ptr.*) orelse return false;
                        if (!try entry.value_ptr.*.equals(bv)) return false;
                    }
                    return true;
                },
                else => error.TypeError,
            },
            else => error.TypeError,
        };
    }

    pub fn add(self: Value, other: Value, allocator: std.mem.Allocator) !Value {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| Value{ .int = a + b },
                .freal => |b| Value{ .freal = @as(f64, @floatFromInt(a)) + b },
                else => error.TypeError,
            },
            .freal => |a| switch (other) {
                .freal => |b| Value{ .freal = a + b },
                .int => |b| Value{ .freal = a + @as(f64, @floatFromInt(b)) },
                else => error.TypeError,
            },
            .string => |a| switch (other) {
                .string => |b| Value{ .string = try std.fmt.allocPrint(allocator, "{s}{s}", .{ a, b }) },
                else => error.TypeError,
            },
            .tuple, .list => |a| switch (other) {
                .tuple, .list => |b| {
                    const result = try allocator.alloc(Value, a.len + b.len);
                    @memcpy(result[0..a.len], a);
                    @memcpy(result[a.len..], b);
                    return Value{ .list = result };
                },
                else => error.TypeError,
            },
            else => error.TypeError,
        };
    }

    pub fn sub(self: Value, other: Value) !Value {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| Value{ .int = a - b },
                .freal => |b| Value{ .freal = @as(f64, @floatFromInt(a)) - b },
                else => error.TypeError,
            },
            .freal => |a| switch (other) {
                .freal => |b| Value{ .freal = a - b },
                .int => |b| Value{ .freal = a - @as(f64, @floatFromInt(b)) },
                else => error.TypeError,
            },
            else => error.TypeError,
        };
    }

    pub fn mul(self: Value, other: Value) !Value {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| Value{ .int = a * b },
                .freal => |b| Value{ .freal = @as(f64, @floatFromInt(a)) * b },
                else => error.TypeError,
            },
            .freal => |a| switch (other) {
                .freal => |b| Value{ .freal = a * b },
                .int => |b| Value{ .freal = a * @as(f64, @floatFromInt(b)) },
                else => error.TypeError,
            },
            else => error.TypeError,
        };
    }

    pub fn div(self: Value, other: Value) !Value {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| blk: {
                    if (b == 0) break :blk error.DivideByZero;
                    break :blk Value{ .int = @divTrunc(a, b) };
                },
                .freal => |b| Value{ .freal = @as(f64, @floatFromInt(a)) / b },
                else => error.TypeError,
            },
            .freal => |a| switch (other) {
                .freal => |b| Value{ .freal = a / b },
                .int => |b| Value{ .freal = a / @as(f64, @floatFromInt(b)) },
                else => error.TypeError,
            },
            else => error.TypeError,
        };
    }

    pub fn rem(self: Value, other: Value) !Value {
        return switch (self) {
            .int => |a| switch (other) {
                .int => |b| blk: {
                    if (b == 0) break :blk error.DivideByZero;
                    break :blk Value{ .int = @rem(a, b) };
                },
                else => error.TypeError,
            },
            else => error.TypeError,
        };
    }
};

pub const Function = struct {
    name: []const u8,
    params: []Param,
    body_ptr: *anyopaque,
    body_len: usize,
    catch_stmts: []ast.CatchStmt,
    closure_scope: ?*Scope,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Function) void {
        self.allocator.free(self.params);
        const body_slice = @as([*]ast.Statement, @ptrCast(@alignCast(self.body_ptr)))[0..self.body_len];
        self.allocator.free(body_slice);
        for (self.catch_stmts) |*c| c.deinit();
        self.allocator.free(self.catch_stmts);
    }
};

pub const Param = struct {
    type_name: []const u8,
    name: []const u8,
};

pub const ClassInstance = struct {
    class_name: []const u8,
    fields: std.StringHashMap(Value),
    methods: std.StringHashMap(*Function),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ClassInstance) void {
        var iter = self.fields.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.fields.deinit();
        var miter = self.methods.iterator();
        while (miter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.methods.deinit();
        self.allocator.free(self.class_name);
        self.allocator.destroy(self);
    }
};

pub const ErrorObj = struct {
    type: []const u8,
    code: []const u8,
    line: usize,
};

pub const Scope = struct {
    parent: ?*Scope,
    variables: std.StringHashMap(Value),
    classes: std.StringHashMap(*ClassDef),
    functions: std.StringHashMap(*Function),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, parent: ?*Scope) Scope {
        return .{
            .parent = parent,
            .variables = std.StringHashMap(Value).init(allocator),
            .classes = std.StringHashMap(*ClassDef).init(allocator),
            .functions = std.StringHashMap(*Function).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Scope) void {
        var iter = self.variables.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.variables.deinit();
        var citer = self.classes.iterator();
        while (citer.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }
        self.classes.deinit();
        var fiter = self.functions.iterator();
        while (fiter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
        }
        self.functions.deinit();
    }
};

pub const ClassDef = struct {
    name: []const u8,
    private_fields: std.StringHashMap(Value),
    private_methods: std.StringHashMap(*Function),
    public_fields: std.StringHashMap(Value),
    public_methods: std.StringHashMap(*Function),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ClassDef) void {
        var iter = self.private_fields.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.private_fields.deinit();
        var miter = self.private_methods.iterator();
        while (miter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.private_methods.deinit();
        var piter = self.public_fields.iterator();
        while (piter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit(self.allocator);
        }
        self.public_fields.deinit();
        var pmiter = self.public_methods.iterator();
        while (pmiter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            entry.value_ptr.*.deinit();
            self.allocator.destroy(entry.value_ptr.*);
        }
        self.public_methods.deinit();
    }
};
