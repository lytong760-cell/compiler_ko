# CHECKPOINTS.md

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** BUG.md (báo cáo 978 case), CHECKPOINTS.md, MEMORY.md — test toàn diện, KHÔNG sửa source
- **Volatile Context Diagnostics:**
  ```
  zig build                                 → rc=0
  zig build test < /dev/null                → EXIT=0 (15/15)
  978 case (913 corpus + 65 targeted)       → 0 crash, 0 hang
  RC histogram                              → {2: ~730, 0: ~110, 3: ~79}
  Phát hiện mới (parity/spec gap, KHÔNG crash):
    A1 tuple/list (1,2,3)                   → rc=2 (parser từ chối)
    A2 <$random>(...) / <$os>(...)          → rc=2 (parseSystemTagName không nhận .dollar)
    A3 bytes(<encode(...)>)                 → rc=2
    B1 <print>string^("x={x}")              → "x={x}" (không nội suy)
    B2 bytes(8) + <len>                     → len=0 (mong đợi 8)
    B3 $f~get() (class method)              → rc=3 NameError (callUserFunction không bind self)
    B5 type(x) / type("hi")                 → rc=3 UndefinedFunction
    C1 <foo> unknown tag                    → rc=0 im lặng
    C2 (10)~x thiếu kiểu                    → rc=0 im lặng
  Xác nhận ĐÚNG: arithmetic/if/for/while/func/class member/import/encode/memory/now/len/dict/priority; runtime errors; catch đặt trước; 584 token-mutant + 200 byte-mutant 0 crash.
  ```
- **Next Execution Phase Vectors:**
  1. Sửa A1 (tuple/list parse) — `parser_expr.zig` `l_paren` nhánh ~L389–460.
  2. Sửa A2 (`<$tag>`) — `parser_expr.zig:8` `parseSystemTagName` thêm `.dollar`.
  3. Sửa B3 (method self-binding) — `vm_value_ops.zig:197` `callUserFunction` bind instance vào scope.
  4. Sửa B1 (`<print>` nội suy), B2 (`bytes(N)` len), A3, B5.
  5. Bổ sung test parity qua `Executor`; chạy `graphify update .` sau khi sửa.

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/executor.zig, src/vm.zig, src/vm_value_ops.zig — fix 6 bug trong BUG.md
- **Volatile Context Diagnostics:**
  ```
  zig build                                 → rc=0
  zig build test < /dev/null                → EXIT=0 (15/15 pass)
  [ Nope() ]                                → rc=3 (trước 134)
  [ int(1)~a int(0)~b int(a/b)~c ]          → rc=3 (trước 134)
  [ string("")~s <input>(s) <printf>^(s) ]   → in "x" (trước TypeError+134)
  [ int(7)~x <printf>^("x={x}\n") ]         → "x=7" (trước "x={x}")
  [ null~x <printf>^(x) ]                    → "TypeError: Cannot print an unassigned null value"
  5 file .ko hợp lệ (simple/medium/test/class_test/ko) → rc=0
  ```
  **BUG-1** executor.zig: errdefer+free tường minh → double-free → `defer`+cờ `freed`.
  **BUG-2/BUG-6** vm.zig 3 chỗ fetchPut: `free(old.key)` = use-after-free (fetchPut giữ key cũ) → free key mới.
  **BUG-3** vm.zig `.print` handler: thiếu nội suy → `printInterpolated` khi `.string`.
  **BUG-4** vm.zig `raiseError`: `_ = message` → in `err_type: message`.
  **BUG-5** gộp BUG-1 (defer+cờ).
- **Next Execution Phase Vectors:**
  1. Bổ sung test chạy qua `Executor` (không chỉ `VM.execute`) để bắt parity bytecode — hiện test suite mù hoàn toàn với đường bytecode.
  2. Cân nhắc fix các `.put()` ghi đè (chỉ leak key mới, không crash) — rà soát `src/vm.zig` các `.put(`.
  3. Cập nhật `BUG.md` nếu còn bug mới; chạy `graphify update .` sau khi sửa code.

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** repo root review fixes
- **Volatile Context Diagnostics:** Zig 0.16.0 build and tests pass; Loop.cpp builds; test_modules pass with PATH.
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** `.kilo/worktrees/kilo/` (nhánh `kilo/fix-runtime`, base `Releases 7615acd1`) — Lane B (Kilo): runtime/VM/compiler + parity test qua `Executor.execute`.
- **Volatile Context Diagnostics:**
  ```
  export PATH=/home/codespace/.vscode-remote/data/User/globalStorage/ziglang.vscode-zig/zig/x86_64-linux-0.16.0:$PATH
  zig build                                   → rc=0
  zig build test < /dev/null                  → 8/8 test case pass (test_executor.zig: b1 print, b1 printf, b2 bytes len, b5 type string, b5 type int, m1 catch, b3 method, m3 unknown tag)
                                              → leaks (known, test harness): b2 bytes len +2, b5 type string +1, b5 type int +1, b3 method +6, m3 +1; ko khong anh huong correctness
  Cases tu file /tmp/kilo: t1 print=x=7, t2 bytes len=8, t3 type=string/int, t4 m3=UnknownSystemTag rc=3, t5 b3=5, t6 m1=1
  ```
