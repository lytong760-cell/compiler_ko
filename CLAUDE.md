# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Summary

`compiler_ko` implements the `.ko` language — a multi-paradigm language (imperative, OO, low-level memory, upward exception handling) — with a Zig-based compiler, bytecode VM, C++/Java/Python native subsystems, and a module store package manager. Target Zig version: **0.16.0** (enforced via `build.zig.zon`).

## Common Commands

```bash
# Build
zig build

# Run a .ko file
./zig-out/bin/ko <file.ko>
./zig-out/bin/ko run <file.ko>
./zig-out/bin/ko run '<inline .ko code>'

# Test (close stdin to prevent hangs)
zig build test < /dev/null

# Run a single test suite
zig build test < /dev/null  # all suites (see testing/test_harness.zig)
zig build test 2>&1 | grep "test_harness"  # filter output

# REPL
./zig-out/bin/ko repl

# Standalone binary build
./zig-out/bin/ko build <file.ko>   # produces build/<name>

# Local module store API server
python3 src/api_server.py --port 8080 --data-dir ./module_store_data

# CLI help
./zig-out/bin/ko --help
```

### Key Environment Notes

- Zig 0.16.0 is required. If `zig` is not in PATH, use the full path or install via the Dockerfile approach.
- `zig build test` writes to stdout via the test runner protocol; always redirect stdin from `/dev/null` to avoid deadlocks.
- Shared libraries (`libko_os.so`, `libko_random.so`, `libko_website.so`, `libko_loop.so`) must be built before module tests run. `zig build test` handles this automatically.

## Architecture

### Hybrid Execution Target Engine

`.ko` source goes through a single frontend pipeline, then dispatches to one of two backends via the `Executor`:

```
Source (.ko) → Lexer → Parser → AST → Executor
                                          ├── bytecode backend (compiler.zig → VM.executeChunk)
                                          └── AST-walker backend (VM.execute)
```

The `Executor` (`src/executor.zig`) selects bytecode only when the program has no `func_decl`, `class_decl`, or `import` statements (checked via `hasFuncOrClassDef` and `hasImportStmt`). All other programs use the AST walker. Both paths produce identical output for supported programs.

### Source Files — Role Map

| File | Role |
|------|------|
| `src/main.zig` | CLI entry point, argument dispatch, REPL, standalone build, `executeCode` |
| `src/lexer.zig` | Tokenizer: `Lexer.init` + `tokenize` → `Token[]` + `Position[]` |
| `src/parser.zig` | Statement-level parser: `Parser.init` + `parse()` → `[]Statement` |
| `src/parser_expr.zig` | Expression parser (precedence climbing, called from parser.zig) |
| `src/ast.zig` | AST node definitions: `Statement`, `Expr`, `VarDecl`, `FuncDecl`, `ClassDecl`, `ControlFlow`, etc. |
| `src/compiler.zig` | AST → bytecode compiler: `Compiler.compileProgram` |
| `src/bytecode.zig` | Opcode enum `Op`, `Instruction` union, `Chunk`, `Function` |
| `src/executor.zig` | Backend dispatcher: bytecode vs AST-walker |
| `src/vm.zig` | VM core: `VM.init`, `executeChunk`, `runFunction`, `dispatchLoop` |
| `src/vm_value_ops.zig` | Expression evaluation, function calls, imports, system tags, I/O |
| `src/value.zig` | Runtime values: `Value` union, `Scope`, `Function`, `ClassDef`, operators |
| `src/operator.zig` | Binary/unary operator dispatch, opcode mapping |
| `src/builtins.zig` | Built-in registration (currently a stub) |
| `src/installer.zig` | Package manager + Firestore/REST API client |
| `src/Loop.cpp` | C++ loop optimization engine → `libko_loop.so` |
| `src/Import.java` | Java module import subsystem (reference implementation) |
| `src/api_server.py` | Local Module Store REST API server (Firestore-compatible) |
| `src/module/` | Built-in C shared library modules: `Os`, `Random`, `Website` |

### Execution Flow

1. **Lexer** (`src/lexer.zig`): `Lexer.init(source)` → `tokenize(allocator)` returns `{tokens, positions}`. Tokens are a tagged union; positions track line/col/column/offset.

2. **Parser** (`src/parser.zig`): `Parser.init(allocator, arena, tokens, positions)` → `parse()` returns `[]Statement`. Expressions are parsed via `parser_expr.zig`. Errors are collected into `Parser.errors` (not thrown immediately) for multi-error diagnostics.

3. **Executor** (`src/executor.zig`): `Executor.init(...)` → `execute(program)`:
   - If no funcs/classes/imports → compile to bytecode via `Compiler.compileProgram`, then run via `VM.executeChunk`.
   - Otherwise → AST-walk via `VM.execute`.

4. **Bytecode VM** (`src/vm.zig`): `runFunction` executes instructions from `chunk.functions[0]` (the `"main"` function). Stack-based VM with 1024-value stack.

