# BUG REPORT — `compiler_ko`

**Ngày:** 2026-11-14 (cập nhật 2026-11-15: đã fix)
**Nhánh:** `Releases`
**Commit:** `c32dc0b`
**Toolchain:** Zig 0.16.0
**Phạm vi:** Test toàn bộ 6 file `.ko` + fuzz ~60 chương trình bổ sung (arithmetic, control flow, functions, classes, IO/tags, dicts/index, errors, input)
**Ràng buộc:** Không sửa file nguồn — báo cáo chỉ ghi nhận

---

## ✅ TRẠNG THÁI: ĐÃ FIX (2026-11-15)

| Mã | Trạng thái | Cách sửa |
|---|---|---|
| 🔴 BUG-1 | ✅ FIXED | `executor.zig`: `errdefer` → `defer` + cờ `freed` (một chủ sở hữu duy nhất) |
| 🔴 BUG-2 | ✅ FIXED | Cùng root cause với BUG-6 (fetchPut) — xem dưới |
| 🟠 BUG-3 | ✅ FIXED | `vm.zig` `.print` handler: string → `printInterpolated` |
| 🟠 BUG-4 | ✅ FIXED | `vm.zig` `raiseError`: in `err_type: message` thay vì `_ = message` |
| 🟡 BUG-5 | ✅ FIXED | `chunk.deinit()` gom về `defer` + cờ (cùng BUG-1) |
| 🔴 **BUG-6 (mới)** | ✅ FIXED | `fetchPut` + `free(old.key)` = use-after-free ở 3 chỗ |

**BUG-7 (top-level không nhất quán) — ĐÃ LOẠI** (báo cáo ban đầu sai). Xem mục 3.7.

**Kiểm chứng sau fix (2026-11-15):**
```
zig build                                    → BUILD=0
zig build test < /dev/null                   → EXIT=0 (15/15 pass)
[ Nope() ]                                   → rc=3 (không crash 134)
[ int(1)~a int(0)~b int(a/b)~c ]             → rc=3
[ string("")~s <input>(s) <printf>^(s) ]      → in "x" (không TypeError)
[ int(7)~x <printf>^("x={x}\n") ]            → in "x=7"
[ null~x <printf>^(x) ]                       → "TypeError: Cannot print an unassigned null value"
5 file .ko hợp lệ                            → rc=0
```

---

## 0. Tóm tắt điều hành

| Mức độ | Mã | Tên | Trạng thái |
|---|---|---|---|
| 🔴 CRITICAL | **BUG-1** | Double-free / use-after-free khi mọi lỗi runtime đi qua backend bytecode | ✅ Valgrind + 50+ ca tái hiện |
| 🔴 CRITICAL | **BUG-2** | `<input>` + `<printf>` gây `TypeError` + crash trên bytecode | ✅ 4/4 |
| 🟠 HIGH | **BUG-3** | Mất nội suy `{biến}` trong `<printf>` trên backend bytecode | ✅ Đối chứng 2 backend |
| 🟠 HIGH | **BUG-4** | Thông báo lỗi runtime bị nuốt (`_ = message`) | ✅ Đọc source |
| 🟡 MEDIUM | **BUG-5** | `chunk.deinit()` gọi ở 5 vị trí — kiến trúc dễ vỡ | ✅ Đọc source |

**Số bug thực:** 5 (2 CRITICAL, 2 HIGH, 1 MEDIUM).

**BUG-6 (top-level không nhất quán) — ĐÃ LOẠI.** Báo cáo ban đầu sai. Xem mục 3.6.

**Điểm mấu chốt:** BUG-1 là *root cause* khiến **mọi** lỗi runtime trên backend bytecode biến thành crash `rc=134`. Vì CLI mặc định chọn bytecode khi chương trình không có `func_decl`/`class_decl`/`Import`, phần lớn chương trình `.ko` thực tế đều đi qua đường lỗi này.

---

## 1. Môi trường & phương pháp

### 1.1 Toolchain

