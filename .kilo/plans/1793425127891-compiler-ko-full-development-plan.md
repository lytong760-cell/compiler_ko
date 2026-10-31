# Plan: Phát triển toàn diện compiler_ko

**Source context**: `REVIEW.md`, `ROADMAP.md`, `nomination.md`, `SPECIFICATION.md`, `MEMORY.md`, `build.zig`
**Scope**: Toàn bộ repo `compiler_ko` (Zig core + C/C++/Java/Python tiers)
**Complexity**: Large

## Summary

Compiler `.ko` đã có nền tảng lexer/parser/AST/VM và polyglot tiers, nhưng các tier chưa wire vào runtime, bytecode backend chưa parity, diagnostics còn yếu. Plan này sắp xếp toàn bộ công việc còn lại theo thứ tự ưu tiên đã xác minh trong `nomination.md`: Bridge layer → Bytecode parity → Diagnostics → Language features → Tooling → Future, kèm gate kiểm chứng giữa các pha và DoD rõ ràng. AST-walker vẫn là fallback cho đến khi bytecode parity đạt 100%.

## Current State (verified)

- `zig build` / `zig build test`: baseline xanh (208/208) theo MEMORY; sandbox hiện tại không có Zig toolchain nên chưa tự chạy lại.
- Java `Import.java`, C++ `Loop.cpp`, C modules, Python `api_server.py` compile được; chưa wire vào VM.
- CRITICAL-1 (bytecode dead) đã fix. Còn 2 HIGH, 10 MEDIUM, 6 LOW.
- Bytecode backend chưa parity: `class_decl`, `class_instantiation`, `.dict` trả `UnsupportedBytecode`; escape `\n` (HIGH-2); aliasing load_var/store_var (HIGH-1).
- Dict overwrite leak (`StringHashMap.put` void) đã sửa sang `fetchPut` trong MEMORY gần nhất; cần verify.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| Build/test | `build.zig:98-139` | `zig build test` chạy 6 file test; module C/C++ build trước test; `mod_check` cho ABI |
| Error handling | `src/vm.zig` (value algebra) | Checked overflow, strict typing, error union `!T`, không swallow |
| Memory | `src/value.zig` (`clone`, `deinit`) | Creator owns; clone khi qua scope; `errdefer` rollback |
| Logging | `VM.setOutputWriter` | Đổi nơi ghi output; bắt buộc dưới test runner |
| FFI safety | `testing/mod_check.c` | Binary C độc lập làm dlopen/dlsym; Zig không link libdl |
| Tests | `testing/test_*.zig` | Assert output thực, không chỉ crash-free |

## Phase 0 — Baseline & Hygiene (M0, security first)

Tasks:
1. Verify toolchain: cài Zig 0.16.0 trong CI/local; chạy `zig build` + `zig build test < /dev/null`.
2. Rotate/verify không còn leaked Firestore key (đã xoá; grep `AIzaSy` = 0).
3. Xoá `.my_pass/` khỏi tracking (đã làm; verify `.gitignore`).
4. Đồng bộ Zig version ở `build.zig.zon`, `Dockerfile`, CI, `CONTEXT.md`.
5. Sửa CI: remove C# job (đã làm); thêm smoke test `.ko`.
6. Verify Docker build (`docker build`).
7. Verify completion zsh/fish (`zsh -n`, `fish --no-execute`).

Validation: `zig build`, `zig build test < /dev/null`, `docker build`, shell syntax checks all pass.

## Phase 1 — Fix HIGH findings (bytecode backend)

Tasks:
1. HIGH-2: unescape `\n` trong `emitLiteral` (`src/compiler.zig:274-289`) hoặc thêm op decode; verify `examples/simple.ko` in newline.
2. HIGH-1a: clone trong `load_var`/`store_var` (`src/vm.zig:1167-1200`) tránh aliasing; test assignment/hoán đổi.
3. HIGH-1b: implement parity cho `class_decl`, `class_instantiation`, dict literal, bytes cast, method call args; hoặc ghi rõ giới hạn + bắt buộc fallback + test.
4. Verify dict overwrite dùng `fetchPut` + deinit old (MEDIUM-10).
5. Class scope leak: destroy `private_scope`/`public_scope` (MEDIUM-9).
6. PriorityStmt leak: fix heap-alloc rồi copy by value (`parser.zig:58-69`).

Validation: `examples/simple.ko`, `examples/medium.ko` output đúng; test bytecode escape/aliasing/dict overwrite pass.

## Phase 2 — Bridge layer (G1, G2, G3)

Tasks:
1. Thiết kế ABI bridge Zig ↔ C/C++/Java (CDEL frame theo SPEC XVII).
2. Implement module loader: `dlopen`/`dlsym` + scope table (Algorithm A), convention paths `./libs`, `~/.ko/plugins`.
3. Marshalling Value ↔ C types (Algorithm B): int/freal/string/bytes/tuple; dict raise TypeError.
4. Dispatch keyword `Loop` sang `Loop.cpp` (Algorithm C integration).
5. Smoke test gọi native module và Loop.
6. ASan/valgrind clean.

Gate A: smoke test gọi module native và Loop; không crash; ASan/valgrind clean.

