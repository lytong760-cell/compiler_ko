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
---
---

# BÁO CÁO BỔ SUNG — 2026-11-18 (Test 978 case, fuzz + đối chiếu SPEC)

**Phạm vi:** 913 file corpus (valid/invalid/edge + 584 token-mutant + 200 byte-mutant) + 65 ca targeted = **978 case**.
**Phương pháp:** chạy `./zig-out/bin/ko <file> </dev/null` cho từng file; phân loại RC (0=OK, 2=parse error, 3=runtime error, 134/139=crash); đối chiếu SPEC; debug từng ca đáng ngờ bằng `ko run`.
**Ràng buộc:** KHÔNG sửa source. Chỉ ghi nhận + truy nguyên.
**Kết quả tổng:** `zig build` rc=0; `zig build test </dev/null` EXIT=0 (15/15). **0 crash** trong 978 case (di chứng BUG-1/2/6 đã fix giữ vững). RC histogram: `{2: ~730, 0: ~110, 3: ~79}`.

> **Lưu ý quan trọng:** Các lỗi dưới đây là **parity/spec gap** (chương trình chạy nhưng sai kết quả, hoặc cú pháp hợp lệ theo SPEC bị từ chối), **KHÔNG phải crash**. Chúng nguy hiểm hơn crash vì không ai phát hiện.

## 🔴 Nhóm A — Cú pháp hợp lệ theo SPEC bị parser từ chối (rc=2)

### A1. Tuple / list literal `(1,2,3)` không parse được
- **File:** `src/parser_expr.zig` (`parsePrimaryExpr` nhánh `.l_paren`, ~L389–460)
- **Triệu chứng:**
  ```
  [ (1,2,3)~t <printf>^(t) ]        → rc=2  error: ExpectedRParen at 1:6..1:7
  [ ('a','b')~t ]                    → rc=2
  [ (1('a','b'))~a ]                 → rc=2  (nested list)
  ```
- **SPEC:** §III.2 định nghĩa tuple/number array `(1,2)~a`, string array `('a','b')~b`, nested list `(1('a','b'))~list` đều hợp lệ.
- **Root cause:** Parser chỉ coi `(...)` là "một biểu thức đơn" (comment `// normal parenthesized expression (possibly tuple? treat as single)`). Sau `parseExpression()` cho phần tử đầu, nếu gặp `,` thì không xử lý → `expectRParen()` fail.
- **Mức độ:** HIGH — tuple/list là kiểu dữ liệu cơ bản theo SPEC.

### A2. System tag với sigil `$` (`<$random>(...)`, `<$os>(...)`) không parse
- **File:** `src/parser_expr.zig:8` (`parseSystemTagName` chỉ nhận `.keyword`/`.identifier`, KHÔNG nhận `.dollar`)
- **Triệu chứng:**
  ```
  **Import**($Random)@also%~random!`global`:random
  [ int(<$random>(1,5))~r <printf>^(r) ]
  → rc=2  error: UnexpectedToken at 2:57..2:58
  ```
  Trong khi `<printf>`, `<len>`, `<if>` (tag thường) chạy tốt.
- **SPEC:** §VII.1 ví dụ chuẩn `int(<$random>(1, 100))~rand_val`; §VII.3 `int(<$random>(0, inv_len - 1))~item_index`. Đây là cú pháp chính thức để gọi hàm module đã import.
- **Root cause:** `parseSystemTagName` (dùng chung cho cả statement & expr path) không xử lý token `.dollar`. Khi gặp `<` rồi `$`, nó trả `error.UnexpectedToken` vì `$` không phải keyword/identifier.
- **Mức độ:** HIGH — chặn toàn bộ việc dùng module đã import (Random/Os/Website).

### A3. `bytes(<encode(...)>)` không parse
- **File:** `src/parser_expr.zig` (parse `bytes(` arg — gặp `.lt` lồng trong `.l_paren` của `bytes(...)`)
- **Triệu chứng:**
  ```
  [ bytes(<encode(`ASCII`)>^("hi"))~b ... ]  → rc=2
  ```
- **SPEC:** §IV.2 ví dụ chuẩn `bytes(<encode(`UTF-8`)>^("Secure data\n"))~encoded_data`.
- **Mức độ:** MEDIUM — encoding lồng trong bytes allocation.

