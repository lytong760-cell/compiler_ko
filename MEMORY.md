### [2026-11-18] LONG-TERM MEMORY DUMP
- **Identified Truths:** 978 case (913 corpus + 65 targeted) → 0 crash, 0 hang. RC: {2:~730, 0:~110, 3:~79}. xac nhan BUG-1/2/6 (fix 2026-11-15) giu vung: moi runtime error tra rc=3 khong con 134. Phat hien parity/spec gap (khong crash, nguy hiem hon vi am tham): A1 tuple/list `(1,2,3)` parse fail (parser_expr.zig l_paren); A2 `<$random>(...)` parse fail (parseSystemTagName khong nhan .dollar, parser_expr.zig:8); A3 `bytes(<encode(...)>)` parse fail; B1 `<print>string^("x={x}")` khong noi suy; B2 `bytes(8)` + `<len>` tra 0; B3 `$f~get()` method call NameError (callUserFunction khong bind self, vm_value_ops.zig:197); B5 `type(x)` UndefinedFunction; C1 `<foo>` unknown tag im lang; C2 `(10)~x` thieu kieu im lang.
- **Architectural Mutations:** Cap nhat BUG.md (them bao cao 978 case cuoi file), CHECKPOINTS.md, MEMORY.md. KHONG sua source.
- **Technical Debt & Anti-Patterns:** Test suite hien chi chay qua VM.execute (AST walker) → mu hoan toan voi duong bytecode; can them test qua Executor de bat parity. Catch dat SAU cau loi khong bat duoc ( dung SPEC §IX.2 backward scan — khong phai bug). var_decl top-level + printf top-level hop le (SPEC §V.1) — khong phai bug.
- **Shared Variables & Symbols:** parseSystemTagName (parser_expr.zig:8) — phai them .dollar de ho tro <$tag>. callUserFunction (vm_value_ops.zig:197) — phai bind instance vao scope cho method.

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

### [2026-11-06] LONG-TERM MEMORY DUMP
- **Identified Truths:** Graphify 0.9.103 (pip `graphifyy[mcp]`) provides stdio MCP server `python -m graphify.serve <graph.json>` exposing 10 tools (query_graph, get_node, get_neighbors, get_community, god_nodes, graph_stats, shortest_path, list_prs, get_pr_impact, triage_prs). Kilo MCP config uses `mcp` key with `type: local`, `command` array, `enabled`, `timeout`; permission keys `{server}_*`. Config shared by Kilo CLI/VS Code/Kilo Code ecosystem via global `~/.config/kilo/kilo.jsonc` and project `.kilo/kilo.jsonc`.
- **Architectural Mutations:** Installed graphifyy[mcp] into /home/codespace/.python/current; ran `graphify install --platform kilo` (skill + command under ~/.config/kilo); built `graphify-out/graph.json` (10564 nodes, 10554 edges, 755 communities) via `graphify update .`; registered `graphify` MCP server in global + project configs with absolute python path and absolute graph path; granted `graphify_*` allow. Verified server initialize/tools/list (~2s).
- **Technical Debt & Anti-Patterns:** Graph is AST-only (no semantic LLM extraction); rebuild needed after code changes (`graphify update .`); absolute python path is environment-specific. Hosted remote MCP (api.graphify.com/mcp, OAuth) is alternative but not configured.
- **Shared Variables & Symbols:** graphify-out/graph.json; /home/codespace/.python/current/bin/python3.
- **Architectural Mutations:** Fixed HIGH-2 bytecode escape in src/compiler.zig (added unescapeString); fixed HIGH-1 aliasing in src/vm.zig (load_var/store_var clone); fixed dict overwrite leak in src/vm.zig; changed API default host to 127.0.0.1.
- **Technical Debt & Anti-Patterns:** Bytecode backend still lacks class/func/dict/bytes parity (falls back to AST walker); potential extra memory copies.
- **Shared Variables & Symbols:** `unescapeString` helper in compiler.zig.


### [2026-11-11] LONG-TERM MEMORY DUMP
- **Identified Truths:** Session bootstrapped: đã nạp MEMORY.md và CHECKPOINTS.md vào ngữ cảnh. **Zig 0.16.0 đã sẵn trong sandbox** (`zig version = 0.16.0`). **Verify thực tế:** `zig build` thành công; `zig build test < /dev/null` exit code 0, toàn bộ suite pass (227 tests: test_harness 1, test_3600 117, test_value 17, test_lexer_extended 40, test_parser_extended 41, test_modules 11), 0 leak. Thông báo "failed command: ... --listen=-" là artifact Zig test runner đọc stdin, không ảnh hưởng exit code. **Sửa code 2 bug:** (1) `src/vm_value_ops.zig` `evaluateInput`: thêm `defer self.allocator.free(line)` (tránh 3 leak allocation mỗi <input>); (2) `src/vm.zig` `execute`: mở rộng `allowed_top` (thêm var_decl, class_instantiation, priority_stmt) để method call + var decl chạy top-level. Các test file đã bỏ comment trong `build.zig` (6 file chạy đầy đủ).
- **Phase 5 hoàn thành (theo yêu cầu user):** (1) `evaluateIdentifier` ném `TypeError` khi đọc biến có giá trị `.null` (chưa assign); (2) Parser validate region `@`: `@loop` chỉ trong loop, `@girc` chỉ trong generic (validator ở parser, có span); `none` (immutable) + `type()` + priority `{n}` đã có sẵn. Toàn bộ suite xanh 227 tests.
- **Architectural Mutations:** build.zig: bỏ comment 5 file test. src/vm_value_ops.zig: defer free line trong evaluateInput + TypeError khi đọc .null. src/vm.zig: mở rộng allowed_top trong execute. src/parser.zig: thêm context flags in_class/in_loop/in_generic + validateRegionRole.
- **Technical Debt & Anti-Patterns:** `zig build test` dùng `--listen=-` làm treo nếu stdin không đóng; luôn chạy với `< /dev/null`. Chạy trực tiếp test binary thiếu `zig-out/bin` trong PATH → test_modules fail FileNotFound (mod_check không tìm được); phải chạy qua `zig build test`.
- **Shared Variables & Symbols:** Chưa có mới trong phiên này.

