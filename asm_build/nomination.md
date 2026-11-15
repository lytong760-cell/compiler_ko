# Báo cáo chi tiết: .ko còn thiếu gì, điểm yếu hiện tại, đề cử và thuật toán

> Mục tiêu: biến `compiler_ko` thành một ngôn ngữ lập trình mạnh mẽ. Tài liệu này tổng hợp chi tiết nhất về (1) những gì `.ko` còn thiếu, (2) điểm yếu hiện tại, (3) đề cử thứ tự thực hiện, và (4) thuật toán đề xuất. Nguồn đối chiếu: `REVIEW.md`, `ROADMAP.md`, `SPECIFICATION.md`, `CONTEXT.md`, `MEMORY.md`, source tree `src/`, tests, build/CI.

---

## 0. Tóm tắt điều hành

- **Trạng thái tổng thể:** Zig core đã có lexer/parser/AST/VM và một bytecode backend một phần; Java `Import.java`, C++ `Loop.cpp`, Python `api_server.py`, C modules tồn tại nhưng **chưa wire vào runtime**.
- **Verified toolchain:** Java 21, g++ 13, gcc 13, Python 3.13 pass compile; Zig compiler không có trong sandbox, nên `zig build`/`zig build test` chưa chạy được ở đây.
- **Findings hiện tại:** 0 CRITICAL mở, 4 HIGH, 12 MEDIUM, 7 LOW theo `REVIEW.md`.
- **16 capability gap (G1–G16)** chưa hoàn chỉnh, ảnh hưởng trực tiếp khả năng chạy chương trình thực tế.
- **Đề cử ưu tiên:** Bridge layer (G1–G3) → Bytecode parity (G4–G8) → Diagnostics (G5) → Language features (G9–G11) → Tooling (G12–G15) → Future (G16).
- **Nguyên tắc:** giữ AST-walker làm fallback cho đến khi bytecode parity đạt 100%; mọi feature mới phải có test assert output thực; spec chỉ khẳng định đã implement khi có bằng chứng.

---

## 1. Bằng chứng baseline (verified)

| Lệnh | Kết quả | Ghi chú |
|------|---------|---------|
| `javac -d /tmp/kilo/kojavacheck src/Import.java` | Thành công (2 deprecation warning `new URL(String)`) | Java tier compile được |
| `g++ -std=c++17 src/Loop.cpp` | Thành công | C++ tier compile được |
| `gcc -std=gnu11 src/module/Os/Os.c` + `Random.c` | Thành công | C module compile được |
| `python3 -m py_compile src/api_server.py` | Thành công | Python API compile được |
| `zig build` / `zig build test` | Chưa chạy | Thiếu Zig toolchain trong sandbox |
| `docker build` | Chưa verify | Cần toolchain/runtime |

**Kích thước source (Zig):**

| File | Lines |
|------|-------|
| `src/vm.zig` | 1466 |
| `src/parser.zig` | 1602 |
| `src/value.zig` | 492 |
| `src/main.zig` | 469 |
| `src/lexer.zig` | 378 |
| `src/installer.zig` | 367 |
| `src/ast.zig` | 354 |
| `src/compiler.zig` | 330 |
| `src/bytecode.zig` | 74 |
| `src/builtins.zig` | 5 |

Nhận xét: `vm.zig` và `parser.zig` quá lớn, tăng rủi ro bảo trì; bytecode backend còn nhiều `UnsupportedBytecode`.

---

## 2. Kiến trúc hiện tại và pipeline thực thi

Pipeline hiện tại:

```text
.ko source -> lexer.zig -> parser.zig -> AST (ast.zig)
            -> VM (vm.zig, AST-walking interpreter)   [fallback, mặc định khi có func/class]
            -> bytecode backend (compiler.zig/bytecode.zig) [chương trình không có func/class]
```

Polyglot tiers:

- Java `Import.java`: librarian/module importer, chưa wire vào VM.
- C++ `Loop.cpp`: optimizer, chưa dispatch từ VM.
- Python `api_server.py`: module store, chưa tích hợp runtime.
- C modules: native libs, chưa load runtime.

**Vấn đề kiến trúc cốt lõi:** các tier tồn tại độc lập, không có ABI bridge; bytecode backend chưa parity; diagnostics chưa có span/multi-error.

---

## 3. Gap matrix chi tiết (G1–G16)

### G1 — Runtime module loading (Import.java → Zig VM)

