# ROADMAP — compiler_ko

## Mục tiêu
Biến `compiler_ko` từ baseline Zig-first polyglot compiler thành compiler `.ko` hoàn chỉnh: lexer/AST sạch, bytecode VM, stdlib, plugin/import, loop optimization, native build, REPL, completion và CI smoke test. Đồng thời chuẩn hóa SPECIFICATION.md làm tài liệu định hướng tương lai (không bắt buộc khớp 100% implementation ngay).

## Trạng thái hiện tại
- `zig build` / `zig build test`: baseline docs ghi xanh, chưa tự verify trong sandbox hiện tại vì thiếu toolchain.
- Bytecode backend còn dead code; `Op.call` encode/decode không tương thích.
- Dict literal, `bytes(<expr>)`, method call args, second `<input>` và method access không ngoặc đang lỗi.
- `Import` và `Loop` chưa tích hợp runtime.
- Completion zsh/fish chưa verify.
- CI có job C# nhưng repo không có `.cs`.
- SPECIFICATION.md đã bổ sung Null/None, Type Introspection, và Region Type Annotations (`@`), nhưng vẫn cần section Future Extensions và Required Source/File Structure.

## Milestone 0 — Baseline & Hygiene
- [ ] #16 Test baseline repair
- [ ] #17 CLI `ko run <file>`
- [ ] #23 Zig version consistency
- [ ] #22 Repo hygiene / drop tracked artifacts
- [ ] Security: rotate leaked Firestore API key, remove from README/SPECIFICATION
- [ ] Remove tracked `.my_pass/auto.bash` force-push loop

## Milestone 1 — Lexer/AST + Bytecode VM
- [ ] #6 Lexer/AST refactor
- [ ] #18 Wire bytecode backend
- [ ] #11 Token positions + multi-error diagnostics
- [ ] #19 Value formatting
- [ ] #20 Method call arguments
- [ ] #21 Second `<input>`
- [ ] #24 Method access without call

## Milestone 2 — Stdlib v1
- [ ] #12 I/O, string, math builtins
- [ ] Make tests assert real output instead of only crash-free

## Milestone 3 — Plugin & Import
- [ ] #9 Plugin loader
- [ ] Java `Import.java` integration
- [ ] Convention paths `libs/`, `~/.ko/plugins/`

## Milestone 4 — Loop Optimization
- [ ] #13 `libko_loop` integration
- [ ] `Loop` keyword dispatch

## Milestone 5 — Native Build
- [ ] #15 `ko build`

## Milestone 6 — REPL & Completion
- [ ] #10 REPL
- [ ] #8 zsh/fish verification

## Milestone 7 — CI & Release
- [ ] #7 Smoke tests
- [ ] Fix/remove C# job
- [ ] Docker build verification

## Milestone 8 — Documentation & Spec Standardization
- [ ] Append SPECIFICATION.md: Future Extensions (concurrency, generics, modules, FFI, tooling, security, testing)
- [ ] Append SPECIFICATION.md: Required Source/File Structure (Zig core, C++/Java tiers, C modules, tests, examples, CI/Docker)
- [ ] Sync SPEC với ROADMAP và các issue đã tạo
- [ ] Đảm bảo spec chỉ định hướng tương lai, không khẳng định đã implement trừ khi code có bằng chứng

## Thứ tự ưu tiên
1. Security & hygiene
2. Documentation & Spec Standardization
3. Test baseline + bytecode wiring
4. Lexer/AST + token positions
5. Stdlib
6. Plugin/import + loop
7. Native build + REPL + completion + CI
