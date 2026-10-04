const std = @import("std");

pub fn main() !void {
    var child = try std.process.Child.init(&[_][]const u8{"echo", "hello"}, std.heap.page_allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Ignore;
    
    try child.spawn();
    const term = try child.wait();
    
    std.debug.print("Process exited with: {}\n", .{term});
}