### [2026-11-13] LONG-TERM MEMORY DUMP
- **Identified Truths:** **Phase 5 (G9-G11) hoàn tất, verify bằng `zig build` exit 0 và `zig build test < /dev/null` EXIT=0 (230 tests pass).** Spec §3 Null/None đã đối chiếu: (1) `Value.print` ném `error.TypeError` khi gặp `.null`; tách `printAllowNull` (in "null") cho đường chẩn đoán — phải đệ quy gọi `printAllowNull` (không gọi `print`) để phá dependency loop Zig; (2) `parseBlock` (parser.zig) sort priority bằng decorate-sort-undecorate: `std.sort.block` là unstable + comparator cũ trả `false` khi bằng priority → vi phạm strict weak ordering, nay sort theo `(priority, index gốc)`; (3) `vm.execute` quét `global_scope.variables` cuối chương trình, ném `NullUnassigned` nếu còn `.null`; (4) `printf` cả 2 đường (evaluateCall + callBuiltin) và `appendValueToString` chặn `.null`. Thêm 3 test vào test_parser_extended.zig (44 tests).
- **Architectural Mutations:** src/value.zig: print/printAllowNull tách biệt. src/parser.zig: parseBlock decorate-sort-undecorate. src/vm.zig: null-scan cuối execute. src/vm_value_ops.zig: guard null ở appendValueToString/printf/callBuiltin.
- **Technical Debt & Anti-Patterns:** `std.sort.block` KHÔNG stable — mọi comparator trả `false` cho phần tử "bằng nhau" là bug tiềm ẩn khi cần giữ thứ tự nguồn. Dependency loop Zig xảy ra khi 2 hàm suy ra error set của nhau qua đệ quy chéo; phải chỉ định đệ quy một chiều.
- **Shared Variables & Symbols:** `Value.printAllowNull` (chẩn đoán), `error.NullUnassigned` (mới trong VM).

### [2026-11-13] LONG-TERM MEMORY DUMP — `ko build` standalone
- **Identified Truths:** **`ko build` giờ tạo binary standalone thật, verify bằng lệnh thật:** `./zig-out/bin/ko build examples/simple.ko` → in "Hello World" (validate) + tạo `build/simple` (19.8MB, 755); `cp build/simple /tmp/standalone_test && /tmp/standalone_test` → in "Hello World", exit 0, **không cần `ko` trong PATH**. `zig build` exit 0; `zig build test < /dev/null` EXIT=0 (230 tests). **Bug nghiêm trọng đã sửa:** dùng chuỗi marker literal (`__KO_STANDALONE_V1__`) để tìm payload là SAI — compiler nhúng chính literal đó vào read-only data của nó, nên `readStandaloneSource` luôn match code bytes → CLI hỏng hoàn toàn (`ko --version` cũng trả về source rác, `UnexpectedToken`). Chuyển sang **footer ở cuối file**: `<compiler bytes><source><payload_len u64 LE><magic u64 LE 0x4B4F5F5341414E44>`, đọc từ EOF lùi lại; binary gốc không có footer nên không bao giờ bị nhận nhầm.
- **Architectural Mutations:** src/main.zig: thêm `STANDALONE_FOOTER_MAGIC`, `buildStandalone` (copy self exe + source + footer + chmod +x), `readStandaloneSource` (validate footer, đọc ngược); `mainInner` gọi `readStandaloneSource` trước mọi xử lý argv.
- **Technical Debt & Anti-Patterns:** **Không bao giờ dùng chuỗi literal làm "magic marker" để phân biệt binary gốc vs binary đã nhúng payload** — compiler sẽ nhúng literal đó vào chính nó. Dùng footer ở cuối file (hoặc section riêng) với magic number dạng integer. API Zig 0.16: `std.process.executablePathAlloc(io, allocator)` (KHÔNG phải `getExecutablePathAlloc`); `Io.Dir.CreateFileOptions` KHÔNG có field `mode` — phải `chmod` sau khi tạo.
- **Shared Variables & Symbols:** `buildStandalone`, `readStandaloneSource`, `STANDALONE_FOOTER_MAGIC` (main.zig).

