# Kế hoạch sửa bug `compiler_ko` — 2 worktree (Claude Code + Kilo)

> Nguồn: `BUG.md` trên nhánh `Releases` (HEAD `7615acd1`, đã đồng bộ `origin/Releases`) + đọc trực tiếp source trong phiên lập plan.
> Đây là **plan-only**. Người thực thi phải chuyển sang agent có quyền ghi (implementation-capable). Các lệnh `git worktree` là **mutating** → agent impl chạy, không phải plan agent.

---

## 1. Mục tiêu & phạm vi

Đưa compiler về **parity bytecode ↔ AST walker** và khép các gap parser/spec còn mở (BUG.md 2026-11-18). **Không** re-fix BUG-1..6 (đã FIXED ở `1db1425a`).

Bug còn mở (theo thứ tự ưu tiên BUG.md):

- **A1** tuple/list `(1,2,3)` parse fail — HIGH
- **A2** `<$tag>` (`<$random>`) parse fail — HIGH
- **B3** class method `$f~get()` NameError (+ Bonus-C nghi UAF `0xAA`) — HIGH
- **M1** `<catch>` bytecode no-op (parity) — HIGH
- **M2** dict colon `{'a':1}` parse sai — HIGH
- **B1** `<print>string^("x={x}")` không nội suy — HIGH
- **B2** `bytes(N)` + `<len>` trả 0 — HIGH
- **A3** `bytes(<encode(...)>)` parse fail — MED
- **B5** `type(x)` UndefinedFunction — MED
- **M3/C1** unknown system tag im lặng / không nhất quán — MED
- **Bonus-B** freal↔int coercion TypeError — MED (tùy quyết định spec)
- **C2/C5** `(10)~x` thiếu kiểu, `<catch>` thiếu backtick — LOW

Ngoài phạm vi: REPL, plugin loader, Phase 7/8, coercion nếu user chốt giữ strict.

---

## 2. Bối cảnh repo đã xác minh

- **Base bắt buộc = `Releases`**, KHÔNG dùng `main`/branch cũ: nhánh `claude` (worktree cũ) ở `0d0a4753` là **divergent, thiếu** các fix BUG-1..6. Chỉ `Releases` mới có `1db1425a` (fix 6 bug) tổ tiên.
- Worktree hiện có (cần xoá): `.kilo/worktrees/claude` (branch `claude`), `.kilo/worktrees/fantasy-land` (branch `fantasy-land`).
- Kiến trúc: `Executor.execute` (`src/executor.zig:52-97`) chọn **bytecode** khi `!hasFuncOrClassDef && !hasImportStmt` → đa số `.ko` thực tế đi bytecode → mọi parity bug khu trú ở đường này.
- Logic runtime tập trung ở `src/vm_value_ops.zig`; `src/vm.zig` chỉ **wrapper** (vd `vm.zig:789` gọi `vm_value_ops.evaluateLiteral`). Opcode handlers thật ở `vm.zig` (`dispatchLoop`).
- Test suite hiện chỉ đi `VM.execute` (AST walker) → mù với bytecode. **Fix này bắt buộc** (Lane Kilo, mục 5.2).

### Neo source đã xác minh (line hiện tại)

| Vùng | File:line |
|---|---|
| `parseSystemTagName` | `parser_expr.zig:8`, `parser.zig:1141` |
| `parsePrimaryExpr` (`.l_paren`) | `parser_expr.zig:183`, `parser.zig:1203` |
| Tuple `.l_paren` (xử lý `first` + dict compact, THIẾU comma) | `parser_expr.zig:389-460` |
| Dict literal `{...}` | `parser_expr.zig:462-510` |
| `isSystemTagOpener` | `parser.zig:1166` |
| `parseVarDecl` | `parser.zig:415` |
| Statement dispatch `{` | `parser.zig:335` |
| `ast.Literal` (`Kind` đã có `tuple`, THIẾU `elements`) | `ast.zig:250-270` |
| `Value` (đã có `.tuple`, `.list`) | `value.zig:4-15` |
| `evaluateLiteral` | `vm_value_ops.zig:68` |
| `callUserFunction` / `...Values` | `vm_value_ops.zig:197` / `:262` |
| `evaluateCall` (printf nội suy) | `vm_value_ops.zig:327`, `:443` |
| `evaluateSystemTag` (print nội suy) | `vm_value_ops.zig:603`, `:616` |
| `callBuiltin` (printf nội suy) | `vm_value_ops.zig:719`, `:732` |
| `compileExpression` / `compileVarDecl` / `compileCatch` | `compiler.zig:219` / `:316` / `:337-344` |
| Opcode `.print` / `.input` / `.len` / `.call_method` | `vm.zig:1236` / `:1255` / `:1268` / `:1002` |
| Opcode `.catch_start` / `.catch_end` (no-op) | `vm.zig:1323-1324` |
| Guard backend | `executor.zig:116-129` (`hasFuncOrClassDef`) |