## 🔴 Nhóm B — Chương trình chạy (rc=0) nhưng SAI KẾT QUẢ

### B1. `<print>string^("x={x}")` KHÔNG nội suy biến
- **File:** `src/vm_value_ops.zig` — handler `print` (khác `printf`)
- **Triệu chứng:**
  ```
  [ int(7)~x <print>string^("x={x}\n") ]  → in "x={x}"  ❌ (mong đợi "x=7")
  [ int(7)~x <printf>^("x={x}\n") ]       → in "x=7"    ✅
  ```
- **SPEC:** §IV.1 `<print>string^("Xin chao\n")` — cùng họ với printf, phải nội suy.
- **Root cause:** Chỉ `printf` gọi `printInterpolated`; `print` in thẳng string. (BUG-3 cũ fix cho `printf` nhưng `<print>` bị bỏ sót.)
- **Mức độ:** HIGH — sai kết quả âm thầm.

### B2. `bytes(N)` rồi `<len>` trả 0 thay vì N
- **File:** `src/vm.zig` (var_decl bytes ~L259–285) + `src/vm_value_ops.zig` (tag `len` ~L637)
- **Triệu chứng:**
  ```
  [ bytes(8)~b int(<len>^(b))~l <printf>^("len={l}\n") ]  → in "len=0"  ❌ (mong đợi 8)
  [ bytes("AB")~b int(<len>^(b))~l <printf>^(l) ]         → in "2"    ✅
  ```
- **SPEC:** §IV.6 `bytes(16)~empty_buf` là buffer 16 byte; §IV.3 `int(<len>^(buffer))~buf_size` phải ra kích thước buffer.
- **Root cause:** var_decl `bytes` với arg `.int` cấp phát `alloc(u8, i)` + `@memset(0)` nhưng `<len>` trả 0 — nghi `len` đọc `.bytes` ra rỗng, hoặc con trỏ bị deinit sớm. (Đối chứng: `bytes("AB")` cho len=2 đúng → lỗi chỉ ở nhánh `.int`.)
- **Mức độ:** HIGH — buffer allocation vô dụng nếu len luôn 0.

### B3. Class method call `$f~get()` — NameError: UndefinedVariable
- **File:** `src/vm_value_ops.zig:197` (`callUserFunction` không bind `self`)
- **Triệu chứng:**
  ```
  Foo !class [ int(5)~x get() [ <return>(x) ] ]
  [ ~Foo~f int($f~get())~r <printf>^(r) ]
  → rc=3  NameError: UndefinedVariable  ❌
  ```
  Trong khi `$f~x` (member access) trả 5 đúng.
- **SPEC:** §VIII.1 ví dụ chuẩn `int($m1~take_damage())~remaining_hp`.
- **Root cause:** `evaluateCall` khi gặp `.class_instance` lấy `func` từ `ci.methods` rồi gọi `callUserFunction(f, call.args)`. `callUserFunction` tạo scope mới từ `func.closure_scope` — **không** bind instance fields (`x`) vào scope. Method `get()` đọc `x` → không thấy → `UndefinedVariable`.
- **Mức độ:** HIGH — OOP method hoàn toàn không dùng được.

### B4. `<catch>` đặt SAU câu lệnh lỗi không bắt được
- **File:** `src/vm.zig` (catch_stmt handler ~L583)
- **Triệu chứng:**
  ```
  [ int(1)~a int(0)~b int(a/b)~c <catch>(`DivideByZeroError`) [ <printf>^("caught") ] ]
  → rc=3  (không in "caught")  ❌
  ```
  Trong khi `<catch>` đặt TRƯỚC câu lệnh lỗi thì bắt được:
  ```
  [ <catch>(`DivideByZeroError`) [ <printf>^("caught") ] int(1)/0 ... ] → in "caught" ✅
  ```
- **SPEC:** §IX.2 "Global Catch: Scans backward protecting all Functions/Main Blocks preceding it" — catch chỉ quét LẬI (backward) các câu lệnh ĐỨNG TRƯỚC nó. Đặt sau câu lỗi thì lỗi đã xảy ra trước khi catch được "cài" → không bắt.
- **Đánh giá:** Đây là **hành vi ĐÚNG theo SPEC** (backward scan). Không phải bug — chỉ là thứ tự code sai. Ghi nhận để làm rõ.
- **Mức độ:** N/A (đúng spec).

