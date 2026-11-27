# Kế hoạch sửa lỗi `compiler_ko` — từ BUG.md + đối chiếu repo

> Nguồn: `BUG.md` (báo cáo 2026-11-14 → đính chính 2026-11-18, 978 case) + đọc trực tiếp source.
> Mọi anchor `file:line` dưới đây đã được xác minh bằng đọc code trong phiên lập plan này.
> **Đây là plan-only.** Việc sửa source phải chuyển sang agent có quyền ghi (implementation-capable).

---

## 1. Mục tiêu & phạm vi

Đưa compiler về **parity bytecode ↔ AST walker** và khép các gap parser/spec đã ghi trong `BUG.md`:

- Nhóm A (parser từ chối cú pháp hợp lệ SPEC): A1 tuple/list, A2 `<$tag>`, A3 `bytes(<encode>)`.
- Nhóm B (chạy nhưng sai kết quả / OOP hỏng): B1 `<print>` nội suy, B2 `bytes(N)`+`<len>`, B3 method self-binding (+ Bonus-C nghi UAF).
- M1 `<catch>` bytecode no-op (parity HIGH).
- M2 dict colon `{'a':1}` parse sai.
- B5 `type()`, M3/C1 unknown tag im lặng.
- (Tùy chọn) Bonus-B freal↔int coercion; C2/C5 siết validate.

**Không** nằm trong phạm vi: REPL/plugin/Phase 7-8, coercion nếu user chốt "giữ strict".

---

## 2. Bối cảnh kiến trúc quan trọng (đã xác minh)

### 2.1 Backend selection — gốc của phần lớn lỗi parity
`src/executor.zig:52-86`:
```
if (!hasFuncOrClassDef(program) && !hasImportStmt(program)) { ... bytecode ... }
```
`hasFuncOrClassDef` (`executor.zig:116-129`) chỉ bắt `func_decl`/`class_decl`/`class_instantiation`.
→ Chương trình **không** có các khai báo này (đa số `.ko` thực tế) **luôn đi bytecode**.
→ Mọi bug parity (catch, bytes, print, method, type) đều khu trú ở đường bytecode.

### 2.2 Test suite mù với bytecode
`testing/test_3600.zig` gọi thẳng `VM.execute()` (AST walker), **không** qua `Executor`/`executeChunk`.
→ BUG-1/2/3 + M1/M2 tồn tại lâu vì test không bao giờ chạm bytecode. **Fix này bắt buộc** (mục 7).

### 2.3 Hai đường `printf`/`print`/`len` khác nhau
- AST: `evaluateCall` (`vm_value_ops.zig:434`), `evaluateSystemTag` (`vm_value_ops.zig:603-684`).
- Bytecode: `callBuiltin` (`vm_value_ops.zig:719-790`) + opcode handlers trong `vm.zig` (`.print` 1236, `.len` 1268, `.input` 1255, `.call` 953, `.call_method` 1002).

### 2.4 Lệnh verify chuẩn
```
export PATH=/home/codespace/.vscode-remote/data/User/globalStorage/ziglang.vscode-zig/zig/x86_64-linux-0.16.0:$PATH
zig build
zig build test < /dev/null        # luôn đóng stdin
./zig-out/bin/ko <file.ko> </dev/null
graphify update .                 # sau khi sửa code
```

---

## 3. Ma trận bug → root cause → hướng sửa

