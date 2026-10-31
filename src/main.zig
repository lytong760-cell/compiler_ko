const std = @import("std");
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");
const installer = @import("installer.zig");
const executor_mod = @import("executor.zig");

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

    if (std.mem.eql(u8, args[1], "-plugins")) {
        var buf: [4096]u8 = undefined;
        var file_writer = std.Io.File.stdout().writer(it.io, &buf);
        const writer = &file_writer.interface;
        writer.print("Plugin directories:\n", .{}) catch {};
        const dirs = [_][]const u8{ "libs", ".ko/plugins" };
        for (dirs) |d| {
            scanPluginDir(writer, it.io, d);
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

    if (std.mem.eql(u8, args[1], "build")) {
        if (args.len < 3) {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(it.io, &buf);
            const writer = &file_writer.interface;
            writer.print("Error: Please specify a .ko file to build\n", .{}) catch {};
            writer.flush() catch {};
            return 1;
        }
        const arg = args[2];
        const source = readSourceFile(allocator, it.io, arg) catch return 1;
        defer allocator.free(source);
        // validate
        const rc = executeCode(allocator, it.io, source, arg) catch 1;
        if (rc != 0) {
            var buf: [4096]u8 = undefined;
            var file_writer = std.Io.File.stderr().writer(it.io, &buf);
            const writer = &file_writer.interface;
            writer.print("Build failed with exit code {d}\n", .{rc}) catch {};
            writer.flush() catch {};
            return rc;
        }
        // create build dir + wrapper
        std.Io.Dir.cwd().createDirPath(it.io, "build") catch {};
        var name_buf: [256]u8 = undefined;
        const base = std.fs.path.basename(arg);
        const stem = if (std.mem.endsWith(u8, base, ".ko")) base[0 .. base.len - 3] else base;
        const out_name = std.fmt.bufPrint(&name_buf, "build/{s}", .{stem}) catch return 1;
        // write wrapper script
        var fbuf: [4096]u8 = undefined;
        var fw = std.Io.Dir.cwd().createFile(it.io, out_name, .{}) catch return 1;
        defer fw.close(it.io);
        _ = std.process.run(allocator, it.io, .{ .argv = &.{ "chmod", "+x", out_name } }) catch {};
        var w = fw.writer(it.io, &fbuf);
        const writer2 = &w.interface;
        writer2.print("#!/bin/sh\nexec ko run '{s}' \"$@\"\n", .{arg}) catch {};
        writer2.flush() catch {};
        // chmod +x
        // (best effort; ignore errors)
        var buf2: [4096]u8 = undefined;
        var fw2 = std.Io.File.stdout().writer(it.io, &buf2);
        const w2 = &fw2.interface;
        w2.print("Built: {s}\n", .{out_name}) catch {};
        w2.flush() catch {};
        return 0;
    }

    if (std.mem.eql(u8, args[1], "repl")) {
        return try runRepl(allocator, it.io);
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

fn scanPluginDir(writer: *std.Io.Writer, io: std.Io, path: []const u8) void {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return;
    defer dir.close(io);
    writer.print("  {s}:\n", .{path}) catch {};
    var iter = dir.iterate();
    while (iter.next(io) catch null) |entry| {
        if (entry.kind != .directory) continue;
        var mbuf: [4096]u8 = undefined;
        const manifest_path = std.fmt.bufPrint(&mbuf, "{s}/{s}/module.json", .{ path, entry.name }) catch continue;
        const data = std.Io.Dir.cwd().readFileAlloc(io, manifest_path, std.heap.page_allocator, .limited(64 * 1024)) catch continue;
        defer std.heap.page_allocator.free(data);
        writer.print("    - {s}\n", .{entry.name}) catch {};
    }
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

    var executor = try executor_mod.Executor.init(allocator, io, source_name, null);
    defer executor.deinit();

    const modules = try scanModuleStore(allocator, io);
    defer allocator.free(modules);
    for (modules) |mod| {
        _ = mod;
    }

    // Execution pipeline: bytecode backend with AST-walker fallback, hidden
    // behind the Executor module's single interface.
    executor.execute(program) catch |err| {
        if (err == error.EndOfInput) return 4;
        if (err == error.RuntimeError) return 3;
        return 3;
    };

    return 0;
}

fn runRepl(allocator: std.mem.Allocator, io: std.Io) !u8 {
    var stdin_buf: [4096]u8 = undefined;
    var file_reader = std.Io.File.stdin().reader(io, &stdin_buf);
    const reader = &file_reader.interface;

    var buf: [4096]u8 = undefined;
    var stdout_file = std.Io.File.stdout().writer(io, &buf);
    const out = &stdout_file.interface;

    var accum = std.array_list.Managed(u8).init(allocator);
    defer accum.deinit();

    var depth: i32 = 0;
    out.writeAll("ko repl (type 'exit' to quit)\n") catch {};
    out.flush() catch {};

    while (true) {
        out.writeAll(if (depth == 0) "ko> " else "... ") catch {};
        out.flush() catch {};

        const line = reader.takeDelimiterInclusive('\n') catch |err| switch (err) {
            error.EndOfStream => break,
            else => {
                std.debug.print("read error: {any}\n", .{err});
                return 1;
            },
        };

        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (depth == 0 and (std.mem.eql(u8, trimmed, "exit") or std.mem.eql(u8, trimmed, "quit"))) {
            break;
        }

        for (line) |c| {
            if (c == '[') depth += 1;
            if (c == ']') depth -= 1;
        }
        try accum.appendSlice(line);

        if (depth <= 0 and accum.items.len > 0) {
            // ensure at least one newline
            if (accum.items[accum.items.len - 1] != '\n') try accum.append('\n');
            const source = accum.items;
            const rc = executeCode(allocator, io, source, "<repl>") catch 1;
            if (rc != 0) std.debug.print("exit code: {d}\n", .{rc});
            accum.clearRetainingCapacity();
            depth = 0;
        }
    }
    out.writeAll("bye\n") catch {};
    out.flush() catch {};
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