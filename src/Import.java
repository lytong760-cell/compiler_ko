import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.*;
import java.nio.file.*;

public class Import {
    
    private static final String FIRESTORE_BASE = "https://firestore.googleapis.com/v1/projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents";
    private static final String API_KEY = System.getenv("KO_FIRESTORE_API_KEY");
    
    private final File tempDir;
    private final File libraryDir;
    
    public Import() {
        String projectRoot = System.getProperty("user.dir");
        this.tempDir = new File(System.getProperty("java.io.tmpdir"), "ko_import_" + System.currentTimeMillis());
        this.libraryDir = new File(projectRoot, "src/module");
        this.libraryDir.mkdirs();
    }
    
    public ImportResult processImport(String moduleName, String alias, String scopeTag) {
        try {
            System.out.println("[Import.java] Processing import: " + moduleName + " as " + alias + " in scope " + scopeTag);
            
            String normalizedName = normalizeModuleName(moduleName);
            
            String githubUrl = queryRegistry(normalizedName);
            if (githubUrl == null) {
                return ImportResult.error("Module not found in registry: " + moduleName);
            }
            
            File repoDir = cloneRepository(githubUrl);
            if (repoDir == null) {
                return ImportResult.error("Failed to clone repository: " + githubUrl);
            }
            
            File zipFile = inspectAndExtractZip(repoDir);
            if (zipFile == null) {
                cleanup(repoDir);
                return ImportResult.error("No valid .zip package found in repository: " + githubUrl);
            }
            
             boolean compiled = compileAndLink(zipFile, alias);
             cleanup(repoDir);
             cleanup(tempDir);
            
             if (!compiled) {
                return ImportResult.error("Failed to compile/link module: " + moduleName);
            }
            
            return ImportResult.success(alias, scopeTag, normalizedName);
            
        } catch (Exception e) {
            return ImportResult.error("Import exception: " + e.getMessage());
        }
    }
    
    private String queryRegistry(String moduleName) {
        System.out.println("[Import.java] Querying registry for: " + moduleName);
        try {
            String apiKey = API_KEY;
            if (apiKey == null || apiKey.isEmpty()) {
                System.out.println("[Import.java] Warning: KO_FIRESTORE_API_KEY environment variable is not set. Using registry without API key.");
            }
            String urlStr = FIRESTORE_BASE + "/libraries/" + URLEncoder.encode(moduleName, "UTF-8");
            if (apiKey != null && !apiKey.isEmpty()) {
                urlStr += "?key=" + apiKey;
            }
            URL url = new URL(urlStr);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("GET");
            conn.setConnectTimeout(10000);
            conn.setReadTimeout(10000);
            
            int status = conn.getResponseCode();
            if (status != 200) {
                System.out.println("[Import.java] Registry query returned status: " + status);
                return null;
            }
            
            String response = readStream(conn.getInputStream());
            String githubUrl = extractJsonField(response, "githubLink");
            if (githubUrl.isEmpty()) {
                githubUrl = extractJsonField(response, "githubUrl");
            }
            
            conn.disconnect();
            return githubUrl.isEmpty() ? null : githubUrl;
        } catch (Exception e) {
            System.out.println("[Import.java] Registry query failed: " + e.getMessage());
            return null;
        }
    }
    
    public String[] listLibraries() {
        System.out.println("[Import.java] Listing all libraries from Module Store...");
        try {
            String urlStr = FIRESTORE_BASE + ":runQuery?key=" + API_KEY;
            URL url = new URL(urlStr);
            HttpURLConnection conn = (HttpURLConnection) url.openConnection();
            conn.setRequestMethod("POST");
            conn.setRequestProperty("Content-Type", "application/json");
            conn.setDoOutput(true);
            conn.setConnectTimeout(15000);
            conn.setReadTimeout(15000);
            
            String postBody = "{\"parent\": \"" + FIRESTORE_BASE.replace("/documents", "/documents") + "\", \"query\": {\"from\": [{\"collectionId\": \"libraries\"}]}}";
            try (OutputStream os = conn.getOutputStream()) {
                byte[] input = postBody.getBytes(StandardCharsets.UTF_8);
                os.write(input, 0, input.length);
            }
            
            int status = conn.getResponseCode();
            if (status != 200) {
                System.out.println("[Import.java] List libraries query returned status: " + status);
                return new String[0];
            }
            
            String response = readStream(conn.getInputStream());
            conn.disconnect();
            
            List<String> libs = new ArrayList<>();
            extractLibraryNames(response, libs);
            return libs.toArray(new String[0]);
        } catch (Exception e) {
            System.out.println("[Import.java] List libraries failed: " + e.getMessage());
            return new String[0];
        }
    }
    
