const std = @import("std");

const FIRESTORE_BASE = "https://firestore.googleapis.com/v1/projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents";
const API_KEY = "AIzaSyDcW3_plpZompdSlSYFr832A-Vq1TyQxvE";

pub const Installer = struct {
    allocator: std.mem.Allocator,
    temp_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) !Installer {
        const temp_dir = try std.fmt.allocPrint(allocator, "/tmp/.ko_temp_{d}", .{std.time.milliTimestamp()});
        try std.fs.cwd().makePath(temp_dir);
        return .{
            .allocator = allocator,
            .temp_dir = temp_dir,
        };
    }

    pub fn deinit(self: *Installer) void {
        self.cleanup() catch {};
        self.allocator.free(self.temp_dir);
    }

    pub fn installLibrary(self: *Installer, lib_name: []const u8) !void {
        std.debug.print("Installing library: {s}...\n", .{lib_name});

        const github_url = try self.queryLibraryMetadata(lib_name);
        std.debug.print("GitHub URL: {s}\n", .{github_url});

        try self.cloneRepo(github_url);
        try self.inspectAndFilterZip();
        const lang = try self.detectLanguage();
        std.debug.print("Detected language: {s}\n", .{lang});

        try self.compileAndLink(lang);
        try self.registerScope(lib_name);

        std.debug.print("Library {s} installed successfully!\n", .{lib_name});
    }

    fn queryLibraryMetadata(self: *Installer, lib_name: []const u8) ![]const u8 {
        const url = try std.fmt.allocPrint(self.allocator, "{s}/libraries/{s}?key={s}", .{
            FIRESTORE_BASE,
            lib_name,
            API_KEY,
        });
        defer self.allocator.free(url);

        var stdout_buf: [65536]u8 = undefined;
        var stdout_list = std.ArrayList(u8).init(self.allocator);
        defer stdout_list.deinit();

        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = &.{"curl", "-s", url},
        });
        defer self.allocator.free(result.stdout);
        switch (result.term) {
            .Exited => |code| {
                if (code != 0) return error.CommandFailed;
            },
            else => return error.CommandFailed,
        }

        const github_url = try self.extractStringField(result.stdout, "githubUrl");
        if (github_url.len == 0) {
            return error.LibraryNotFound;
        }
        return github_url;
    }

    fn cloneRepo(self: *Installer, repo_url: []const u8) !void {
        std.debug.print("Cloning repository: {s}\n", .{repo_url});
        _ = try self.runCommand(&.{"git", "clone", repo_url, self.temp_dir});
    }

    fn inspectAndFilterZip(self: *Installer) !void {
        var dir = try std.fs.cwd().openDir(self.temp_dir, .{ .iterate = true });
        defer dir.close();

        var found_zip = false;
        var iter = dir.iterate();
        while (try iter.next()) |entry| {
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
        while (try iter2.next()) |entry| {
            if (!std.mem.endsWith(u8, entry.name, ".zip")) {
                try dir.deleteTree(entry.name);
            }
        }
    }

    fn detectLanguage(self: *Installer) ![]const u8 {
        var dir = try std.fs.cwd().openDir(self.temp_dir, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".zip")) {
                const extract_dir = try std.fmt.allocPrint(self.allocator, "{s}/extracted", .{self.temp_dir});
                defer self.allocator.free(extract_dir);
                try std.fs.cwd().makePath(extract_dir);
                _ = try self.runCommand(&.{"unzip", "-q", entry.name, "-d", extract_dir});

                var ext_dir = try std.fs.cwd().openDir(extract_dir, .{ .iterate = true });
                defer ext_dir.close();

                var file_iter = ext_dir.iterate();
                while (try file_iter.next()) |file| {
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
            var args = std.ArrayList([]const u8).init(self.allocator);
            defer args.deinit();
            try args.append("javac");
            try args.append("-d");
            try args.append(self.temp_dir);
            _ = try self.runCommand(args.items);
        } else if (std.mem.eql(u8, lang, "c")) {
            var args = std.ArrayList([]const u8).init(self.allocator);
            defer args.deinit();
            try args.append("gcc");
            try args.append("-shared");
            try args.append("-fPIC");
            try args.append("-o");
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/lib.so", .{self.temp_dir}));
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/*.c", .{self.temp_dir}));
            _ = try self.runCommand(args.items);
        } else if (std.mem.eql(u8, lang, "cpp")) {
            var args = std.ArrayList([]const u8).init(self.allocator);
            defer args.deinit();
            try args.append("g++");
            try args.append("-shared");
            try args.append("-fPIC");
            try args.append("-o");
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/lib.so", .{self.temp_dir}));
            try args.append(try std.fmt.allocPrint(self.allocator, "{s}/*.cpp", .{self.temp_dir}));
            _ = try self.runCommand(args.items);
        } else if (std.mem.eql(u8, lang, "zig")) {
            var args = std.ArrayList([]const u8).init(self.allocator);
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
        std.debug.print("Registering scope for: {s}\n", .{lib_name});
        const scope_file = try std.fmt.allocPrint(self.allocator, "/tmp/.ko_scopes/{s}.scope", .{lib_name});
        defer self.allocator.free(scope_file);
        try std.fs.cwd().makePath("/tmp/.ko_scopes");
        try std.fs.cwd().writeFile(.{ .path = scope_file, .data = lib_name });
    }

    fn runCommand(self: *Installer, args: []const []const u8) !void {
        const result = std.process.Child.run(.{
            .allocator = self.allocator,
            .argv = args,
        });
        defer self.allocator.free(result.stdout);
        switch (result.term) {
            .Exited => |code| {
                if (code != 0) return error.CommandFailed;
            },
            else => return error.CommandFailed,
        }
    }

    pub fn cleanup(self: *Installer) !void {
        _ = std.fs.cwd().access(self.temp_dir, .{}) catch {};
        std.fs.cwd().deleteTree(self.temp_dir) catch {};
    }

    fn extractStringField(self: *Installer, json: []const u8, field: []const u8) ![]const u8 {
        _ = self;
        var iter = std.mem.splitSequence(u8, json, "\"");
        var found_field = false;
        while (iter.next()) |part| {
            if (found_field) {
                const value_part = iter.next() orelse "";
                if (std.mem.startsWith(u8, std.mem.trim(u8, value_part, " \n\t:"), "stringValue")) {
                    const val_start = std.mem.indexOf(u8, value_part, ":") orelse 0;
                    const val = std.mem.trim(u8, value_part[val_start + 1 ..], " \n\t\"{}");
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