- **Capability:** `Import` keyword / `ko -install` load `.so`/module vào scope table.
- **Trạng thái:** Chưa wire. `Import.java` tồn tại, `installer.zig` có install logic, nhưng VM không dlopen/dlsym.
- **File:** `src/main.zig`, `src/vm.zig`, `src/Import.java`, `src/installer.zig`.
- **Failure mode:** Module installed nhưng không gọi được trong `.ko`; symbol lookup fail.
- **Mức:** HIGH.
- **Fix đề xuất:** ABI bridge + scope table registration (Algorithm A).
- **Complexity:** O(E) với E = số export; memory O(E).

### G2 — Loop.cpp integration vào VM

- **Capability:** Keyword `Loop` dispatch sang C++ tối ưu.
- **Trạng thái:** Chưa wire. `Loop.cpp` compile ok nhưng VM không gọi.
- **File:** `src/vm.zig`, `src/Loop.cpp`.
- **Failure mode:** Loop chạy qua interpreter, không có tối ưu; hoặc không nhận diện keyword.
- **Mức:** HIGH.

### G3 — JNI/JNA bridge native libs

- **Capability:** Marshalling `.ko` Value ↔ C types.
- **Trạng thái:** Chưa có.
- **File:** `src/vm.zig`.
- **Failure mode:** Crash/UB khi truyền string/bytes/dict sang C.
- **Mức:** HIGH.

### G4 — Bytecode backend parity (func/class/dict/method args)

- **Capability:** Compiler/VM bytecode cho class/func/dict/method/input.
- **Trạng thái:** Một phần. `Compiler.init` append Function (`src/compiler.zig:19-25`); nhưng `class_decl`, `class_instantiation`, `.dict` trả `error.UnsupportedBytecode` và fallback AST-walker.
- **File:** `src/compiler.zig`, `src/vm.zig`, `src/main.zig`.
- **Failure mode:** Chương trình có func/class/dict tự động fallback; bytecode path không parity.
- **Mức:** HIGH.

### G5 — Token source positions + multi-error diagnostics

- **Capability:** Lexer carry (line,col), parser multi-error với synchronize.
- **Trạng thái:** Chưa có.
- **File:** `src/lexer.zig`, `src/parser.zig`.
- **Failure mode:** Chỉ báo lỗi đầu tiên; không có span chính xác.
- **Mức:** MEDIUM.

### G6 — Dict literals và `bytes(<expr>)`

- **Capability:** `{key: value}` và `bytes(<expr>)~x`.
- **Trạng thái:** Chưa có bytecode/AST parity đầy đủ. Parser đã parse `DictEntry` (theo MEMORY), VM `evaluateLiteral` populate `StringHashMap`; compiler `emitLiteral(.dict)` trả `UnsupportedBytecode`.
- **File:** `src/compiler.zig`, `src/vm.zig`, `src/parser.zig`, `src/ast.zig`.
- **Failure mode:** Dict overwrite leak (Zig 0.16 `StringHashMap.put` void) nếu không dùng `fetchPut`.
- **Mức:** MEDIUM.

### G7 — Method call arguments + method access không gọi

- **Capability:** `$obj.method(args)` và `$obj.method` (không gọi).
- **Trạng thái:** Chưa xử lý đầy đủ.
- **File:** `src/vm.zig`, `src/parser.zig`.
- **Mức:** MEDIUM.

### G8 — Second `<input>` trong một chương trình

- **Capability:** Nhiều `<input>` không reuse buffer.
- **Trạng thái:** Chưa xử lý.
- **File:** `src/vm.zig`.
- **Mức:** MEDIUM.

### G9 — Null/None + type introspection `type(...)`

- **Capability:** `Value.null`, `Value.none`, `type(expr)`.
- **Trạng thái:** Một phần. SPEC đã bổ sung, code một phần.
- **File:** `src/value.zig`, `src/vm.zig`.
- **Mức:** MEDIUM.

### G10 — Region type annotations `@`

- **Capability:** `@private`, `@public`, `@also`, `@loop`, `@girc`.
- **Trạng thái:** Một phần. SPEC có mô tả; parser/VM cần validate context.
- **File:** `src/parser.zig`, `src/vm.zig`.
- **Mức:** MEDIUM.

### G11 — Priority statements `{n}`

- **Capability:** `{0}`, `{1}` thứ tự thực thi.
- **Trạng thái:** Một phần.
- **File:** `src/vm.zig`, `src/parser.zig`.
- **Mức:** LOW.

### G12 — REPL `ko repl`

- **Capability:** Interactive REPL.
- **Trạng thái:** Chưa có.
- **File:** `src/main.zig`.
- **Mức:** MEDIUM.