    public String[] searchLibraries(String query) {
        System.out.println("[Import.java] Searching libraries for: " + query);
        String[] all = listLibraries();
        List<String> matches = new ArrayList<>();
        for (String lib : all) {
            if (lib.toLowerCase().contains(query.toLowerCase())) {
                matches.add(lib);
            }
        }
        return matches.toArray(new String[0]);
    }
    
    private File cloneRepository(String githubUrl) {
        System.out.println("[Import.java] Cloning repository: " + githubUrl);
        try {
            File repoDir = new File(tempDir, "repo_" + System.currentTimeMillis());
            repoDir.mkdirs();
            
            File logFile = new File(tempDir, "clone_" + System.currentTimeMillis() + ".log");
            ProcessBuilder pb = new ProcessBuilder("git", "clone", githubUrl, repoDir.getAbsolutePath());
            pb.directory(tempDir);
            pb.redirectErrorStream(true);
            pb.redirectOutput(logFile);
            Process process = pb.start();
            int exitCode = process.waitFor();

            String output = readFile(logFile);

            if (exitCode != 0) {
                System.out.println("[Import.java] Git clone failed: " + output);
                return null;
            }

            System.out.println("[Import.java] Clone successful: " + repoDir.getAbsolutePath());
            return repoDir;
        } catch (Exception e) {
            System.out.println("[Import.java] Clone exception: " + e.getMessage());
            return null;
        }
    }
    
    private File inspectAndExtractZip(File repoDir) {
        System.out.println("[Import.java] Inspecting repository for .zip package...");
        File zipFile = findZipRecursive(repoDir);
        
        if (zipFile == null) {
            System.out.println("[Import.java] No .zip file found in repository.");
            return null;
        }
        
        deleteNonZipFilesRecursive(repoDir, zipFile);
        
        System.out.println("[Import.java] Found .zip package: " + zipFile.getName());
        return zipFile;
    }
    
    private File findZipRecursive(File dir) {
        File[] files = dir.listFiles();
        if (files == null) return null;
        
        File zipFile = null;
        for (File f : files) {
            if (f.isFile() && f.getName().toLowerCase().endsWith(".zip")) {
                if (zipFile == null) {
                    zipFile = f;
                }
            } else if (f.isDirectory()) {
                File found = findZipRecursive(f);
                if (found != null) {
                    if (zipFile == null) {
                        zipFile = found;
                    }
                }
            }
        }
        return zipFile;
    }
    
    private void deleteNonZipFilesRecursive(File dir, File preserveFile) {
        File[] files = dir.listFiles();
        if (files == null) return;
        
        for (File f : files) {
            if (f.isDirectory()) {
                deleteNonZipFilesRecursive(f, preserveFile);
            } else if (!f.equals(preserveFile)) {
                deleteRecursive(f);
            }
        }
    }
    