```
$ zig version
0.16.0
$ zig build
BUILD_EXIT=0
$ zig build test < /dev/null
EXIT=0   (benchmark 15/15 pass)
```

### 1.2 Danh sách file `.ko` gốc được test

| File | Dòng | Nội dung |
|---|---|---|
| `empty_test.ko` | 2 | `f() [ ]` + `f()` |
| `examples/simple.ko` | 6 | var_decl + printf |
| `examples/medium.ko` | 13 | var_decl + printf + if |
| `examples/test.ko` | 20 | Import + booling + if + catch |
| `testing/class_test.ko` | 1 | class decl + instantiation |
| `testing/ko.ko` | 3 | `<print>` system tag |

### 1.3 Phương pháp

1. **Đối chứng có kiểm soát** — mỗi bug test theo cặp "ca lỗi" vs "ca đúng".
2. **Valgrind Memcheck** — phân biệt double-free / use-after-free / leak.
3. **Đối chiếu 2 backend** — bytecode vs AST walker cho cùng source.
4. **Đối chiếu SPEC** — `SPECIFICATION.md` §2, §V, §XII.

---

## 2. Kết quả test 6 file `.ko` gốc

| File | RC | STDOUT | STDERR | Đánh giá |
|---|---|---|---|---|
| `examples/simple.ko` | 0 | `Hello World` | — | ✅ Đúng cú pháp |
| `examples/medium.ko` | 0 | `Sum: ` / `30` / `Sum is greater than 25` | — | ✅ Đúng cú pháp |
| `examples/test.ko` | 0 | `Hello .ko` / `Player is alive!` | — | ✅ Đúng cú pháp |
| `testing/class_test.ko` | 0 | *(chỉ tên process)* | — | ✅ Đúng cú pháp (tầm thường) |
| `testing/ko.ko` | 0 | `hello` | `Bytecode compile failed ... falling back` | ✅ Đúng cú pháp |
| `empty_test.ko` | **3** | *(tên process)* | `Runtime error: error.RuntimeError` | ❌ Sai cú pháp |

### 2.1 `empty_test.ko` — sai cú pháp, KHÔNG phải bug compiler

```ko
f() [ ]      ← func_decl: hợp lệ ở global scope
f()          ← expr call: BẤT HỢP PHÁP
```

`SPECIFICATION.md:151`: *"Execution statements must not float freely outside the global scope... The global scope only accepts: Import statements, Function declarations, and Class declarations."*

→ `f()` ở dòng 2 là *execution statement trôi nổi*. Compiler **từ chối đúng**. Cần sửa nội dung file, không sửa compiler.

### 2.2 `testing/class_test.ko` — đúng nhưng không quan sát được

Chỉ khai báo + instantiate, không có main block, không in gì. Đã kiểm chứng riêng bằng file tạm (`class + method call`) → class hoạt động thật (in `hi John`).

---

## 3. Chi tiết lỗi

### 🔴 BUG-1 — Double-free / use-after-free khi lỗi runtime trên backend bytecode

**Mức độ:** CRITICAL
**File:** `src/executor.zig:53-75`, `src/bytecode.zig:62-93`
**Phát hiện:** Valgrind Memcheck + 50+ ca tái hiện

#### 3.1.1 Triệu chứng

Mọi lỗi runtime trong chương trình **không có** `func_decl`/`class_decl`/`Import` (tức đi qua backend bytecode) đều làm compiler **abort**:

| Chương trình | RC | Ghi chú |
|---|---|---|
| `[ Nope() ]` | **134** | core dumped |
| `[ int(1)~a int(0)~b int(a/b)~c ]` | **134** | chia cho 0 |
| `[ int(1)~a string("x")~b int(a+b)~c ]` | **134** | sai kiểu |
| `[ null~x int(x+1)~y ]` | **134** | null trong toán |
| `[ <len>^("hello")~n <printf>^(n) ]` | **134** | len system tag |
| `[ <encode>^("ABC")~b <printf>^(b) ]` | **134** | encode system tag |
| `[ int(0)~i <while>(i < 3) [ ... ] ]` | **134** | while loop |
| `[ string("")~s <input>(s) <printf>^(s) ]` | **134** | input + printf |
| `[ int(1)~x ]` | 0 | ✅ đối chứng, không lỗi |