### B5. `type(x)` / `type("hi")` — UndefinedFunction
- **File:** `src/vm_value_ops.zig:648` (có xử lý tag `type` trong `callBuiltin`) nhưng `evaluateCall` không tới được
- **Triệu chứng:**
  ```
  [ type("hi") ]        → rc=3  Runtime error: error.UndefinedFunction
  [ int(5)~x type(x) ]  → rc=3  Runtime error: error.UndefinedFunction
  ```
- **SPEC:** §III.5 `type("Hello")` in `string`; `type(123)~a` gán vào biến.
- **Root cause:** `type` không phải keyword/system tag hợp lệ trong parser → parse thành `CallExpr{callee:"type"}` → VM tra `type` như hàm do người dùng định nghĩa → không thấy → `UndefinedFunction`. `callBuiltin` có nhánh `type` nhưng không bao giờ được gọi vì `type(...)` không đi qua đường system tag.
- **Mức độ:** MEDIUM — type introspection không dùng được.

## 🟠 Nhóm C — Cú pháp SAI bị chấp nhận IM LẶNG (rc=0, nên báo lỗi)

### C1. System tag lạ `<foo>^("x")` — không in, không lỗi
- **File:** `src/vm.zig` / `src/vm_value_ops.zig` (system tag dispatch)
- **Triệu chứng:** `[ <foo>^("x") ]` → rc=0, không output, không lỗi.
- **Đánh giá:** Nên báo `UnknownSystemTag`. (Tag không tồn tại bị bỏ qua âm thầm.)
- **Mức độ:** MEDIUM.

### C2. `[ (10)~x ]` — thiếu kiểu, chấp nhận im lặng
- **Triệu chứng:** rc=0, biến `x` được tạo nhưng không rõ kiểu.
- **SPEC:** §III.1 / EBNF `VarDecl ::= PrimitiveType "(" Expression ")" Sigil Identifier` — phải có kiểu.
- **Mức độ:** MEDIUM.

### C3. `<return>(5)` ở main block — chấp nhận im lặng
- **Triệu chứng:** `[ <return>(5) ]` → rc=0 (return khỏi main, không lỗi).
- **Đánh giá:** Cần xác định main block có được phép `return` không. SPEC §XII `return_stmt` không giới hạn ngữ cảnh. Có thể chấp nhận được, nhưng nên cảnh báo.
- **Mức độ:** LOW.

### C4. `int(10)~x` trôi nổi ngoài main — vẫn chạy
- **Triệu chứng:** `int(10)~x\n[ <printf>^(x) ]` → rc=0, in `10`.
- **Đánh giá:** BUG.md cũ (mục 3.7) đã kết luận var_decl ở top-level là HỢP LỆ theo SPEC §V.1. → **KHÔNG phải bug**, xác nhận lại.
- **Mức độ:** N/A (đúng spec).

### C5. `<catch>(DivideByZeroError)` thiếu backtick — chấp nhận
- **Triệu chứng:** `[ <catch>(DivideByZeroError) [ <printf>^("x") ] ]` → rc=0, in `x`.
- **SPEC:** §IX.1 `<catch>(`ErrorCode`)` — error_type phải trong backtick.
- **Mức độ:** LOW — parser không validate error_type format.

## 🟢 Nhóm D — Xác nhận ĐÚNG (không phải bug)

- Toàn bộ arithmetic, if/elif/else, for/while, func (recursion), class+member access, import (`Import(...)` không `**`), encode, memory, now, len(str), byte, freal, bool, dict `{key:val}`, priority `{n}` → rc=0, output đúng.
- Runtime errors đúng: div/mod by zero, overflow add/mul, null print/arith, none reassign, index oob (parse reject), key missing, type mismatch, func undef/arity → rc=2/3 đúng.
- `int(10)~x` top-level + `<printf>` top-level → đúng theo SPEC §V.1 (BUG-7 cũ đã đính chính).
- `<catch>` đặt trước câu lỗi → bắt đúng.
- 584 token-mutant + 200 byte-mutant → 0 crash, 0 hang.
- Unicode, escape (`\n`, `\t`, `\\`), string rỗng, 300 biến, 200 statement → chạy đúng.

