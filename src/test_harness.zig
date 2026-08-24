const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const vm = @import("vm.zig");

fn runSource(allocator: std.mem.Allocator, source: []const u8) !void {
    var lx = lexer.Lexer.init(source);
    const tokens = try lx.tokenize(allocator);
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    const program = try pr.parse();

    var virtual_machine = try vm.VM.init(allocator);
    defer virtual_machine.deinit();

    try virtual_machine.execute(program);
}

const TEST_PROGRAMS = [_][]const u8{
    "[ int(10)~x ]",
    "[ string(\"hello\")~s ]",
    "[ int(1)~a int(2)~b int(a + b)~sum ]",
    "[ <if>(1 == 1) [ <printf>^(\"ok\") ] ]",
    "[ <printf>^(\"test\n\") ]",
    "[ int(<len>^(\"hello\"))~l ]",
    "[ booling(\\True\\)~flag ]",
    "[ byte(65)~b ]",
    "[ bytes(16)~buf ]",
    "[ int(10)~x <if>(x > 5) [ <printf>^(\"big\") ] ]",
    "[ <catch>(`Error`) [ <printf>^(\"caught\") ] ]",
    "[ int(100)~x int(50)~y int(x - y)~z ]",
    "[ freal(3.14)~pi ]",
    "[ int(0)~x int(0)~y int(x + y)~z ]",
    "[ int(10)~x int(5)~y int(x % y)~rem ]",
};

test "test_3600_iterations" {
    const gpa = std.testing.allocator;
    var total_time: u64 = 0;
    var max_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    var success_count: usize = 0;
    
    const iterations = 3600;
    const programs = TEST_PROGRAMS.len;
    
    for (0..iterations) |i| {
        const prog_idx = i % programs;
        const source = TEST_PROGRAMS[prog_idx];
        
        const start = std.time.nanoTimestamp();
        
        runSource(gpa, source) catch {
            continue;
        };
        
        const end = std.time.nanoTimestamp();
        const elapsed_i128 = end - start;
        const elapsed: u64 = @intCast(elapsed_i128);
        total_time += elapsed;
        if (elapsed > max_time) max_time = elapsed;
        if (elapsed < min_time) min_time = elapsed;
        success_count += 1;
    }
    
    const avg_time = if (success_count > 0) total_time / success_count else 0;
    std.debug.print("\n=== 3600 Iteration Benchmark ===\n", .{});
    std.debug.print("Successful iterations: {d}/{d}\n", .{success_count, iterations});
    std.debug.print("Average time: {d} ns\n", .{avg_time});
    std.debug.print("Min time: {d} ns\n", .{min_time});
    std.debug.print("Max time: {d} ns\n", .{max_time});
    std.debug.print("Total time: {d} ms\n", .{total_time / 1_000_000});
}
