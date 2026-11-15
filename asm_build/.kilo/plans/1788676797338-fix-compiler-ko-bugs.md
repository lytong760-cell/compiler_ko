# Fix compiler_ko Bugs — Implementation Plan

## Summary
Fix 28 confirmed bugs across `src/` and `test/` in the `compiler_ko` Zig interpreter.
Bugs verified by reading source: memory safety (UB, use-after-free, invalid free),
logic errors (both-branches execute, lost assignments, infinite loops, wrong error types),
memory leaks (string duplication, missing deinit), and broken test suite.

---

## Phase 1 — Fix Memory Safety & UB (P0 — crashes / wrong behavior)

### 1.1 `src/parser.zig` — `<else>` creates uninitialized `Expr`
- **Lines 472, 821**: `try self.allocator.create(ast.Expr)` allocates without initialization.
- **Fix**: Change `ControlFlow.condition` to `?*Expr` in `ast.zig:111`.
- In `parser.zig` set `.condition = null` for `else_stmt`.
- In `vm.zig:220-233` use `if (cf.condition) |cond|` guard.
- In `ast.zig:122` `ControlFlow.deinit` guard `condition` with `if (self.condition) |c| c.deinit();`.

### 1.2 `src/vm.zig` — `assignValue` dict write is lost
- **Lines 368-375**: `d` is captured by value; `@constCast(&d).put(...)` writes to a local copy.
- **Fix**: Remove `.dict => |d|` copy; use the object expression directly:
  ```zig
  .dict => |d_ptr| {
      const d = d_ptr.*;
      // ... use d directly (or better: evaluateIndexAccess returns a pointer/reference)
  }
  ```
  Better: refactor `evaluateIndexAccess` / `evaluateMemberAccess` to return mutable access
  or duplicate the dict, then write back. Minimal patch: evaluate the object again and
  re-fetch from scope, or simply `obj` must be re-evaluated after mutation.

### 1.3 `src/ast.zig` — `ClassInstantiation.deinit` frees arena-owned strings
- **Lines 53-56**: `allocator.free(self.class_name)` and `allocator.free(self.instance_name)`
  free slices borrowed from the arena allocator.
- **Fix**: Do not free these strings in `ClassInstantiation.deinit`. The AST lives in the
  arena and is freed wholesale by `arena.deinit()` in `main.zig:101`.

### 1.4 `src/value.zig` — `Value.deinit` UB on `.tuple` / `.list`
- **Lines 22-24**: `.tuple, .list` always reads `self.tuple`. If the active tag is `.list`,
  reading `.tuple` is UB (just happens to share layout).
- **Fix**: Separate branches:
  ```zig
  .tuple => { for (self.tuple) ... allocator.free(self.tuple); },
  .list => { for (self.list) ... allocator.free(self.list); },
  ```

### 1.5 `src/vm.zig` — `Function.body_ptr` use-after-free
- **Lines 632-634**: `body_ptr` is `*anyopaque`; instance methods hold pointers into the
  `ClassDef` functions. `ClassDef.deinit` (via `vm.deinit` -> `global_scope.functions`) frees
  the functions while instances may still be alive.
- **Fix**: Clone function pointer into instance on class instantiation, or make `ClassDef`
  own the function bodies and never destroy them while instances exist. Easiest: increment
  refcount or move function bodies to a shared arena.

### 1.6 `src/main.zig` — free-then-use on tokenize error
- **Lines 93-98**: `defer allocator.free(tokens)` runs after `tokenize` error; if `tokenize`
  fails, `tokens` is uninitialized.
- **Fix**: Move `defer allocator.free(tokens)` inside the `else` branch after successful
  tokenization, or null-check.

---

## Phase 2 — Fix Logic Bugs (P1 — incorrect semantics)

### 2.1 `src/vm.zig` — catch never matches specific error types
- **Line 65**: `self.raiseError("RuntimeError", @errorName(err))` always sets
  `error_type = "RuntimeError"`, ignoring the actual error type.
