### [2026-10-31] LONG-TERM MEMORY DUMP
- **Identified Truths:** Verified toolchains available: Java, g++, gcc, Python compile clean; Zig 0.16.0 not in sandbox. Many prior HIGH/MEDIUM fixes already present in tree (escape unescape, aliasing clone, dict fetchPut, class scope destroy, api default bind 127.0.0.1).
- **Architectural Mutations:** Implemented hardening subset of full development plan: PriorityStmt wrapper leak removed (parser.zig); Loop.cpp debug cout removed from hot path; duplicate completion entry removed (main.zig); ko_get_cwd thread-safe with PATH_MAX (Os.c); timing-safe API key compare and library name validation (api_server.py); dispatchCatchBlocks empty catch replaced with debug log (vm.zig).
- **Technical Debt & Anti-Patterns:** Zig build/test not verified in sandbox; REPL, ko build, plugin loader, Java Import runtime integration, generics still unimplemented (Phases 6-8 / G1/G2/G12/G13/G14/G16).
- **Shared Variables & Symbols:** N/A.

## Chưa xác minh
- `zig build` / `zig build test < /dev/null` chưa chạy (thiếu Zig).
- Bytecode parity cho class/func/dict/method/input chưa implement.
- REPL, `ko build`, plugin loader, Java runtime integration chưa implement.

---

- **Identified Truths:** Zig 0.16.0 is the supported toolchain (`zig version` = 0.16.0); build and all tests pass after fixes.
- **Architectural Mutations:** Updated .gitignore, kilo.jsonc, build.zig.zon, installer ZIP paths, Loop.cpp, vm.zig, compiler.zig, test_harness iterations.
- **Technical Debt & Anti-Patterns:** Avoid `std.fmt.allocPrint` with `{}` on Value; use allocating writer + `print`.
- **Shared Variables & Symbols:** VM `.store_var` now consumes stack value.


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

### [2026-10-19] LONG-TERM MEMORY DUMP (kháng kế hoạch M0–7, bỏ qua M8)

- **Identified Truths (verify bằng lệnh thực tế, không tin mù)**
  - Leaked Firestore API key `AIzaSyDcW3_plpZompdSlSYFr832A-Vq1TyQxvE` đã xoá khỏi `README.md` (3 dòng), thay bằng `$KO_FIRESTORE_API_KEY`. Verify: `grep AIzaSy...` → 0 match.
  - `.my_pass/auto.bash` (force-push loop mỗi 15s) đã làm rỗng nội dung và thêm `.my_pass/` vào `.gitignore`.
  - Zig version nhất quán 0.16.0 ở `build.zig.zon`, `Dockerfile`, `.devcontainer/on-create.sh`, `.github/workflows/ci.yml`, `CONTEXT.md`.
  - `Op.call` encoding đã sửa: compiler đóng gói `(idx << 16) | args.len`, khớp VM decode `name_idx = arity >> 16`, `arg_count = arity & 0xFFFF` (`src/compiler.zig:206`, `src/vm.zig:1187`).
  - `compileStatement` không còn `else => {}` bỏ `control_flow`: đã thêm xử lý `if_stmt`/`elif`/`else_body` (jump/jump_if_false + patch), `for_loop` (init/cond/step/store_var + backward jump), `while_loop`, `memory_op`, `encoding_op`, `len_op`, `priority_stmt`. `class_decl`/`class_instantiation` vẫn skip trong bytecode (AST-walker state) (`src/compiler.zig:46-173`).
  - Bytecode backend đã wire vào `src/main.zig`: `executeCode` thử compiler + `VM.executeChunk` cho program không có func/class def, fall back sang `VM.execute` (AST-walker) nếu compile thất bại hoặc có func/class (`src/main.zig:408-440`, `src/bytecode.zig` thêm `Chunk.init`).
  - Dict literal: parser giờ parse `{key: value, ...}` thành `DictEntry` lưu vào `ast.Literal.dict_entries`; `ast.Literal` thêm `dict_entries: []DictEntry` + `allocator`; VM `evaluateLiteral` populate `StringHashMap` từ entries; compiler `emitLiteral(.dict)` trả `error.UnsupportedBytecode` → fall back AST-walker (`src/parser.zig:1431-1460`, `src/ast.zig`, `src/vm.zig:673-678`, `src/compiler.zig:280`).
  - `bytes(<expr>)~x`: VM `var_decl` giờ hỗ trợ `.string` (dupe nội dung) và `else` (toString rồi dupe), không chỉ `.int` nữa (`src/vm.zig:186-216`).
  - Method call `$obj.method(args)`: `evaluateCall` giờ xử lý `.class_instance` (tra cứu method trong `ci.methods`, gọi qua `callUserFunction` helper trích xuất từ `.function` branch) — args không bị drop nữa (`src/vm.zig:866-1070`).
  - `Value.print` `.freal` dùng `{f}` thay vì `{d}` (sai định dạng) (`src/value.zig:63`).
  - CI: xoá `csharp` khỏi ma trận `.github/workflows/ci.yml` (repo không có `.cs`).