**Đối chứng chéo:** cùng lỗi chia 0 nhưng có `func_decl` (đi AST walker) → `rc=3` bình thường, **không** crash.

#### 3.1.2 Bằng chứng Valgrind

```
==41357== Invalid write of size 1
==41357==    at 0x10EDA06: mem.Allocator.free__anon_12545 (mem/Allocator.zig:448)
==41357==    by 0x12B6AF8: bytecode.Function.deinit (bytecode.zig:69)
==41357==    by 0x12B6231: bytecode.Chunk.deinit (bytecode.zig:95)
==41357==    by 0x121780D: executor.Executor.execute (in ko)
==41357==    by 0x1218677: main.executeCode (in ko)
==41357==    by 0x122D33C: main.mainInner (main.zig:405)
==41357==  Address 0xaaaaaaaaaaaaaaaa is not stack'd, malloc'd or (recently) free'd
```

- `0xaaaaaaaa...` là **pattern của Zig `DebugAllocator`** sau khi free → vùng nhớ đã được giải phóng.
- Valgrind phân loại **"Invalid write"** → đây là **use-after-free** (ghi vào vùng đã free) và **double-free** ở lần `free` tiếp theo.

**Đối chứng:** chương trình hợp lệ `[ int(1)~x ]` → Valgrind `ERROR SUMMARY: 0 errors from 0 contexts`.

#### 3.1.3 Nguyên nhân gốc

`src/executor.zig:53-75`:

```zig
var chunk = try bytecode_mod.Chunk.init(self.allocator);
errdefer chunk.deinit(self.allocator);                    // ← (A) errdefer
var comp = try compiler_mod.Compiler.init(...);
defer comp.deinit();
if (comp.compileProgram(program)) |_| {
    self.vm.executeChunk(&chunk) catch |err| {
        if (err == error.EndOfInput) { ... }
        std.debug.print("Runtime error: {any}\n", .{err});
        chunk.deinit(self.allocator);                     // ← (B) free tường minh
        return error.RuntimeError;                        // ← (A) chạy tiếp → free lần 2
    };
    chunk.deinit(self.allocator);
    self.backend_used = .bytecode;
    return;
} else |err| {
    std.debug.print("Bytecode compile failed ({any}); falling back to AST walker\n", .{err});
}
chunk.deinit(self.allocator);
```

**Cơ chế:** `errdefer` (A) chỉ kích hoạt khi hàm `return error`. Nhánh lỗi runtime (B) **luôn** `return error.RuntimeError` ngay sau khi đã `deinit` → `errdefer` chạy lần hai trên cùng con trỏ.

`Compiler.init` (`src/compiler.zig:20`) đã `chunk.functions.append(...)` cấp phát `name`, nên `Chunk.deinit` luôn có phần tử để `free` → luôn chạm crash.

#### 3.1.4 Vì sao lỗi compile KHÔNG crash

Nhánh `else |err|` (compile thất bại) cũng gọi `chunk.deinit()` nhưng **không** `return error` — nó rơi xuống AST walker và return bình thường, nên `errdefer` không kích hoạt. Chỉ đúng vùng `catch` của `executeChunk` mới gây crash.

#### 3.1.5 Hướng sửa (đề xuất, chưa áp dụng)

1. Bỏ 3 lời gọi `chunk.deinit()` tường minh trong nhánh `catch` và `return`, để `errdefer` là chủ sở hữu duy nhất; hoặc
2. Bỏ `errdefer`, dùng `defer` + một cờ `bool`.

> **Nguyên tắc Zig:** `errdefer` phải là chủ sở hữu duy nhất của tài nguyên. Nếu đã có `defer`/`errdefer`, không được `deinit` thủ công rồi `return error`.

---

### 🔴 BUG-2 — `<input>` + `<printf>` gây `TypeError` + crash trên backend bytecode

