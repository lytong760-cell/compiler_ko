# Plan thực thi cho compiler_ko

## 1. Mục tiêu
Khôi phục an toàn và baseline cho `compiler_ko` trong phạm vi đã chọn: sửa 3 CRITICAL, 7 HIGH, hygiene, và khôi phục `zig build`/`zig build test` + smoke test. Các milestone bytecode parity, stdlib, import/loop, native build, REPL, completion và CI/Docker được đánh dấu deferred, không phải phần thực thi của plan này.

## 2. Phạm vi và nguyên tắc
- Phạm vi thực thi: Phase 0 (security/hygiene) + Phase 1 (baseline build/test + smoke).
- Không sửa source trong giai đoạn lập kế hoạch.
- Chỉ coi bằng chứng từ lệnh thực tế là trạng thái đúng; docs cũ có thể sai.
- `ROADMAP.md` chỉ mang tính định hướng; ưu tiên theo `REVIEW.md` và code hiện tại.
- Zig toolchain không có trong sandbox, nên mọi thay đổi Zig phải verify lại khi có toolchain.
- API key: chỉ xoá khỏi log và giữ env `KO_FIRESTORE_API_KEY`; rotation thực hiện ngoài repo.
- Không commit trừ khi người dùng yêu cầu.
- Deferred: bytecode parity, lexer/parser/VM correctness, stdlib, import/loop, native build, REPL, completion, CI/Docker, docs alignment.

## 3. Trạng thái hiện tại đã xác minh
- `REVIEW.md` xác định 3 CRITICAL, 7 HIGH, 6 MEDIUM, 3 LOW.
- `MEMORY.md` ghi `zig build test` từng treo vì ghi stdout vào protocol test runner; đã sửa bằng `VM.setOutputWriter` + `Writer.Discarding`.
- Bytecode backend đã wire vào `src/main.zig`, nhưng class/function vẫn fallback AST-walker.
- `Op.call` encoding đã đồng bộ `(idx << 16) | args.len`.
- Dict literal và `bytes(<expr>)` đã có sửa nhưng chưa verify runtime.
- Method call `$obj.method(args)` đã xử lý `.class_instance`, chưa verify.
- `api_server.py` còn in secret ở dòng 264.
- `Import.java` và `installer.zig` có rủi ro path traversal và Zip Slip.
- Completion zsh/fish chưa verify.

## 4. Thứ tự ưu tiên
1. Bảo mật và hygiene.
2. Baseline build/test và smoke test.
3. Bytecode backend parity và regression tests.
4. Lexer/AST và VM correctness.
5. Builtins/stdlib.
6. Plugin/import và loop optimization.
7. Native build, REPL, completion, CI/Docker.

## 5. Phase 0 — Bảo mật và hygiene (CRITICAL)
### 0.1 Xoá secret khỏi log
- File: `src/api_server.py`, hàm `main()`, dòng 264.
- Sửa: không in `API_KEY`; chỉ in trạng thái `configured` hoặc `not configured`.
- Không thực hiện rotation trong repo; rotation là bước deploy/operations ngoài repo.
- Validate: `python3 -m py_compile src/api_server.py`; grep `API Key:` phải 0.