---

### [2026-11-12] LONG-TERM MEMORY DUMP

- **Identified Truths:** Zig 0.16.0 đã sẵn trong sandbox (`zig version = 0.16.0`). **Verify thực tế:** `zig build` thành công (không output lỗi). `zig build test < /dev/null` exit code 0, toàn bộ suite pass (227 tests: test_harness 1, test_3600 117, test_value 17, test_lexer_extended 40, test_parser_extended 41, test_modules 11), 0 leak. Thông báo "failed command: ... --listen=-" là artifact Zig test runner đọc stdin, không ảnh hưởng exit code.
- **Architectural Mutations:** Không có thay đổi code trong phiên này (chỉ verify trạng thái hiện có).
- **Technical Debt & Anti-Patterns:** `zig build test` dùng `--listen=-` làm treo nếu stdin không đóng; luôn chạy với `< /dev/null`. Chạy trực tiếp test binary thiếu `zig-out/bin` trong PATH → test_modules fail FileNotFound (mod_check không tìm được); phải chạy qua `zig build test`.
- **Shared Variables & Symbols:** `KO_FIRESTORE_API_KEY` (biến môi trường, không hardcode).

---

### [2026-11-12] LONG-TERM MEMORY DUMP (URL Module Store)

- **Identified Truths:** Đã thay đổi URL Module Store trong `SPECIFICATION.md:490` từ `https://ko-vietnam.ai.studio/mobule-store` sang `https://ko-lang.ai.studio/mobule-store`. Verify bằng `grep ko-lang SPECIFICATION.md` → 1 match, `grep ko-vietnam SPECIFICATION.md` → 0 match.
- **Architectural Mutations:** Sửa 1 dòng trong SPECIFICATION.md (URL Module Store). Không thay đổi code build hay runtime.
- **Technical Debt & Anti-Patterns:** URL này chỉ là documentation trong SPECIFICATION.md; code installer (`src/installer.zig`) đọc API key từ env và gọi Firestore project `argon-shine-w40ks`, không hardcode URL module-store trong code Zig.
- **Shared Variables & Symbols:** `KO_FIRESTORE_API_KEY` (biến môi trường, không hardcode).

---

### [2026-11-12] LONG-TERM MEMORY DUMP (Module Store API)

- **Identified Truths:** Đã thay đổi Module Store API trong `SPECIFICATION.md` và `src/installer.zig`: bỏ Firestore REST API, dùng REST API JSON thuần của `https://ko-lang.ai.studio`.
  - `ko -list` → `GET https://ko-lang.ai.studio/api/module` (trả JSON array).
  - `ko -install <name>` → `GET https://ko-lang.ai.studio/api/module/<name>` (trả JSON object với `githubLink`/`githubUrl`).
  - Verify thực tế: `zig build` exit 0; `zig build test < /dev/null` exit 0, 227 tests pass.
- **Architectural Mutations:** 
  - `SPECIFICATION.md`: thay sección "Library Registry Gateway and API" từ Firestore endpoints thành REST API JSON mới (`/api/module`, `/api/module/<name>`).
  - `src/installer.zig`: xoá hằng `FIRESTORE_BASE`/`FIRESTORE_PARENT`, hàm `getApiKey`; thêm `MODULE_STORE_BASE = "https://ko-lang.ai.studio"`; `listLibraries()` gọi `curl -s {base}/api/module`; `queryLibraryMetadata()` gọi `curl -s {base}/api/module/{name}` và trả về toàn bộ JSON text; `extractStringField()` viết lại để parse JSON thuần (`"field":"value"`) thay vì định dạng Firestore (`"stringValue"`).
- **Technical Debt & Anti-Patterns:** `extractStringField` là JSON parser đơn giản (hand-rolled), không xử lý escaped string trong value; đủ cho metadata module store hiện tại. Không còn đọc `KO_FIRESTORE_API_KEY` trong installer (API mới không yêu cầu key theo spec).
- **Shared Variables & Symbols:** `MODULE_STORE_BASE` hằng trong installer.zig.

---

### [2026-11-12] LONG-TERM MEMORY DUMP (Module Store API cleanup in SPECIFICATION.md)

- **Identified Truths:** Đã xóa hoàn toàn mọi tham chiếu đến Firestore khỏi `SPECIFICATION.md` (trừ 1 ghi chú lịch sử tại dòng 781 về việc xóa API key rò rỉ). Flow diagram bước 2 đã đổi từ "Firestore GET API Query" thành "Module Store REST API Query: GET https://ko-lang.ai.studio/api/module/<library>". Verify bằng `grep -i firestore SPECIFICATION.md` → chỉ còn 1 match tại dòng 781 (ghi chú lịch sử).
- **Architectural Mutations:** Sửa SPECIFICATION.md: endpoint list/install và flow diagram đã dùng REST API JSON mới của `ko-lang.ai.studio`.
- **Technical Debt & Anti-Patterns:** Không còn hardcode URL Firestore nào trong spec.
- **Shared Variables & Symbols:** `MODULE_STORE_BASE` hằng trong installer.zig.