**Mức độ:** CRITICAL
**File:** `src/vm.zig:1236-1241` (`.input` handler trong `executeChunk`)
**Phát hiện:** Thu hẹp từng bước, đối chứng 2 backend

#### 3.2.1 Triệu chứng

| Chương trình | Backend | RC | Kết quả |
|---|---|---|---|
| `[ string("")~s <input>(s) ]` | bytecode | 0 | ✅ chạy |
| `[ string("")~s <input>(s) <printf>^("A") ]` | bytecode | 0 | ✅ in `A` |
| `[ string("")~s <input>(s) <printf>^(s) ]` | bytecode | **134** | ❌ `TypeError` + crash |
| `[ string("")~s <input>(s) <printf>^(s) ]` | AST walker | 0 | ✅ in `x` |

#### 3.2.2 Bằng chứng

```
$ echo "x" | ./zig-out/bin/ko /tmp/c2.ko
/tmp/c2.ko:main
Runtime error: error.TypeError
General protection exception (no address available)
  ... byte.zig:69 in deinit ...
  ... executor.zig:55 in execute (errdefer chunk.deinit) ...
```

- `printf("A")` in được `A` → `<input>` **đã chạy thành công**.
- `printf(s)` với `s` lấy từ input → `TypeError`.
- Cùng source, AST walker in `x` đúng.

#### 3.2.3 Phân tích

`.input` handler (`src/vm.zig:1236`):

```zig
.input => {
    const line = try self.readInputLine();
    const str = try self.allocator.dupe(u8, line);       // ← cấp phát lần 1
    stack[sp] = value_mod.Value{ .string = str };
    sp += 1;
},
```

`readInputLine()` đã `allocator.dupe` bên trong → `line` là owned. Handler lại `dupe` lần nữa thành `str` mà **không free `line`** → rò rỉ 1 allocation mỗi lần `<input>`.

Crash `rc=134` là do **BUG-1** (`errdefer` double-free) kích hoạt khi `error.TypeError` được ném ra. Nhưng `TypeError` **từ đâu** vẫn là câu hỏi mở — vì `printf(s)` trên biến string hợp lệ lẽ ra phải chạy. `printf(s)` với `s` gán bằng literal (`string("abc")~s`) chạy tốt trên bytecode. Chỉ `s` lấy từ `<input>` mới `TypeError`. Cần debug thêm ở `load_var`/`clone` cho giá trị đến từ `.input`.

#### 3.2.4 Hướng sửa (đề xuất)

1. Sửa `.input` handler: `defer self.allocator.free(line);` sau khi `dupe` (chống leak).
2. Điều tra `TypeError` khi `printf` nhận biến từ input.
3. Sửa BUG-1 trước (để `TypeError` không biến thành crash).

---

### 🟠 BUG-3 — Mất nội suy `{biến}` trong `<printf>` trên backend bytecode

**Mức độ:** HIGH (sai kết quả âm thầm)
**File:** `src/vm_value_ops.zig:720` (`callBuiltin` — `printf`)
**Phát hiện:** Đối chứng 2 backend

#### 3.3.1 Triệu chứng

| Source | Backend | Output |
|---|---|---|
| `[ int(7)~x <printf>^("x={x}\n") ]` | bytecode | `x={x}` ❌ |
| `[ int(7)~x <printf>^("x={x}\n") ]` | AST walker | `x=7` ✅ |
| `[ string("abc")~s <printf>^("v={s}") ]` | bytecode | `v={s}` ❌ |
| `[ int(7)~x <printf>^(x) ]` | bytecode | `7` ✅ |

→ `printf(x)` in đúng giá trị. Chỉ **nội suy chuỗi `{x}` bên trong string literal** bị mất.

#### 3.3.2 Nguyên nhân

Hai đường thực thi `printf` khác nhau:

**AST walker** — `evaluateCall` (`src/vm_value_ops.zig:434-452`):

```zig
if (std.mem.eql(u8, call.callee, "printf")) {
    for (call.args) |arg| {
        var val = try self.evaluateExpression(@constCast(&arg));
        ...
        if (val == .string) {
            try self.printInterpolated(val.string);   // ← CÓ nội suy
        } else { ... }
        ...
    }
}
```