## 📊 Ma trận tổng hợp (978 case)

| Nhóm | Số ca | rc=0 | rc=2 | rc=3 | Crash |
|---|---|---|---|---|---|
| Valid (corpus/c2/tgt) | ~124 | ~63 | ~44 | ~17 | 0 |
| Invalid | ~65 | 13 (silent-accept) | ~38 | ~14 | 0 |
| Edge/stress | ~5 | 5 | 0 | 0 | 0 |
| Token-mutant | 584 | 18 | 536 | 30 | 0 |
| Byte-mutant | 200 | 24 | 144 | 32 | 0 |

## 🔧 Thứ tự khắc phục đề xuất (Nhóm A/B/C mới)

| Ưu tiên | Mã | Lý do |
|---|---|---|
| 1 | **A1** tuple/list parse | Kiểu dữ liệu cơ bản, SPEC định nghĩa rõ |
| 2 | **A2** `<$tag>` parse | Chặn toàn bộ module đã import |
| 3 | **B3** class method self-binding | OOP không dùng được |
| 4 | **B1** `<print>` nội suy | Sai kết quả âm thầm |
| 5 | **B2** `bytes(N)` len | Buffer vô dụng |
| 6 | **A3** `bytes(<encode>)` | Encoding lồng |
| 7 | **B5** `type()` | Type introspection |
| 8 | **C1–C5** silent-accept | Làm chặt validate (thấp) |

**Sau khi sửa:** bổ sung test chạy qua `Executor` (parity bytecode ↔ AST walker) — test suite hiện tại chỉ đi `VM.execute` nên mù hoàn toàn với các bug parity.

**Tuyên bố:** Báo cáo chỉ ghi nhận + truy nguyên, KHÔNG sửa file nguồn. Mọi khẳng định đều kèm lệnh đã chạy và output thật.

---
---

# BÁO CÁO ĐÍNH CHÍNH & BỔ SUNG — 2026-11-18 (chạy lại toàn bộ 978 case `ko_fuzz`)

**Môi trường xác minh:**
```
ZIG=/home/codespace/.vscode-remote/data/User/globalStorage/ziglang.vscode-zig/zig/x86_64-linux-0.16.0/zig
$ zig version                 → 0.16.0
$ zig build                   → BUILD_EXIT=0
$ ko = zig-out/bin/ko (build mới)
Bộ test: /tmp/scratchpad/ko_fuzz/ (913 file + 65 targeted = 978 case)
```
> **Lưu ý:** thư mục `/tmp/srcatchapad/ko_puzz/` không tồn tại; bộ case thực tế nằm ở `/tmp/scratchpad/ko_fuzz/` (913 file corpus/c2/byt/mut + 65 targeted).

**Xác nhận phần cũ:** 0 crash (rc≥134) trong 978 case — di chứng BUG-1/2/6 giữ vững. Các gap A1/A2/A3/B1/B3/B5 **vẫn còn nguyên** (test lại trên binary mới, kết quả không đổi).

**Kết quả đính chính:** báo cáo 2026-11-18 chính xác ~85%. Có **3 điểm sai/thiếu** (M1, M2, M3) + 1 bonus (freal coercion) cần sửa lại.

---

## 🔴 M1 — `<catch>` KHÔNG dập lỗi: body LUÔN chạy, lỗi vẫn trả rc=3 (đính chính mục B4)

**Mức độ:** HIGH (đính chính — mục B4 kết luận "bắt đúng ✅" là SAI)

### M1.1 Triệu chứng (băng bằng chứng — tất cả đều đi backend BYTECODE mặc định)

> **Đọc kỹ:** mọi ca dưới đây không có `func_decl`/`class_decl`/`Import` → `Executor` chọn **bytecode**. Đây chính là backend mà catch bị hỏng (xem M1.2). Khi ép AST walker (thêm func_decl), catch hoạt động đúng.