- **Fix**: Pass the actual error name to `raiseError`, e.g.
  `self.raiseError("DivideByZero", "DivideByZeroError")` from the call site, and change
  `raiseError` to accept `err_type` and `message`.

### 2.2 `src/vm.zig` — integer overflow on `int(i64max)~x int(x+1)~y`
- **value.zig add/sub/mul/div/rem** do not check overflow.
- **Fix**: Use Zig checked arithmetic (`@addWithOverflow`, etc.) or wrap in `catch` and
  raise `error.OverflowError` with message. Add `overflow` check before each arithmetic op
  and call `self.raiseError("OverflowError", "integer overflow")`.

### 2.3 `src/vm.zig` — `bytes(-1)` casts negative to unsigned
- **Line 99**: `@intCast(i)` when `i < 0` panics.
- **Fix**: Validate `i >= 0` before `@intCast` and raise `TypeError` if negative.

### 2.4 `src/vm.zig` — `for(~i=1&=3)` infinite loop (no default increment)
- **Parser.zig lines 288-335**: `step` is optional and only parsed if `(expr)` follows the
  init. The grammar `~i=1&=3` has no step.
- **VM.zig lines 234-253**: If `cf.step` is null, the loop variable is never incremented.
- **Fix**: Default step to `+1` when `step` is null in the parser (create a literal `1`
  expression), or add a default increment in `vm.zig` when `step` is null.

### 2.5 `src/vm.zig` — `<len>` / `<encode>` / `<memory>` statements calculated then discarded
- **Lines 265-285**: These evaluate their expression but ignore the result (`_ = val`).
  They should produce side effects or be expressions.
- **Fix**: Make `memory_op` (`dete`) free the value; make `memory_op` (`address`) return
  address string; make `encoding_op` return bytes; make `len_op` return length. Remove
  the statement-level parsing for these and only allow them as expressions inside
  `printf` / assignments.

### 2.6 `src/parser.zig` — `bytes(<encode(\ASCII`)>)~buf` parser error
- **Line 732-860**: `parseSystemTagStmt` handles `encode` with `(...)` inside the tag, but
  `parseSystemTagExpr` (line 1365) does not implement `encode(...)` as a tag expression.
- **Fix**: Add `encode` handling in `parseSystemTagExpr` similar to the statement version.

### 2.7 `src/parser.zig` — `<now>(hp + 1)~hp` parser error
- **Root cause**: `<now>` is a statement-level tag. When the parser reads `<now>(...)`,
  the `<` of the next statement is consumed as part of `parseSystemTagExpr` or left in
  the token stream causing a shift.
- **Fix**: Ensure `parseNowStmt` (and other tag-statement parsers) consume exactly the
  intended tokens and do not over-consume. Specifically, `parseNowStmt` already requires
  `>` after the expression; if the source is `<now>(hp + 1)~hp`, after parsing `hp + 1`
  it expects `>` but sees `~`. This is a grammar design issue. Document that `<now>`
  must be followed by `>` in source, or add a dedicated `~hp` target parser.

### 2.8 `src/parser.zig` — Tuple/list and dict literals not parsed
- **Lines 1341-1356**: `{...}` creates an empty dict literal and discards items.
- **Fix**: Store parsed items in the `Literal` struct (add `tuple_items` / `dict_entries`
  or reuse `raw` / extend `Literal`). Create a proper `dict` value in the VM with key-value
  pairs. Also add tuple syntax `(...)` parsing in `parseExpression`.

### 2.9 `src/vm.zig` — both `<if>` and `<else>` bodies execute
- **Root cause**: `parseSystemTagStmt` for `<if>` returns the if-stmt, but if the
  caller/parser does not skip subsequent statements, the `<else>` is also parsed as a
  separate statement.
- **Fix**: Confirm `if/elif/else` are parsed as a single chained `ControlFlow` node or
  that the parser consumes the entire if/elif/else chain before returning.

---

## Phase 3 — Fix Memory Leaks (P1 — OOM / poor performance)

