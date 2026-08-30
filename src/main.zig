const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const vm = @import("vm.zig");
const ast = @import("ast.zig");
const installer = @import("installer.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try std.io.getStdOut().writer().print("Usage: ko <file.ko>\n", .{});
        try std.io.getStdOut().writer().print("       ko -install <library>\n", .{});
        try std.io.getStdOut().writer().print("       ko -list\n", .{});
        try std.io.getStdOut().writer().print("       ko -search <query>\n", .{});
        return;
    }

    if (std.mem.eql(u8, args[1], "-install")) {
        if (args.len < 3) {
            try std.io.getStdErr().writer().print("Error: Please specify a library name\n", .{});
            return;
        }
        var inst = installer.Installer.init(allocator) catch |err| {
            try std.io.getStdErr().writer().print("Error initializing installer: {any}\n", .{err});
            return;
        };
        defer inst.deinit();

        inst.installLibrary(args[2]) catch |err| {
            try std.io.getStdErr().writer().print("Installation failed: {any}\n", .{err});
            try std.io.getStdErr().writer().print("Auto-purging failed installation...\n", .{});
        };
        return;
    }

    if (std.mem.eql(u8, args[1], "-list")) {
        var inst = installer.Installer.init(allocator) catch |err| {
            try std.io.getStdErr().writer().print("Error initializing installer: {any}\n", .{err});
            return;
        };
        defer inst.deinit();

        const libs = inst.listLibraries() catch |err| {
            try std.io.getStdErr().writer().print("Failed to list libraries: {any}\n", .{err});
            return;
        };
        defer allocator.free(libs);

        try std.io.getStdOut().writer().print("Available libraries in Module Store:\n", .{});
        for (libs) |lib| {
            try std.io.getStdOut().writer().print("  - {s}\n", .{lib});
        }
        return;
    }

    if (std.mem.eql(u8, args[1], "-search")) {
        if (args.len < 3) {
            try std.io.getStdErr().writer().print("Error: Please specify a search query\n", .{});
            return;
        }
        var inst = installer.Installer.init(allocator) catch |err| {
            try std.io.getStdErr().writer().print("Error initializing installer: {any}\n", .{err});
            return;
        };
        defer inst.deinit();

        const results = inst.searchLibraries(args[2]) catch |err| {
            try std.io.getStdErr().writer().print("Search failed: {any}\n", .{err});
            return;
        };
        defer allocator.free(results);

        try std.io.getStdOut().writer().print("Search results for '{s}':\n", .{args[2]});
        for (results) |lib| {
            try std.io.getStdOut().writer().print("  - {s}\n", .{lib});
        }
        return;
    }

    const file_path = args[1];
    const source = std.fs.cwd().readFileAlloc(allocator, file_path, 10 * 1024 * 1024) catch |err| {
        try std.io.getStdErr().writer().print("Error reading file: {any}\n", .{err});
        return;
    };
    defer allocator.free(source);

    var lx = lexer.Lexer.init(source);
    const tokens = lx.tokenize(allocator) catch |err| {
        try std.io.getStdErr().writer().print("Lexer error: {any}\n", .{err});
        return;
    };
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    const program = pr.parse() catch |err| {
        try std.io.getStdErr().writer().print("Parser error: {any}\n", .{err});
        return;
    };
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    var virtual_machine = try vm.VM.init(allocator);
    defer virtual_machine.deinit();

    virtual_machine.execute(program) catch |err| {
        try std.io.getStdErr().writer().print("Runtime error: {any}\n", .{err});
        return;
    };
}
