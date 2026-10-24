# CHECKPOINTS.md — Trạng thái thực thi hiện tại

Cập nhật ở **mỗi lần thay đổi trạng thái**. Đọc file này **trước khi** sửa code.

---

### LAST KNOWN EXECUTION CHECKPOINT

- **Task State:** `IN_PROGRESS` — plan M0–7 đang thực hiện, bỏ qua M8 theo yêu cầu người dùng
- **Active Node/Context:** `/workspace/app` (repo root là `/workspace/app`, không phải `/workspaces/compiler_ko`), nhánh `main`, working tree đã sửa nhưng **chưa commit**
- **Volatile Context Diagnostics:**
  ```
  Zig toolchain: KHÔNG có trong sandbox → không thể chạy `zig build`, `zig build test`, `docker build`
  Các thay đổi đã thực hiện (không compile-test được):
    - README.md: xoá leaked Firestore API key, dùng $KO_FIRESTORE_API_KEY
    - .my_pass/auto.bash: làm rỗng (force-push loop); .gitignore thêm .my_pass/
    - .github/workflows/ci.yml: xoá csharp khỏi ma trận CI
    - src/compiler.zig: Op.call encoding (idx<<16)|args.len; compileStatement xử lý control_flow/memory_op/encoding_op/len_op/priority_stmt; emitJumpPlaceholder/patchJump giữ đúng op (.jump vs .jump_if_false)
    - src/main.zig: wire bytecode backend (Compiler + VM.executeChunk) với AST-walker fallback; thêm hasFuncOrClassDef; import compiler/bytecode
    - src/bytecode.zig: thêm Chunk.init(allocator)
    - src/ast.zig: thêm DictEntry, Literal.dict_entries, Literal.allocator, Literal.deinit(dict)
    - src/parser.zig: nhánh `{` parse key:value pairs thành DictEntry; tất cả Literal création thêm dict_entries + allocator
    - src/vm.zig: var_decl bytes() hỗ trợ string + expr khác (không chỉ .int); evaluateLiteral populate dict từ dict_entries; evaluateCall thêm callUserFunction helper + .class_instance (method call không drop args)
    - src/value.zig: Value.print .freal dùng {f} thay vì {d}
  ```
- **Next Execution Phase Vectors (cần Zig toolchain để verify):**
  1. Chạy `zig build` → exit 0
  2. Chạy `zig build test < /dev/null` → tất cả test passed
  3. Chạy `docker build` → exit 0; `./ko --version` → `ko 0.1.0`
  4. Smoke test `examples/simple.ko` → output đúng
  5. Thêm test assert output thực cho bytecode path, dict literal, bytes(<expr>)
  6. Nếu có Zig: hoàn thành M3–M7 (stdlib, plugin/Import, Loop, `ko build`, REPL, completion)

---

## Xanh là gì, và không xanh là gì (trước khi sửa, cần verify lại)

| Mốc | Trạng thái (trước sửa) |
|---|---|
| `zig build` | xanh (baseline) |
| `zig build test` | xanh, 208/208 (baseline) |
| `docker build` | xanh (baseline) |
| Smoke test CLI | xanh (baseline) |
| Completion bash | xanh |
| Completion zsh/fish | chưa verify (thiếu shell) |

---

## Issue đang mở

Đã tạo 23 issue. **Chưa issue nào được đóng** — đóng khi code còn nằm trong working tree là sai.

Còn mở: #6, #8, #9, #10, #11, #12, #13, #15, #18, #21, #24
Đã xử lý trong lần này (chờ verify + commit): #7 (CI csharp), #18 (bytecode backend + Op.call), #19 (freal format), #20 (method call args), #28/29 (dict literal, bytes expr)

---

## Cạm bẫy đã gặp — đừng lặp lại

1. **Verify bằng artifact cũ là pass giả.** Luôn build vào thư mục **sạch**.
2. **`zig build test` dưới test runner cần stdin.** Truyền `< /dev/null` khi chạy thủ công.
3. **Agent song song phá việc nhau.** Dùng `git worktree add` cho từng agent, verify rồi tích hợp.
4. **Báo cáo sub-agent không đáng tin nếu không tự chạy lệnh.**
5. **Không có Zig toolchain trong sandbox** → tất cả thay đổi Zig cần verify lại khi có toolchain.

---

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** `.kilo/agents/*.md` (68 agent definitions converted to Kilo format)
- **Volatile Context Diagnostics:** `kilo agent list` now reports all 68 custom agents as loaded (mode: all); previously 0 loaded due to missing `mode` and invalid `model`/`color` fields. Evidence: `Loaded agents count = 73 total (68 custom + 5? built-in? Actually total includes built-ins)`.
- **Next Execution Phase Vectors:**
  1. Reload VSCode window if agents not visible in Kilo picker.
  2. Optionally tune `mode` per agent (primary/subagent/all) and model IDs.

---

### LAST KNOWN EXECUTION CHECKPOINT (code review)

- **Task State:** SUCCESS
- **Active Node/Context:** `/workspaces/compiler_ko`, branch `emcunieu-cute-patch-1`, `REVIEW.md` đã cập nhật (untracked), working tree modified nhưng **chưa commit**
- **Volatile Context Diagnostics:** Review chi tiết xong. Không còn CRITICAL. 1 HIGH (HIGH-4 bytecode chưa parity class/function/dict). 8 MEDIUM (bind 0.0.0.0, ko_get_cwd static buffer, thiếu CORS/rate limit, installer không timeout, detectLanguage không đệ quy, v.v.). 4 LOW. Verdict: WARNING. Zig toolchain chưa có trong sandbox → không verify `zig build`, `zig build test`, `docker build`.
- **Next Execution Phase Vectors:**
  1. Commit các fix hiện tại (working tree chưa commit).
  2. Khi có Zig toolchain: chạy `zig build`, `zig build test < /dev/null`, `docker build`, smoke test `examples/simple.ko`.
  3. Đóng HIGH-4: implement bytecode cho class/function/dict, hoặc document fallback rõ ràng + test assert output.
  4. Sửa MEDIUM-1 (bind 127.0.0.1), MEDIUM-2 (ko_get_cwd thread-safe), MEDIUM-3 (CORS/rate limit), MEDIUM-7 (timeout installer.runCommand), MEDIUM-8 (detectLanguage đệ quy).
  5. Verify zsh/fish completion.

### LAST KNOWN EXECUTION CHECKPOINT
- **Task State:** SUCCESS
- **Active Node/Context:** Adversarial review of REVIEW.md findings completed.
- **Volatile Context Diagnostics:** Verified via zsh -n, fish --no-execute, valgrind clean, Zig 0.16 hash_map source inspection.
- **Next Execution Phase Vectors:** Apply dict overwrite fix (fetchPut) and PriorityStmt wrapper leak fix if desired.