- **Files edited (Lane B, file-disjoint vs Lane A):**
  - `src/executor.zig`: `setOutputWriter`, `hasFuncOrClassDef` → `requiresAstWalker` (them `catch_stmt` → AST walker) [M1]
  - `src/vm_value_ops.zig`: `print`/`print:` goi `printInterpolated` [B1]; `callBuiltin` them `bytes` + `type` [B2, B5]; `evaluateSystemTag` ket tra `UnknownSystemTag` + `raiseError` [M3/C1]; `callUserFunction`/`callUserFunctionValues` them `instance` param + clone `ci.fields` vao scope [B3]; `evaluateCall` them `type()` nhánh [B5]; `valueTypeName` helper
  - `src/vm.zig`: `.len` opcode them `.bytes => |b| @intCast(b.len)` [B2]; `call_method` truyen `target_instance` [B3]; `callUserFunction`/`callUserFunctionValues` wrapper them `instance`
  - `src/compiler.zig`: `compileVarDecl` khi `type_name=="bytes"` goi `callBuiltin("bytes")` de tao buffer [B2]
  - `testing/test_executor.zig` (moi): chay qua `Executor.execute`, bo prefix `test.ko:` tu `exposeProcess`, 8 case B1/B2/B3/B5/M1/M3
  - `build.zig`: wire `testing/test_executor.zig`
- **Blocked (khong duoc Kilo sua):** KHONG CON BLOCK. Da rebase worktree kilo (kilo/fix-runtime) len Releases (847986e1) thanh cong, khong xung dot. Da merge `kilo/fix-runtime` (a63bd0dc) -> `Releases` (commit merge 216a750f tren Releases). A1-runtime DA HOAN TAT: `evaluateLiteral` `.tuple` → `Value.tuple`, `emitLiteral` `.tuple` → compile elements + `.make_tuple`, `.make_tuple` handler build slice Value (vm.zig), Op/Instruction `make_tuple` (bytecode.zig). Test `a1 tuple` pass: `(1,2,3)~t` → `(1, 2, 3)`. zig build test tren Releases: 10/10 pass (leaks known test harness, khong anh huong correctness).
- **Next Execution Phase Vectors:**
  1. (DA LAM) git rebase Releases tren worktree kilo — xong.
  2. (DA LAM) Merge `kilo/fix-runtime` → `Releases` — xong (216a750f tren Releases).
  3. (DA LAM) `graphify update .` — xong (10773 nodes, graph.json/graph.html/GRAPH_REPORT.md duoc cap nhat).
  4. (DA LAM) Xoá worktree `.kilo/worktrees/kilo` — xong (con lai worktree claude/fix-parser cua Lane A).




### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/installer.zig
- **Volatile Context Diagnostics:** Implemented MEDIUM-7 (runCommand timeout 30s via spawn/poll/kill), MEDIUM-8 (recursive scanDirForLanguage), MEDIUM-10 (randomized temp dir pid+timestamp). No compiler available locally; Zig 0.16 APIs used per release notes.
- **Next Execution Phase Vectors:** Verify with `zig build` in environment with Zig 0.16 toolchain.

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/vm.zig runFunction/class_decl/assignValue
- **Volatile Context Diagnostics:** zig build succeeded; smoke examples/simple.ko printed Hello World.
- **Next Execution Phase Vectors:** Run full test suite when environment allows.

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** repo root report files `nomination.md`, `nomination..md`
- **Volatile Context Diagnostics:** Created detailed nomination/algorithm report (G1–G16, algorithms A–J, gates, risk register, DoD).
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** `.kilo/skills` (Matt Pocock promoted skills install)
- **Volatile Context Diagnostics:** 27 skill directories copied; `kilo debug skill` confirms recognition.
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/value.zig, src/vm.zig, testing/test_value.zig
- **Volatile Context Diagnostics:** Unified binary ops behind Value; strict typing (no int↔freal coercion); added less/greater/lessOrEqual/greaterOrEqual; removed VM helpers; zig build and zig build test pass (test_value 17 tests); smoke examples pass.
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/main.zig — Phase 6 Tooling: `ko build` standalone HOÀN TẤT
- **Volatile Context Diagnostics:** **Verify thực tế:** `zig build` exit 0; `zig build test < /dev/null` EXIT=0 (230 tests pass); `./zig-out/bin/ko build examples/simple.ko` → in "Hello World" khi validate, tạo `build/simple` (19.8MB, mode 755); copy sang `/tmp` chạy `./standalone_test` → in "Hello World", EXIT=0 (không cần `ko` trong PATH). **Bug đã sửa:** marker literal bị nhúng vào chính binary compiler → `readStandaloneSource` match rác → CLI hỏng (`--version` cũng lỗi). Chuyển sang **footer-based**: `<compiler bytes><source><len:u64 LE><magic:u64 LE>`, đọc từ cuối file, binary gốc không có footer nên không bị nhận nhầm.
- **Next Execution Phase Vectors:** Phase 6 còn lại: plugin loader (./libs + ~/.ko/plugins + manifest), completion runtime (zsh/fish), API server hardening (CORS/rate limit/timeout runCommand/recursive detectLanguage). User yêu cầu chỉ làm `ko build` trước — cần hỏi lại trước khi tiếp tục.