---

## 3. Bước 0 — Thiết lập worktree (agent impl chạy; plan agent KHÔNG chạy)

```bash
# 0.1 Đóng mọi session Kilo đang gắn với worktree cũ (agent-manager.json:
#     xoá session/worktree trỏ tới wt-1795157833326-1 và wt-1795177672690-1,
#     hoặc dùng UI Agent Manager để remove). Tránh xoá worktree đang active.

# 0.2 Xoá 2 worktree cũ
git worktree remove --force .kilo/worktrees/claude
git worktree remove --force .kilo/worktrees/fantasy-land

# 0.3 (tuỳ chọn) xoá branch cũ để khỏi nhầm
git branch -D claude fantasy-land

# 0.4 Tạo 2 worktree MỚI, cùng base Releases
git worktree add -b claude/fix-parser  .kilo/worktrees/claude Releases
git worktree add -b kilo/fix-runtime   .kilo/worktrees/kilo   Releases

# 0.5 Xác minh
git worktree list
# kỳ vọng: .../compiler_ko (Releases) + .../.kilo/worktrees/claude (claude/fix-parser)
#          + .../.kilo/worktrees/kilo (kilo/fix-runtime)
```

Ghi chú: nếu dùng **Kilo Agent Manager** thay vì `git worktree` tay, tạo 2 worktree qua UI với `parentBranch = Releases`; không dùng `main`. Nếu tạo tay, cập nhật `.kilo/agent-manager.json` cho khớp (worktree mới + branch mới).

---

## 4. Phân chia việc (file-disjoint, minimal conflict)

Nguyên tắc: **mỗi agent sở hữu một tập file riêng** (tránh double-edit gây hỏng — bài học MEMORY 2026-10-01). Chỉ A1 có **contract** xuyên 2 lane.

### Lane A — Claude Code: Frontend / Parser / AST
- Worktree: `.kilo/worktrees/claude` — branch `claude/fix-parser`
- **Sở hữu:** `src/parser.zig`, `src/parser_expr.zig`, `src/ast.zig`
- **Không** đụng `vm*.zig` / `compiler.zig` / `executor.zig` / `value.zig`.
- Bug: **A1 (nửa front)**, A2, A3, M2, C2, C5.

### Lane B — Kilo: Runtime / VM / Compiler + parity test
- Worktree: `.kilo/worktrees/kilo` — branch `kilo/fix-runtime`
- **Sở hữu:** `src/vm.zig`, `src/vm_value_ops.zig`, `src/compiler.zig`, `src/executor.zig`, `src/value.zig`, `src/operator.zig`, `testing/test_executor.zig` (mới), `build.zig`
- **Không** đụng `parser*.zig` / `ast.zig`.
- Bug: **A1 (nửa runtime)**, B1, B2, B3+Bonus-C, M1, B5, M3/C1, Bonus-B.

### Hợp đồng A1 (contract)
- Claude thêm vào `ast.Literal`: `elements: []*ast.Expr` + cập nhật `Kind.tuple` + `deinit` (free từng `elements` + slice).
- Kilo tiêu thụ `lit.elements` trong `evaluateLiteral` để tạo `Value.tuple`/`.list`.
- **Thứ tự merge:** Claude merge vào `Releases` TRƯỚC → Kilo `git rebase Releases` (hoặc merge) rồi mới build. Kilo KHÔNG build được A1-runtime cho tới khi có `elements` → vì vậy Kilo làm B1/B2/B3/M1/B5/M3 trước, A1-runtime làm sau cùng.

---

## 5. Task list chi tiết

### 5.1 Lane A — Claude Code (`.kilo/worktrees/claude`)

Thứ tự (rẻ → khó):

1. **A2 `<$tag>`** (nhanh, mở khoá module):
   - `parser_expr.zig:8` `parseSystemTagName` và `parser.zig:1141`: nếu token `.dollar` → `advance()` rồi đọc `identifier`/`keyword` (giữ nguyên `$` trong tên hoặc strip — chọn theo SPEC §VII).
   - `parser.zig:1166` `isSystemTagOpener`: chấp nhận `peek(1) == .dollar`.
   - Verify: `[ int(<$random>(1,5))~r <printf>^(r) ]` parse OK (rc≠2).