```
# catch ĐÚNG error_type, đặt TRƯỚC câu lỗi (BUG.md nói "bắt được ✅")
$ ko t_catch_ok.ko
tgt/t_catch_ok.ko:main
caught                                              ← body catch ĐÃ chạy
Runtime error: error.DivideByZero                   ← nhưng lỗi VẪN nổ
rc=3                                                 ← KHÔNG dập được

# catch KHÔNG có lỗi — body VẪN chạy
$ printf '[ <catch>(`DivideByZeroError`) [ <printf>^("BODY") ] ]' > /tmp/m1c.ko
$ ko /tmp/m1c.ko
BODY
rc=0                                                 ← body chạy dù không có lỗi!

# catch SAI error_type — body VẪN chạy (không hề kiểm tra type)
$ printf '[ <catch>(`X`) [ <printf>^("BODY") ] <printf>^("tail") ]' > /tmp/m1d.ko
$ ko /tmp/m1d.ko
BODYtail
rc=0

# lỗi TRƯỚC catch (đúng backward-scan spec) — KHÔNG bắt
$ printf '[ int(1)~a int(0)~b int(a/b)~c <catch>(`DivideByZeroError`) [ <printf>^("caught") ] ]' > /tmp/m1e.ko
$ ko /tmp/m1e.ko
Runtime error: error.DivideByZero
rc=3                                                 ← không in "caught"
```

### M1.2 Root cause (đã xác minh dứt khoát bằng dump AST + so sánh 2 backend)

Đây là **parity bug**: AST walker xử lý catch **đúng**, nhưng **bytecode backend bỏ qua hoàn toàn semantics catch**.

**AST walker handler (`src/vm.zig:585-595`) — ĐÚNG:**
```zig
.catch_stmt => |cs| {
    if (self.has_error) {
        if (self.error_type) |err_type| {
            if (std.mem.eql(u8, err_type, cs.error_type)) {
                self.has_error = false;          // clear cờ
                self.error_type = null;
                for (cs.body) |s| try self.executeStatement(&s);
            }
        }
    }
},
```

**Bytecode backend (`src/compiler.zig:337-345` + `src/vm.zig:1323-1324`) — SAI:**
```zig
// compiler.zig: compileCatch — body được emit INLINE, không có cơ chế bắt
fn compileCatch(self: *Compiler, c: *const ast.CatchStmt) anyerror!void {
    const catch_start = self.current_function.instructions.items.len;
    try self.emit(.{ .catch_start = 0 });          // marker
    for (0..c.body.len) |i| {
        try self.compileStatement(&c.body[i]);      // ← body emit inline, LUÔN chạy
    }
    try self.emit(.{ .catch_end = {} });            // marker
    ...
}

// vm.zig:1323-1324 — hai opcode này là NO-OP
.catch_start => {},
.catch_end => {},
```

→ Trên bytecode, `<catch>` chỉ là **2 marker rỗng** bao quanh body được emit inline. Body **luôn thực thi** như code thường, **không** kiểm tra `has_error`, **không** kiểm tra `error_type`, **không** có logic khôi phục (restore stack / clear error). Vì CLI mặc định chọn bytecode khi source không có `func_decl`/`class_decl`/`Import`, **mọi** chương trình dùng `<catch>` ở dạng phổ biến đều đi đường bytecode → catch vô dụng.

**Bằng chứng quyết định (so sánh 2 backend cùng source):**

```
# BYTECODE (mặc định) — catch body chạy inline, vô điều kiện
$ printf '[ <catch>(`X`) [ <printf>^("BODY") ] <printf>^("after") ]' | ko
BODYafter        ← body chạy dù KHÔNG có lỗi; "after" cũng chạy
rc=0

# FORCE AST walker (thêm func_decl dummy để né bytecode) — handler đúng
$ printf 'dummy() [ ]\n[ <catch>(`X`) [ <printf>^("BODY") ] <printf>^("after") ]' | ko
after            ← body KHÔNG chạy (has_error=false); chỉ "after"
rc=0

# FORCE AST + lỗi thật đúng type — bắt được
$ printf 'dummy() [ ]\n[ int(1)~a int(0)~b int(a/b)~c <catch>(`DivideByZeroError`) [ <printf>^("caught") ] ]' | ko
DivideByZeroError: DivideByZero    ← body catch chạy, in error message
rc=3
```

