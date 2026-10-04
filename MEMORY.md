# MEMORY.md — Ký ức dài hạn của compiler_ko

Ghi lại những điều đã xác minh được, để phiên sau không phải đo lại từ đầu.
Chỉ ghi kèm **bằng chứng**. Điều chưa kiểm chứng thì để dưới "Chưa xác minh".

---

### [2026-10-01] LONG-TERM MEMORY DUMP

- **Identified Truths**
  - `zig build test` **treo vô hạn**. Nguyên nhân KHÔNG phải stdin (đó chỉ là 3 test fail) mà là **25 test dùng `<printf>` ghi thẳng ra stdout — mà dưới `zig build test`, stdout chính là kênh binary protocol của test runner**. Ghi xen làm hỏng byte stream, hai đầu deadlock. Đã sửa bằng `VM.setOutputWriter` + `Writer.Discarding` trong test harness.
  - `stdin` của `zig build test` **phải đóng** khi chạy thủ công: `zig build test < /dev/null`. Nếu không, có thể treo.
  - Kiểm tra build có thể **đỏ tạm thời** khi nhiều agent đang ghi file cùng lúc. Không phải lỗi thật — kiểm tra lại sau khi agent dừng.

- **Architectural Mutations**
  - Thêm `build.zig.zon` với `.minimum_zig_version = "0.16.0"`. Đây là thứ chặn việc 3 phiên bản Zig mâu thuẫn tồn tại lâu không ai thấy.
  - Root `build.zig` build **4 thư viện dùng chung**: `libko_os.so` (9 symbol `ko_*`), `libko_random.so` (4), `libko_website.so` (7), `libko_loop.so` (8).
  - API Zig 0.16 đúng cho thư viện C: `b.createModule` + `Module.addCSourceFiles` + `b.addLibrary(.{ .linkage = .dynamic, .root_module = ... })`. `addCSourceFiles`/`addCMacro`/`addIncludePath` nằm trên **Module**, không phải `Compile`.
  - **`addSubdirectory` không tồn tại trong Zig 0.16.** Đã xác minh bằng grep `/opt/zig/lib/std/Build.zig`. Vì vậy 3 file `src/module/*/build.zig` đã bị xoá thay vì nối.
  - Một file `.c`/`.cpp` **không thể làm Zig root source file**. Trỏ `addLibrary.root_module.root_source_file` vào file C sẽ khiến Zig compile nó như Zig và báo `no module named 'root'`.
  - C flags bắt buộc cho module C: `-std=gnu11 -fPIC -D_GNU_SOURCE` (vì `Os.c` dùng `setenv`/`popen`, không khai báo với `-std=c11`). `Loop.cpp` cần `-std=c++17 -fPIC` và `link_libcpp`.

- **Technical Debt & Anti-Patterns**
  - Bytecode backend là **dead code**: `src/compiler.zig` có **0 importer**, `executeChunk` chỉ có dòng định nghĩa không có lời gồi. `compileProgram` chỉ xử lý 7/14 biến thể statement, `else => {}` âm thầm bỏ `control_flow` (toàn bộ if/else và loop).
  - **`Op.call` mã hóa không tương thích**: `compiler.zig` đóng gói `idx + args.len` vào một `u32`, VM decode bằng `name_idx = arity >> 16`. Mọi lệnh call đều sai.
  - `ko_random_float` trước chia cho `INT64_MAX` nên chỉ trả `[0, 0.00043]` thay vì `[0,1)`. Đã sửa, đo lại: max `0.99999950896`, avg `0.500215`.
  - `Loop.cpp` `optimizeWhileLoop` nhận `conditionLambda` rồi **vứt đi** → `executeCacheAlignedLoop` lặp vô hạn. Đã sửa bằng `maxIterations` cap + callback C thuần.
  - Dict literal: parser parse entry rồi **vứt đi**, luôn cấp map rỗng. Cú pháp spec (`SPECIFICATION.md:141`) là `(1{'a'})~d`, cả hai dạng đều hỏng.
  - `bytes(<expr>)~x` chỉ khớp `.int`, mọi biểu thức khác âm thầm cho buffer 0 byte.
  - Repo từng có **16.255 file tracked** (15.372 từ thư mục `zig/` 341 MB + 804 từ `.zig-global-cache/`). Đã dọn còn 64.
  - Có thư mục tên **bắt đầu bằng dấu cách** (`" .zig-cache"`) — đây là lý do `git rm` báo `pathspec did not match`. Đã untrack và thêm vào `.gitignore`.
  - Sub-agent chạy song parallel trên cùng repo đã nhiều lần phá hỏng việc của nhau. Phải dùng git worktree riêng cho từng agent.