### G13 — `ko build` native binary

- **Capability:** Compile `.ko` → native executable.
- **Trạng thái:** Chưa có.
- **File:** `src/main.zig`, `build.zig`.
- **Mức:** MEDIUM.

### G14 — Plugin loader convention paths

- **Capability:** Scan `./libs`, `~/.ko/plugins`.
- **Trạng thái:** Chưa có.
- **File:** `src/installer.zig`.
- **Mức:** MEDIUM.

### G15 — Shell completion verify zsh/fish

- **Trạng thái:** Chưa verify (`zsh -n`, `fish --no-execute`).
- **Mức:** LOW.

### G16 — Generics `@girc(T)`

- **Trạng thái:** Future extension.
- **Mức:** LOW.

---

## 4. Điểm yếu hiện tại (weakness analysis)

### 4.1 Runtime & architecture

- Polyglot tiers (Java/C++/Python/C) **chưa wire** vào runtime; không có ABI bridge.
- Bytecode backend **chưa parity**; nhiều statement trả `UnsupportedBytecode` và fallback AST-walker.
- `vm.zig` và `parser.zig` quá lớn, khó bảo trì; exhaustive switch/dispatch rủi ro.
- Fallback logic trong `main.zig` che giấu lỗi parity, khó biết backend nào đang chạy.

### 4.2 Memory safety

- Bytecode aliasing: `stack[sp] = val` borrow không clone (`src/vm.zig:1189-1203`) → UB/potential corruption.
- Dict overwrite leak: Zig 0.16 `StringHashMap.put` void → old key/value leak nếu không `fetchPut`.
- `PriorityStmt` wrapper heap-alloc rồi copy by value → leak per priority statement (`parser.zig:58-69`).
- `ClassDef.deinit` phải destroy cả `private_scope`/`public_scope`; rủi ro double-free nếu không allocation gốc.
- FFI borrowed pointer lifetime chưa được enforce.

### 4.3 Language semantics

- Null/None chưa phân biệt rõ mutable/immutable.
- `type(...)` chưa đầy đủ.
- Region `@` chưa validate context.
- Priority `{n}` chưa scheduler hoàn chỉnh.
- Method call args và method access không gọi chưa xử lý.
- Second `<input>` reuse buffer.

### 4.4 Diagnostics & DX

- Không có token positions (line,col).
- Parser dừng ở lỗi đầu tiên; không synchronize.
- Không có multi-error report.
- Error messages chưa có span/hint.

### 4.5 Testing & quality

- Test chưa assert output thực (chỉ crash-free).
- Zig build/test chưa verify trong sandbox.
- CI có job C# không phù hợp repo.
- Docker build chưa verify.
- Completion zsh/fish chưa verify.

### 4.6 Tooling & ecosystem

- Chưa có REPL.
- Chưa có native build.
- Plugin loader chưa convention paths.
- Module store API chưa tích hợp runtime.
- Docs/spec chưa đồng bộ đầy đủ (Milestone 8).

### 4.7 Security & infra

- Đã fix leaked Firestore API key.
- Bind `0.0.0.0` trong API server (MEDIUM).
- Thiếu CORS/rate limit.
- Installer `runCommand` chưa timeout.
- `detectLanguage` chưa đệ quy.

---

## 5. Để trở thành ngôn ngữ lập trình mạnh mẽ: các trụ cột bắt buộc

Một ngôn ngữ mạnh cần đồng thời:

1. **Runtime ổn định:** VM + bytecode parity + memory safety.
2. **FFI/module system:** gọi native libs an toàn, load plugin.
3. **Diagnostics tốt:** multi-error, span, hint.
4. **Type system rõ ràng:** Null/None, type introspection, region annotations, generics.
5. **stdlib phong phú:** I/O, string, math, collections.
6. **Tooling:** REPL, build, completion, formatter/linter.
7. **Performance:** loop optimization, JIT/AOT, cache-friendly.
8. **Safety:** ASan/valgrind, fuzz, sandbox.
9. **Ecosystem:** package manager, plugin convention, docs, examples.
10. **Spec discipline:** spec chỉ khẳng định đã implement khi có bằng chứng.

---

## 6. Tiêu chí đề cử (scoring)

Mỗi gap được chấm theo 5 trục (1–5):