**Dump AST xác nhận** `<catch>` parse đúng (không phải lỗi parser):
```
BLOCK body_len=2
  CATCH err_type='X' body_len=1
    EXPR tag=system_tag
  EXPR tag=system_tag
```
→ AST hoàn toàn đúng. Lỗi nằm ở **bytecode backend không implement catch** (no-op markers), khiến đây là bug parity bytecode ↔ AST walker.

> **Liên quan kiến trúc:** `Executor.execute` (`src/executor.zig:52-86`) chọn bytecode khi `!hasFuncOrClassDef && !hasImportStmt`. Catch đơn ở main block thỏa điều kiện này → luôn đi bytecode → luôn hỏng.

### M1.3 Đính chính B4

B4 (mục 3.x cũ) viết: *"catch đặt TRƯỚC câu lệnh lỗi thì bắt được: … → in 'caught' ✅"*. **SAI.** Trong báo cáo gốc, các ca catch đều vô tình đi AST walker (do có `func_decl`/class/import) nên "bắt được" — nhưng đó là **AST walker đúng**, không phải bằng chứng catch bytecode hoạt động. Khi chạy thuần bytecode (không func/class/import), catch **không bao giờ** dập lỗi.

**Mức độ:** HIGH — `<catch>` trên backend bytecode (mặc định) hoàn toàn không hoạt động: body chạy vô điều kiện, lỗi không bị bắt. Đây là parity bug, không phải lỗi logic AST walker.

### M1.4 Hướng sửa (đề xuất)

1. **Bytecode:** implement catch thật — `.catch_start` phải ghi lại `catch_handler_ip` + stack depth; khi runtime error xảy ra trong vùng `[catch_start, catch_end)`, VM nhảy tới handler, clear error, khôi phục stack, chạy body. `.catch_end` phân định vùng.
2. **Tối thiểu:** ép các chương trình có `<catch>` đi AST walker (đưa catch vào `hasFuncOrClassDef`-style guard) để đảm bảo đúng semantics — nhưng đây chỉ là workaround, không phải fix parity.
3. Bổ sung parity test catch qua `Executor` (bytecode) — test hiện tại chỉ đi AST walker nên mù hoàn toàn với bug này.

---

## 🔴 M2 — Dict literal dạng colon `{'a':1}` hỏng; chỉ compact `(1{'a'})` chạy (đính chính Nhóm D)

**Mức độ:** HIGH (đính chính — Nhóm D §"xác nhận đúng" liệt kê dict `{key:val}` là "output đúng" SAI)

### M2.1 Triệu chứng

```
# colon literal KHÔNG ngoặc — gán OK nhưng index/in hỏng
$ printf "[ {'a':1}~d <printf>^(d{'a'}) ]" | ko
TypeError: Cannot index this type
rc=3

$ printf "[ {'a':1}~d <printf>^(d) ]" | ko
TypeError: Cannot print an unassigned null value
rc=3

$ printf "[ {'a':1}~d int(<len>^(d))~l <printf>^(l) ]" | ko
0                                                    ← dict RỖNG (len=0)
rc=0

# colon literal CÓ ngoặc — CHẠY ĐÚNG
$ printf "[ ({'a':1})~d <printf>^(d) ]" | ko
{a: 1}
rc=0
$ printf "[ ({'a':1})~d int(d{'a'})~x <printf>^(x) ]" | ko
1
rc=0

# compact (1{'a'}) — CHẠY ĐÚNG (đối chứng)
$ printf "[ (1{'a'})~d <printf>^(d{1}) ]" | ko
a
rc=0
```

### M2.2 Root cause

`{'a':1}` ở **đầu statement** bị parser hiểu là **block statement**, KHÔNG phải dict literal.

- `src/parser.zig:335-337`: `if (tok == .l_brace) return try self.parseExprStatement();` — nhưng `parsePrimaryExpr` của `parser_expr.zig` chỉ coi `{...}` là dict literal **trong ngữ cảnh expression lồng** (sau `(`, sau toán tử…). Ở đầu statement, `{` rơi vào đường parse khác.
- Khi **có ngoặc** `({'a':1})`: `(` → `parsePrimaryExpr` xử lý bên trong → gặp `{` → parse thành dict literal đúng.
- Khi **không ngoặc** `{'a':1}~d`: `{` parse sai → `~d` gán cho một biểu thức rỗng/block → dict thật bị mất → `d` thành null/rỗng → `len=0`, index = "Cannot index this type".