### 0.2 Ngăn path traversal trong import/register
- Files: `src/Import.java` (`processImport`, `registerScope`), `src/installer.zig` (`registerScope`).
- Sửa: validate alias/lib_name chỉ cho `[A-Za-z0-9_-]`, reject `..`, `/`, `\`.
- Validate: unit/integration test với `../evil`, `foo/bar`, `..`.

### 0.3 Ngăn Zip Slip
- Files: `src/Import.java` (`unzip`), `src/installer.zig` (`unzip`).
- Sửa: dùng API giải nén có kiểm tra path hoặc validate entries trước khi giải nén.
- Validate: test zip chứa `../` entry phải fail và không ghi ngoài thư mục.

### 0.4 Dọn repo hygiene
- Xoá tracked artifacts nếu còn (`zig/`, `.zig-global-cache/`, thư mục tên bắt đầu bằng space).
- Cập nhật `.gitignore` cho `.my_pass/`, cache dirs.
- Validate: `git status` sạch, `git ls-files` không chứa artifacts.

## 6. Phase 1 — Sửa HIGH issues
### 1.1 `listLibraries` không tạo URL với key null
- File: `src/Import.java`, `listLibraries()`.
- Sửa: trả lỗi sớm nếu `API_KEY == null`; không tiếp tục request.
- Validate: test thiếu env trả lỗi rõ ràng.

### 1.2 Loop.cpp context và validation
- File: `src/Loop.cpp`.
- Sửa:
  - `ko_loop_execute_while_loop` truyền đúng `condCtx` cho condition.
  - `recordFor` validate `start <= end` và step > 0; tránh underflow.
- Validate: loop tests và case `start > end`.

### 1.3 Bytecode backend fallback rõ ràng
- Files: `src/compiler.zig`, `src/main.zig`, `src/vm.zig`, `src/bytecode.zig`.
- Mục tiêu: giữ AST-walker fallback cho class/function; không còn `else => {}` âm thầm bỏ statement; thêm test chứng minh fallback.
- Không yêu cầu full parity trong plan này.
- Validate: test chương trình có/không func/class.

### 1.4 Java process handling
- File: `src/Import.java`, các hàm compile.
- Sửa: đọc stream trước `waitFor()` hoặc redirect output; tránh deadlock > pipe buffer.
- Validate: compile module lớn không treo.

### 1.5 CI dead C# steps
- File: `.github/workflows/ci.yml`.
- Sửa: xoá steps `if: matrix.language == 'csharp'` và setup .NET.
- Validate: YAML parse và CI matrix không chứa C#.

### 1.6 Docker CMD
- File: `Dockerfile`.
- Sửa: `CMD ["./ko", "--help"]` hoặc entrypoint hợp lý.
- Validate: `docker build`, `docker run --rm ko` exit 0.

## 7. Phase 2 — Baseline build/test
### 7.1 Xác minh Zig toolchain
- Cài/kiểm tra Zig 0.16.0 theo `build.zig.zon`.
- Validate: `zig version` trả `0.16.0`.

### 7.2 Build sạch
- Chạy `zig build` vào thư mục build sạch.
- Validate: exit 0, binary `zig-out/bin/ko`, shared libs tồn tại.

### 7.3 Test baseline
- Chạy `zig build test < /dev/null`.
- Validate: toàn bộ test pass, không treo.

### 7.4 Smoke test CLI
- Chạy `./zig-out/bin/ko --version` → `ko 0.1.0`.
- Chạy `./zig-out/bin/ko examples/simple.ko` và kiểm tra output.
- Validate: exit 0.

## 8. Deferred phases (ngoài phạm vi A)
Các phase sau không thực thi trong plan này; giữ lại làm backlog:
- Full bytecode parity cho class/function.
- Lexer/AST/VM correctness (token positions, dict, bytes, method access, second input).
- Builtins/stdlib.
- Runtime module loading và import integration.
- Native build, REPL, completion verification.
- Documentation/spec alignment.
- `zig version`
- `zig build`
- `zig build test < /dev/null`
- `python3 -m py_compile src/api_server.py`
- `javac -d /tmp/kojavacheck src/Import.java`
- `g++ -std=c++17 -shared -fPIC src/Loop.cpp -o /tmp/libko_loop.so`
- `docker build -t ko .`
- `docker run --rm ko --version`
- Smoke tests examples.

## 14. Rủi ro và blockers
- Không có Zig toolchain trong sandbox.
- Zsh/fish không có để verify completion.
- Repo đang có thay đổi chưa commit; cần tránh ghi đè.
- Sub-agent song song có thể phá file; nên dùng worktree riêng.

## 15. Open questions
- Có nên implement bytecode parity cho class/function hay giữ AST-walker fallback?
- Có nên bind API server mặc định `127.0.0.1` thay vì `0.0.0.0`?
- Có cần thêm rate limiting/CORS cho API server không?
- Có cần rotate Firestore API key và cập nhật secret manager không?
