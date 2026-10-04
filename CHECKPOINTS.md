# CHECKPOINTS.md — Trạng thái thực thi hiện tại

Cập nhật ở **mỗi lần thay đổi trạng thái**. Đọc file này **trước khi** sửa code.

---

### LAST KNOWN EXECUTION CHECKPOINT

- **Task State:** `SUCCESS` — baseline xanh, roadmap còn nợ
- **Active Node/Context:** `/workspaces/compiler_ko`, commit `9f2e537e`, nhánh `main`, working tree sạch
- **Volatile Context Diagnostics:**
  ```
  zig build                → exit 0
  zig build test           → 14/14 steps, 208/208 tests passed, exit 0, không leak
  docker build             → exit 0, chạy thật, ./ko --version → ko 0.1.0
  zig-out/lib/             → libko_os.so(9) libko_random.so(4) libko_website.so(7) libko_loop.so(8)
  git ls-files | wc -l     → 64  (từng là 16.255)
  worktree                 → không còn worktree nào đang dùng
  ```
  Lưu ý: `zig build test` **phải** chạy với `< /dev/null`, nếu không có thể treo.
- **Next Execution Phase Vectors:**
  1. Sửa **dict literal** — parser parse entry rồi vứt đi. Cú pháp spec `SPECIFICATION.md:141` là `(1{'a'})~d`; cả hai dạng đều hỏng.
  2. Sửa **`bytes(<expr>)~x`** trong `src/vm.zig` — hiện chỉ khớp `.int`, mọi biểu thức khác cho buffer 0 byte.
  3. **#18 viết lại bytecode backend** — ưu tiên sửa `Op.call` encoding không tương thích trước, vì nó chặn mọi thứ khác.
  4. **#11 thêm vị trí vào Token** — phải làm trước khi refactor parser, nếu không lexer bị viết hai lần.
  5. Xử lý job `csharp` trong CI (repo có 0 file `.cs` nhưng job vẫn gọi `dotnet build`).

---

## Xanh là gì, và không xanh là gì

| Mốc | Trạng thái |
|---|---|
| `zig build` | xanh |
| `zig build test` | xanh, 208/208 |
| `docker build` | xanh |
| Smoke test CLI (`ko run examples/simple.ko`) | xanh |
| Completion `bash` | xanh, `bash -n` OK |
| Completion `zsh` / `fish` | **chưa verify** — thiếu shell trên máy |

---

## Issue đang mở

Đã tạo 23 issue. **Chưa issue nào được đóng** — đóng khi code còn nằm trong working tree là sai, vì issue đóng nhưng code chưa vào lịch sử git.

Đã xử lý xong, chờ commit rồi đóng: #4, #7 (một phần), #16, #17, #19, #20, #22, #23

Còn mở: #6, #8, #9, #10, #11, #12, #13, #15, #18, #21, #24

---

## Cạm bẫy đã gặp — đừng lặp lại

1. **Verify bằng artifact cũ là pass giả.** `javac` fail nhưng thư mục class còn class từ lần trước → lệnh chạy ra kết quả đúng như thuộc code cũ. Luôn build vào thư mục **sạch**.
2. **Ba lần verify gần nhất, 3 lần lỗi là do test của tôi chứ không phải do code.** Truyền `maxIterations=0`, kỳ vọng sai số vòng lặp, đọc `git diff` khi HEAD đã đổi.
3. **`zig build test` dưới test runner cần stdin.** Nếu test có đọc stdin mà không inject, runner sẽ treo.
4. **Agent song song phá việc nhau.** Dùng `git worktree add` cho từng agent dưới `.kilo/worktrees/<tên>`, verify trong worktree rồi mới tích hợp. Xoá worktree ngay khi xong.
5. **Báo cáo của sub-agent không đáng tin nếu không tự chạy lệnh.** Đã gặp: agent tuyên bố xong nhưng code không compile, agent xoá sạch file test, agent tự mâu thuẫn trong chính ví dụ của nó.
6. **`git reset` của agent làm mất hàng nghìn deletion đã staged.** Đã xảy ra hai lần.