---

### [2026-11-12] LONG-TERM MEMORY DUMP (Module Store API real-structure verify)

- **Identified Truths:** Đã curl thực tế API `https://ko-lang.ai.studio` để xác minh cấu trúc JSON thật:
  - `GET /api/module` → JSON array: `[{"name":"cloud","githubLink":"https://github.com/lytong760-cell/cloud","description":"none","tags":["zig"],"userId":"...","createdAt":"...","detail":{...}}]`
  - `GET /api/module/<name>` → JSON object: `{"name":"cloud","detail":{"name":"cloud","githubLink":"...","description":"none","tags":["zig"],"userId":"...","createdAt":"..."}}`
  - `githubLink` nằm **trong `detail`** (nested), không ở cấp cao nhất. Không có `version`, `language`, `githubUrl`, `zipUrl` trong response thật.
  - Verify thực tế: `zig build` EXIT=0; `zig build test < /dev/null` EXIT=0, 227 tests pass.
- **Architectural Mutations:**
  - `SPECIFICATION.md`: cập nhật ví dụ response JSON cho `/api/module` và `/api/module/<name>` khớp với cấu trúc thật (có `detail` nested, có `tags`, `userId`, `createdAt`).
  - `src/installer.zig`: thêm `extractDetailField()` parse JSON nested `"detail":{...}` để lấy `githubLink`; xoá `extractStringField()` cũ (không dùng nữa); `installLibrary()` gọi `extractDetailField(metadata, "githubLink")`.
- **Technical Debt & Anti-Patterns:** `extractDetailField` là JSON parser hand-rolled đơn giản, chỉ xử lý quoted string value, không xử lý escaped string. Đủ cho metadata module store hiện tại.
- **Shared Variables & Symbols:** `MODULE_STORE_BASE` hằng trong installer.zig.

---

### [2026-11-12] LONG-TERM MEMORY DUMP (Module Store API spec placeholder)

- **Identified Truths:** Đã cập nhật `SPECIFICATION.md` dùng placeholder `<name>`, `<url>`, `<description>`, `<tag>`, `<userId>`, `<timestamp>` thay vì giá trị cứng "cloud" trong ví dụ response JSON của `/api/module` và `/api/module/<name>`. Cấu trúc JSON khớp với curl thực tế đã verify trước đó (githubLink nằm trong `detail` nested).
- **Architectural Mutations:** Sửa SPECIFICATION.md: ví dụ JSON response dùng placeholder generic.
- **Technical Debt & Anti-Patterns:** Không có.
- **Shared Variables & Symbols:** `MODULE_STORE_BASE` hằng trong installer.zig.

---

### [2026-11-15] LONG-TERM MEMORY DUMP — Fix 6 bug từ BUG.md

- **Identified Truths:** Đã fix toàn bộ bug trong `BUG.md`, verify bằng lệnh thật:
  ```
  zig build                                 → rc=0
  zig build test < /dev/null                → EXIT=0 (15/15 pass)
  [ Nope() ]                                → rc=3 (trước: 134 crash)
  [ int(1)~a int(0)~b int(a/b)~c ]          → rc=3 (trước: 134)
  [ string("")~s <input>(s) <printf>^(s) ]   → in "x" (trước: TypeError + crash)
  [ int(7)~x <printf>^("x={x}\n") ]         → "x=7" (trước: "x={x}")
  [ null~x <printf>^(x) ]                    → "TypeError: Cannot print an unassigned null value" (trước: message rỗng)
  ```
  - **BUG-1 (double-free, CRITICAL):** `src/executor.zig` dùng `errdefer chunk.deinit()` + 3 lời gọi `chunk.deinit()` tường minh trong nhánh catch/return. Khi lỗi runtime → `chunk.deinit()` tường minh rồi `return error` → `errdefer` free lần 2 trên cùng con trỏ → heap corruption (rc=134). **Fix:** `errdefer` → `defer` + cờ `freed: bool`; mọi đường thoát chỉ free một lần.
  - **BUG-2 (input+printf crash, CRITICAL):** Cùng root cause với BUG-6. `[ string("")~s <input>(s) <printf>^(s) ]` store `s` 2 lần (var_decl + input); lần 2 `fetchPut` free key cũ → key trong map thành dangling → `load_var s` trả null → `TypeError` + crash. Chỉ xảy ra khi store ≥2 lần.
  - **BUG-3 (mất nội suy printf, HIGH):** `vm.zig` `.print` instruction handler (dùng cho `<printf>` bytecode) gọi `val.print()` trực tiếp, không nội suy `{x}`. AST walker (`evaluateCall`) gọi `printInterpolated`. **Fix:** `.print` handler: `val == .string` → `printInterpolated(val.string)`. (Lưu ý: `callBuiltin("printf")` cũng thiếu nội suy — đã sửa tương tự, nhưng đường bytecode thực tế đi qua `.print` instruction.)
  - **BUG-4 (nuốt message lỗi, HIGH):** `vm.zig` `raiseError` có `_ = message;` vứt bỏ toàn bộ ngữ cảnh. **Fix:** in `"{err_type}: {message}\n"` qua `stdoutWriter()` (giữ test hermetic — harness dùng discarding writer).
  - **BUG-5 (5 đường deinit, MEDIUM):** Gộp cùng BUG-1 — `defer` + cờ `freed`.
  - **BUG-6 (fetchPut use-after-free, CRITICAL — root cause thật của BUG-2):** 3 chỗ trong `src/vm.zig` (`.store_var` ~932, `assignValue` dict ~748, `.dict_set` ~1314) gọi `fetchPut(owned, val)` rồi `free(old_entry.key)`. **Zig 0.16 `fetchPut` GIỮ KEY CŨ** khi key đã tồn tại (chứng minh: `OLDKEY k1=true k2=false`, `KEPT k1=true k2=false`) → `old_entry.key` CHÍNH LÀ key map đang dùng → `free` nó = use-after-free → key thành rác → mọi `get()` sau đó trả null. **Fix:** khi `fetchPut` trả `Some(old)`: **free key MỚI** (`owned`/`key_copy`/`duped_key`), giữ `old_entry.key`; chỉ deinit `old_entry.value`.