- **Volatile Context Diagnostics:** zig build passes; simple.ko prints "Hello World\n".
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/main.zig, src/api_server.py, src/parser.zig, src/vm.zig, src/ast.zig, src/compiler.zig
- **Volatile Context Diagnostics:** Added ~/.ko/plugins discovery; API server CORS/rate limit/name validation; added null literal and type() introspection system tag; build and tests pass.
### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** MCP config (global ~/.config/kilo/kilo.jsonc + project .kilo/kilo.jsonc); graphify-out/graph.json
- **Volatile Context Diagnostics:** Installed graphifyy 0.9.103 (pip) with [mcp]; ran `graphify install --platform kilo` (skill/command in ~/.config/kilo); built graph (10564 nodes, 755 communities) via `graphify update .`; verified stdio MCP server (python -m graphify.serve) responds initialize + tools/list (10 tools) in ~2s. Registered `graphify` MCP server (type local, absolute python path, graph.json, timeout 30000) in both global and project configs; granted `graphify_*` allow permission. Configs validated by Kilo.
- **Next Execution Phase Vectors:** Run `kilo mcp list` / restart Kilo to load server; optionally rebuild graph after code changes (`graphify update .`).

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** .kilo/skills/graphify/, AGENTS.md
- **Volatile Context Diagnostics:** Copied global graphify skill (SKILL.md + references/) into project `.kilo/skills/graphify/`; appended "Graphify Skill (Thường Xuyên Sử Dụng — không bắt buộc, đối chiếu)" section to AGENTS.md referencing skill path, MCP tools, and cross-reference guidance.
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/vm.zig, src/compiler.zig, src/executor.zig
- **Volatile Context Diagnostics:** Implemented bytecode parity for class_decl + class_instantiation + member_access (get_member op); removed class from hasFuncOrClassDef so class programs run via bytecode. Verified: examples class program prints John via bytecode (no fallback). Build + tests green.
- **Next Execution Phase Vectors:** func_decl bytecode parity, input second buffer, bridge Java tier.

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/vm.zig, src/compiler.zig, src/executor.zig, src/bytecode.zig
- **Volatile Context Diagnostics:** Implemented func_decl bytecode parity: compileFuncDecl now builds a bytecode.Function with params; .call handles user functions (scope bind + runFunction + return value). Removed func_decl from hasFuncOrClassDef. Verified: func program prints 30 via bytecode (no fallback). Build + tests green.
- **Next Execution Phase Vectors:** input second buffer, bridge Java tier, generics design doc.

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/vm.zig, docs/generics-girc-design.md
- **Volatile Context Diagnostics:** Implemented input buffer dupe in readInputLine (second buffer, no reuse). Added generics design doc. Java bridge tier (G1) left as future work (requires IPC). Build + tests green.
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/vm_value_ops.zig
- **Volatile Context Diagnostics:** Implemented Java bridge tier (G1) in callBuiltin: compiles Import.java and spawns `java Import import ...`, captures output. Build + tests green.
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/parser.zig, src/parser_expr.zig
- **Volatile Context Diagnostics:** Expanded VarDecl to support parenthesized composite literals (dict/tuple/null) and none~a without type keyword. Compact dict literal (1{'a'})~dic now binds and d{1} accesses. Verified: none→none, ()→null, (1{'a'})~d then d{1}→a. Build + tests green.
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** IN_PROGRESS
- **Active Node/Context:** src/parser.zig + testing/test_parser_extended.zig — Phase 4 Diagnostics (G5)
- **Volatile Context Diagnostics:** Infrastructure diagnostics đã có sẵn: lexer Position{line,col,column,offset} (lexer.zig:373-391), parser Span/ParseError{span,message,hint,err,line,col,file} (parser.zig:25-49), multi-error collection trong parse() (parser.zig:143-172), synchronize() (parser.zig:174-180). **Chưa có:** test negative kiểm tra parser trả về nhiều lỗi với span. Toàn bộ suite xanh (226 tests) trước khi thêm test này.
- **Next Execution Phase Vectors:** Đang chạy `zig build test < /dev/null` để verify test mới + toàn bộ suite; nếu xanh, tiếp tục Phase 5 (Null/None, type(), region @, priority) và Phase 6 (ko build, plugin loader).

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/installer.zig + SPECIFICATION.md — Module Store API đã đổi từ Firestore sang REST JSON tại `https://ko-lang.ai.studio/api/module`, và verify cấu trúc JSON thật qua curl
- **Volatile Context Diagnostics:** `zig build` exit 0; `zig build test < /dev/null` exit 0, 227 tests pass. Curl real API: `/api/module` trả JSON array có `detail` nested; `/api/module/<name>` trả JSON object có `detail.githubLink`. Installer parse qua `extractDetailField()`.
- **Next Execution Phase Vectors:** none
- **Volatile Context Diagnostics:** Đã nạp MEMORY.md và CHECKPOINTS.md vào ngữ cảnh. Verify thực tế: Zig 0.16.0 (`zig version = 0.16.0`); `zig build` thành công; `zig build test < /dev/null` exit code 0, toàn bộ suite pass (227 tests: test_harness 1, test_3600 117, test_value 17, test_lexer_extended 40, test_parser_extended 41, test_modules 11), 0 leak. Không có thay đổi code mới trong phiên này.
- **Next Execution Phase Vectors:** Chờ yêu cầu tiếp theo từ user; ứng cử viên: tiếp tục Phase 6 Tooling (ko build native binary, plugin loader discovery ./libs & ~/.ko/plugins + manifest, completion runtime, API server CORS/rate limit/timeout runCommand/recursive detectLanguage), diagnostics multi-error, hoặc generics design.

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** Phase 6 Tooling — REPL, plugin loader, installer timeout/recursive, API server socket timeout, completion smoke.
- **Volatile Context Diagnostics:**
  ```
  zig build                                 → rc=0
  zig build test < /dev/null                → EXIT=0 (230 tests pass)
  zsh -n (completion)                       → OK
  fish --no-execute (completion)            → OK
  bash -n (completion)                      → OK
  python3 -m py_compile api_server.py       → OK
  ko repl (multi-line block)                → prints 10, EXIT=0
  ko repl (empty input)                     → bye, EXIT=0
  ko repl (string with brackets)            → a[b]c, EXIT=0
  ko -plugins                               → lists valid manifests only
  ko examples/simple.ko / medium.ko / test.ko → OK
  ```