2. **M2 dict colon đầu statement**:
   - `parser.zig:335` dispatch `{`: thử parse **dict literal** + hậu tố `~ident` → `VarDecl` (thay vì `parseExprStatement`).
   - Verify: `[ {'a':1}~d <printf>^(d{'a'}) ]` → `1`; `[ {'a':1}~d <printf>^(d) ]` → `{a: 1}` (không còn `len=0`).
3. **A1 nửa front (tuple/list)**:
   - `ast.zig:250-270`: thêm `elements: []*ast.Expr`; `deinit` free elements + slice; cập nhật **mọi** `ast.Literal{...}` initializer (dùng `elements = &.{}`).
   - `parser_expr.zig:389-460`: sau `first = parseExpression()`, nếu gặp `,` → gom `expr ("," expr)*` thành `elements`, tạo `Literal{.kind=.tuple, .elements=...}`; giữ nhánh dict compact `(k{v})` và `({...})` hiện có.
   - Verify: `[ (1,2,3)~t ]`, `[ ('a','b')~t ]`, `[ (1('a','b'))~a ]` parse OK (rc≠2). Runtime verify để Lane B.
4. **A3 `bytes(<encode(...)>)`**: reproduce → sửa nhánh parse arg của `bytes(`/`parseVarDecl` (`parser.zig:415`) để nhận `system_tag` lồng trong `.l_paren`.
5. **C2 `(10)~x` thiếu kiểu**: báo lỗi/cảnh báo khi expr statement `(...)`~ident không có type.
6. **C5 `<catch>(DivideByZeroError)` thiếu backtick**: validate `error_type` dạng `` `Ident` `` tại parse catch.
7. Commit + mở PR/MR nhánh `claude/fix-parser` → `Releases`; viết `zig build` xanh + test parser.

### 5.2 Lane B — Kilo (`.kilo/worktrees/kilo`)

Thứ tự (độc lập A1 trước, A1-runtime sau):

1. **Hạ tầng parity test** (làm trước để bắt regression):
   - Tạo `testing/test_executor.zig` chạy **qua `Executor.execute`** cho các ca B1/B2/B3/M1/B5/M3 (không dùng `VM.execute`). Wire vào `build.zig`.
   - Verify `zig build test < /dev/null` xanh baseline (các ca parity mới đỏ = mong đợi, đánh dấu `xfail` tới khi fix).
2. **B1 `<print>` nội suy**: `vm_value_ops.zig:603-616` nhánh `print`/`print:` → `printInterpolated(arg.string)` khi `.string`.
3. **B2 `bytes(N)` + `<len>`**:
   - `vm.zig:1268` `.len`: thêm nhánh `.bytes => |b| @intCast(b.len)`.
   - Đảm bảo var_decl `bytes` với arg `.int` cấp phát `N` byte (@memset 0) và lưu `.bytes` (kiểm `compiler.zig:316` `compileVarDecl` + vm var_decl; nếu bytecode compile thẳng `.int` → sửa để tạo buffer).
4. **B3 + Bonus-C method self-binding + UAF**:
   - `vm_value_ops.zig:197` `callUserFunction` và `:262` `callUserFunctionValues`: tạo scope, **clone `ci.fields` vào `scope.variables`** (+ bind self nếu SPEC) trước khi chạy body. Tránh double-free: `clone()` từng field.
   - Chạy Valgrind ca method → xác nhận hết `0xAA` (Bonus-C).
5. **M1 catch bytecode**: khuyến nghị **workaround đúng ngay** — thêm `catch_stmt` vào guard `executor.zig:116` (`hasFuncOrClassDef` → đổi tên `requiresAstWalker`) để source có catch đi AST walker. Ghi TODO implement catch handler stack (`.catch_start`/`.catch_end` + `vm.zig:1323-1324`) ở task riêng.
6. **B5 `type()`**: `vm_value_ops.zig:327` `evaluateCall` thêm nhánh `type` (đầu hàm) + `:719` `callBuiltin` (dùng chung logic `evaluateSystemTag:648-668`).
7. **M3/C1 unknown tag**: cuối `evaluateSystemTag` (`vm_value_ops.zig` ~cuối hàm) → `raiseError("UnknownSystemTag", ...)` + `return error.RuntimeError`; đồng bộ `compiler.zig:308-309`.
8. **Bonus-B freal↔int** (tùy chọn, OPTIONAL): thêm coercion int→freal trong `operator.zig`/`value.zig` `applyBinary` khi 1 vế freal 1 vế int. **Chỉ làm nếu user đồng ý đổi SPEC.**
9. **A1 nửa runtime** (SAU khi Claude merge):
   - `vm_value_ops.zig:68` `evaluateLiteral`: `.tuple` → duyệt `lit.elements`, build `Value.tuple` (hoặc `.list`), `deinit` đúng.
   - `compiler.zig:219` `compileExpression`: `.tuple` → opcode `make_tuple` **hoặc** `return error.UnsupportedBytecode` (fallback AST). Khuyến nghị fallback trước.
   - Bật lại parity test tuple (bỏ `xfail`).
