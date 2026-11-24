const std = @import("std");
const ast = @import("ast.zig");
const vm_mod = @import("vm.zig");
const compiler_mod = @import("compiler.zig");
const bytecode_mod = @import("bytecode.zig");

pub const Backend = enum { bytecode, ast_walker };

pub const Executor = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    source_name: []const u8,
    vm: *vm_mod.VM,
    owns_vm: bool,
    backend_used: Backend = .ast_walker,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, source_name: []const u8, injected_vm: ?*vm_mod.VM) !Executor {
        const duped = try allocator.dupe(u8, source_name);
        errdefer allocator.free(duped);

        const owns = injected_vm == null;

        const vm_ptr = if (injected_vm) |v| v else blk: {
            const v = try allocator.create(vm_mod.VM);
            errdefer allocator.destroy(v);
            v.* = try vm_mod.VM.init(allocator, io, source_name);
            break :blk v;
        };
        errdefer if (owns) vm_ptr.deinit();

        return .{
            .allocator = allocator,
            .io = io,
            .source_name = duped,
            .vm = vm_ptr,
            .owns_vm = owns,
        };
    }

    pub fn deinit(self: *Executor) void {
        if (self.owns_vm) {
            self.vm.deinit();
            self.allocator.destroy(self.vm);
        }
        self.allocator.free(self.source_name);
    }

    pub fn backend(self: *const Executor) Backend {
        return self.backend_used;
    }

    pub fn setOutputWriter(self: *Executor, writer: *std.Io.Writer) void {
        self.vm.setOutputWriter(writer);
    }

    pub fn execute(self: *Executor, program: []ast.Statement) !void {
        if (!requiresAstWalker(program) and !hasImportStmt(program)) {
            var chunk = try bytecode_mod.Chunk.init(self.allocator);
            // Single owner: `defer` runs on every exit path, and `freed` guards
            // against the early frees below. Using `errdefer` here (the previous
            // shape) double-freed whenever a runtime error was returned after an
            // explicit chunk.deinit(): the errdefer fired on the same pointer a
            // second time, corrupting the heap (rc=134, SIGABRT).
            var freed = false;
            defer if (!freed) chunk.deinit(self.allocator);
            var comp = try compiler_mod.Compiler.init(self.allocator, &chunk, "main", 0);
            defer comp.deinit();
            if (comp.compileProgram(program)) |_| {
                self.vm.executeChunk(&chunk) catch |err| {
                    if (err == error.EndOfInput) {
                        std.debug.print("InputError: end of input\n", .{});
                        freed = true;
                        chunk.deinit(self.allocator);
                        return error.EndOfInput;
                    }
                    std.debug.print("Runtime error: {any}\n", .{err});
                    freed = true;
                    chunk.deinit(self.allocator);
                    return error.RuntimeError;
                };
                freed = true;
                chunk.deinit(self.allocator);
                self.backend_used = .bytecode;
                return;
            } else |err| {
                std.debug.print("Bytecode compile failed ({any}); falling back to AST walker\n", .{err});
            }
            freed = true;
            chunk.deinit(self.allocator);
        }

        self.backend_used = .ast_walker;
        self.vm.execute(program) catch |err| {
            if (err == error.EndOfInput) {
                std.debug.print("InputError: end of input\n", .{});
                return error.EndOfInput;
            }
            std.debug.print("Runtime error: {any}\n", .{err});
            return error.RuntimeError;
        };
    }
};


fn hasImportStmt(program: []ast.Statement) bool {
    for (program) |stmt| {
        switch (stmt) {
            .expr => |e| {
                if (e.* == .call and std.mem.eql(u8, e.call.callee, "Import")) return true;
            },
            .block => |b| {
                if (hasImportStmt(b.body)) return true;
            },
            else => {},
        }
    }
    return false;
}

fn requiresAstWalker(program: []ast.Statement) bool {
    for (program) |stmt| {
        switch (stmt) {
            .func_decl => return true,
            .class_decl => return true,
            .class_instantiation => return true,
            .catch_stmt => return true,
            .block => |b| {
                if (requiresAstWalker(b.body)) return true;
            },
            else => {},
        }
    }
    return false;
}