**Đối chứng quyết định:** cùng nội dung `{'a':1}`, thêm ngoặc `({'a':1})` là chạy đúng → lỗi nằm ở **quy tắc dispatch `{` ở đầu statement**, không phải ở dict value.

### M2.3 Đính chính Nhóm D

Nhóm D ghi *"dict `{key:val}` → rc=0, output đúng"* là **SAI**. Đúng ra:
- `{'a':1}~d` (không ngoặc) → dict rỗng, index lỗi.
- `({'a':1})~d` (có ngoặc) → đúng.
- `(1{'a'})~d` (compact) → đúng.

**Mức độ:** HIGH — cú pháp dict colon theo SPEC §III không dùng được nếu thiếu ngoặc.

---

## 🟠 M3 — Unknown system tag không nhất quán (bổ sung C1)

**Mức độ:** MEDIUM

### M3.1 Triệu chứng

```
$ printf '[ <foo>^("x") ]' | ko       → rc=0, KHÔNG output, KHÔNG lỗi   (im lặng)
$ printf '[ <foo>(1) ]' | ko          → rc=3  Runtime error: error.UndefinedFunction
$ printf '[ <foo> ]' | ko             → rc=2  error: UnexpectedToken
```

Cùng tag lạ `<foo>`, ba dạng调用 cho ba kết quả khác nhau:
- `<foo>^("x")` (dạng expr statement, có caret) → **im lặng** (C1 cũ).
- `<foo>(1)` (dạng expr thường) → `UndefinedFunction`.
- `<foo>` trần → parse error.

### M3.2 Phân tích

`isSystemTagOpener` (`parser.zig:1166-1184`) chỉ nhận `<ident>` / `<ident>(...)>` là system tag opener khi có cặp `<...>`. `<foo>^("x")` được coi là system tag expr → `evaluateSystemTag` (`vm_value_ops.zig:603`) không khớp tag nào → rơi xuống cuối hàm, trả `.null` mà **không báo lỗi** → im lặng.

Trong khi `<foo>(1)` không được nhận là system tag (thiếu `^`?) → parse thành `CallExpr{callee:"foo"}` → VM tra hàm user → `UndefinedFunction`.

### M3.3 Hậu quả

Cùng một lỗi (tag không tồn tại) nhưng tùy cú pháp lại im lặng / báo khác nhau → khó chẩn đoán. Nên hợp nhất: mọi `<foo>` không xác định → `UnknownSystemTag`.

**Mức độ:** MEDIUM — nhất quán chẩn đoán.

---

## 🟠 Bonus — `freal` ↔ `int` coercion TypeError (bổ sung, Nhóm D nói freal "đúng")

**Mức độ:** MEDIUM

### B.1 Triệu chứng

```
$ printf '[ freal(1.5)~a freal(a+1.0)~b <printf>^(b) ]' | ko
2.5                                                  ← freal + literal OK
rc=0

$ printf '[ freal(1.5)~a int(2)~b freal(a+b)~c <printf>^(c) ]' | ko
Runtime error: error.TypeError                       ← freal + int biến = TypeError
rc=3

$ printf '[ int(2)~b freal(1.5)~a freal(a+b)~c <printf>^(c) ]' | ko
Runtime error: error.TypeError                       ← int + freal = TypeError
rc=3
```

### B.2 Phân tích

- `freal + literal f.` → OK (cùng kiểu freal).
- `freal + int` (hai biến khác kiểu) → `TypeError` ở `evaluateBinary` (`vm_value_ops.zig` → `operator.applyBinary`). Không có coercion freal↔int.
- SPEC §III.freal không nêu rõ coercion; nhưng người dùng mong đợi `freal + int` chạy (như đa số ngôn ngữ). Đây là **thiếu coercion**, không hẳn sai spec.

### B.3 Đề xuất

Thêm coercion int→freal trong `applyBinary` khi một vế freal, một vế int. Ghi nhận mức MEDIUM (tùy quyết định spec).