    private boolean compileAndLink(File zipFile, String alias) {
        System.out.println("[Import.java] Compiling and linking: " + zipFile.getName() + " as " + alias);
        try {
            File extractDir = new File(tempDir, "extracted");
            extractDir.mkdirs();
            
            File moduleDir = new File(libraryDir, alias);
            moduleDir.mkdirs();
            
            ProcessBuilder unzipPb = new ProcessBuilder("unzip", "-q", zipFile.getAbsolutePath(), "-d", extractDir.getAbsolutePath());
            unzipPb.directory(tempDir);
            unzipPb.redirectErrorStream(true);
            Process unzipProcess = unzipPb.start();
            unzipProcess.waitFor();
            
            String lang = detectLanguage(extractDir);
            System.out.println("[Import.java] Detected language: " + lang);
            
            boolean compiled = false;
            switch (lang) {
                case "java":
                    compiled = compileJava(extractDir, alias);
                    break;
                case "c":
                    compiled = compileC(extractDir, alias);
                    break;
                case "cpp":
                    compiled = compileCpp(extractDir, alias);
                    break;
                case "nodejs":
                    compiled = compileNodeJs(extractDir, alias);
                    break;
                case "zig":
                    compiled = compileZig(extractDir, alias);
                    break;
                case "python":
                case "lua":
                    compiled = true;
                    break;
                case "ko":
                    compiled = compileKo(extractDir, alias);
                    break;
                default:
                    System.out.println("[Import.java] Unsupported language: " + lang);
                    compiled = false;
            }
            
            if (compiled) {
                writeModuleManifest(moduleDir, alias, lang);
            }
            
            return compiled;
        } catch (Exception e) {
            System.out.println("[Import.java] Compile/link exception: " + e.getMessage());
            return false;
        }
    }
    
    private boolean compileJava(File extractDir, String alias) {
        try {
            File moduleDir = new File(libraryDir, alias);
            File classesDir = new File(moduleDir, "classes");
            classesDir.mkdirs();
            
            List<File> javaFiles = new ArrayList<>();
            collectFiles(extractDir, ".java", javaFiles);
            
            List<String> args = new ArrayList<>();
            args.add("javac");
            args.add("-d");
            args.add(classesDir.getAbsolutePath());
            for (File f : javaFiles) {
                args.add(f.getAbsolutePath());
            }
            
            ProcessBuilder pb = new ProcessBuilder(args);
            pb.directory(extractDir);
            pb.redirectErrorStream(true);
            Process process = pb.start();
            String output = readStream(process.getInputStream());
            int exitCode = process.waitFor();
            
            if (exitCode != 0) {
                System.out.println("[Import.java] Java compilation failed: " + output);
                return false;
            }
            
            return true;
        } catch (Exception e) {
            System.out.println("[Import.java] Java compile exception: " + e.getMessage());
            return false;
        }
    }
    
    private boolean compileC(File extractDir, String alias) {
        try {
            File moduleDir = new File(libraryDir, alias);
            File outputLib = new File(moduleDir, "lib" + alias + ".so");
            List<File> cFiles = new ArrayList<>();
            collectFiles(extractDir, ".c", cFiles);
            
            if (cFiles.isEmpty()) {
                System.out.println("[Import.java] No .c files found for C compilation");
                return false;
            }
            
            List<String> args = new ArrayList<>();
            args.add("gcc");
            args.add("-shared");
            args.add("-fPIC");
            args.add("-o");
            args.add(outputLib.getAbsolutePath());
            for (File f : cFiles) {
                args.add(f.getAbsolutePath());
            }
            
            ProcessBuilder pb = new ProcessBuilder(args);
            pb.directory(extractDir);
            pb.redirectErrorStream(true);
            Process process = pb.start();
            String output = readStream(process.getInputStream());
            int exitCode = process.waitFor();
            
            if (exitCode != 0) {
                System.out.println("[Import.java] C compilation failed: " + output);
                return false;
            }
            
            return true;
        } catch (Exception e) {
            System.out.println("[Import.java] C compile exception: " + e.getMessage());
            return false;
        }
    }
    
    private boolean compileCpp(File extractDir, String alias) {
        try {
            File moduleDir = new File(libraryDir, alias);
            File outputLib = new File(moduleDir, "lib" + alias + ".so");
            List<File> cppFiles = new ArrayList<>();
            collectFiles(extractDir, ".cpp", cppFiles);
            
            if (cppFiles.isEmpty()) {
                System.out.println("[Import.java] No .cpp files found for C++ compilation");
                return false;
            }
            
            List<String> args = new ArrayList<>();
            args.add("g++");
            args.add("-shared");
            args.add("-fPIC");
            args.add("-o");
            args.add(outputLib.getAbsolutePath());
            for (File f : cppFiles) {
                args.add(f.getAbsolutePath());
            }
            
            ProcessBuilder pb = new ProcessBuilder(args);
            pb.directory(extractDir);
            pb.redirectErrorStream(true);
            Process process = pb.start();
            int exitCode = process.waitFor();
            
            if (exitCode != 0) {
                System.out.println("[Import.java] C++ compilation failed");
                return false;
            }
            
            return true;
        } catch (Exception e) {
            System.out.println("[Import.java] C++ compile exception: " + e.getMessage());
            return false;
        }
    }
    
