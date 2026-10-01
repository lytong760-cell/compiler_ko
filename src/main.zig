const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const vm = @import("vm.zig");
const ast = @import("ast.zig");
const installer = @import("installer.zig");

const ModuleManifest = struct {
    name: []const u8,
    version: []const u8,
    language: []const u8,
    builtin: bool,
    path: []const u8,
};

fn scanModuleStore(allocator: std.mem.Allocator, io: std.Io) ![]ModuleManifest {
    var manifests = std.array_list.Managed(ModuleManifest).init(allocator);
    errdefer manifests.deinit();

    var module_dir = std.Io.Dir.cwd();
    var dir = module_dir.openDir(io, "src/module", .{ .iterate = true }) catch return &.{};
    defer dir.close(io);
    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        if (entry.kind != .directory) continue;

        const manifest_path = try std.fmt.allocPrint(allocator, "src/module/{s}/module.json", .{entry.name});
        defer allocator.free(manifest_path);

        const content = dir.readFileAlloc(io, manifest_path, allocator, .limited(4096)) catch continue;
        defer allocator.free(content);

        var parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch continue;
        defer parsed.deinit();

        const obj = parsed.value.object;
        const name_val = obj.get("name") orelse continue;
        const version_val = obj.get("version") orelse continue;
        const language_val = obj.get("language") orelse continue;
        const builtin_val = obj.get("builtin") orelse std.json.Value{ .bool = false };

        const path = try std.fmt.allocPrint(allocator, "src/module/{s}", .{entry.name});
        defer allocator.free(path);

        const name = name_val.string;
        const version = version_val.string;
        const language = language_val.string;
        const builtin = builtin_val.bool;

        try manifests.append(ModuleManifest{
            .name = name,
            .version = version,
            .language = language,
            .builtin = builtin,
            .path = path,
        });
    }

    const result = try allocator.alloc(ModuleManifest, manifests.items.len);
    @memcpy(result, manifests.items);
    return result;
}

const VERSION = "0.1.0";

fn printUsage(it: std.process.Init) void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(it.io, &buf);
    const writer = &file_writer.interface;
    writer.print(
        \\Usage: ko <file.ko>
        \\       ko run <code>
        \\       ko -install <library>
        \\       ko -list
        \\       ko -search <query>
        \\       ko --version
        \\       ko --help
        \\       ko --generate-completion <bash|zsh|fish>
    , .{}) catch {};
    writer.flush() catch {};
}

fn printHelp(it: std.process.Init) void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(it.io, &buf);
    const writer = &file_writer.interface;
    writer.print(
        \\Usage: ko <file.ko>
        \\       ko run <code>
        \\       ko -install <library>
        \\       ko -list
        \\       ko -search <query>
        \\       ko --version
        \\       ko --help
        \\       ko --generate-completion <bash|zsh|fish>
        \\
        \\Commands:
        \\  <file.ko>       Run a .ko source file
        \\  run <code>      Run inline .ko code
        \\  -install <lib>  Install a library from the Module Store
        \\  -list           List all available libraries
        \\  -search <query> Search libraries by name
        \\  --version       Print compiler version
        \\  --help          Print this help message
        \\  --generate-completion <shell>  Output shell completion script
    , .{}) catch {};
    writer.flush() catch {};
}

pub fn main(it: std.process.Init) !void {
    const exit_code = mainInner(it) catch |err| {
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.stderr().writer(it.io, &buf);
        const writer = &file_writer.interface;
        writer.print("Error: {any}\n", .{err}) catch {};
        writer.flush() catch {};
        std.process.exit(1);
    };
    std.process.exit(exit_code);
}

