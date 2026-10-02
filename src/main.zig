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

const COMPLETION_COMMANDS = [_][]const u8{
    "run",
    "-install",
    "-list",
    "-search",
    "--version",
    "--help",
    "--generate-completion",
    "--generate-completion", // duplicate for consistency
};

fn unsupportedShell(it: std.process.Init, shell: []const u8) noreturn {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stderr().writer(it.io, &buf);
    const writer = &file_writer.interface;
    writer.print("Error: unsupported shell '{s}': expected bash, zsh, or fish\n", .{shell}) catch {};
    writer.flush() catch {};
    std.process.exit(1);
}

fn generateBashCompletion() []const u8 {
    return \\#!/usr/bin/env bash
\\#completion for ko
\\ko_completion() {
\\    local cur prev words cword
\\    _init_completion || return
\\
\\    case $prev in
\\        run|-install|-search)
\\            COMPREPLY=($(compgen -f -- "$cur"));;
\\        *)
\\            local commands
\\            commands=(run -install -list -search --version --help --generate-completion)
\\            COMPREPLY=($(compgen -W "${commands[*]}" -- "$cur"));;
\\    esac
\\}
\\complete -F ko_completion ko
;
}

fn generateZshCompletion() []const u8 {
    return \\#compdef ko
\\
\\ko() {
\\    local -a commands
\\    commands=(
\\        'run:run a .ko source file or inline code'
\\        '-install [library]:library to install'
\\        '-list:list all available libraries'
\\        '-search [query]:search libraries'
\\        '--version:print compiler version'
\\        '--help:print this help message'
\\        '--generate-completion [shell]:generate shell completion (bash, zsh, fish)'
\\    )
\\    _arguments -C $commands
\\}
\\compdef ko
;
}

fn generateFishCompletion() []const u8 {
    return \\# Fish completion for ko
\\complete -c ko -l generate-completion -s g -x -a 'bash zsh fish' -d 'Generate shell completion'
\\complete -c ko -l help -s h -x -d 'Print this help message'
\\complete -c ko -l version -x -d 'Print compiler version'
\\complete -c ko -l install -s i -x -a '(__fish_complete_path)' -d 'Install a library from the Module Store'
\\complete -c ko -l search -s s -x -a '(__fish_complete_path)' -d 'Search libraries by name'
\\complete -c ko -l list -x -d 'List all available libraries'
\\complete -c ko -l run -r -d 'Run a .ko source file or inline code'
;
}

fn printUsage(it: std.process.Init) void {
    var buf: [4096]u8 = undefined;
    var file_writer = std.Io.File.stdout().writer(it.io, &buf);
    const writer = &file_writer.interface;
    writer.print(
        \\Usage: ko <file.ko>
        \\       ko run <file|code>
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
        \\       ko run <file|code>
        \\       ko -install <library>
        \\       ko -list
        \\       ko -search <query>
        \\       ko --version
        \\       ko --help
        \\       ko --generate-completion <shell>
        \\
        \\Commands:
        \\  <file.ko>       Run a .ko source file
        \\  run <file|code>  Run a .ko source file, or run the argument as inline .ko code when it is not a file path (a .ko suffix or an existing file is treated as a file path)
        \\  -install <lib>  Install a library from the Module Store
        \\  -list           List all available libraries
        \\  -search <query> Search libraries by name
        \\  --version       Print compiler version
        \\  --help          Print this help message
        \\  --generate-completion <shell> Generate shell completion script (bash, zsh, fish)
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
        const arg = args[2];
        if (isFilePath(it.io, arg)) {
            const source = readSourceFile(allocator, it.io, arg) catch return 1;
            defer allocator.free(source);
            return try executeCode(allocator, it.io, source, arg);
        }
        return try executeCode(allocator, it.io, arg, "<repl>");
    }

    if (std.mem.eql(u8, args[1], "--generate-completion")) {
        if (args.len < 3) {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(it.io, &buf);
            const writer = &file_writer.interface;
            writer.print("Error: --generate-completion requires a shell: bash, zsh, or fish\n", .{}) catch {};
            writer.flush() catch {};
            return 1;
        }
        const script: []const u8 = if (std.mem.eql(u8, args[2], "bash"))
            generateBashCompletion()
        else if (std.mem.eql(u8, args[2], "zsh"))
            generateZshCompletion()
        else if (std.mem.eql(u8, args[2], "fish"))
            generateFishCompletion()
        else
            unsupportedShell(it, args[2]);
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(it.io, &buf);
        const writer = &file_writer.interface;
        writer.writeAll(script) catch {};
        writer.flush() catch {};
        return 0;
    }

    // Default: treat first arg as a .ko file path
    const file_path = args[1];
    const source = readSourceFile(allocator, it.io, file_path) catch return 1;
    defer allocator.free(source);

    return try executeCode(allocator, it.io, source, file_path);
}

fn readSourceFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(10 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(io, &buf);
            const writer = &file_writer.interface;
            writer.print("Error: file '{s}' not found\n", .{path}) catch {};
            writer.flush() catch {};
            return error.FileNotFound;
        },
        else => {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(io, &buf);
            const writer = &file_writer.interface;
            writer.print("Error: could not read file '{s}': {any}\n", .{ path, err }) catch {};
            writer.flush() catch {};
            return err;
        },
    };
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
        if (err == error.EndOfInput) {
            std.debug.print("InputError: end of input\n", .{});
            return 4;
        }
        std.debug.print("Runtime error: {any}\n", .{err});
        return 3;
    };

    return 0;
}

fn isFilePath(io: std.Io, arg: []const u8) bool {
    if (std.mem.endsWith(u8, arg, ".ko")) return true;
    const stat = std.Io.Dir.cwd().statFile(io, arg, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return false,
    };
    return stat.kind == .file;
}