## Phase 3 — Bytecode parity (G4, G6, G7, G8)

Tasks:
1. `class_decl`/`class_instantiation` bytecode support.
2. `BUILD_DICT` + dict literals; `CAST_BYTES`.
3. `CALL_METHOD` với args; method access không gọi.
4. Second `<input>` buffer (allocate mới, không reuse).
5. Test assert output thực; fallback rate → 0 cho supported features.

Gate B: chương trình có func/class/dict/method/input chạy qua bytecode (không fallback) và output đúng.

## Phase 4 — Diagnostics (G5)

Tasks:
1. Lexer token positions (line,col) trong token struct.
2. Parser multi-error + synchronize đến statement boundary.
3. DiagnosticReport format (list {span, message, hint}).
4. Test negative.

Gate C: parser trả nhiều lỗi với span; test negative pass.

## Phase 5 — Language features (G9, G10, G11)

Tasks:
1. Null (mutable placeholder) vs None (immutable) semantics + TypeError khi dùng null chưa assign.
2. `type(...)` introspection.
3. Region `@` validation theo context (private/public/also/loop/girc).
4. Priority scheduler `{n}` (stable sort theo source order).
5. Test assert output thực.

Gate D: test assert output thực cho null/none/type/@/priority.

## Phase 6 — Tooling (G12, G13, G14, G15)

Tasks:
1. REPL `ko repl` (state giữa input, completeness check brackets).
2. `ko build` native binary.
3. Plugin loader discovery (`./libs`, `~/.ko/plugins`, manifest validation).
4. Completion verify zsh/fish (đã verify syntax; runtime test).
5. API server: default bind 127.0.0.1, CORS/rate limit, validate tên, timeout runCommand, detectLanguage đệ quy.

Gate E: REPL/build/plugin/completion hoạt động.

## Phase 7 — MEDIUM/LOW hardening

Tasks:
- MEDIUM-1..8, LOW-1..6 còn lại (Os.c static buffer thread-safe, magic numbers, timing compare, Java version, duplicate completion entry, empty catch debug log).
- Tách `vm.zig`/`parser.zig` lớn thành module theo trách nhiệm.
- Remove `std::cout` debug trong Loop.cpp hot loop.
- Java JSON parsing (extractJsonField) harden.

## Phase 8 — Future (G16)

Tasks:
1. Generics `@girc(T)` design doc.
2. Monomorphization prototype.
Gate F: design approved trước code.

## Files to Change (primary)

| File | Action | Why |
|---|---|---|
| `src/compiler.zig` | UPDATE | escape, parity |
| `src/vm.zig` | UPDATE | aliasing, load/store clone, dict, class scope, diagnostics |
| `src/parser.zig` | UPDATE | PriorityStmt leak, multi-error, positions |
| `src/lexer.zig` | UPDATE | token positions |
| `src/value.zig` | UPDATE | Null/None, type introspection helpers |
| `src/main.zig` | UPDATE | REPL, build, bytecode dispatch, completion |
| `src/installer.zig` | UPDATE | timeout, recursive detect, validation |
| `src/api_server.py` | UPDATE | bind, CORS, rate limit, validation |
| `src/module/Os/Os.c` | UPDATE | thread-safe buffer, magic numbers |
| `src/Loop.cpp` | UPDATE | remove debug cout |
| `build.zig` | UPDATE | new test files, modules |
| `.github/workflows/ci.yml` | UPDATE | smoke tests, remove C# |

## Validation (project-wide)

```bash
zig build
zig build test < /dev/null
javac -d /tmp/kilo/kojavacheck src/Import.java
g++ -std=c++17 src/Loop.cpp
gcc -std=gnu11 src/module/Os/Os.c src/module/Random/Random.c
python3 -m py_compile src/api_server.py
zsh -n <completion> ; fish --no-execute <completion>
docker build .
```

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| Bytecode aliasing | High | Clone Value; ASan tests |
| Dict overwrite leak | Medium | fetchPut + deinit old |
| FFI lifetime | High | Borrowed pointer scoped to call |
| Parser multi-error regression | Medium | synchronize robust; tests |
| Module partial load | Medium | errdefer unload |
| Generics scope creep | Medium | Design doc gate |
| Large files maintainability | Low | Split by responsibility |

## Acceptance (DoD per gap)

1. Code implement theo algorithm tương ứng.
2. Có test assert output thực.
3. `zig build` + `zig build test` xanh.
4. Không regression ở smoke examples.
5. Cập nhật `REVIEW.md`/`MEMORY.md`/`CHECKPOINTS.md`.
6. Spec chỉ khẳng định đã implement khi có bằng chứng.

## Open Questions

- Ưu tiên bắt đầu từ Phase 0 (baseline) hay Phase 1 (HIGH fixes) nếu Zig toolchain chưa có trong sandbox?
- Có cần giữ Java tier như reference-only hay wire thật sự vào runtime (G1)?
- Generics có cần thiết cho v1 hay defer sau v2?

Recommended answers: bắt đầu Phase 0+1 song song (baseline verify + HIGH fixes); wire Java tier thật (G1) theo bridge; defer generics đến sau v1.