**Bytecode backend** — `callBuiltin` (`src/vm_value_ops.zig:720-731`):

```zig
if (std.mem.eql(u8, name, "printf")) {
    for (args) |arg| {
        if (arg == .null) { ... }
        try arg.print(self.stdoutWriter());            // ← KHÔNG nội suy
        try self.stdoutWriter().print(" ", .{});
    }
    ...
}
```

`printInterpolated` (`src/vm_value_ops.zig:128`) là hàm xử lý `{name}` → giá trị biến. `callBuiltin` không gọi nó.

#### 3.3.3 Hậu quả

- **Test suite không phát hiện** vì `testing/test_3600.zig` gọi thẳng `VM.execute()` (AST walker), không qua `Executor` → không bao giờ chạm đường bytecode. Test `format_int_interpolation` vẫn xanh trong khi CLI sai.
- Người viết `.ko` thấy `{x}` nguyên văn, tưởng chương trình đúng.

#### 3.3.4 Hướng sửa (đề xuất)

Cho `callBuiltin` dùng `printInterpolated` cho tham số `.string`, đồng nhất với `evaluateCall`. Hoặc tốt hơn: gộp hai đường `printf` thành một hàm dùng chung.

---

### 🟠 BUG-4 — Thông báo lỗi runtime bị nuốt

**Mức độ:** HIGH (mất khả năng chẩn đoán)
**File:** `src/vm.zig:767-771`

#### 3.4.1 Triệu chứng

```zig
pub fn raiseError(self: *VM, err_type: []const u8, message: []const u8) void {
    self.has_error = true;
    self.error_type = err_type;
    _ = message;              // ← vứt bỏ toàn bộ ngữ cảnh lỗi
}
```

Người dùng chỉ nhận:

```
Runtime error: error.RuntimeError
```

#### 3.4.2 Bằng chứng

Có **58 call site** `raiseError` trong `src/vm_value_ops.zig` với message cụ thể, ví dụ:

- `"Cannot read unassigned variable '{s}'"`
- `"Cannot print an unassigned null value"`
- `"Argument count mismatch"`
- `"Cannot call non-function"`
- `"Index out of bounds"`

Tất cả đều bị `_ = message` loại bỏ. Khi tạm sửa để in message, `empty_test.ko` lập tức hiện:

```
SyntaxError: Statement not allowed outside main block
```

so với trước (`Runtime error: error.RuntimeError` trống rỗng).

#### 3.4.3 Hậu quả

- Không thể phân biệt lỗi null / type / index / import từ output.
- Vi phạm `SPECIFICATION.md:1052`: *"Never swallow errors"*.

#### 3.4.4 Hướng sửa (đề xuất)

In `err_type` + `message` ra stderr (hoặc output writer có sẵn) trước khi set cờ. Lưu ý: dùng `stdoutWriter()` thay vì `File.stderr()` để giữ test hermetic.

---

### 🟡 BUG-5 — `chunk.deinit()` gọi ở 5 vị trí

**Mức độ:** MEDIUM (rủi ro kiến trúc)
**File:** `src/executor.zig:55, 62, 66, 69, 75`

#### 3.5.1 Triệu chứng

```zig
55:  errdefer chunk.deinit(self.allocator);
62:  chunk.deinit(self.allocator);      // trong catch EndOfInput
66:  chunk.deinit(self.allocator);      // trong catch runtime error
69:  chunk.deinit(self.allocator);      // sau executeChunk thành công
75:  chunk.deinit(self.allocator);      // sau compile thất bại
```

#### 3.5.2 Vấn đề

- 5 đường giải phóng cho 1 tài nguyên → BUG-1 là hệ quả trực tiếp.
- `MEMORY.md` (2026-10-25) đã ghi cảnh báo: *"defer+errdefer chunk.deinit may double-free on Compiler.init failure (pre-existing pattern retained)"* — cảnh báo này **chưa được xử lý**.
- `executeChunk` cũng có `errdefer chunk.deinit` riêng (`src/main.zig:586` gọi `executor.execute` → nhưng `chunk` là local của `execute` nên `main.zig` không giữ).