| Trục | Ý nghĩa |
|------|---------|
| Impact | Ảnh hưởng đến khả năng chạy chương trình thực tế |
| Blocker | Có chặn các feature khác không |
| Effort | Chi phí triển khai (thấp = điểm cao) |
| Risk | Rủi ro regression / memory safety |
| Testability | Dễ viết test assert output |

**Priority Score = Impact×3 + Blocker×2 + Testability×2 − Effort − Risk**

Đề cử thứ tự = sort giảm dần Priority Score, tie-break theo Blocker rồi Impact.

---

## 7. Dependency graph và critical path

```text
G1 (module loading)
 ├─ G3 (FFI marshalling)
 └─ G2 (Loop integration) ── depends on G3

G4 (bytecode parity)
 ├─ G6 (dict/bytes)
 ├─ G7 (method args/access)
 └─ G8 (second input)

G5 (diagnostics) ── độc lập, có thể song song

G9/G10/G11 ── phụ thuộc parser/VM core

G12/G13/G14/G15 ── tooling, sau core stable

G16 ── future, sau generics design
```

**Critical path:** G1 → G3 → G2 và G4 → (G6/G7/G8) → G5 → G9/G10/G11 → G12/G13/G14/G15 → G16.

---

## 8. Bảng đề cử thứ tự thực hiện (algorithm-first)

| Thứ tự | Nhóm | Gap | Lý do đề cử |
|--------|------|-----|-------------|
| 1 | Bridge layer | G1, G2, G3 | Ảnh hưởng trực tiếp khả năng chạy chương trình thực; mở đường cho module/loop |
| 2 | Bytecode parity | G4, G5, G6, G7, G8 | Hoàn thiện compiler/VM; giảm fallback |
| 3 | Diagnostics | G5 | Lexer carry span + multi-error; cải thiện DX |
| 4 | Language features | G9, G10, G11 | Null/None/type, @, priority |
| 5 | Tooling | G12, G13, G14, G15 | REPL, build, plugin loader, completion |
| 6 | Future | G16 | Generics monomorphization |

### 8.1 Gate bắt buộc giữa các pha

- **Gate A (sau Bridge):** smoke test gọi module native và Loop; không crash; valgrind/ASan clean.
- **Gate B (sau Bytecode parity):** chương trình có func/class/dict/method/input chạy qua bytecode (không fallback) và output đúng.
- **Gate C (sau Diagnostics):** parser trả nhiều lỗi với span; test negative.
- **Gate D (sau Language features):** test assert output thực cho null/none/type/@/priority.
- **Gate E (sau Tooling):** `ko repl`, `ko build`, plugin discovery hoạt động; completion verify.
- **Gate F (Future):** generics design doc approved trước code.

---

## 9. Thuật toán đề xuất chi tiết

### 9.1 Algorithm A — Module loading (G1)

```text
resolveModule(name, scopeTag):
  1. lookup scope table by name
  2. if not loaded:
     a. locate lib file in libs/ or ~/.ko/plugins/
     b. dlopen(lib)
     c. dlsym all exported symbols from module.json
     d. register into scope table (global/main/func/class/function_name)
  3. bind module handle to scope
  4. on failure: unload partially, raise ModuleNotFoundError
```

- **Data structures:** `ScopeTable: HashMap(name → ModuleHandle)`, `ModuleHandle { lib, exports[] }`.
- **Complexity:** O(E), E = số export.
- **Memory:** O(E).
- **Edge cases:** symbol missing → rollback dlopen; version mismatch → error; duplicate load → reuse handle.
- **Safety:** không để dangling handle; errdefer unload.

### 9.2 Algorithm B — FFI marshalling (G3)

```text
marshalKoToC(value):
  int    -> int64_t
  freal  -> double
  string -> const char* (borrowed, lifetime scoped to call)
  bytes  -> uint8_t* + size
  tuple/list -> array pointer + length
  dict   -> not supported (raise TypeError)
```

- **Call frame:** argument slots; cleanup borrowed strings after call.
- **Lifetime rule:** borrowed pointer chỉ hợp lệ trong duration của call; không lưu vào C state.
- **Error path:** marshal fail → raise TypeError, không gọi C.

### 9.3 Algorithm C — Bytecode parity (G4, G6, G7, G8)

Compiler:

```text
compileStatement:
  class_decl        -> emit class metadata constant + instantiate scope table
  func_decl         -> compile body into new Function chunk, store in constants
  dict literal      -> emit BUILD_DICT with key/value pairs
  bytes(expr)       -> compile expr, emit CAST_BYTES
  method call       -> emit CALL_METHOD (receiver, method, argc)
  second input      -> allocate new input buffer slot, no reuse of previous
```