fn mainInner(it: std.process.Init) !u8 {
    const allocator = it.arena.allocator();
    const args = try it.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        printUsage(it);
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.stderr().writer(it.io, &buf);
        const writer = &file_writer.interface;
        writer.print("Error: No command specified\n", .{}) catch {};
        writer.flush() catch {};
        return 1;
    }

    // Global flags
    if (std.mem.eql(u8, args[1], "--version")) {
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(it.io, &buf);
        const writer = &file_writer.interface;
        writer.print("ko {s}\n", .{VERSION}) catch {};
        writer.flush() catch {};
        return 0;
    }
    if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
        printHelp(it);
        return 0;
    }

    // Subcommands requiring at least one more arg
    if (std.mem.eql(u8, args[1], "-install")) {
        if (args.len < 3) {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(it.io, &buf);
            const writer = &file_writer.interface;
            writer.print("Error: Please specify a library name\n", .{}) catch {};
            writer.flush() catch {};
            return 1;
        }
        var inst = try installer.Installer.init(allocator, it.io, it.minimal.environ);
        defer inst.deinit();

        inst.installLibrary(args[2]) catch |err| {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(it.io, &buf);
            const writer = &file_writer.interface;
            writer.print("Installation failed: {any}\n", .{err}) catch {};
            writer.print("Auto-purging failed installation...\n", .{}) catch {};
            writer.flush() catch {};
            return 1;
        };
        return 0;
    }

    if (std.mem.eql(u8, args[1], "-list")) {
        const modules = scanModuleStore(allocator, it.io) catch |err| {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(it.io, &buf);
            const writer = &file_writer.interface;
            writer.print("Failed to scan module store: {any}\n", .{err}) catch {};
            writer.flush() catch {};
            return 1;
        };
        defer allocator.free(modules);

        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(it.io, &buf);
        const writer = &file_writer.interface;
        writer.print("Available modules in Module Store:\n", .{}) catch {};
        for (modules) |mod| {
            writer.print("  - {s} v{s} [{s}]\n", .{ mod.name, mod.version, mod.language }) catch {};
        }
        writer.flush() catch {};
        return 0;
    }

    if (std.mem.eql(u8, args[1], "-search")) {
        if (args.len < 3) {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(it.io, &buf);
            const writer = &file_writer.interface;
            writer.print("Error: Please specify a search query\n", .{}) catch {};
            writer.flush() catch {};
            return 1;
        }
        var inst = try installer.Installer.init(allocator, it.io, it.minimal.environ);
        defer inst.deinit();

        const results = inst.searchLibraries(args[2]) catch |err| {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(it.io, &buf);
            const writer = &file_writer.interface;
            writer.print("Search failed: {any}\n", .{err}) catch {};
            writer.flush() catch {};
            return 1;
        };
        defer allocator.free(results);

        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(it.io, &buf);
        const writer = &file_writer.interface;
        writer.print("Search results for '{s}':\n", .{args[2]}) catch {};
        for (results) |lib| {
            writer.print("  - {s}\n", .{lib}) catch {};
        }
        writer.flush() catch {};
        return 0;
    }

    if (std.mem.eql(u8, args[1], "run")) {
        if (args.len < 3) {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(it.io, &buf);
            const writer = &file_writer.interface;
            writer.print("Error: Please specify code to run\n", .{}) catch {};
            writer.flush() catch {};
            return 1;
        }
        const code = args[2];
        return try executeCode(allocator, it.io, code, "<repl>");
    }

    // Default: treat first arg as a .ko file path
    const file_path = args[1];
    const source = std.Io.Dir.cwd().readFileAlloc(it.io, file_path, allocator, .limited(10 * 1024 * 1024)) catch |err| {
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.stderr().writer(it.io, &buf);
        const writer = &file_writer.interface;
        writer.print("Error reading file: {any}\n", .{err}) catch {};
        writer.flush() catch {};
        return 1;
    };
    defer allocator.free(source);

    return try executeCode(allocator, it.io, source, file_path);
}

fn executeCode(allocator: std.mem.Allocator, io: std.Io, source: []const u8, source_name: []const u8) !u8 {
    var lx = lexer.Lexer.init(source);
    const tokens = blk: {
        const t = lx.tokenize(allocator) catch |err| {
            std.debug.print("Lexer error: {any}\n", .{err});
            return 2;
        };
        break :blk t;
    };
    defer allocator.free(tokens);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    var pr = parser.Parser.init(allocator, &arena, tokens);
    const program = pr.parse() catch |err| {
        std.debug.print("Parser error: {any}\n", .{err});
        return 2;
    };
    defer {
        for (program) |*stmt| stmt.deinit();
    }

    var virtual_machine = try vm.VM.init(allocator, io, source_name);
    defer virtual_machine.deinit();

    const modules = try scanModuleStore(allocator, io);
    defer allocator.free(modules);
    for (modules) |mod| {
        _ = mod;
    }

    virtual_machine.execute(program) catch |err| {
        std.debug.print("Runtime error: {any}\n", .{err});
        return 3;
    };

    return 0;
}