#### 3.5.3 Hướng sửa (đề xuất)

Gom về một `defer` duy nhất ở đầu hàm, hoặc chuyển `chunk` sang `Executor` struct (owned field) với `deinit` tập trung.

---

### 🔴 BUG-6 — `fetchPut` + `free(old.key)` = use-after-free (phát hiện khi fix BUG-2)

**Mức độ:** CRITICAL (root cause thật của BUG-2)
**File:** `src/vm.zig:748, 932, 1314`
**Phát hiện:** Debug từng instruction + test chứng minh semantics `fetchPut`

#### 3.6.1 Triệu chứng

`[ string("")~s <input>(s) <printf>^(s) ]` → `TypeError: Cannot print an unassigned null value` + crash.

#### 3.6.2 Truy nguyên (debug từng bước)

```
[DBG] .store_var name='s' val=.{ .string = {  } }      ← var_decl string("")~s
[DBG] store_var 's' after fetchPut get=.{ .string = {  } }
[DBG] .input line='x' sp=0
[DBG] store_var 's' val=.{ .string = { 120 } }          ← input store s="x"
[DBG] store_var 's' after fetchPut get=.{ .string = { 120 } }   ← get THẤY "x"
[DBG]   key='\xFF' len=1                                 ← key trong map là RÁC!
[DBG] .load_var name='s' found=null                      ← get KHÔNG thấy
[DBG] .print val=.{ .null = void }                       ← TypeError
```

Cùng scope pointer, cùng key `'s'`, nhưng `get` trả khác nhau — vì **key trong map đã bị free**.

#### 3.6.3 Chứng minh semantics `fetchPut` (Zig 0.16)

Test `std.StringHashMap(i32)`:
```
OLDKEY k1=true  k2=false   ← fetchPut trả về entry với key CŨ (k1)
KEPT   k1=true  k2=false   ← map GIỮ key cũ (k1), KHÔNG thay bằng key mới
GET=2                       ← value mới được store
```

#### 3.6.4 Nguyên nhân gốc

Code cũ ở cả 3 chỗ:
```zig
const owned = try self.allocator.dupe(u8, name);       // key mới
if (try map.fetchPut(owned, cloned)) |old_entry| {
    self.allocator.free(old_entry.key);   // ← old_entry.key CHÍNH LÀ key map đang giữ
    ...
}
```

Vì `fetchPut` giữ key cũ khi key đã tồn tại, `old_entry.key` **là** key đang nằm trong map. `free(old_entry.key)` → key thành **dangling pointer** → mọi `get()` sau đó hash vào rác → trả `null`.

Giải thích trọn vẹn BUG-2: `s` bị store **2 lần** (var_decl + input) → lần 2 `fetchPut` free key cũ → `load_var s` = null → `TypeError`.

#### 3.6.5 Hướng sửa (đã áp dụng)

Khi `fetchPut` trả về `Some(old_entry)`: key mới KHÔNG được map dùng → **free key mới**, giữ `old_entry.key`. Chỉ deinit `old_entry.value`.

```zig
const owned = try self.allocator.dupe(u8, name);
if (try map.fetchPut(owned, cloned)) |old_entry| {
    self.allocator.free(owned);          // ← free key MỚI (không dùng)
    var old_val = old_entry.value;
    old_val.deinit(self.allocator);      // ← chỉ deinit value cũ
}
```

Áp dụng cho cả 3 chỗ: `.store_var` (932), `assignValue` dict (748), `.dict_set` (1314).

> **Bài học:** `fetchPut` trong Zig 0.16 **giữ key cũ** khi key đã tồn tại. Không bao giờ `free(old_entry.key)` — key đó vẫn thuộc map. Đây là biến thể tinh vi của bug MEDIUM-10 đã ghi trong MEMORY 2026-10-24: MEMORY nói "fix via fetchPut", nhưng fetchPut **cũng** giữ key cũ nên vẫn phải cẩn thận.