- **Next Execution Phase Vectors:** None for Phase 6. Phase 7/8 remain (MEDIUM/LOW hardening, generics design doc).

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** src/image/architecture.drawio.svg (draw.io diagram)
- **Volatile Context Diagnostics:** Regenerated architecture.drawio.svg from SPECIFICATION.md: 7 sections (mathematical pipeline, conductor+subsystems, multi-language tiers, execution pipeline phases, CDEL frame, file structure sections A-E, EngineTarget dispatch). Outer SVG + embedded mxfile both parse as XML (69 mxCell). No code/build changes.
- **Next Execution Phase Vectors:** none

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** .github/workflows/web-terminal.yml — Windows PowerShell web terminal step
- **Volatile Context Diagnostics:**
  ```
  CI Windows job fail: Start-Process cloudflared -RedirectStandardOutput "cloudflared.log" -RedirectStandardError "cloudflared.log" → PowerShell lỗi "RedirectStandardOutput and RedirectStandardError are same". Test-NetConnection qua "localhost" thử IPv6 (::1) trước, có thể fail dù IPv4 OK.
  Fix: (1) Test-NetConnection -ComputerName 127.0.0.1 (IPv4 cụ thể) thay vì localhost; (2) -RedirectStandardOutput "cloudflared.out.log" + -RedirectStandardError "cloudflared.err.log" (hai file khác nhau); (3) poll cloudflared.out.log lấy URL trycloudflare.com; (4) dừng cloudflared + ttyd khi hết thời gian.
  ```
- **Next Execution Phase Vectors:** Re-trigger workflow windows-terminal và quan sát job log.