| Mã | Mức | File:dòng (đã xác minh) | Root cause | Hướng sửa |
|---|---|---|---|---|
| **A1** tuple/list | HIGH | `parser_expr.zig:389-460` (`.l_paren`); `ast.zig:250-270` (Literal thiếu `elements`) | `(...)` chỉ coi là 1 expr; gặp `,` → `expectRParen` fail. AST chưa có chỗ chứa list elements. | Thêm field `elements: []*Expr` cho `Literal` (kind `.tuple`/mới `.list`); parser gom `expr (, expr)*`; VM `evaluateLiteral` → `Value{ .tuple/.list }`; bytecode: thêm opcode `make_tuple`/`make_list` **hoặc** trả `UnsupportedBytecode` để fallback AST. |
| **A2** `<$tag>` | HIGH | `parser_expr.zig:8-21` `parseSystemTagName` (chỉ `.keyword`/`.identifier`); `parser.zig:1166-1185` `isSystemTagOpener` (không nhận `.dollar`) | Token `.dollar` (đã có ở `lexer.zig:21,249`) không được tiêu thụ. | `parseSystemTagName`: nếu `.dollar` → `advance()` rồi đọc identifier/keyword. `isSystemTagOpener`: cho `peek(1)==.dollar`. |
| **A3** `bytes(<encode(...)>)` | MED | `parser_expr.zig` (parse `bytes(` / var_decl) + `parser.zig:415-437` `parseVarDecl` | Cần tái hiện chính xác; nghi lồng `<...>` trong `bytes(...)` không vào nhánh system-tag của parseExpression. | Reproduce → fix nhánh parse arg của `bytes(`/var_decl để nhận `system_tag` lồng. |
| **B1** `<print>` không nội suy | HIGH | `vm_value_ops.zig:626-636` (`print` ghi thẳng `arg.string`) | Chỉ `printf` gọi `printInterpolated`; `print` dùng `writeAll` thô. Bytecode: compiler không xử lý tag `print` (`compiler.zig:290-311`) → rơi AST, nên fix tại AST là đủ trước. | `evaluateSystemTag` nhánh `print`/`print:` → `printInterpolated(arg.string)` khi `.string`. |
| **B2** `bytes(N)` len=0 | HIGH | `compiler.zig:316-321` `compileVarDecl` (bỏ qua `type_name`); `vm.zig:1268-1280` `.len` thiếu `.bytes` | Bytecode `compileVarDecl` compile thẳng `value_expr` (số 8) rồi `store_var` → lưu **int**, không phải buffer bytes. `.len` opcode rơi `else => 0`. | (a) `compileVarDecl`: nếu `type_name=="bytes"` → emit path tạo bytes (opcode mới `make_bytes` hoặc gọi builtin `bytes`). (b) `.len` handler thêm `.bytes => |b| @intCast(b.len)`. |
| **B3** method self-binding (+Bonus-C) | HIGH | `vm_value_ops.zig:197-260` `callUserFunction`; `262+` `callUserFunctionValues`; `vm_value_ops.zig:459-466` (AST `.class_instance`); `vm.zig:1002-1037` `.call_method` | Method scope tạo từ `func.closure_scope` (scope class), **không** chứa instance fields → `load_var x` = UndefinedVariable. Bonus-C: nghi `0xAA` UAF đi kèm. | Truyền instance vào call: tạo scope, **copy `ci.fields` (clone) vào `scope.variables`** (+ bind self nếu SPEC cần) trước khi chạy body. Áp cho cả `callUserFunction` (AST) và `callUserFunctionValues` (bytecode `.call_method`). Sau fix chạy Valgrind xác nhận hết `0xAA`. |
| **M1** catch no-op | HIGH | `compiler.zig:337-345` `compileCatch` (body inline); `vm.zig:1323-1324` `.catch_start/.catch_end` = no-op | Trên bytecode catch chỉ là 2 marker rỗng; body luôn chạy, lỗi không bắt. | **Khuyến nghị (an toàn):** đưa `catch_stmt` vào guard `hasFuncOrClassDef` (đổi tên/ mở rộng) → chương trình có catch đi AST walker (đúng semantics ngay). **Tùy chọn sau:** implement catch thật trong `executeChunk` (catch-handler stack: start_ip/end_ip/handler_ip/stack_depth). |
| **M2** dict colon parse | HIGH | `parser.zig:335-337` (`{`→parseExprStatement), `1145-1148`; `parser_expr.zig:462-510` (dict literal) | `{'a':1}~d` ở đầu statement: parse `{...}` thành expr dict rồi **không** tiêu thụ `~d` → `d` không được gán đúng. | Ở statement dispatch: nếu `{` → thử parse dict literal + `~name` thành var_decl; hoặc trong `parseExprStatement` hỗ trợ hậu tố `~ident`. |
| **B5** `type()` | MED | `vm_value_ops.zig:327+` `evaluateCall` (tra identifier `type` → fail); `callBuiltin:719` không có `type` | `type` không phải tag; parse thành `CallExpr{callee:"type"}` → tra user func → UndefinedFunction. | Thêm nhánh `type` trong `evaluateCall` (đầu hàm) **và** `callBuiltin` (dùng chung logic `evaluateSystemTag:648-668`). |
| **M3/C1** unknown tag im lặng | MED | `vm_value_ops.zig:603-684` cuối hàm `return .null` | Tag lạ rơi xuống trả null, không lỗi; 3 cú pháp cho 3 kết quả khác nhau. | Cuối `evaluateSystemTag` → `raiseError("UnknownSystemTag", ...)` + `return error.RuntimeError`. Rà `compiler.zig:308-309` đồng bộ. |
| **C2** `(10)~x` thiếu kiểu | MED | `parser.zig:335-337` → parseExprStatement | `{`/`(` expr statement không bắt buộc type. | (Thấp) Báo lỗi nếu expr statement là `(...)`~ident không có type. |
| **C5** catch thiếu backtick | LOW | `parser.zig:1276` parse catch | Không validate `error_type` format. | (Thấp) Validate dạng `` `Ident` ``. |
| **Bonus-B** freal↔int | MED | `value.zig:181+` `add` strict; `operator.applyBinary` | Không coercion freal↔int → TypeError. | (Tùy chọn) Thêm coercion int→freal khi 1 vế freal. Cần user chốt có đổi SPEC không. |

