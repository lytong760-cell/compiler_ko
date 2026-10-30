# Plan: Unify value arithmetic behind the Value module

## Goal

Make `src/value.zig` the single source of truth for all binary operations in the `.ko` compiler, eliminating the duplicated arithmetic in `src/vm.zig` (`addValues`, `subValues`, …). Deepen the Value module so bugs concentrate in one place (locality) and both execution paths (AST-walker and bytecode) share one implementation (leverage).

## Context / decisions (from grilling)

- **Scope**: unify *all* binary ops — arithmetic (`+ - * / %`), comparison (`< > <= >=`), equality (`== !=`), and logical (`and`/`or`) — into `Value`. VM keeps only orchestration/wrapping.
- **Source of truth**: `Value` module methods.
- **Predicate methods on Value** return `bool` (like `equals`): `less`, `greater`, `lessOrEqual`, `greaterOrEqual`. VM wraps into `Value{ .booling = ... }`.
- **Overflow**: checked — `@addWithOverflow`/`@subWithOverflow`/`@mulWithOverflow` returning `OverflowError`. Applies to both paths (was only AST path).
- **Type strictness (user decision)**: remove *all* implicit coercion between `int` and `freal`. Mixed-type arithmetic/comparison/equality returns `TypeError`. Apply to AST path too (currently coerces) so both paths are strict and consistent.
- **String ordering**: supported in both paths (Value.less handles `.string`).
- **Logical ops**: keep truthiness via `toBool` (not strict to `booling`), matching current AST behavior.
- **Equality internal**: `Value.equals` becomes strict (no int↔freal coercion).
- **Deletion test**: remove VM helpers; complexity concentrates in `Value`.
- **Tests**: add unit tests for Value binary ops; run `zig build test`.

## Affected files

- `src/value.zig` — edit arithmetic/comparison/equality methods; add new predicate methods.
- `src/vm.zig` — `evaluateBinary` and `binaryOp` delegate to Value; delete helper functions.
- `testing/` — add unit tests for Value ops (new file or extend existing harness).
- (Optional) `GLOSSARY.md` / ADR — record strict-typing decision.

## Implementation steps

### Step 1 — Make `Value` strict and complete

In `src/value.zig`:

1. `add`:
   - Remove `.int => .freal` and `.freal => .int` coercion branches.
   - Keep overflow check for int+int; freal+freal only; string concat; list/tuple concat.
   - int+int overflow → `OverflowError`; mixed types → `TypeError`.

2. `sub`, `mul`:
   - Remove coercion branches; keep overflow checks for int; freal only with freal; else `TypeError`.

3. `div`:
   - Remove coercion; int/int with zero check → `DivideByZero`; freal/freal; else `TypeError`.

4. `rem`:
   - int/int only with zero check; else `TypeError`.

5. `equals`:
   - Remove int↔freal coercion; int==int, freal==freal only; mixed → `TypeError`.

6. Add methods:
   - `less(self, other) !bool`
   - `greater(self, other) !bool`
   - `lessOrEqual(self, other) !bool`
   - `greaterOrEqual(self, other) !bool`
   Each: int/int, freal/freal, string/string (mem.order) comparisons; no coercion; else `TypeError`. Mirror `compareLess`/etc semantics minus coercion.

7. (Optional) Add `logicalAnd`/`logicalOr` returning `Value{.booling}`? Decision: keep in VM using `toBool`. No change to Value. If desired later, add.

### Step 2 — Wire VM to Value

In `src/vm.zig`:

1. `evaluateBinary`:
   - `.add` → `try left.add(right, self.allocator)`
   - `.sub` → `try left.sub(right)`
   - `.mul` → `try left.mul(right)`
   - `.div` → `try left.div(right)`
   - `.rem` → `try left.rem(right)`
   - `.logical_and` → `Value{ .booling = (try left.toBool()) and (try right.toBool()) }` (unchanged)
   - `.logical_or` → `Value{ .booling = (try left.toBool()) or (try right.toBool()) }` (unchanged)
   - `.eq` → `Value{ .booling = try left.equals(right) }`
   - `.neq` → `Value{ .booling = !(try left.equals(right)) }`
   - `.lt` → `Value{ .booling = try left.less(right) }`
   - `.gt` → `Value{ .booling = try left.greater(right) }`
   - `.lte` → `Value{ .booling = try left.lessOrEqual(right) }`
   - `.gte` → `Value{ .booling = try left.greaterOrEqual(right) }`

2. `binaryOp` (bytecode):
   - Replace each `self.xxxValues(...)` with the corresponding Value method call (same as above, wrapping bools).
   - Remove `addValues`, `subValues`, `mulValues`, `divValues`, `remValues`, `andValues`, `orValues`, `eqValues`, `neqValues`, `ltValues`, `gtValues`, `lteValues`, `gteValues`, `compareLess` (if moved), `compareGreater`, `compareLessOrEqual`, `compareGreaterOrEqual`.

3. Delete now-unused private helpers.

### Step 3 — Tests

- Add unit tests in `testing/` (or a new `testing/test_value.zig`) covering:
  - int arithmetic + overflow → `OverflowError`
  - freal arithmetic
  - mixed type → `TypeError`
  - string concat
  - list/tuple concat
  - div by zero → `DivideByZero`
  - rem
  - equals (same/opposite types)
  - less/greater/lessOrEqual/greaterOrEqual for int, freal, string
  - mixed comparison → `TypeError`
- Wire new test file into `build.zig` if needed (check existing test registration).
- Run `zig build test`.

### Step 4 — Verification

- `zig build` (compile).
- `zig build test` (all tests pass).
- Smoke-run existing `.ko` examples to ensure strict typing doesn't break documented behavior; check `testing/` fixtures.

### Step 5 — (Optional) Docs

- Add an ADR under `docs/adr/` recording the strict-typing decision (no int↔freal coercion) so future reviews don't re-suggest coercion.
- Update `GLOSSARY.md` if any term changes.

## Risks / things to check

- Existing tests or `.ko` programs may rely on int↔freal coercion; strictness will surface as `TypeError`. Search codebase/examples for mixed-type expressions before/after.
- Bytecode path currently less capable (no coercion, no string compare); unification *adds* capability; behavior changes for bytecode execution.
- Ownership: `Value.add` allocates strings/lists via allocator; ensure bytecode path passes `self.allocator`.
- `equals` used internally in `value.zig` (tuple/dict) and `vm.zig`; strictness affects dict key comparison (keys must be same type).

## Out of scope

- Candidate 2 (bytecode compiler wire/remove).
- Candidate 3 (installer ports & adapters).
- Candidate 4 (AST/value decoupling).
- Candidate 5 (VM split).

These remain separate deepening opportunities.
HTMLEOF
TS=$(date +%s); cp /tmp/plan_tmp.md /dev/null 2>/dev/null; echo ok