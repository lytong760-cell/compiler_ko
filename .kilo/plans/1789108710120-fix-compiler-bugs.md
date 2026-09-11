# Plan: Fix Critical Bugs in .ko Compiler

## Goal
Fix all critical and high-priority bugs identified in the code review of the .ko compiler, then verify the fixes by building and running the test suite.

## Scope
- Fix 8 critical/high-priority bugs in the Zig compiler core
- Verify by building with `zig build` and running `zig test` on all test files
- Do NOT implement missing features (Import runtime integration, Loop.cpp integration)

## Bugs to Fix

### Bug #1: Token conflict - `%%` vs `pipe_pipe`
**File:** `src/lexer.zig:196-203`
**Issue:** `%%` is mapped to `Token.pipe_pipe`, which conflicts with the `|` comment delimiter
**Fix:** 
- Change `%%` token to a new token type `logical_or` (or reuse `percent` and handle `%%` as two `percent` tokens in parser)
- Update parser to recognize `percent percent` as logical OR

### Bug #6: Parser dead code after `parseSystemTagStmt`
**File:** `src/parser.zig:858-1018`
**Issue:** Code after `else` handling is unreachable because it's outside the if/elif/else chain
**Fix:** Move the remaining tag handlers (`catch`, `return`, `now`, `memory`, `input`, `encode`, default caret/l_paren) into the proper if/elif/else chain before line 858

### Bug #7: Duplicate parsing logic
**File:** `src/parser.zig`
**Issue:** `parseSystemTagStmt` handles `<if>`, `<elif>`, `<else>`, `<catch>`, `<return>`, etc., but `parseStatement` also has separate handlers for these
**Fix:** Remove duplicate handlers from `parseStatement` and rely solely on `parseSystemTagStmt` for system tags

### Bug #13: `Expr` union missing `index_access`
**File:** `src/ast.zig:199-224`
**Issue:** `Expr` union doesn't have `.index_access` variant, but VM uses it in `assignValue` and `evaluateIndexAccess`
**Fix:** Add `.index_access: *IndexAccess` to the `Expr` union

### Bug #15: VM doesn't skip `elif`/`else` after `if` matches
**File:** `src/vm.zig:233-287`
**Issue:** `execute` iterates sequentially through statements, so after an `if` matches, `elif`/`else` blocks still execute
**Fix:** Implement `if/elif/else` chaining logic - when an `if` matches, skip subsequent `elif`/`else` statements

### Bug #17: Class instance dangling pointers
**File:** `src/vm.zig:154-176`
**Issue:** When creating class instances, fields are copied by pointer, not by value. If `ClassDef` is deinit'd, instance has dangling pointers
**Fix:** Deep clone values when copying from ClassDef to instance

### Bug #30: Import statement not implemented in VM
**File:** `src/vm.zig:631-634`
**Issue:** VM raises `NotImplementedError` for Import calls
**Fix:** For now, make it a no-op or print a warning (full implementation requires Loop.cpp and Import.java integration which is out of scope)

### Bug #33: Memory management improvements
**Files:** `src/vm.zig`, `src/value.zig`
**Issue:** Inconsistent memory management patterns
**Fix:** 
- Replace dangerous `unreachable` after catch with proper error propagation
- Fix `ClassInstance.deinit` to not self-destroy
- Ensure all allocations are properly paired with deallocations

## Implementation Order

1. **Bug #13** - Add `index_access` to `Expr` union (prerequisite for other fixes)
2. **Bug #6** - Fix parser dead code (critical for correct parsing)
3. **Bug #7** - Remove duplicate parsing logic
4. **Bug #1** - Fix token conflict for `%%`
5. **Bug #15** - Fix if/elif/else execution logic
6. **Bug #17** - Fix class instance memory management
7. **Bug #30** - Make Import a no-op with warning
8. **Bug #33** - Memory management improvements
9. **Verification** - Build and test

## Verification Steps

1. Run `zig build` to ensure no compile errors
2. Run `zig test src/test_3600.zig`
3. Run `zig test src/test_harness.zig`
4. Run `zig test src/test_lexer_extended.zig`
5. Run `zig test src/test_parser_extended.zig`
6. Run `zig build test` to run all tests
7. Test with a sample .ko program that uses the fixed features

## Risks
- Fixing Bug #6 may reveal additional parser issues in existing tests
- Fixing Bug #13 requires updating multiple files that reference `index_access`
- Bug #1 fix may require changes to both lexer and parser

## Out of Scope
- Implementing full Import runtime integration (requires Loop.cpp and Import.java)
- Implementing Loop.cpp integration into VM
- Adding new language features
- Writing new tests (only fixing existing bugs)