5. **AST Walker** (`src/vm.zig` + `src/vm_value_ops.zig`): `executeStatement` switches over `Statement` variants; `evaluateExpression` recursively evaluates `Expr` nodes.

### Language Syntax Quick Reference

| Construct | Syntax |
|-----------|--------|
| Variable decl | `int(10)~x`, `string("hi")~s`, `freal(3.14)~pi` |
| Block | `[ statement... ]` |
| Function | `name(param1, param2) [ body ]` |
| Class | `ClassName !class [ @private [ ... ] ]` |
| Class instantiation | `~ClassName~instanceName` |
| Method call | `$instance~method()` or `string($instance~method())~result` |
| Control flow | `<if>(cond) [ ... ] <elif>(cond) [ ... ] <else> [ ... ]` |
| Loops | `**Loop** <for>(~i=1&=5) [ ... ]`, `**Loop** <for.f.whle>@also [ ... ]` |
| Import | `**Import**($Module)@also%~alias!`global`:alias` |
| Output | `<printf>^("text\n")` |
| Input | `<input>(varName)` or `<input>("prompt")&=string("")~var` |
| Comments | `| comment |` |
| Priority | `{N} statement` |
| Return | `<return>(expr)` |
| Exception catch | `<catch>(`ErrorType`) [ ... ]` |
| Immediate mutation | `<now>(value)>varName` |
| Memory address | `<memory>^varName` |
| Memory free | `<memory>dete(varName)` |
| Encode | `<encode(`UTF-8`)>^("text")` |
| Length | `<len>^("hello")` |
| Null/none | `null~x` or `()~x`, `none~x` |
| Dict | `(1{'key': 'value'})~d` or `d{key}` to access |
| Tuple/list | `(1, 2)~t` |

### Built-in C Modules

Each module lives in `src/module/<Name>/` with:
- `<Name>.c` — implementation
- `<Name>.h` — C header
- `module.json` — manifest (name, version, language, exports, compiler)

Modules are compiled as shared libraries by `build.zig` and loaded at runtime via `std.DynLib` (dlopen). Exports use the `ko_` prefix and are called from Zig via `VM.dispatchLoop` or `callBuiltin`.

### C++ Loop Engine (`src/Loop.cpp`)

Provides optimized loop execution via C ABI (`ko_loop_*` functions). The Zig VM loads `libko_loop.so` dynamically and calls into it for `**Loop**` constructs. The engine supports unroll factors, cache-line alignment, and bounded iterations to prevent infinite loops.

### Java Import Subsystem (`src/Import.java`)

Reference implementation of module import. Handles dynamic path resolution, GitHub repository cloning, ZIP extraction, compilation/linking, and scope registration. The Zig runtime can invoke this via subprocess for Java-based modules.

### Package Manager (`src/installer.zig`)

`ko -install <library>` pipeline:
1. Query Module Store API (Firestore or local REST)
2. Clone library's GitHub repository
3. Inspect for `.zip` package
4. Auto-detect language and compile
5. Register scope

### CLI Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage error, file I/O error, or missing argument |
| 2 | Compile error (lexer or parser failure) |
| 3 | Runtime error (VM execution failure) |
| 4 | Input error (EndOfInput) |

### Testing

- `testing/test_harness.zig` — 15 smoke tests covering basic programs
- `testing/test_3600.zig` — comprehensive end-to-end tests
- `testing/test_lexer_extended.zig` — lexer tokenization tests
- `testing/test_parser_extended.zig` — parser error/span tests
- `testing/test_modules.zig` — shared library ABI tests via `mod_check.c`
- `testing/test_value.zig` — value type and operator tests

Tests use `VM.setInputBuffer()` and `VM.setOutputWriter()` to stay hermetic. Always close stdin when running manually.

### Standalone Binary Build

`ko build <file.ko>` appends the source code and a footer (length + magic bytes) to a copy of the `ko` executable. At startup, `readStandaloneSource` checks for the footer and executes the embedded source if present. This produces a self-contained executable under `build/<name>`.

### Memory Management

- `executeCode` in `main.zig` uses an `ArenaAllocator` for parser and VM lifetime.
- `Value` types are freed via `Value.deinit()` — strings, bytes, dicts, and nested containers are recursively freed.
- `Scope` owns its variables map; `Scope.deinit()` frees all keys and values.
- Shared library handles are kept alive in `VM.loaded_libs` for the duration of execution.

### Conventions

- All Zig code uses `std.mem.Allocator` explicitly; no global allocator state.
- `const` correctness is enforced on all pointer/value types where applicable.
- Error handling uses Zig error unions (`!T`); never suppress errors with `_ = catch {}` (per AGENTS.md).
- C modules use `-std=gnu11 -fPIC -D_GNU_SOURCE` flags for compatibility.
- C++ modules use `-std=c++17 -fPIC` with `KO_LOOP_NO_MAIN` macro.
- The `booling` type name is intentional (not a typo) — it appears in lexer, parser, and value types.