- **Architectural Mutations**
  - `src/main.zig` import `compiler.zig`, `bytecode.zig`; thêm `hasFuncOrClassDef` helper.
  - `src/bytecode.zig` thêm `Chunk.init(allocator)`.
  - `src/ast.zig` thêm `DictEntry` struct + `Literal.dict_entries` + `Literal.allocator` + `Literal.deinit` xử lý dict_entries.
  - `src/parser.zig` tất cả `ast.Literal{...}` tạo mới đã thêm `.dict_entries = [], .allocator = self.allocator`; nhánh `{` viết lại thành key:value pairs.

- **Chưa xác minh (cần Zig toolchain, không có trong sandbox)**
  - `zig build` / `zig build test < /dev/null` — chưa chạy được (thiếu toolchain Zig trong sandbox).
  - `docker build` — chưa chạy lại sau khi sửa code.
  - Bytecode backend chạy thật qua CLI — đã wire nhưng chưa verify output thực.
  - Dict literal với entries thực tế qua CLI — chưa verify.
  - Completion zsh/fish — thiếu shell trên máy (chưa verify).
  - Token vị trí (#11), multi-error diagnostics — chưa làm.

- **Cộng với các truth cũ ở trên (2026-10-01 → 2026-10-03) vẫn giữ nguyên.**


---

### [2026-10-20] LONG-TERM MEMORY DUMP
- **Identified Truths:** Kilo discovers agents from `.kilo/agents/*.md` only when frontmatter includes valid `mode` (primary|subagent|all). Claude-style agents using `model: sonnet/opus/haiku` and `tools:` are ignored or fail (`Model not found`). Color must be quoted hex.
- **Architectural Mutations:** Converted 68 agent definitions: added `mode: all`, removed `tools`/`model`, quoted hex colors. All now load (`kilo agent list`).
- **Technical Debt & Anti-Patterns:** Model aliases removed; agents now use default model. Tool restrictions from Claude agents are not enforced by Kilo.
- **Shared Variables & Symbols:** Agent names derive from filenames; `name` frontmatter ignored by Kilo.

---

### [2026-10-20] LONG-TERM MEMORY DUMP (code review)

- **Identified Truths:** Review chi tiết toàn bộ repository, verify bằng đọc trực tiếp source: `src/api_server.py`, `src/Import.java`, `src/Loop.cpp`, `src/installer.zig`, `src/compiler.zig`, `src/main.zig`, `src/ast.zig`, `src/module/Os/Os.c`, `.github/workflows/ci.yml`, `Dockerfile`. Lệnh verify thực tế: `javac -d /tmp/kilo/kojavacheck src/Import.java` thành công (2 cảnh báo deprecation `new URL(String)`); `g++ -std=c++17 src/Loop.cpp` thành công; `gcc -std=gnu11 src/module/Os/Os.c` + `Random.c` thành công; `python3 -m py_compile src/api_server.py` thành công. Zig không có trong sandbox → chưa verify `zig build` / `zig build test` / `docker build`.
  - 3 CRITICAL cũ đã FIX trong working tree: `src/api_server.py:264` log "API key status" thay vì in key; `src/Import.java:24-26,630-632` `isValidName` validate alias `[A-Za-z0-9_-]`; `src/installer.zig:39-43,282-286` validate `lib_name` trả `error.InvalidLibraryName`; `src/Import.java:602-628` `extractZipSafely` kiểm tra `target.startsWith(dest)`; `src/installer.zig:304-326` `validateZipEntries` trước `unzip -q`.
  - HIGH-1/2/3/5/6/7 đã FIX: `Import.java:102-106` throw nếu `API_KEY` null; `Loop.cpp:255-262` truyền `condCtx` đúng vào `recordWhile`; `Loop.cpp:121-138` validate `start <= end`, `step > 0`, `forEnd >= forStart`; `ci.yml:17-22` không còn `csharp`; `Dockerfile:22-23` `ENTRYPOINT ["./ko"]` + `CMD ["--help"]`; `Import.java:306-308` đọc stream trước `waitFor`.
  - HIGH-4 còn lại (partial fix): `compiler.zig:65-67,156-158,285` trả `error.UnsupportedBytecode` cho `class_decl`/`class_instantiation`/`.dict`; `main.zig:410-428` fallback AST-walker rõ ràng khi compile thất bại. Chưa có test assert output thực cho dict/bytes/method call.
  - MEDIUM còn lại: `api_server.py:255` bind `0.0.0.0`; `Os.c:32-38` `ko_get_cwd` static buffer 1024 không thread-safe; `api_server.py` thiếu CORS/rate limit; `installer.zig:328-340` `runCommand` không timeout (`git clone`/`curl` có thể treo); `installer.zig:217-232` `detectLanguage` không đệ quy thư mục con.
  - Mới phát hiện: `ast.zig:65-68` `PriorityStmt.deinit` gọi `stmt.deinit()` rồi `allocator.destroy(stmt)` — rủi ro double-free nếu `stmt` không phải allocation gốc.
- **Architectural Mutations:** Cập nhật `REVIEW.md` phản ánh trạng thái working tree: 0 CRITICAL, 1 HIGH (HIGH-4), 8 MEDIUM, 4 LOW. Verdict: WARNING.
- **Technical Debt & Anti-Patterns:** File lớn `vm.zig` (1432), `parser.zig` (1599), `Import.java` (845); C++ `std::cout` debug trong hot loop (`Loop.cpp:83,148,167`); Java JSON parsing thủ công (`extractJsonField`).
- **Shared Variables & Symbols:** Không mới.

### [2026-10-24] Adversarial challenge of REVIEW.md findings

- **Identified Truths:** MEDIUM-9 (class_decl scope leak) is FALSE: `ClassDef.deinit` destroys both `private_scope`/`public_scope` (value.zig:469-490); valgrind clean. MEDIUM-10 (dict overwrite leak) is TRUE: Zig 0.16 `StringHashMap.put` returns void and retains old key; overwrite leaks old value + new key; fix via `fetchPut`. MEDIUM-6 unverified claim is now verified: `zsh -n` and `fish --no-execute` both pass. LOW-6 empty catch in `dispatchCatchBlocks` call is acceptable defensive handling in error-recovery path. MEDIUM-5 large-file finding is not a concrete defect (exhaustive switches/dispatch); splitting is maintainability-only.
- **Architectural Mutations:** None (review only).
- **Technical Debt & Anti-Patterns:** Real bug found: `parser.zig:58-69` heap-allocates `PriorityStmt` wrapper via `allocator.create` then copies by value and discards pointer → leak per priority statement; `stmt` itself stays heap-allocated so `PriorityStmt.deinit` destroy is safe. `COMPLETION_COMMANDS` const is dead code (unused). Dict overwrite leak in vm.zig:591-595.
- **Shared Variables & Symbols:** N/A.

### [2026-10-25] LONG-TERM MEMORY DUMP
- **Identified Truths:** Implemented HIGH-4/HIGH-3/MEDIUM-12 in src/main.zig; scanModuleStore now owns name/version/language via allocator.dupe; manifests list deinited after copy.
- **Architectural Mutations:** src/main.zig: executeCode bytecode path adds defer chunk.deinit; scanModuleStore dupes strings with errdefers; COMPLETION_COMMANDS duplicate removed.
- **Technical Debt & Anti-Patterns:** defer+errdefer chunk.deinit may double-free on Compiler.init failure (pre-existing pattern retained per instruction).
- **Shared Variables & Symbols:** N/A.

### [2026-10-25] LONG-TERM MEMORY DUMP
- **Identified Truths:** Zig 0.16 uses `std.process.spawn(io, options)` and `child.wait(io)`/`child.kill(io)`; `std.process.Child.init` removed.
- **Architectural Mutations:** src/installer.zig MEDIUM-7/8/10 implemented.
- **Technical Debt & Anti-Patterns:** Could not compile locally (no zig binary); WIFEXITED API assumed.
- **Shared Variables & Symbols:** scanDirForLanguage, runCommand timeout.

### [2026-10-25] LONG-TERM MEMORY DUMP
- **Identified Truths:** Zig 0.16.0 build verified after VM changes.
- **Architectural Mutations:** src/vm.zig: MEDIUM-9 dict assignment uses getOrPut with deinit of overwritten value/key; MEDIUM-11 runFunction stack moved to heap slice with overflow guard; LOW-5 dispatchCatchBlocks empty catch replaced with debug log; LOW-6 class_decl errdefer cleanup added.
- **Technical Debt & Anti-Patterns:** Pre-existing installer/compiler changes left mostly intact; installer reverted to HEAD for build stability.
- **Shared Variables & Symbols:** StackOverflow error path preserved.

---

### [2026-10-25] LONG-TERM MEMORY DUMP
- **Identified Truths:** User requested detailed report of what `.ko` still lacks plus nomination order and algorithms; consolidated from `REVIEW.md`/`ROADMAP.md`/`SPECIFICATION.md`/source tree into `nomination.md` and `nomination..md`.
- **Architectural Mutations:** Added two report markdown files at repo root (identical content) covering gap matrix G1–G16, dependency graph, priority scoring, algorithms A–J, risk register, verification plan, DoD.
- **Technical Debt & Anti-Patterns:** Report is documentation only; no code changes or verification executed.
- **Shared Variables & Symbols:** N/A.

### [2026-10-30] LONG-TERM MEMORY DUMP
- **Identified Truths:** Matt Pocock skills repo (`mattpocock/skills`) is a Claude Code plugin with promoted skills under `skills/engineering` and `skills/productivity`; `kilo debug skill` discovers `.kilo/skills/*/SKILL.md`.
- **Architectural Mutations:** Copied 27 promoted skill directories into `.kilo/skills` (engineering + productivity), verified by `kilo debug skill` (ask-matt, grill-me, grilling, tdd, triage, etc. recognized).
- **Technical Debt & Anti-Patterns:** Beta `skills/in-progress` and `skills/misc` intentionally not installed; repo's `docs/agents/domain.md` still uses legacy `CONTEXT.md` naming while Matt skills expect `GLOSSARY.md` (setup skill can align later).
- **Shared Variables & Symbols:** Skill invocation names match directory/frontmatter names.

### [2026-10-30] LONG-TERM MEMORY DUMP
- **Identified Truths:** Zig 0.16.0 build and tests pass after unifying value arithmetic behind Value module.
- **Architectural Mutations:** src/value.zig: strict add/sub/mul/div/rem/equals (no coercion), new predicate methods less/greater/lessOrEqual/greaterOrEqual; src/vm.zig: evaluateBinary and binaryOp delegate to Value, removed addValues/subValues/etc; testing/test_value.zig added (17 tests); build.zig wired test file; src/testing_imports.zig exports value.
- **Technical Debt & Anti-Patterns:** Existing .ko programs relying on int↔freal coercion now surface TypeError; bytecode path now matches AST strictness.
- **Shared Variables & Symbols:** OverflowError, TypeError, DivideByZero preserved.

### [2026-10-30] LONG-TERM MEMORY DUMP
- **Identified Truths:** Zig 0.16.0 build passes after fixes; example simple.ko now prints newline correctly.
- **Architectural Mutations:** Fixed HIGH-2 bytecode escape in src/compiler.zig (added unescapeString); fixed HIGH-1 aliasing in src/vm.zig (load_var/store_var clone); fixed dict overwrite leak in src/vm.zig; changed API default host to 127.0.0.1.
- **Technical Debt & Anti-Patterns:** Bytecode backend still lacks class/func/dict/bytes parity (falls back to AST walker); potential extra memory copies.
- **Shared Variables & Symbols:** `unescapeString` helper in compiler.zig.