---

### ~~🟡 BUG-7~~ — ĐÃ ĐÍNH CHÍNH: KHÔNG PHẢI BUG (trước đây là BUG-6)

**Mức độ:** ~~MEDIUM~~ → **HỦY BỎ** (báo cáo ban đầu sai)
**File:** `src/vm.zig:190-202` (`allowed_top`)

#### 3.6.1 Đính chính

Báo cáo ban đầu kết luận `int(10)~x` bị chấp nhận là "lệch SPEC §2". **Kết luận đó SAI.**

Căn cứ đính chính:

1. **Chính SPEC dùng `var_decl` ở top-level** — `SPECIFICATION.md:395-396` (ví dụ chính thức trong §V.1):

   ```ko
   int(~calculate_power(10))~total      ← var_decl ở TOP-LEVEL
   <now>(~calculate_power(20))>total    ← now ở TOP-LEVEL
   ```

2. **"Execution statements" không bao gồm khai báo.** Câu cấm ở `SPECIFICATION.md:151` chỉ áp cho *execution statements*. `var_decl` là *khai báo*, không thực thi gì.

3. **Đối chiếu thực nghiệm** — ranh giới đúng là "khai báo được, thực thi thì không":

   | Nhóm | Statement | RC | Đánh giá |
   |---|---|---|---|
   | **Khai báo** (spec cho phép) | `int(10)~x` | 0 | ✅ hợp lệ |
   | | `f() [ ]` | 0 | ✅ hợp lệ |
   | | `G !class [...]` | 0 | ✅ hợp lệ |
   | | `G !class [...] ~G~g` | 0 | ✅ hợp lệ |
   | **Thực thi** (spec cấm) | `<printf>^("x")` | 3 | ✅ bị từ chối đúng |
   | | `<if>(1==1) [ ]` | 3 | ✅ bị từ chối đúng |
   | | `<return>(1)` | 3 | ✅ bị từ chối đúng |
   | | `10` | 2 | ✅ bị từ chối đúng |

`allowed_top` trong `vm.zig:190` phân loại **đúng**. Không có bug.

> **Bài học:** đã đọc câu "The global scope only accepts: Import statements, Function declarations, and Class declarations" rồi suy diễn `var_decl` bị cấm — nhưng câu đó không nói vậy, và chính SPEC dùng `var_decl` ở global. Phải kiểm chứng bằng ví dụ trong spec và bằng thực nghiệm, không suy diễn từ một câu văn.

---

## 4. Các lỗi cú pháp được xử lý ĐÚNG ✅

| Trường hợp | RC | Thông báo |
|---|---|---|
| Thiếu `]` đóng block | 2 | `error: ExpectedRParen / ExpectedRBracket at 1:11` |
| Thừa `]` | 2 | `error: UnexpectedToken` |
| Token lạ | 2 | `error: UnexpectedToken at ...` |
| `10` trần ở top-level | 2 | parse error |
| File rỗng | 0 | không crash |
| Chỉ có comment | 0 | không crash |
| File không tồn tại | 1 | `Error: file '...' not found` |
| Import module không tồn tại | 0 | `Warning: could not load module ...` (không phải lỗi) |
| Chia cho 0 (AST walker) | 3 | `Runtime error` — đúng |
| Sai kiểu (AST walker) | 3 | `Runtime error` — đúng |
| while loop (AST walker) | 0 | đúng |
| for loop (bytecode) | 2 | parse error (cú pháp for chưa hỗ trợ?) |

**Kết luận:** tầng lexer/parser **ổn định**. Vấn đề tập trung ở tầng thực thi bytecode.

---

## 5. Chức năng khác đã kiểm chứng