- **Shared Variables & Symbols**
  - `VM.setInputBuffer(buf)` — nạp stdin cố định, giữ test hermetic
  - `VM.setOutputWriter(w)` — đổi nơi ghi output; **bắt buộc** khi chạy dưới test runner
  - `isSystemTagOpener()` trong `parser.zig` — phân biệt `<` toán tử với `<` mở system tag
  - Kiểu `booling` là **đúng**, không phải typo (`src/value.zig`, `src/lexer.zig`)

---

### [2026-10-02] LONG-TERM MEMORY DUMP

- **Identified Truths**
  - `Import.java` compile **sạch** chỉ khi dùng `javac` ra thư mục class **sạch**. Kiểm tra bằng thư mục class cũ sẽ ra **pass giả**.
  - `Process` **không phải `AutoCloseable`** trên javac 25 → `try (Process process = ...)` không compile. Phải dùng biến thường.
  - `File.Reader.interface` trỏ ngược về struct cha bằng `@fieldParentPtr`. Copy `.interface` ra khỏi biến tạm gây `panic: switch on corrupt value`. Phải giữ **cả struct `File.Reader`**.
  - `@cImport` + `<dlfcn.h>` vi phạm ràng buộc "zero-dependency linking matrix" của AGENTS.md. Đã chuyển sang chương trình C độc lập `testing/mod_check.c`.

- **Architectural Mutations**
  - `testing/mod_check.c` — binary C độc lập làm `dlopen`/`dlsym`/gọi hàm/assert. Zig test chỉ chạy nó qua `std.process.run`. Tầng Zig **không còn link `libdl`**.
  - Test module **gọi hàm thật**, không chỉ check symbol: đổi tên `ko_file_exists` → 2 test đỏ với `SymbolNotFound`.

- **Technical Debt & Anti-Patterns**
  - `waitFor()` **trước** rồi đọc pipe là mẫu gây treo khi output >64 KB. Phải `redirectOutput` sang file hoặc đọc trước.
  - `dlclose` gọi **trước** khi test dùng con trỏ hàm → use-after-dlclose → segfault.
  - `defer a.free(sym)` với `sym` từ `dlsym` → free memory không được phép free.
  - `ko_exec` từng gọi `popen(cmd, "r")` — **command injection**. Đã thay bằng `fork`/`execve` + từ chối ký tự shell.

- **Shared Variables & Symbols**
  - `mod_check.c` các check: `file_exists_true`, `file_exists_false`, `file_size`, `random_reproducible`, `random_differs`, `random_float_range`, `exec_rejects_injection`, `exec_simple`, `symbol`

---

### [2026-10-03] LONG-TERM MEMORY DUMP

- **Identified Truths**
  - `$g~Show` (method access không ngoặc) **đã được sửa**, xác minh bằng file `.ko` thật: `$g~Show` + `<printf>` → in `ok`. Issue #24 coi như xong.
  - 4 phép so sánh `a < b`, `a <= b`, `a > b`, `a >= b` **không hồi quy** sau khi sửa `isSystemTagOpener`.
  - `docker build` chạy thật thành công, `docker run ./ko --version` → `ko 0.1.0`.

- **Architectural Mutations**
  - Xoá 3 file `src/module/*/build.zig` — chúng là dead code vì `addSubdirectory` không tồn tại ở Zig 0.16.
  - `ko_exec` dùng `fork`/`execve`, thêm timeout, giới hạn output, từ chối ký tự shell.
  - `Random.c` dùng C11 atomics + CAS loop. Đo: 8 luồng × 448 cặp → **0 trùng lặp**.

- **Technical Debt & Anti-Patterns**
  - Zsh/fish **không có** trên máy → syntax của completion script cho 2 shell đó **chưa được verify**. bash đã verify OK.
  - `README.md` từng hướng dẫn sai path (`zig test src/test_3600.zig` thay vì `zig build test`). Đã sửa.
  - `gh` CLI có 2.98.0 nhưng **không xác thực** → phải dùng `github_*` MCP tools.

- **Shared Variables & Symbols**
  - `addPathDir(b.getInstallPath(.bin, ""))` để test tìm được binary helper
  - `mod_check_exe.root_module.linkSystemLibrary("dl", .{ .use_pkg_config = .force })`

---

## Chưa xác minh

- Completion script zsh/fish (thiếu shell trên máy)
- Bytecode backend chưa từng chạy thật
- Dict literal, `bytes(<expr>)`, `#11` vị trí token: **chưa sửa**
- Nhiều test chỉ assert "không crash" vì output bị discard → xanh chưa đồng nghĩa ngôn ngữ đúng
