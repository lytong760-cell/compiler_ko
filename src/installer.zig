const std = @import("std");

const FIRESTORE_BASE = "https://firestore.googleapis.com/v1/projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents";
const FIRESTORE_PARENT = "projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents";

fn getApiKey(environ_map: std.process.Environ.Map) ![]const u8 {
    if (environ_map.get("KO_FIRESTORE_API_KEY")) |key| {
        return key;
    } else {
        return error.MissingApiKey;
    }
}

pub const Installer = struct {
    allocator: std.mem.Allocator,
    temp_dir: []const u8,
    environ_map: std.process.Environ.Map,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, environ: std.process.Environ) !Installer {
        const temp_dir = try std.fmt.allocPrint(allocator, "/tmp/.ko_temp_{d}", .{std.posix.getppid()});
        try std.Io.Dir.cwd().createDirPath(io, temp_dir);
        const environ_map = try std.process.Environ.createMap(environ, allocator);
        return .{
            .allocator = allocator,
            .temp_dir = temp_dir,
            .environ_map = environ_map,
            .io = io,
        };
    }

    pub fn deinit(self: *Installer) void {
        self.cleanup() catch {};
        self.allocator.free(self.temp_dir);
        self.environ_map.deinit();
    }

    pub fn installLibrary(self: *Installer, lib_name: []const u8) !void {
        std.debug.print("Installing library: {s}...\n", .{lib_name});

        const github_url = try self.queryLibraryMetadata(lib_name);
        defer self.allocator.free(github_url);
        std.debug.print("GitHub URL: {s}\n", .{github_url});

        try self.cloneRepo(github_url);
        try self.inspectAndFilterZip();
        const lang = try self.detectLanguage();
        std.debug.print("Detected language: {s}\n", .{lang});

        try self.compileAndLink(lang);
        try self.registerScope(lib_name);

        std.debug.print("Library {s} installed successfully!\n", .{lib_name});
    }

    pub fn listLibraries(self: *Installer) ![]const []const u8 {
        std.debug.print("Querying all libraries from Module Store...\n", .{});

        const api_key = try getApiKey(self.environ_map);
        defer self.allocator.free(api_key);

        const url = try std.fmt.allocPrint(self.allocator, "{s}:runQuery?key={s}", .{
            FIRESTORE_BASE,
            api_key,
        });
        defer self.allocator.free(url);

        const post_body = try std.fmt.allocPrint(self.allocator,
            \\{{"parent": "{s}", "query": {{"from": [{{"collectionId": "libraries"}}]}}}}
            , .{FIRESTORE_PARENT});
        defer self.allocator.free(post_body);

        const result = std.process.run(self.allocator, self.io, .{
            .argv = &.{ "curl", "-s", "-X", "POST", "-H", "Content-Type: application/json", "-d", post_body, url },
        }) catch |err| {
            std.debug.print("curl failed: {any}\n", .{err});
            return error.CommandFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.stdout.len == 0) {
            std.debug.print("No libraries found or empty response.\n", .{});
            return &[_][]const u8{};
        }

        var list = std.array_list.Managed([]const u8).init(self.allocator);
        defer list.deinit();

        var iter = std.mem.splitSequence(u8, result.stdout, "\"name\":");
        var count: usize = 0;
        while (iter.next()) |part| {
            if (count == 0) {
                count += 1;
                continue;
            }
            var name_iter = std.mem.splitSequence(u8, part, "\"");
            if (name_iter.next()) |_| {
                if (name_iter.next()) |doc_name| {
                    const trimmed = std.mem.trim(u8, doc_name, " ,\n\r");
                    const lib_name_start = std.mem.lastIndexOf(u8, trimmed, "/") orelse 0;
                    if (lib_name_start < trimmed.len) {
                        const lib_name = trimmed[lib_name_start + 1 ..];
                        if (lib_name.len > 0) {
                            try list.append(lib_name);
                        }
                    }
                }
            }
        }

        const result_slice = try self.allocator.alloc([]const u8, list.items.len);
        @memcpy(result_slice, list.items);
        return result_slice;
    }

    pub fn searchLibraries(self: *Installer, query: []const u8) ![]const []const u8 {
        std.debug.print("Searching libraries for: {s}...\n", .{query});

        const all_libs = try self.listLibraries();
        defer self.allocator.free(all_libs);

        var matches = std.array_list.Managed([]const u8).init(self.allocator);
        defer matches.deinit();

        for (all_libs) |lib| {
            if (std.mem.indexOfPos(u8, lib, 0, query) != null) {
                try matches.append(lib);
            }
        }

        const result_slice = try self.allocator.alloc([]const u8, matches.items.len);
        @memcpy(result_slice, matches.items);
        return result_slice;
    }

    fn queryLibraryMetadata(self: *Installer, lib_name: []const u8) ![]const u8 {
        const api_key = try getApiKey(self.environ_map);
        defer self.allocator.free(api_key);

        const url = try std.fmt.allocPrint(self.allocator, "{s}/libraries/{s}?key={s}", .{
            FIRESTORE_BASE,
            lib_name,
            api_key,
        });
        defer self.allocator.free(url);

        const result = std.process.run(self.allocator, self.io, .{
            .argv = &.{"curl", "-s", url},
        }) catch |err| {
            std.debug.print("curl failed: {any}\n", .{err});
            return error.CommandFailed;
        };
        defer self.allocator.free(result.stdout);

        var github_url = try self.extractStringField(result.stdout, "githubLink");
        if (github_url.len == 0) {
            github_url = try self.extractStringField(result.stdout, "githubUrl");
        }
        if (github_url.len == 0) {
            return error.LibraryNotFound;
        }
        const duped = try self.allocator.dupe(u8, github_url);
        return duped;
    }

    fn cloneRepo(self: *Installer, repo_url: []const u8) !void {
        std.debug.print("Cloning repository: {s}\n", .{repo_url});
        _ = try self.runCommand(&.{"git", "clone", repo_url, self.temp_dir});
    }

    fn inspectAndFilterZip(self: *Installer) !void {
        var dir = try std.Io.Dir.cwd().openDir(self.io, self.temp_dir, .{ .iterate = true });
        defer dir.close(self.io);

        var found_zip = false;
        var iter = dir.iterate();
        while (try iter.next(self.io)) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zip")) {
                found_zip = true;
                break;
            }
        }

        if (!found_zip) {
            std.debug.print("No .zip file found in repository. Purging...\n", .{});
            try self.cleanup();
            return error.NoZipFile;
        }

        var iter2 = dir.iterate();
        while (try iter2.next(self.io)) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".zip")) {
                try dir.deleteTree(self.io, entry.name);
            }
        }
    }

    fn detectLanguage(self: *Installer) ![]const u8 {
        var dir = try std.Io.Dir.cwd().openDir(self.io, self.temp_dir, .{ .iterate = true });
        defer dir.close(self.io);

        var iter = dir.iterate();
        while (try iter.next(self.io)) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zip")) {
                const extract_dir = try std.fmt.allocPrint(self.allocator, "{s}/extracted", .{self.temp_dir});
                defer self.allocator.free(extract_dir);
                try std.Io.Dir.cwd().createDirPath(self.io, extract_dir);
                _ = try self.runCommand(&.{"unzip", "-q", entry.name, "-d", extract_dir});

                var ext_dir = try std.Io.Dir.cwd().openDir(self.io, extract_dir, .{ .iterate = true });
                defer ext_dir.close(self.io);

                var file_iter = ext_dir.iterate();
                while (try file_iter.next(self.io)) |file| {
                    if (file.kind == .file) {
                        if (std.mem.endsWith(u8, file.name, ".java")) return "java";
                        if (std.mem.endsWith(u8, file.name, ".lua")) return "lua";
                        if (std.mem.endsWith(u8, file.name, ".py")) return "python";
                        if (std.mem.endsWith(u8, file.name, ".c")) return "c";
                        if (std.mem.endsWith(u8, file.name, ".cpp")) return "cpp";
                        if (std.mem.endsWith(u8, file.name, ".js")) return "nodejs";
                        if (std.mem.endsWith(u8, file.name, ".ko")) return "ko";
                        if (std.mem.endsWith(u8, file.name, ".zig")) return "zig";
                    }
                }
            }
        }
        return "unknown";
    }

    fn compileAndLink(self: *Installer, lang: []const u8) !void {
        std.debug.print("Compiling {s} code...\n", .{lang});
        if (std.mem.eql(u8, lang, "java")) {
            var args = std.array_list.Managed([]const u8).init(self.allocator);
            defer args.deinit();
            try args.append("javac");
            try args.append("-d");
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}", .{self.temp_dir}));
            _ = try self.runCommand(args.items);
        } else if (std.mem.eql(u8, lang, "c")) {
            var args = std.array_list.Managed([]const u8).init(self.allocator);
            defer args.deinit();
            try args.append("gcc");
            try args.append("-shared");
            try args.append("-fPIC");
            try args.append("-o");
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/lib.so", .{self.temp_dir}));
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/*.c", .{self.temp_dir}));
            _ = try self.runCommand(args.items);
        } else if (std.mem.eql(u8, lang, "cpp")) {
            var args = std.array_list.Managed([]const u8).init(self.allocator);
            defer args.deinit();
            try args.append("g++");
            try args.append("-shared");
            try args.append("-fPIC");
            try args.append("-o");
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/lib.so", .{self.temp_dir}));
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/*.cpp", .{self.temp_dir}));
            _ = try self.runCommand(args.items);
        } else if (std.mem.eql(u8, lang, "zig")) {
            var args = std.array_list.Managed([]const u8).init(self.allocator);
            defer args.deinit();
            try args.append("zig");
            try args.append("build-lib");
            try args.append("-fPIC");
            try args.append("-O");
            try args.append("ReleaseFast");
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/lib", .{self.temp_dir}));
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/*.zig", .{self.temp_dir}));
            _ = try self.runCommand(args.items);
        }
    }

    fn registerScope(self: *Installer, lib_name: []const u8) !void {
        std.debug.print("Registering module in store: {s}\n", .{lib_name});
        const module_dir = try std.fmt.allocPrint(self.allocator, "src/module/{s}", .{lib_name});
        defer self.allocator.free(module_dir);
        try std.Io.Dir.cwd().createDirPath(self.io, module_dir);
        
        const manifest_path = try std.fmt.allocPrint(self.allocator, "{s}/module.json", .{module_dir});
        defer self.allocator.free(manifest_path);
        
        const manifest_content = try std.fmt.allocPrint(self.allocator,
            \\{{"name":"{s}","version":"1.0.0","language":"c","installed_at":{d}}}
            , .{ lib_name, std.Io.Timestamp.now(self.io, .real).toMilliseconds() });
        defer self.allocator.free(manifest_content);
        
        try std.Io.Dir.cwd().writeFile(self.io, .{ .sub_path = manifest_path, .data = manifest_content });
        std.debug.print("Module manifest written to: {s}\n", .{manifest_path});
    }

    fn runCommand(self: *Installer, args: []const []const u8) !void {
        const result = try std.process.run(self.allocator, self.io, .{
            .argv = args,
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        switch (result.term) {
            .exited => |code| {
                if (code != 0) return error.CommandFailed;
            },
            else => return error.CommandFailed,
        }
    }

    pub fn cleanup(self: *Installer) !void {
        _ = std.Io.Dir.cwd().access(self.io, self.temp_dir, .{}) catch {};
        std.Io.Dir.cwd().deleteTree(self.io, self.temp_dir) catch {};
    }

    fn extractStringField(self: *Installer, json: []const u8, field: []const u8) ![]const u8 {
        _ = self;
        var iter = std.mem.splitSequence(u8, json, "\"");
        var found_field = false;
        while (iter.next()) |part| {
            if (found_field) {
                if (std.mem.eql(u8, part, "stringValue")) {
                    _ = iter.next() orelse "";
                    const val = iter.next() orelse "";
                    return val;
                }
            }
            if (std.mem.eql(u8, part, field)) {
                found_field = true;
            }
        }
        return "";
    }
};
