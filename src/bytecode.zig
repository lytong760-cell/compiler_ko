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
    call_method,
    ret,
    print,
    input,
    now,
    len,
    memory,
    encode,
    make_dict,
    dict_set,
    catch_start,
    catch_end,
    import,
    get_member,
    index_access,
    class_decl_start,
    class_decl_private_done,
    class_decl_finish,
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
    call_method: u32,
    ret: void,
    print: void,
    input: void,
    now: void,
    len: void,
    memory: void,
    encode: void,
    make_dict: void,
    dict_set: void,
    catch_start: u32,
    catch_end: void,
    import: void,
    get_member: void,
    index_access: void,
    class_decl_start: u32,
    class_decl_private_done: void,
    class_decl_finish: void,
};

pub const Function = struct {
    name: []const u8,
    params: [][]const u8,
    instructions: std.array_list.Managed(Instruction),
    arity: u32,

    pub fn deinit(self: *Function, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        for (self.params) |p| allocator.free(p);
        if (self.params.len > 0) allocator.free(self.params);
        self.instructions.deinit();
    }
};

pub const Chunk = struct {
    functions: std.array_list.Managed(Function),
    constants: std.array_list.Managed(value_mod.Value),

    pub fn init(allocator: std.mem.Allocator) !Chunk {
        return .{
            .functions = std.array_list.Managed(Function).init(allocator),
            .constants = std.array_list.Managed(value_mod.Value).init(allocator),
        };
    }

    pub fn deinit(self: *Chunk, allocator: std.mem.Allocator) void {
        for (self.functions.items) |*f| f.deinit(allocator);
        self.functions.deinit();
        for (self.constants.items) |*c| c.deinit(allocator);
        self.constants.deinit();
    }
};
