const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const vm = @import("vm.zig");

const TEST_PROGRAMS = [_][]const u8{
    \\[ int(10)~x ],
    \\[ string("hello")~s ],
    \\[ int(1)~a int(2)~b int(a + b)~sum ],
    \\[ <if>(1 == 1) [ <printf>^("ok") ] ],
    \\[ <printf>^("test\n") ],
    \\[ int(<len>^("hello"))~l ],
    \\[ booling(\True\)~flag ],
    \\[ byte(65)~b ],
    \\[ bytes(16)~buf ],
    \\[ int(10)~x <if>(x > 5) [ <printf>^("big") ] ],
    \\[ <catch>(`Error`) [ <printf>^("caught") ] ],
    \\[ int(100)~x int(50)~y int(x - y)~z ],
    \\[ freal(3.14)~pi ],
    \\[ int(0)~x int(0)~y int(x + y)~z ],
    \\[ int(10)~x int(5)~y int(x % y)~rem ],
};

test "test_3600_iterations" {
    const gpa = std.testing.allocator;
    var total_time: u64 = 0;
    var max_time: u64 = 0;
    var min_time: u64 = std.math.maxInt(u64);
    
    const iterations = 3600;
    const programs = TEST_PROGRAMS.len;
    
    for (0..iterations) |i| {
        const prog_idx = i % programs;
        const source = TEST_PROGRAMS[prog_idx];
        
        const start = std.time.nanoTimestamp();
        
        var lx = lexer.Lexer.init(source);
        const tokens = lx.tokenize(gpa) catch {
            continue;
        };
        defer gpa.free(tokens);
        
        var arena = std.heap.ArenaAllocator.init(gpa);
        defer arena.deinit();
        
        var pr = parser.Parser.init(gpa, &arena, tokens);
        const program = pr.parse() catch {
            continue;
        };
        defer {
            for (program) |*stmt| stmt.deinit();
        }
        
        var virtual_machine = vm.VM.init(gpa) catch {
            continue;
        };
        defer virtual_machine.deinit();
        
        virtual_machine.execute(program) catch {};
        
        const end = std.time.nanoTimestamp();
        const elapsed = @intCast(u64, end - start);
        total_time += elapsed;
        if (elapsed > max_time) max_time = elapsed;
        if (elapsed < min_time) min_time = elapsed;
    }
    
    const avg_time = total_time / iterations;
    std.debug.print("\n=== 3600 Iteration Benchmark ===\n", .{});
    std.debug.print("Total iterations: {d}\n", .{iterations});
    std.debug.print("Average time: {d} ns\n", .{avg_time});
    std.debug.print("Min time: {d} ns\n", .{min_time});
    std.debug.print("Max time: {d} ns\n", .{max_time});
    std.debug.print("Total time: {d} ms\n", .{total_time / 1_000_000});
}