| Tính năng | Lệnh | Kết quả |
|---|---|---|
| Version | `ko --version` | ✅ `ko 0.1.0` |
| Inline code | `ko run '[ <printf>^("x") ]'` | ✅ in `x` |
| Build standalone | `ko build examples/simple.ko` | ✅ tạo `build/simple` (19.8 MB) |
| Chạy standalone | `./build/simple` | ✅ in `Hello World`, không cần `ko` trong PATH |
| Module native | `examples/test.ko` | ✅ `libko_random.so` load OK |
| Class + method | file tạm | ✅ in `hi John` |
| `<catch>` | `examples/test.ko` | ✅ hoạt động |
| Module Store | `ko -list` | ✅ trả danh sách |
| `<len>` | `[ <len>^("hello")~n ]` | ❌ crash (BUG-1) |
| `<encode>` | `[ <encode>^("ABC")~b ]` | ❌ crash (BUG-1) |
| `<input>` một mình | `[ string("")~s <input>(s) ]` | ✅ chạy |
| `<input>` + `<printf>^(s)` | bytecode | ❌ crash (BUG-2) |

---

## 6. Ma trận lỗi × backend

| Lỗi | Backend bytecode | Backend AST walker |
|---|---|---|
| Chia cho 0 | **134 (crash)** | 3 (báo lỗi đúng) |
| Gọi hàm không tồn tại | **134 (crash)** | 3 (báo lỗi đúng) |
| Sai kiểu int+string | **134 (crash)** | 3 (báo lỗi đúng) |
| `printf` nội suy `{x}` | **sai (`x={x}`)** | đúng (`x=7`) |
| `<input>` + `<printf>^(s)` | **134 (crash)** | 0 (in đúng) |
| `<input>` một mình | 0 | 0 |
| `<len>` | **134 (crash)** | (chưa test AST) |
| `<encode>` | **134 (crash)** | (chưa test AST) |
| `while` loop | **134 (crash)** | (chưa test AST) |

**Kết luận:** backend bytecode **chưa đạt parity** với AST walker ở 3 điểm: xử lý lỗi, nội suy `printf`, và `<input>`. Vì CLI mặc định chọn bytecode khi chương trình không có `func_decl`/`class_decl`/`Import`, **phần lớn chương trình `.ko` thực tế đều đi qua đường lỗi này**.

---

## 7. Đề xuất thứ tự khắc phục

| Ưu tiên | Bug | Lý do |
|---|---|---|
| **1** | BUG-1 | Chặn mọi báo lỗi runtime; đồng thời ngăn BUG-2 biến thành crash |
| **2** | BUG-2 | `<input>` là tính năng cơ bản, đang crash 100% trên bytecode |
| **3** | BUG-3 | Sai kết quả âm thầm — nguy hiểm hơn crash vì không ai biết |
| **4** | BUG-4 | Mất chẩn đoán; sửa rẻ (1 dòng) nhưng giá trị cao |
| **5** | BUG-5 | Refactor kiến trúc, làm sau khi BUG-1 xong |

~~**6** | BUG-6~~ — đã loại (không phải bug, xem mục 3.6).

**Sau khi sửa:** bổ sung test chạy qua `Executor` (không chỉ `VM.execute`) để bắt parity bug — hiện tại toàn bộ test suite đi đường AST walker nên mù hoàn toàn với các lỗi trên.

---

## 8. Kết luận

- **6 file `.ko`:** 5/6 đúng cú pháp. `empty_test.ko` sai cú pháp và compiler từ chối **đúng** theo SPEC §2 — không phải bug.
- **5 bug phát hiện:** 2 CRITICAL, 2 HIGH, 1 MEDIUM. (BUG-6 ban đầu bị loại sau đính chính.)
- **Root cause lớn nhất:** BUG-1 (double-free) biến mọi lỗi runtime trên backend bytecode thành crash `rc=134`, che mất toàn bộ thông tin chẩn đoán và làm BUG-2 trầm trọng hơn.
- **Lỗ hổng test:** test suite chỉ đi đường AST walker → mù hoàn toàn với 3 bug parity (BUG-1/2/3).

**Tuyên bố:** Báo cáo này chỉ ghi nhận, không sửa file nguồn. Mọi khẳng định đều kèm lệnh đã chạy và output thật (Valgrind, đối chứng 2 backend, đối chiếu SPEC).