VM:

```text
executeChunk:
  maintain scope stack + class table + function table
  CALL_METHOD: resolve method from class_instance.methods, push new frame
  BUILD_DICT: pop 2*N values, construct dict
  CAST_BYTES: convert string to bytes
```

- **Dict overwrite:** dùng `getOrPut` + deinit old value/key (Zig 0.16 `put` void leak fix).
- **Method args:** không drop args; truyền qua call frame.
- **Input:** mỗi `<input>` allocate buffer mới, không reuse.

### 9.4 Algorithm D — Multi-error diagnostics (G5)

```text
Lexer:
  token = { kind, lexeme, start: (line,col), end: (line,col) }

Parser:
  errors = []
  while not EOF:
    try parseStatement()
    catch ParseError e:
      errors.append(e with span)
      synchronize to next statement boundary
  if errors: return DiagnosticReport(errors)
```

- **Complexity:** O(n) tokens, O(k) errors.
- **Synchronize:** skip đến `;`/newline/block boundary.
- **Output:** DiagnosticReport chứa list {span, message, hint}.

### 9.5 Algorithm E — Null/None + type introspection (G9)

```text
Value.null = placeholder (mutable)
Value.none = immutable empty

type(expr):
  evaluate expr
  return type name string (int, freal, string, booling, byte, bytes, tuple, list, dict, function, class_instance, null, none)
```

- **Distinction:** `null` mutable placeholder; `none` immutable empty.
- **Edge:** `type(null)` → "null"; `type(none)` → "none".

### 9.6 Algorithm F — Region type annotations (G10)

```text
parseRegionAnnotation:
  if token == '@':
    role = parseIdentifier()
    attach role to following block/statement
    roles: private, public, also, loop, girc
```

- **Validation:** role phải khớp context (class body cho phép private/public; loop cho phép also).
- **Error:** invalid role in context → DiagnosticError.

### 9.7 Algorithm G — Priority scheduler (G11)

```text
executeBlock(statements):
  groups = map priority -> list statements (stable)
  for priority in sorted(groups.keys()):
    for stmt in groups[priority] (source order):
      execute(stmt)
```

- **Default priority:** 0.
- **Stability:** giữ thứ tự nguồn trong cùng priority.

### 9.8 Algorithm H — REPL (G12)

```text
loop:
  read line
  if command: handle (:help, :quit, :load)
  else append to buffer; if complete block -> parse+execute; print result
```

- **Completeness check:** brackets balanced + parser accept.
- **State:** giữ scope/env giữa các input.

### 9.9 Algorithm I — Native build (G13)

```text
ko build file.ko:
  compile .ko -> C/Zig source or bytecode bundle
  invoke zig build-lib / zig build-exe
  output executable in ./build/
```

- **Output:** executable + metadata.
- **Error:** build fail → report compiler errors.

### 9.10 Algorithm J — Plugin loader (G14)

```text
discoverPlugins():
  scan ./libs, ~/.ko/plugins
  for each plugin:
    validate manifest.json
    register in module store
```

- **Manifest:** name, version, language, exports, abi.
- **Validation:** reject malformed manifest; log skip.

---

## 10. Kế hoạch phase chi tiết (tasks + acceptance)

### Phase 1 — Bridge layer (G1–G3)

Tasks:
1. Thiết kế ABI bridge Zig ↔ C/C++/Java.
2. Implement module loader (dlopen/dlsym) + scope table.
3. Marshalling Value ↔ C types.
4. Dispatch `Loop` keyword sang `Loop.cpp`.
5. Thêm smoke test gọi native module.

Acceptance:
- `ko run example.ko` gọi được function từ `.so`.
- Loop native chạy và output đúng.
- ASan/valgrind clean.

### Phase 2 — Bytecode parity (G4, G6, G7, G8)

Tasks:
1. `class_decl`/`class_instantiation` bytecode support.
2. `BUILD_DICT` + dict literals.
3. `CAST_BYTES`.
4. `CALL_METHOD` với args.
5. Method access không gọi.
6. Second `<input>` buffer.

Acceptance:
- Chương trình có func/class/dict/method/input chạy qua bytecode (không fallback).
- Output đúng.

### Phase 3 — Diagnostics (G5)

Tasks:
1. Lexer token positions.
2. Parser multi-error + synchronize.
3. DiagnosticReport format.

Acceptance:
- Parser trả nhiều lỗi với span.
- Test negative pass.

### Phase 4 — Language features (G9–G11)