10. Commit + PR `kilo/fix-runtime` → `Releases`.

---

## 6. Thứ tự tích hợp & tránh xung đột

1. Claude (Lane A) hoàn tất → merge `claude/fix-parser` → `Releases` (build + test xanh).
2. Kilo (Lane B) `git rebase Releases` → làm nốt A1-runtime + parity test → merge `kilo/fix-runtime` → `Releases`.
3. Vì 2 lane **sở hữu file tách biệt**, xung đột merge gần như = 0; ngoại lệ duy nhất là `build.zig` (chỉ Kilo sửa) và `ast.Literal.elements` (contract, Claude đi trước).

---

## 7. Kiểm thử / validation (mỗi lane + sau tích hợp)

```bash
export PATH=/home/codespace/.vscode-remote/data/User/globalStorage/ziglang.vscode-zig/zig/x86_64-linux-0.16.0:$PATH
zig build
zig build test < /dev/null            # luôn đóng stdin
```

Parity matrix (mỗi ca chạy bytecode + AST, so output):

| Bug | Ca kiểm |
|---|---|
| A1 | `(1,2,3)~t <printf>^(t)` → `(1, 2, 3)`; `('a','b')~t` parse OK |
| A2 | `<$random>(1,5)` có Import → parse+chạy |
| A3 | `bytes(<encode(`UTF-8`)>^("hi"))~b` → parse OK |
| B1 | `[ int(7)~x <print>string^("x={x}\n") ]` → `x=7` |
| B2 | `bytes(8)~b int(<len>^(b))~l` → `8` |
| B3 | `Foo !class[int(5)~x get()[<return>(x)]] ~Foo~f int($f~get())~r` → `5`, Valgrind 0 |
| M1 | catch đặt trước lỗi → bắt đúng, bytecode==AST |
| M2 | `[ {'a':1}~d <printf>^(d{'a'}) ]` → `1` |
| B5 | `type("hi")` → `string`; `type(123)` → `int` |
| M3 | `[ <foo>^("x") ]` → `UnknownSystemTag`, rc≠0 |

- Regression: chạy lại bộ 978 case (nếu còn ở `/tmp/scratchpad/ko_fuzz/`) → 0 crash.
- Memory: Valgrind ca method call (B3/Bonus-C) + `fetchPut` paths.
- Graph: `graphify update .` sau khi merge vào `Releases`.

---

## 8. Rủi ro & giảm thiểu

| Rủi ro | Giảm thiểu |
|---|---|
| Sửa parser làm hỏng case hợp lệ | Chạy full 978 case sau mỗi nhóm; ưu tiên A2/M2 đơn lẻ. |
| Hai agent chạm cùng file | File-disjoint; hợp đồng `Literal.elements`; merge Claude trước. |
| A1 đổi `ast.Literal` | Cập nhật mọi initializer + `deinit`; `zig build` bắt lỗi thiếu field. |
| B3 copy fields → double-free | `clone()` từng field; Valgrind; tái dùng pattern `instantiateClassByName`. |
| M1 workaround che mất parity | Ghi TODO catch bytecode; parity test catch vẫn chạy AST. |
| Worktree cũ còn session active | Đóng session Kilo trước khi `git worktree remove`. |
| Bonus-B đổi semantics | Để OPTIONAL; nếu làm phải update SPEC + test. |

---

## 9. Ngoài phạm vi

REPL, plugin loader, Phase 7/8, completion runtime; bytecode catch handler đầy đủ (tách task); ghi field qua `$self` trong method; coercion freal↔int (trừ khi user chốt).

---

## 10. Quyết định mặc định (không chặn)

1. Base = `Releases` (bắt buộc, do `main`/branch cũ thiếu fix).
2. Branch mới: `claude/fix-parser`, `kilo/fix-runtime`; xoá branch `claude`/`fantasy-land` cũ (tuỳ chọn).
3. A1 runtime: **fallback AST** (`UnsupportedBytecode`) trước, tối ưu opcode sau.
4. M1: **workaround guard** (đưa catch vào AST walker) trước; implement catch bytecode tách task.
5. B3: chỉ **đọc** field; ghi `$self~field` là follow-up.
6. Bonus-B: **giữ strict** (ngoài scope) trừ khi user yêu cầu.