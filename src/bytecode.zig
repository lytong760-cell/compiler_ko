const std = @import("std");
const value_mod = @import("value.zig");

pub const Op = enum(u8) {
    load_const,
    load_var,
    store_var,
    binary,
    unary,
    jump,
    jump_if_false,
    call,
    ret,
    print,
    input,
    now,
    len,
    memory,
    encode,
    catch_start,
    catch_end,
    import,
};

pub const Instruction = union(Op) {
    load_const: usize,
    load_var: usize,
    store_var: usize,
    binary: u8,
    unary: u8,
    jump: i32,
    jump_if_false: i32,
    call: u32,
    ret: void,
    print: void,
    input: void,
    now: void,
    len: void,
    memory: void,
    encode: void,
    catch_start: u32,
    catch_end: void,
    import: void,
};

pub const Function = struct {
    name: []const u8,
    instructions: std.array_list.Managed(Instruction),
    arity: u32,

    pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.instructions.deinit();
    }
};

pub const Chunk = struct {
    functions: std.array_list.Managed(Function),
    constants: std.array_list.Managed(value_mod.Value),

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        for (self.functions.items) |*f| f.deinit(allocator);
        self.functions.deinit();
        for (self.constants.items) |*c| c.deinit(allocator);
        self.constants.deinit();
    }
};