Tasks:
1. Null/None semantics.
2. `type(...)`.
3. Region `@` validation.
4. Priority scheduler.

Acceptance:
- Test assert output thực.

### Phase 5 — Tooling (G12–G15)

Tasks:
1. REPL.
2. `ko build`.
3. Plugin loader.
4. Completion verify.

Acceptance:
- REPL/build/plugin/completion hoạt động.

### Phase 6 — Future (G16)

Tasks:
1. Generics design doc.
2. Monomorphization prototype.

Acceptance:
- Design approved trước code.

---

## 11. Risk register

| Risk | Ảnh hưởng | Giảm thiểu |
|------|-----------|------------|
| Bytecode aliasing (HIGH-1) | UB/memory corruption | Clone Value khi load/store; test ASan |
| Dict overwrite leak | Memory leak | `fetchPut` + deinit old |
| FFI lifetime | Use-after-free | Borrowed pointer scoped to call |
| Parser multi-error regression | Crash | synchronize robust; tests |
| Module partial load | Resource leak | errdefer unload |
| Generics complexity | Scope creep | Design doc gate trước code |
| File lớn (vm/parser) | Maintainability | Tách module theo phase |

---

## 12. Kế hoạch verification

- **Zig:** `zig build`, `zig build test`, smoke examples (`examples/simple.ko`).
- **C/C++:** `g++ -std=c++17`, `gcc -std=gnu11`.
- **Java:** `javac`.
- **Python:** `python3 -m py_compile`.
- **CI:** sửa/remove C# job; thêm smoke test `.ko`.
- **Docker:** `docker build`.
- **Completion:** `zsh -n`, `fish --no-execute`.
- **Memory:** ASan/valgrind cho VM/module loading.
- **Fuzz:** parser/lexer fuzz (future).

---

## 13. Definition of Done (DoD)

Một gap được coi là DONE khi:

1. Code implement theo algorithm tương ứng.
2. Có test assert output thực (không chỉ crash-free).
3. `zig build` + `zig build test` xanh.
4. Không regression ở smoke examples.
5. Cập nhật `REVIEW.md`/`MEMORY.md`/`CHECKPOINTS.md` phản ánh trạng thái.
6. Spec chỉ khẳng định đã implement khi có bằng chứng.

---

## 14. KPI / metrics để theo dõi

- **Bytecode coverage:** % statement kinds compile được bytecode (target 100%).
- **Fallback rate:** % chương trình fallback AST-walker (target 0 cho supported features).
- **Test output assertions:** số test assert output thực (target tăng mỗi phase).
- **Diagnostics quality:** số lỗi báo trong 1 lần parse (target multi-error).
- **Memory safety:** ASan/valgrind clean.
- **Build reproducibility:** `zig build` xanh trên CI.

---

## 15. Phụ lục — Tham chiếu file

| File | Vai trò |
|------|---------|
| `src/lexer.zig` | Tokenization |
| `src/parser.zig` | Parsing/AST construction |
| `src/ast.zig` | AST nodes |
| `src/vm.zig` | AST-walking VM |
| `src/compiler.zig` | Bytecode compiler |
| `src/bytecode.zig` | Chunk/Op definitions |
| `src/value.zig` | Value types |
| `src/main.zig` | CLI entry |
| `src/Import.java` | Module importer (Java tier) |
| `src/Loop.cpp` | Loop optimizer (C++ tier) |
| `src/installer.zig` | Install/plugin logic |
| `src/api_server.py` | Module store API |
| `SPECIFICATION.md` | Formal spec |
| `ROADMAP.md` | Milestones/issues |
| `REVIEW.md` | Findings & review |
| `MEMORY.md` | Long-term memory |
| `CHECKPOINTS.md` | Checkpoints |

---

## 16. Kết luận

`.ko` đã có nền tảng compiler (lexer/parser/AST/VM) và polyglot tiers, nhưng **chưa wire** các tier vào runtime và **chưa parity bytecode** cho các tính năng cốt lõi. Để trở thành ngôn ngữ mạnh mẽ, phải giải quyết đồng thời runtime stability, FFI/module system, diagnostics, type system, stdlib, tooling, performance, safety và ecosystem. Đề cử bắt đầu từ **Bridge layer (G1–G3)**, sau đó **Bytecode parity (G4–G8)**, **Diagnostics (G5)**, **Language features (G9–G11)**, **Tooling (G12–G15)**, cuối cùng **Future (G16)**. Mỗi pha phải đi kèm test assert output thực và gate verification trước khi chuyển pha.