    private boolean compileNodeJs(File extractDir, String alias) {
        try {
            File moduleDir = new File(libraryDir, alias);
            moduleDir.mkdirs();
            
            File packageJson = new File(extractDir, "package.json");
            if (packageJson.exists()) {
                ProcessBuilder pb = new ProcessBuilder("npm", "install");
                pb.directory(extractDir);
                pb.redirectErrorStream(true);
                Process process = pb.start();
                int npmExitCode = process.waitFor();
                if (npmExitCode != 0) {
                    System.out.println("[Import.java] npm install exited with code: " + npmExitCode);
                }
            }
            
            File mainFile = findMainFile(extractDir, ".js");
            if (mainFile == null) {
                System.out.println("[Import.java] No entry .js file found");
                return false;
            }
            
            File destFile = new File(moduleDir, "main.js");
            copyFile(mainFile, destFile);
            return true;
        } catch (Exception e) {
            System.out.println("[Import.java] Node.js compile exception: " + e.getMessage());
            return false;
        }
    }
    
    private boolean compileZig(File extractDir, String alias) {
        try {
            File moduleDir = new File(libraryDir, alias);
            File outputLib = new File(moduleDir, "lib" + alias + ".so");
            List<File> zigFiles = new ArrayList<>();
            collectFiles(extractDir, ".zig", zigFiles);

            if (zigFiles.isEmpty()) {
                System.out.println("[Import.java] No .zig files found for Zig compilation");
                return false;
            }

            File entryFile = findZigEntryPoint(zigFiles);
            if (entryFile == null) {
                System.out.println("[Import.java] No Zig entry point found (no main.zig or pub fn main)");
                return false;
            }

            List<String> args = new ArrayList<>();
            args.add("zig");
            args.add("build-lib");
            args.add("-fPIC");
            args.add("-O");
            args.add("ReleaseFast");
            args.add("-o");
            args.add(outputLib.getAbsolutePath());
            args.add(entryFile.getAbsolutePath());

            ProcessBuilder pb = new ProcessBuilder(args);
            pb.directory(extractDir);
            pb.redirectErrorStream(true);
            Process process = pb.start();
            int exitCode = process.waitFor();

            if (exitCode != 0) {
                System.out.println("[Import.java] Zig compilation failed");
                return false;
            }

            return true;
        } catch (Exception e) {
            System.out.println("[Import.java] Zig compile exception: " + e.getMessage());
            return false;
        }
    }