- **Architectural Mutations:**
  - `src/executor.zig`: `errdefer chunk.deinit()` → `defer if (!freed) chunk.deinit()` + cờ `freed`.
  - `src/vm.zig`: `.print` handler nội suy string; `raiseError` in message; `.input` handler bỏ `dupe` lần 2 (dùng `line` trực tiếp); 3 chỗ `fetchPut` free key mới thay vì key cũ.
  - `src/vm_value_ops.zig`: `callBuiltin("printf")` nội suy string (đồng nhất với `evaluateCall`).
  - `BUG.md`: thêm mục "TRẠNG THÁI: ĐÃ FIX" + BUG-6 (fetchPut).

- **Technical Debt & Anti-Patterns:**
  - **`fetchPut` giữ key cũ** — đây là biến thể tinh vi của MEDIUM-10 (MEMORY 2026-10-24 nói "fix via fetchPut", nhưng fetchPut **cũng** giữ key cũ nên vẫn phải cẩn thận: không bao giờ `free(old_entry.key)`).
  - **`errdefer` + free tường minh = double-free** — `errdefer` phải là chủ sở hữu duy nhất. Nếu đã `defer`/`errdefer`, không được `deinit` thủ công rồi `return error`.
  - **Test suite mù với bytecode** — `testing/test_3600.zig` gọi thẳng `VM.execute()` (AST walker), không qua `Executor` → không bao giờ chạm đường bytecode. Đây là lý do BUG-1/2/3 tồn tại lâu: `format_int_interpolation` xanh trong khi CLI in sai `x={x}`.
  - **Debug bằng cách thêm print tạm** là cách duy nhất tìm ra BUG-6: triệu chứng (`TypeError`) không chỉ đúng nguyên nhân (key map bị free). Phải in từng instruction (`.store_var`/`.load_var`/key iterator) mới thấy key là byte rác.

- **Shared Variables & Symbols:**
  - `freed: bool` (cờ trong `executor.execute`).
  - `printInterpolated` (đã có, giờ dùng cả ở `.print` handler bytecode).
  - `error.NullUnassigned`, `Value.printAllowNull` (giữ nguyên).

---

### [2026-11-15] LONG-TERM MEMORY DUMP — Kiểm chứng semantics `fetchPut` (Zig 0.16)

- **Identified Truths:** Test `std.StringHashMap(i32)` cho kết quả:
  ```
  OLDKEY k1=true  k2=false   ← fetchPut trả về entry với key CŨ (k1)
  KEPT   k1=true  k2=false   ← map GIỮ key cũ (k1), KHÔNG thay bằng key mới
  GET=2                       ← value mới được store
  ```
  → Khi `fetchPut` trả `Some(old_entry)`, `old_entry.key` là key đang nằm trong map. Key mới (`owned`/`key_copy`/`duped_key`) KHÔNG được dùng → phải free key mới, không free key cũ.

- **Architectural Mutations:** Không (đây là chân lý ngôn ngữ, dùng để fix BUG-6).

- **Technical Debt & Anti-Patterns:** Mọi code dùng `fetchPut` + `free(old.key)` đều là use-after-free tiềm ẩn. Đã fix 3 chỗ trong `src/vm.zig`; các `.put()` khác chỉ leak key mới (không crash) nhưng vẫn nên rà soát.

- **Shared Variables & Symbols:** N/A.

---

### [2026-11-15] LONG-TERM MEMORY DUMP
- **Identified Truths:** architecture.drawio.svg is a draw.io-compatible file: outer SVG with `content` attribute holding escaped mxfile; both layers must be valid XML.
- **Architectural Mutations:** Replaced placeholder 1x1 SVG with full architecture diagram derived from SPECIFICATION.md.
- **Technical Debt & Anti-Patterns:** None.
- **Shared Variables & Symbols:** Node IDs: title, src, lex, ast, scope, eng, exec, state, srcbox, cond, imp, loop, java, cpp, zig, ph1..ph8, cf1..cf6, secA..secE, d1..d3, s1..s7.