---

## 4. Thứ tự thực thi (task list chi tiết)

### Giai đoạn 0 — Hạ tầng test parity (làm TRƯỚC, để bắt regression)
1. Tạo `testing/test_executor.zig` (hoặc thêm vào `test_3600.zig`) chạy **qua `Executor.execute`** cho các ca đại diện: printf nội suy, input+printf, div0 (rc=3 không 134), catch, method call, bytes+len, tuple/list.
2. Wire vào `build.zig` (mẫu: các `test_*` hiện có).
3. Verify: `zig build test < /dev/null` xanh baseline (chưa fix → các ca parity mới sẽ đỏ, đó là mong đợi).

### Giai đoạn 1 — Parser (A1, A2, A3, M2, C2/C5)
4. **A2** (rẻ, chặn module): sửa `parseSystemTagName` + `isSystemTagOpener` nhận `.dollar`.
5. **A1** tuple/list: mở rộng `ast.Literal` (`elements`), parser `.l_paren` gom `,`-separated, VM `evaluateLiteral`, bytecode fallback.
6. **M2** dict colon: sửa dispatch `{` ở statement để nhận `dict ~name`.
7. **A3** `bytes(<encode>)`: reproduce rồi fix parse lồng.
8. **C2/C5** siết validate (thấp).

### Giai đoạn 2 — Bytecode parity (B2, B1, B3, M1)
9. **B2**: `compileVarDecl` xử lý `type_name=="bytes"`; `.len` opcode thêm `.bytes`.
10. **B1**: `evaluateSystemTag` `print` → `printInterpolated`.
11. **B3 + Bonus-C**: bind instance fields vào method scope ở cả 2 đường; Valgrind.
12. **M1**: mở rộng guard cho `catch_stmt` (workaround đúng ngay); ghi chú follow-up implement catch bytecode.

### Giai đoạn 3 — Introspection & chẩn đoán (B5, M3/C1)
13. **B5** `type()`: thêm nhánh ở `evaluateCall` + `callBuiltin`.
14. **M3/C1**: unknown tag → `UnknownSystemTag`.

### Giai đoạn 4 — Tùy chọn (Bonus-B, nếu user đồng ý)
15. freal↔int coercion trong `applyBinary`.

### Giai đoạn 5 — Tổng kết
16. `graphify update .`; cập nhật `BUG.md` (đánh dấu FIXED + bằng chứng), `CHECKPOINTS.md`, `MEMORY.md`.

---

## 5. File bị ảnh hưởng

| File | Thay đổi |
|---|---|
| `src/ast.zig` | `Literal` thêm `elements` (tuple/list); `deinit` tương ứng. |
| `src/parser_expr.zig` | `parseSystemTagName` (A2), `.l_paren` (A1), `print` (B1 gián tiếp), dict (M2). |
| `src/parser.zig` | `isSystemTagOpener` (A2), statement dispatch `{`/`(` (M2/C2), `parseVarDecl` (A3). |
| `src/vm.zig` | `.len` bytes (B2), `.call_method` self-bind (B3), catch guard (M1), unknown tag (M3 gián tiếp). |
| `src/vm_value_ops.zig` | `callUserFunction`/`callUserFunctionValues` (B3), `evaluateCall` (B5), `evaluateSystemTag` (B1/B5/M3), `callBuiltin` (B5). |
| `src/compiler.zig` | `compileVarDecl` (B2), `compileCatch` (M1 nếu làm bytecode), `compileExpression` (A1 fallback, print). |
| `src/bytecode.zig` | Opcode mới nếu chọn bytecode cho tuple/list/bytes (tùy chọn). |
| `src/executor.zig` | Guard `hasFuncOrClassDef` thêm `catch_stmt` (M1). |
| `testing/test_executor.zig` (mới) + `build.zig` | Parity test. |