    private File findZigEntryPoint(List<File> zigFiles) {
        for (File f : zigFiles) {
            if (f.getName().equals("main.zig")) {
                return f;
            }
        }
        for (File f : zigFiles) {
            try {
                String content = new String(java.nio.file.Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
                if (content.contains("pub fn main")) {
                    return f;
                }
            } catch (IOException e) {
                // skip
            }
        }
        return null;
    }
    
    private boolean compileKo(File extractDir, String alias) {
        try {
            File moduleDir = new File(libraryDir, alias);
            moduleDir.mkdirs();
            
            File mainFile = findMainFile(extractDir, ".ko");
            if (mainFile == null) {
                System.out.println("[Import.java] No .ko entry file found");
                return false;
            }
            
            File destFile = new File(moduleDir, "main.ko");
            copyFile(mainFile, destFile);
            return true;
        } catch (Exception e) {
            System.out.println("[Import.java] .ko compile exception: " + e.getMessage());
            return false;
        }
    }
    
    private String detectLanguage(File extractDir) {
        File[] files = extractDir.listFiles();
        if (files == null) return "unknown";
        
        for (File f : files) {
            if (f.isFile()) {
                String name = f.getName().toLowerCase();
                if (name.endsWith(".java")) return "java";
                if (name.endsWith(".lua")) return "lua";
                if (name.endsWith(".py")) return "python";
                if (name.endsWith(".c")) return "c";
                if (name.endsWith(".cpp")) return "cpp";
                if (name.endsWith(".js")) return "nodejs";
                if (name.endsWith(".ko")) return "ko";
                if (name.endsWith(".zig")) return "zig";
            } else if (f.isDirectory()) {
                String lang = detectLanguage(f);
                if (!lang.equals("unknown")) return lang;
            }
        }
        return "unknown";
    }
    
    private File findMainFile(File dir, String extension) {
        File[] files = dir.listFiles();
        if (files == null) return null;
        
        for (File f : files) {
            if (f.isFile() && f.getName().toLowerCase().endsWith(extension)) {
                return f;
            } else if (f.isDirectory()) {
                File found = findMainFile(f, extension);
                if (found != null) return found;
            }
        }
        return null;
    }
    
    private void collectFiles(File dir, String extension, List<File> result) {
        File[] files = dir.listFiles();
        if (files == null) return;
        
        for (File f : files) {
            if (f.isFile() && f.getName().toLowerCase().endsWith(extension)) {
                result.add(f);
            } else if (f.isDirectory()) {
                collectFiles(f, extension, result);
            }
        }
    }
    
    private void writeModuleManifest(File moduleDir, String alias, String lang) {
        try {
            File manifest = new File(moduleDir, "module.json");
            String json = String.format(
                "{\"name\":\"%s\",\"version\":\"1.0.0\",\"language\":\"%s\",\"installed_at\":\"%d\"}",
                alias, lang, System.currentTimeMillis()
            );
            try (FileWriter fw = new FileWriter(manifest)) {
                fw.write(json);
            }
            System.out.println("[Import.java] Module manifest written: " + manifest.getAbsolutePath());
        } catch (Exception e) {
            System.out.println("[Import.java] Manifest write failed: " + e.getMessage());
        }
    }
    
    private void copyFile(File src, File dest) throws IOException {
        try (FileInputStream fis = new FileInputStream(src);
             FileOutputStream fos = new FileOutputStream(dest)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = fis.read(buf)) > 0) {
                fos.write(buf, 0, n);
            }
        }
    }
    
    private String normalizeModuleName(String moduleName) {
        return moduleName.replaceAll("^\\$", "").toLowerCase();
    }
    
    private void cleanup(File dir) {
        if (dir != null && dir.exists()) {
            deleteRecursive(dir);
        }
    }
    
    private void deleteRecursive(File file) {
        if (file.isDirectory()) {
            File[] children = file.listFiles();
            if (children != null) {
                for (File child : children) {
                    deleteRecursive(child);
                }
            }
        }
        file.delete();
    }
    
    private String readFile(File file) {
        try {
            return new String(java.nio.file.Files.readAllBytes(file.toPath()), StandardCharsets.UTF_8);
        } catch (Exception e) {
            return "";
        }
    }

    private String readStream(InputStream is) throws IOException {
        StringBuilder sb = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(is, StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line);
            }
        }
        return sb.toString();
    }
    
    private String extractJsonField(String json, String field) {
        String search = "\"" + field + "\"";
        int idx = json.indexOf(search);
        if (idx == -1) return "";
        
        int valueStart = json.indexOf(':', idx + search.length());
        if (valueStart == -1) return "";
        
        valueStart++;
        while (valueStart < json.length() && Character.isWhitespace(json.charAt(valueStart))) {
            valueStart++;
        }
        
        if (valueStart >= json.length()) return "";
        
        if (json.charAt(valueStart) == '"') {
            int endQuote = findUnescapedQuote(json, valueStart + 1);
            if (endQuote == -1) return "";
            return json.substring(valueStart + 1, endQuote);
        } else if (json.charAt(valueStart) == '{') {
            int endBrace = findMatchingBrace(json, valueStart);
            if (endBrace == -1) return "";
            return json.substring(valueStart, endBrace + 1);
        }
        
        return "";
    }
    
    private int findUnescapedQuote(String json, int start) {
        for (int i = start; i < json.length(); i++) {
            if (json.charAt(i) == '"') {
                int backslashCount = 0;
                int j = i - 1;
                while (j >= 0 && json.charAt(j) == '\\') {
                    backslashCount++;
                    j--;
                }
                if (backslashCount % 2 == 0) {
                    return i;
                }
            }
        }
        return -1;
    }
    
    private void extractLibraryNames(String json, List<String> result) {
        String search = "\"name\":";
        int idx = 0;
        while ((idx = json.indexOf(search, idx)) != -1) {
            int valueStart = idx + search.length();
            while (valueStart < json.length() && Character.isWhitespace(json.charAt(valueStart))) {
                valueStart++;
            }
            
            if (valueStart < json.length() && json.charAt(valueStart) == '"') {
                int endQuote = json.indexOf('"', valueStart + 1);
                if (endQuote != -1) {
                    String fullName = json.substring(valueStart + 1, endQuote);
                    int lastSlash = fullName.lastIndexOf('/');
                    if (lastSlash >= 0 && lastSlash < fullName.length() - 1) {
                        String libName = fullName.substring(lastSlash + 1);
                        if (!libName.isEmpty() && !result.contains(libName)) {
                            result.add(libName);
                        }
                    }
                }
            }
            idx = valueStart;
        }
    }
    
    private int findMatchingBrace(String json, int start) {
        int depth = 0;
        for (int i = start; i < json.length(); i++) {
            char c = json.charAt(i);
            if (c == '{') depth++;
            else if (c == '}') {
                depth--;
                if (depth == 0) return i;
            }
        }
        return -1;
    }
    
    public static class ImportResult {
        public final boolean success;
        public final String alias;
        public final String scopeTag;
        public final String moduleName;
        public final String errorMessage;
        
        private ImportResult(boolean success, String alias, String scopeTag, String moduleName, String errorMessage) {
            this.success = success;
            this.alias = alias;
            this.scopeTag = scopeTag;
            this.moduleName = moduleName;
            this.errorMessage = errorMessage;
        }
        
        public static ImportResult success(String alias, String scopeTag, String moduleName) {
            return new ImportResult(true, alias, scopeTag, moduleName, null);
        }
        
        public static ImportResult error(String message) {
            return new ImportResult(false, null, null, null, message);
        }
    }
    
    public static void main(String[] args) {
        if (args.length == 0) {
            System.out.println("Usage: Import <command> [options]");
            System.out.println("Commands:");
            System.out.println("  import <module> <alias> <scope> - Import a module");
            System.out.println("  list - List all available libraries");
            System.out.println("  search <query> - Search for libraries");
            System.exit(1);
        }
        
        String command = args[0].toLowerCase();
        Import importer = new Import();
        
        try {
            switch (command) {
                case "import":
                    if (args.length < 4) {
                        System.err.println("Error: Missing arguments for import command. Usage: import <module> <alias> <scope>");
                        System.exit(1);
                    }
                    ImportResult result = importer.processImport(args[1], args[2], args[3]);
                    if (result.success) {
                        System.out.println("Import successful: " + result.alias + " in scope " + result.scopeTag + " from " + result.moduleName);
                        System.exit(0);
                    } else {
                        System.err.println("Error: " + result.errorMessage);
                        System.exit(1);
                    }
                    break;
                case "list":
                    String[] libraries = importer.listLibraries();
                    if (libraries.length == 0) {
                        System.out.println("No libraries found.");
                    } else {
                        System.out.println("Available libraries:");
                        for (String lib : libraries) {
                            System.out.println("  - " + lib);
                        }
                    }
                    break;
                case "search":
                    if (args.length < 2) {
                        System.err.println("Error: Missing search query. Usage: search <query>");
                        System.exit(1);
                    }
                    String[] results = importer.searchLibraries(args[1]);
                    if (results.length == 0) {
                        System.out.println("No results found for query: " + args[1]);
                    } else {
                        System.out.println("Search results for \"" + args[1] + "\":");
                        for (String lib : results) {
                            System.out.println("  - " + lib);
                        }
                    }
                    break;
                default:
                    System.err.println("Error: Unknown command: " + command);
                    System.err.println("Usage: Import <command> [options]");
                    System.err.println("Commands: import, list, search");
                    System.exit(1);
            }
        } catch (Exception e) {
            System.err.println("Fatal error: " + e.getMessage());
            System.exit(1);
        }
    }
}