### [2026-11-24] LONG-TERM MEMORY DUMP (Kilo / Lane B)
- **Identified Truths:** `zig build` → rc=0 (worktree kilo, có ast.zig/parser.zig/parser_expr.zig từ Lane A copy vào để build); `zig build test < /dev/null` → 10/10 test_executor case pass (b1 print, b1 printf, b2 bytes len, b5 type string, b5 type int, m1 catch, b3 method reads field, m3 unknown tag, a1 tuple). B2 bytes(8)+<len>=8, B1 print="x=7", B5 type("hi")="string", type(123)="int", M3 <foo>=UnknownSystemTag rc=3, B3 method=5, M1 catch không vào body khi không lỗi, A1 tuple `(1,2,3)~t` → `(1, 2, 3)`. Leaks (known, test harness only): b2 +2, b5 +1+1, b3 +6, m3 +1, a1 +2; không ảnh hưởng correctness. Chạy trực tiếp `ko run` các file /tmp/kilo/t1..t8.ko, ta1/ta1b/ta1c xác nhận lại.
- **Architectural Mutations:** `.kilo/worktrees/kilo/src/executor.zig` (`setOutputWriter`, `requiresAstWalker` thay `hasFuncOrClassDef` + `catch_stmt` → AST walker) [M1]; `src/vm_value_ops.zig` (print→`printInterpolated` [B1], `callBuiltin` +`bytes`/+`type` [B2,B5], `evaluateSystemTag` ném `UnknownSystemTag`+raiseError [M3/C1], `callUserFunction`/`Values` +`instance`+clone `ci.fields` vào scope [B3], `evaluateCall` +`type()` [B5], `valueTypeName` helper, `evaluateLiteral` `.tuple` duyệt `lit.elements` build `Value.tuple` [A1-runtime]); `src/vm.zig` (`.len` +`.bytes` [B2], `call_method` +`target_instance` [B3], `callUserFunction`/`Values` wrappers +`instance`, `.make_tuple` handler build slice Value [A1-runtime]); `src/compiler.zig` (`compileVarDecl` bytes→buffer [B2], `emitLiteral` `.tuple` compile elements + emit `.make_tuple` [A1-runtime]); `src/bytecode.zig` (+Op `make_tuple: u32`, +Instruction `make_tuple` [A1-runtime]); `testing/test_executor.zig` (mới, qua `Executor.execute`, bo prefix `exposeProcess`, 10 case); `build.zig` (wire test). Root `testing/test_executor.zig` + `build.zig` + src/* Kilo da sync. Releases = 847986e1 (co Land A ast.Literal.elements + parser tuple) → root `zig build` rc=0, `zig build test < /dev/null` 10/10 pass (leaks known test harness). Worktree kilo (kilo/fix-runtime) da `git rebase Releases` thanh cong (commit a63bd0dc -> 514ea974 tren Releases), zig build test 10/10 pass.
- **Technical Debt & Anti-Patterns:** Test suite cũ chỉ qua `VM.execute` (AST walker) → mù bytecode; mới test qua `Executor.execute` (hợp lý plan §5.2). Leaks trong test harness do `bytes` buffer + clone không free trong capture (không phải runtime bug). Hợp đồng A1: Lane A thêm `ast.Literal.elements` + `deinit` (ast.zig:250-281), Kilo tiêu thụ `lit.elements` (evaluateLiteral, compiler.zig emitLiteral).
- **Shared Variables & Symbols:** `callUserFunction(self, func, args, instance?)`, `callUserFunctionValues(self, func, args, instance?)`; `valueTypeName(v) → []const u8`; `requiresAstWalker(program) → bool`; `exposeProcess()` ghi prefix `{file_path}:main` (test capture bo dòng này).

### [2026-11-24T06:39:26Z] LONG-TERM MEMORY DUMP (Kilo / Lane B — hoan tat)
- **Identified Truths:** Da merge `kilo/fix-runtime` (commit a63bd0dc) vao `Releases` (commit merge 216a750f tren Releases). `zig build test < /dev/null` tai Releases: 10/10 pass (leaks known test harness, khong anh huong correctness). `graphify update .` thanh cong: 10773 nodes, 10786 edges, 776 communities; graph.json/graph.html/GRAPH_REPORT.md duoc cap nhat trong graphify-out. Da xoa worktree `.kilo/worktrees/kilo`. Con lai worktree `.kilo/worktrees/claude` (claude/fix-parser, cua Lane A).
- **Architectural Mutations:** Releases chua tat ca fix Lane B: B1 print/printf noi suy, B2 bytes(N)+len, B3 method self-binding+clone fields, M1 catch AST walker, B5 type(), M3/C1 UnknownSystemTag, A1-runtime (.tuple/emitLiteral/.make_tuple opcode). Co 10 case test qua Executor.execute (testing/test_executor.zig).
- **Technical Debt & Anti-Patterns:** Khong con.
- **Shared Variables & Symbols:** Khong con.

### [2026-11-27] LONG-TERM MEMORY DUMP — Sửa web-terminal.yml (Windows + Linux web terminal)
- **Identified Truths:** Worker user báo "Powershell không vào đc" / "nhấn URL thì không kết nối" / lỗi 504 trên job `windows-terminal` và `linux-terminal`. Nguyên nhân gốc: (1) `cloudflared` dùng `-RedirectStandardOutput "tunnel.log"` → URL công khai bị ghi vào file thay vì job log, người dùng không thấy URL; (2) `cloudflared` chạy ngay sau `sleep 2`/`5` mà `ttyd` có thể chưa listen trên port 8899 → cloudflared trả 504 Gateway Timeout; (3) URL tunnel từ cloudflared cần thời gian để được in ra log, nếu đọc log quá sớm sẽ không có URL; (4) Windows: `Test-NetConnection -ComputerName localhost` thử IPv6 (`::1`) trước, có thể fail dù IPv4 `127.0.0.1` OK; (5) Windows PowerShell không cho `-RedirectStandardOutput` và `-RedirectStandardError` trỏ cùng file. Không có thay đổi code compiler/Zig.
- **Architectural Mutations:** Sửa `.github/workflows/web-terminal.yml`:
  - Windows step (sau dòng 100): dọn sạch tiến trình cũ `ttyd` + `cloudflared` trước khi khởi động; `ttyd.exe -W -p 8899 powershell.exe` chạy nền `-NoNewWindow`; **poll `Test-NetConnection -ComputerName 127.0.0.1 -Port 8899` mỗi 1s lên to 30s** trước khi chạy cloudflared (mencegah 504, tránh IPv6 `::1` fail); `cloudflared.exe tunnel --url http://localhost:8899` chạy nền `-NoNewWindow -PassThru -RedirectStandardOutput "cloudflared.out.log" -RedirectStandardError "cloudflared.err.log" | Out-Null` (hai file khác nhau); **poll `cloudflared.out.log` mỗi 1s lên to 30s** để lấy URL `https://....trycloudflare.com`, in `PUBLIC URL: <url>` rõ ràng vào job log; cuối bước dừng cả `cloudflared` và `ttyd` theo tên tiến trình.
  - Linux step (dòng 47-62): `ttyd -W -p 8899 bash &` chạy nền; **poll `nc -z localhost 8899` (hoặc `/dev/tcp`) mỗi 1s lên to 30s** trước khi chạy cloudflared; `/tmp/cloudflared tunnel --url http://localhost:8899 2>&1 | tee /tmp/tunnel.log &`; **poll `/tmp/tunnel.log` mỗi 1s lên to 30s** để lấy URL trycloudflare.com. Cùng logic dừng tiến trình khi hết thời gian.
- **Technical Debt & Anti-Patterns:** Tải binary `ttyd.win32.exe` / `cloudflared-windows-amd64.exe` / `cloudflared-linux-amd64` từ `releases/latest/download` — nếu asset tên thay đổi thì job sẽ fail; chưa verify trên runner thực (không có Windows/Linux sandbox trong thời gian này); cloudflared quick tunnel URL là ngẫu nhiên mỗi lần, người dùng phải copy URL từ job log.
- **Shared Variables & Symbols:** `.github/workflows/web-terminal.yml:47-126`.


### [2026-11-27] LONG-TERM MEMORY DUMP
- **Identified Truths:** GitHub Actions Windows cũ đăng ký `testing/test_modules.zig` dù `mod_check` bị bỏ qua trên Windows và gây 11/11 spawn failures. Lệnh đã chạy: `zig build test < /dev/null` exit 0 trên Linux; `zig build -Dtarget=x86_64-windows` exit 0; `git diff --check` exit 0.
- **Architectural Mutations:** `build.zig` tách core test suite khỏi module POSIX test suite; module suite chỉ đăng ký trên non-Windows. `.github/workflows/web-terminal.yml` đọc cả stdout và stderr của cloudflared thay vì tên file `cloudflared.log` không tồn tại.
- **Technical Debt & Anti-Patterns:** Không dùng test POSIX `.so/dlopen/dlsym` trên Windows. Không giả định Cloudflare ghi URL tunnel vào một log cố định; URL có thể ở stdout hoặc stderr.
- **Shared Variables & Symbols:** `files[]` là core test suite; `module_test_files` chỉ chứa `testing/test_modules.zig` trên POSIX; `cloudflared.out.log` và `cloudflared.err.log` là hai log đã redirect.

---
### [2026-11-28] LONG-TERM MEMORY DUMP — Sửa web-terminal.yml (Windows PowerShell "Reconnecting...")

- **Identified Truths:** Worker báo Windows job `windows-terminal` bị màn hình trình duyệt "Reconnecting..." liên tục, Linux job `linux-terminal` bình thường. Nguyên nhân: `cloudflared.exe` dùng `-RedirectStandardOutput "cloudflared.out.log" -RedirectStandardError "cloudflared.err.log"` → URL công khai bị ghi vào file thay vì job log, và output của cloudflared khi ghi sang file (không phải terminal/pipe) có thể bị buffer/không flush kịp → tunnel không ổn định. Theo known fact `web_terminal_windows_cloudflared_stdout`: Windows job KHÔNG được dùng `-RedirectStandardOutput` cho `cloudflared.exe`; cloudflared phải in URL trực tiếp lên stdout (job log). Verify: YAML valid qua `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/web-terminal.yml'))"` → "YAML valid".
- **Architectural Mutations:** Sửa `.github/workflows/web-terminal.yml`:
  - Bỏ `-RedirectStandardOutput "cloudflared.out.log" -RedirectStandardError "cloudflared.err.log"` khỏi `Start-Process .\cloudflared.exe tunnel --url ...` (dòng 139). cloudflared giờ in URL trực tiếp lên stdout → xuất hiện trong GitHub Actions job log, người dùng copy URL mở trình duyệt.
  - Xoá vòng lặp đọc file `cloudflared.out.log`/`cloudflared.err.log` (dòng 142-155 cũ) vì file không còn được tạo. Giữ thông báo `=== PUBLIC URL BELOW ===`, sleep giữ terminal, dừng `cloudflared` + `ttyd` khi hết thời gian.
  - Linux step không đổi (dùng `2>&1 | tee /tmp/tunnel.log` đã gửi output đồng thời lên stdout và file).
- **Technical Debt & Anti-Patterns:** Không dùng `-RedirectStandardOutput`/` -RedirectStandardError` cho cloudflared trên Windows PowerShell. Không đọc log file để lấy URL — dựa vào job log của GitHub Actions.
- **Shared Variables & Symbols:** `.github/workflows/web-terminal.yml:137-144` (Windows step, sau edit).

---
### [2026-11-28] LONG-TERM MEMORY DUMP (thêm) — cloudflared kết nối qua IPv6 [::1] bị từ chối

- **Identified Truths:** Sau fix redirect stdout, cloudflare logs vẫn báo `dial tcp [::1]:8899: connectex: No connection could be made because the target machine actively refused it.` Nguyên nhân: cloudflared tunnel URL là `http://localhost:8899`, `localhost` trên Windows giải quyết thành IPv6 `[::1]` trước, nhưng ttyd chỉ lắng nghe IPv4 `127.0.0.1` → cloudflared không kết nối được origin → trình duyệt vẫn "Reconnecting...". Verify: cloudflared log thực tế in `dest=https://poll-social-themselves-motorcycles.trycloudflare.com/... originService=http://localhost:8899` kèm lỗi `[::1]:8899` refused.
- **Architectural Mutations:** Thay `http://localhost:8899` thành `http://127.0.0.1:8899` trong аргум `--url` của `Start-Process .\cloudflared.exe` (dòng 139). Ép cloudflared dùng IPv4, khớp với ttyd lắng nghe `127.0.0.1:8899` (kiểm tra sẵn qua `Test-NetConnection -ComputerName 127.0.0.1` ở dòng 127).
- **Technical Debt & Anti-Patterns:** Không dùng `localhost` làm originService của cloudflared trên Windows do `localhost` có thể resolve IPv6 `[::1]`; luôn dùng `127.0.0.1` rõ ràng.
- **Shared Variables & Symbols:** `.github/workflows/web-terminal.yml:139` (`--url http://127.0.0.1:8899`).

---
### [2026-11-28 07:35 UTC] LONG-TERM MEMORY DUMP — Reconnect khi Windows origin ttyd từ chối kết nối

- **Identified Truths:**
  - Log đính kèm báo `originService=http://127.0.0.1:8899` và `connectex: ... actively refused it` (Pasted text #1, 2026-11-28 07:34:41Z), nên nguyên nhân IPv6/localhost không còn giải thích được lỗi hiện tại; chưa xác định vì sao listener ttyd dừng.
  - `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/web-terminal.yml')); print('YAML valid')"` → `YAML valid`; `git diff --check` → exit 0.
  - `gh run view 46121775530 --repo lytong760-cell/compiler_ko --json status,conclusion,url` → `status=completed`, `conclusion=cancelled`.
- **Architectural Mutations:** `.github/workflows/web-terminal.yml` yêu cầu `TERMINAL_USERNAME`/`TERMINAL_PASSWORD` secrets trên cả hai hệ điều hành trước khi mở shell; ttyd bật credential auth; Windows capture stdout/stderr của ttyd, giám sát process/cổng và cloudflared, đồng thời dừng process khi thoát bình thường hoặc lỗi. Xác nhận nội dung qua `git diff -- .github/workflows/web-terminal.yml`; YAML hợp lệ theo lệnh nêu trên.
- **Technical Debt & Anti-Patterns:** Chưa có xác minh chạy thực tế trên Windows runner; lệnh `command -v pwsh` và `command -v actionlint` không trả về đường dẫn. Cần cấu hình hai repository secrets trước khi chạy workflow mới.
- **Shared Variables & Symbols:** `.github/workflows/web-terminal.yml`: `TERMINAL_USERNAME`, `TERMINAL_PASSWORD`, `$ttydProcess`, `$tunnelProcess`.

## Chưa xác minh
- Chưa xác minh ttyd trên Windows có giữ listener ổn định suốt phiên; cần chạy lại workflow sau khi cấu hình secrets.