### 3.1 `src/value.zig` — `Value.deinit` missing `.string` branch
- **Lines 19-44**: `.string` falls into `else => {}` and is never freed.
- **Fix**: Add `.string => allocator.free(self.string)`.

### 3.2 `src/vm.zig` — `evaluateLiteral` duplicates string every call
- **Line 411**: `self.allocator.dupe(u8, lit.raw)` allocates a new copy each evaluation.
- **Fix**: Cache literals or use `lit.raw` directly when the source lifetime exceeds the
  value lifetime (arena). Since AST lives in arena, store `lit.raw` directly instead of
  duplicating.

### 3.3 `src/vm.zig` — `evaluateSystemTag` printf path leaks
- **Lines 790-810**: `encode` allocates bytes that are never freed when the value is
  discarded.
- **Fix**: Ensure any allocated string/bytes in system-tag evaluation is either owned by
  the returned `Value` (and later freed by caller) or freed before return.

### 3.4 `src/vm.zig` — redeclaration leaks old value
- **`var_decl` / `assignValue`**: When a variable already exists, `getOrPut` returns the
  existing slot, but the old value is not `deinit`'d before overwriting.
- **Fix**: Call `gop.value_ptr.*.deinit(allocator)` before assigning the new value.

---

## Phase 4 — Fix Test Suite (P2 — validation)

### 4.1 `src/test_lexer_extended.zig` — weak assertions
- **Current**: `expect(tokens.len == 2)` only checks count.
- **Fix**: Assert token types and values, e.g.
  `expect(tokens[0] == .keyword and tokens[0].keyword == .int_kw)`.

### 4.2 `src/test_parser_extended.zig` — swallowed errors
- **Lines 5-21**: `parseSource` catches and prints errors, returning `void`. The test
  passes regardless.
- **Fix**: Change `parseSource` to return `!void` and remove internal `catch` so Zig test
  runner detects failures.

### 4.3 `src/test_harness.zig` — 3600/3600 "success" with 1043 errors
- **Lines 57-59**: `runSource(...) catch { continue; }` silently swallows errors.
- **Fix**: Track failures; at end, `expect(success_count == iterations)` or print a
  failure summary.

### 4.4 `src/test_3600.zig` — memory leaks in tests
- **Lines 24-31**: `runSource` does not `defer arena.deinit()` after `pr.parse()`, and
  `program` is not freed after `execute`.
- **Fix**: Add `defer for (program) |*s| s.deinit();` after parse, and ensure all
  allocations are freed. Re-enable GPA leak detection by running with `--stacktrace`.

---

## Phase 5 — Other Fixes (P2)

### 5.1 `src/vm.zig` — `has_returned` global flag breaks nested calls
- **Lines 11, 627**: `has_returned` / `return_value` are VM-global, not call-stack-local.
- **Fix**: Move `return_value` and `has_returned` into a per-call stack frame (array of
  structs pushed on function call, popped on return).

### 5.2 `src/vm.zig` — overflow check in `Value` arithmetic
- **value.zig `add`, `sub`, `mul`**: Use Zig checked ops (`@addWithOverflow`) and return
  `error.OverflowError`.

### 5.3 `src/lexer.zig` — `next()` returns `!?Token` but never returns `null`
- **main.zig:94**: `orelse Token.eof` is dead code.
- **Fix**: Change `next()` to return `!Token` and simplify callers.

---

## Execution Order
1. Phase 1 (memory safety) — required before anything else, otherwise tests crash.
2. Phase 2 (logic bugs) — makes the interpreter semantically correct.
3. Phase 3 (memory leaks) — fixes test failures and runtime bloat.
4. Phase 4 (test suite) — ensures regressions are caught.
5. Phase 5 (other) — polish.

## Validation
After each phase: `zig build test` must pass with GPA reporting zero leaks.
Manual validation with `.ko` programs from `examples/` and `testing/`.
Run `zig build run -- <example.ko>` to confirm basic execution.