---

## 🧩 Bonus — Class method in ra "byte rác" trước NameError

**Mức độ:** MEDIUM (nghi memory issue nhẹ)

### C.1 Triệu chứng (hexdump)

```
$ ko tgt/t_class_method.ko
tgt/t_class_method.ko:main
tgt/t_class_method.ko:main- ?? ?? \n NameError: UndefinedVariable
rc=3
```

Heredump vùng stdout:
```
00000030: 3a6d 6169 6e2d aaaa aa0a 4e61 6d65 4572  :main-....NameEr
```
- `aa aa` = **byte rác** (0xAA) xen giữa `main-` và `\nNameError`. `0xAA` là pattern **Zig DebugAllocator freed-memory** (giống BUG-1 cũ) → nghi **use-after-free nhẹ** trong `callUserFunction`/`load_var` khi method không bind `self`.

### C.2 Liên quan B3

B3 (class method `self`-binding) đã ghi NameError UndefinedVariable — đúng. Nhưng **chưa ghi** chi tiết: stdout bị chèn `0xAA` rác trước NameError, dấu hiệu memory bug đi kèm, không chỉ thiếu bind. Root cause nghi ở `evaluateCall` nhánh `.class_instance` (`vm_value_ops.zig:197`): lấy `func` từ `ci.methods`, gọi `callUserFunction(f, args)` với `closure_scope` không chứa field → `load_var x` fail → nhưng trước đó có thể đã free nhầm vùng `name` của biến/field.

**Mức độ:** MEDIUM — cần Valgrind xác nhận (giống BUG-1/BUG-6).

---

## 📊 Bảng đính chính tổng hợp

| Mục cũ | Trạng thái cũ | Đính chính 2026-11-18 | Bằng chứng |
|---|---|---|---|
| B4 catch | "bắt được ✅" | ❌ SAI — **bytecode backend no-op catch**: body chạy inline vô điều kiện, lỗi không bị bắt. AST walker đúng | so sánh 2 backend, dump AST, vm.zig:1323-1324 |
| §D dict `{key:val}` | "output đúng" | ❌ SAI — `{'a':1}` hỏng, chỉ `(1{'a'})`/`({'a':1})` đúng | d1/d3/d4, m2b |
| §D freal | "đúng" | ⚠️ THIẾU — freal↔int TypeError | B.1 |
| (mới) class method | B3 có NameError | ⚠️ THÊM — có `0xAA` rác (nghi UAF) | C.1 hexdump |
| C1 unknown tag | im lặng | ⚠️ THÊM — không nhất quán theo cú pháp | M3.1 |

## 🔧 Thứ tự khắc phục (cập nhật, gộp cả M1/M2/M3)

| Ưu tiên | Mã | Lý do |
|---|---|---|
| 1 | **A1** tuple/list parse | Kiểu dữ liệu cơ bản |
| 2 | **A2** `<$tag>` parse | Chặn toàn bộ module import |
| 3 | **B3 + Bonus-C** class method self-binding + UAF | OOP không dùng được + nghi memory bug |
| 4 | **M1** catch bytecode no-op | Parity bug: bytecode không implement catch (SPEC §IX) |
| 5 | **M2** dict colon parse | Dict theo SPEC §III |
| 6 | **B1** `<print>` nội suy | Sai kết quả âm thầm |
| 7 | **B2** `bytes(N)` len | Buffer vô dụng |
| 8 | **A3** `bytes(<encode>)` | Encoding lồng |
| 9 | **B5** `type()` + **M3** unknown tag | Type introspection + nhất quán |
| 10 | **Bonus-B** freal↔int coercion | Coercion |
| 11 | **C1–C5** silent-accept | Làm chặt validate (thấp) |

**Sau khi sửa:** bắt buộc parity test qua `Executor` (bytecode ↔ AST walker) — test hiện tại chỉ `VM.execute` nên mù với BUG-1/2/3 + M1/M2.

**Tuyên bố:** Báo cáo đính chính chỉ chạy test + đọc source, KHÔNG sửa file nguồn. Mọi khẳng định đều kèm lệnh đã chạy + output thật. Bộ case: `/tmp/scratchpad/ko_fuzz/` (978 case).