---

## 6. Quyết định thiết kế cần chốt khi implement

1. **A1 tuple/list ở bytecode:** làm opcode mới (`make_tuple`/`make_list`) hay fallback AST? → Khuyến nghị: **fallback AST** trước (return `error.UnsupportedBytecode`), tối ưu opcode sau.
2. **M1 catch ở bytecode:** workaround (guard → AST) hay implement catch handler stack? → Khuyến nghị: **workaround ngay**, implement bytecode catch ở task riêng (rủi ro unwind qua Zig error).
3. **B3 self-binding:** chỉ đọc field, hay hỗ trợ cả ghi `$self~field = ...`? → Khuyến nghị: **đọc field** (đủ cho B3), ghi field là follow-up.
4. **Bonus-B coercion:** có đổi SPEC không? Mặc định **giữ strict** (ngoài scope) trừ khi user yêu cầu.

---

## 7. Kế hoạch kiểm thử (validation)

- **Build:** `zig build` → rc=0.
- **Unit:** `zig build test < /dev/null` → EXIT=0, thêm `test_executor` xanh.
- **Parity matrix (mỗi ca chạy 2 đường bytecode/AST, so output):**
  - `int(7)~x <printf>^("x={x}")` → `x=7` (B1)
  - `bytes(8)~b int(<len>^(b))~l` → `8` (B2)
  - `Foo !class[int(5)~x get()[<return>(x)]] ~Foo~f int($f~get())~r` → `5`, Valgrind 0 error (B3/C)
  - `<catch>` đặt trước lỗi → bắt đúng, rc=0 khi bắt; AST walker==bytecode (M1)
  - `{'a':1}~d <printf>^(d{'a'})` → `1` (M2)
  - `(1,2,3)~t ...`, `('a','b')~t` → parse OK, index đúng (A1)
  - `<$random>(1,5)` có Import → parse+chạy (A2)
  - `type("hi")`, `type(123)` → `string`/`int` (B5)
  - `<foo>^("x")` → `UnknownSystemTag` rc≠0 (M3)
- **Regression:** chạy lại bộ 978 case (`/tmp/scratchpad/ko_fuzz/`) → 0 crash.
- **Memory:** Valgrind ca method call (Bonus-C) + `fetchPut` paths.
- **Graph:** `graphify update .`.

---

## 8. Rủi ro & giảm thiểu

| Rủi ro | Giảm thiểu |
|---|---|
| Sửa parser làm hỏng case hợp lệ | Chạy full 978 case sau mỗi nhóm; ưu tiên A2/M2 đơn lẻ trước. |
| B3 copy fields gây double-free | `clone()` từng field; Valgrind; tái dùng pattern `instantiateClassByName` (`vm_value_ops.zig:173-195`). |
| M1 workaround che mất parity thật | Ghi rõ TODO implement catch bytecode; parity test catch vẫn chạy AST (đúng) + đánh dấu backend. |
| A1 thay đổi `ast.Literal` | Cập nhật mọi `ast.Literal{...}` initializer + `deinit`; `zig build` bắt lỗi thiếu field. |
| Coercion freal/int đổi semantics | Để ngoài scope; nếu làm phải update SPEC + test. |

---

## 9. Ngoài phạm vi (out of scope)

- REPL, plugin loader, Phase 7/8 hardening, completion runtime.
- Tối ưu bytecode cho tuple/list/bytes (nếu chọn fallback).
- Ghi field qua `$self` trong method.
- Coercion freal↔int (trừ khi user chốt).

---

## 10. Câu hỏi mở (cần user chốt trước/trong implement)

1. A1: bytecode opcode mới hay fallback AST? (đề xuất: fallback AST)
2. M1: workaround guard hay implement catch bytecode đầy đủ? (đề xuất: workaround, catch bytecode tách task)
3. B3: chỉ đọc field hay hỗ trợ ghi `$self~field`? (đề xuất: chỉ đọc)
4. Bonus-B: có nới coercion freal↔int (đổi SPEC) không? (đề xuất: không, giữ strict)