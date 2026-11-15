const std = @import("std");

const MODULE_STORE_BASE = "https://ko-lang.ai.studio";

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
        for (lib_name) |c| {
            if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '-')) {
                return error.InvalidLibraryName;
            }
        }
        std.debug.print("Installing library: {s}...\n", .{lib_name});

        const metadata = try self.queryLibraryMetadata(lib_name);
        defer self.allocator.free(metadata);

        const github_url = try self.extractDetailField(metadata, "githubLink");
        defer self.allocator.free(github_url);
        if (github_url.len == 0) {
            const github_url2 = try self.extractDetailField(metadata, "githubUrl");
            defer self.allocator.free(github_url2);
            if (github_url2.len == 0) {
                return error.LibraryNotFound;
            }
            std.debug.print("GitHub URL: {s}\n", .{github_url2});
            try self.cloneRepo(github_url2);
        } else {
            std.debug.print("GitHub URL: {s}\n", .{github_url});
            try self.cloneRepo(github_url);
        }

        try self.inspectAndFilterZip();
        const lang = try self.detectLanguage();
        std.debug.print("Detected language: {s}\n", .{lang});

        try self.compileAndLink(lang);
        try self.registerScope(lib_name);

        std.debug.print("Library {s} installed successfully!\n", .{lib_name});
    }

    pub fn listLibraries(self: *Installer) ![]const []const u8 {
        std.debug.print("Querying all libraries from Module Store...\n", .{});

        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/module", .{MODULE_STORE_BASE});
        defer self.allocator.free(url);

        const result = std.process.run(self.allocator, self.io, .{
            .argv = &.{ "curl", "-s", url },
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
        const url = try std.fmt.allocPrint(self.allocator, "{s}/api/module/{s}", .{ MODULE_STORE_BASE, lib_name });
        defer self.allocator.free(url);

        const result = std.process.run(self.allocator, self.io, .{
            .argv = &.{ "curl", "-s", url },
        }) catch |err| {
            std.debug.print("curl failed: {any}\n", .{err});
            return error.CommandFailed;
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);

        if (result.stdout.len == 0) {
            return error.LibraryNotFound;
        }

        const duped = try self.allocator.dupe(u8, result.stdout);
        return duped;
    }

    fn extractDetailField(self: *Installer, json: []const u8, field: []const u8) ![]const u8 {
        // Parse JSON with nested "detail": { "field": "value", ... }
        var idx: usize = 0;
        while (idx < json.len) {
            if (json[idx] == '"') {
                const key_start = idx;
                idx += 1;
                var key_end: usize = idx;
                while (key_end < json.len and json[key_end] != '"') key_end += 1;
                if (key_end >= json.len) break;
                const key_len = key_end - key_start - 1;
                if (key_len == 6 and std.mem.eql(u8, json[key_start + 1 .. key_end], "detail")) {
                    idx = key_end + 1;
                    while (idx < json.len and (json[idx] == ' ' or json[idx] == '\t' or json[idx] == '\n' or json[idx] == '\r' or json[idx] == ':')) idx += 1;
                    while (idx < json.len and (json[idx] == ' ' or json[idx] == '\t' or json[idx] == '\n' or json[idx] == '\r')) idx += 1;
                    if (idx < json.len and json[idx] == '{') {
                        var d_idx = idx + 1;
                        while (d_idx < json.len) {
                            if (json[d_idx] == '"') {
                                const d_key_start = d_idx;
                                d_idx += 1;
                                var d_key_end: usize = d_idx;
                                while (d_key_end < json.len and json[d_key_end] != '"') d_key_end += 1;
                                if (d_key_end >= json.len) break;
                                const d_key_len = d_key_end - d_key_start - 1;
                                if (d_key_len == field.len and std.mem.eql(u8, json[d_key_start + 1 .. d_key_end], field)) {
                                    d_idx = d_key_end + 1;
                                    while (d_idx < json.len and (json[d_idx] == ' ' or json[d_idx] == '\t' or json[d_idx] == '\n' or json[d_idx] == '\r' or json[d_idx] == ':')) d_idx += 1;
                                    while (d_idx < json.len and (json[d_idx] == ' ' or json[d_idx] == '\t' or json[d_idx] == '\n' or json[d_idx] == '\r')) d_idx += 1;
                                    if (d_idx < json.len and json[d_idx] == '"') {
                                        d_idx += 1;
                                        const val_start = d_idx;
                                        while (d_idx < json.len and json[d_idx] != '"') d_idx += 1;
                                        if (d_idx < json.len) {
                                            const val = json[val_start .. d_idx];
                                            return try self.allocator.dupe(u8, val);
                                        }
                                    }
                                } else {
                                    d_idx = d_key_end + 1;
                                }
                            } else {
                                d_idx += 1;
                            }
                        }
                    }
                } else {
                    idx = key_end + 1;
                }
            } else {
                idx += 1;
            }
        }
        return "";
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
                const zip_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.temp_dir, entry.name });
                defer self.allocator.free(zip_path);
                try self.validateZipEntries(zip_path);
                const extract_dir = try std.fmt.allocPrint(self.allocator, "{s}/extracted", .{self.temp_dir});
                defer self.allocator.free(extract_dir);
                try std.Io.Dir.cwd().createDirPath(self.io, extract_dir);
                _ = try self.runCommand(&.{ "unzip", "-q", zip_path, "-d", extract_dir });

                var ext_dir = try std.Io.Dir.cwd().openDir(self.io, extract_dir, .{ .iterate = true });
                defer ext_dir.close(self.io);

                if (try self.scanDirForLanguage(ext_dir)) |lang| return lang;
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
        for (lib_name) |c| {
            if (!(std.ascii.isAlphanumeric(c) or c == '_' or c == '-')) {
                return error.InvalidLibraryName;
            }
        }
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

    fn validateZipEntries(self: *Installer, zip_name: []const u8) !void {
        const result = try std.process.run(self.allocator, self.io, .{
            .argv = &.{ "unzip", "-Z1", zip_name },
        });
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        switch (result.term) {
            .exited => |code| {
                if (code != 0) return error.CommandFailed;
            },
            else => return error.CommandFailed,
        }
        var lines = std.mem.splitScalar(u8, result.stdout, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "/")) return error.ZipSlip;
            if (std.mem.indexOfScalar(u8, line, '\\') != null) return error.ZipSlip;
            var parts = std.mem.splitScalar(u8, line, '/');
            while (parts.next()) |part| {
                if (std.mem.eql(u8, part, "..")) return error.ZipSlip;
            }
        }
    }

    fn runCommand(self: *Installer, args: []const []const u8) !void {
        const result = std.process.run(self.allocator, self.io, .{
            .argv = args,
            .timeout = .{ .duration = .{ .raw = std.Io.Duration.fromSeconds(30), .clock = .real } },
        }) catch |err| switch (err) {
            error.Timeout => return error.CommandTimeout,
            else => return error.CommandFailed,
        };
        defer self.allocator.free(result.stdout);
        defer self.allocator.free(result.stderr);
        switch (result.term) {
            .exited => |code| {
                if (code != 0) return error.CommandFailed;
            },
            else => return error.CommandFailed,
        }
    }

    fn scanDirForLanguage(self: *Installer, dir: std.Io.Dir) !?[]const u8 {
        var iter = dir.iterate();
        while (try iter.next(self.io)) |entry| {
            if (entry.kind == .file) {
                if (std.mem.endsWith(u8, entry.name, ".java")) return "java";
                if (std.mem.endsWith(u8, entry.name, ".lua")) return "lua";
                if (std.mem.endsWith(u8, entry.name, ".py")) return "python";
                if (std.mem.endsWith(u8, entry.name, ".c")) return "c";
                if (std.mem.endsWith(u8, entry.name, ".cpp")) return "cpp";
                if (std.mem.endsWith(u8, entry.name, ".js")) return "nodejs";
                if (std.mem.endsWith(u8, entry.name, ".ko")) return "ko";
                if (std.mem.endsWith(u8, entry.name, ".zig")) return "zig";
            } else if (entry.kind == .directory) {
                var subdir = dir.openDir(self.io, entry.name, .{ .iterate = true }) catch continue;
                defer subdir.close(self.io);
                if (try self.scanDirForLanguage(subdir)) |lang| return lang;
            }
        }
        return null;
    }

    pub fn cleanup(self: *Installer) !void {
        _ = std.Io.Dir.cwd().access(self.io, self.temp_dir, .{}) catch {};
        std.Io.Dir.cwd().deleteTree(self.io, self.temp_dir) catch {};
    }
};
