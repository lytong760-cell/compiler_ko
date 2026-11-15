# CONTEXT.md

Single source of truth for the `compiler_ko` project. Skills, agents, and contributors should reference this file instead of reconstructing project context from scattered issues.

## Project

`compiler_ko` is a polyglot compiler for the `.ko` language. The architecture splits work across three tiers: Zig owns the runtime and native backend, C++ owns the middle-end optimizer and IR, and Java owns the frontend tooling and AST surface.

Current milestone: issue-driven delivery. Each GitHub issue defines one bounded capability with explicit acceptance criteria.

## Directory layout

- `src/main.zig` - CLI entry point and command dispatch
- `src/lexer.zig` - Lexical analysis
- `src/parser.zig` - Parser producing the AST
- `src/ast.zig` - AST node definitions
- `src/vm.zig` - Bytecode VM and AST-walking interpreter
- `src/bytecode.zig` - Bytecode instruction set and chunk layout
- `src/compiler.zig` - AST to bytecode compiler
- `src/value.zig` - Runtime value system and helpers
- `src/installer.zig` - Library installer and module store client
- `src/module/` - Example shared-library modules (Os, Random, Website)
- `testing/` - Test fixtures and Zig test files
- `build.zig` - Zig build system configuration
- `build.zig.zon` - Package manifest, pins `minimum_zig_version`

## Issue map

Active work is tracked in GitHub Issues. Canonical issue references:

- #5 CLI Framework & `ko <file>` / `ko run <code>` (closed)
- #6 Lexer/AST Refactor + Bytecode VM
- #10 REPL (`ko repl`)
- #11 Error Reporting: File/Line/Column + Multi-error Collect
- #9 Plugin Loader + `Import` Subsystem (shared lib)
- #8 Completion Scripts (bash/zsh/fish)
- #12 Stdlib v1: I/O + String + Math
- #4 CONTEXT.md Glossary + Architecture
- #13 Loop Optimization Subsystem (shared lib)
- #14 Registry Client + `ko install/list/search` (closed)
- #15 `ko build` -> Native Binary
- #16 Test Baseline Repair — unblock `zig build test`
- #17 `ko run <file>` runs a file path, not just inline code
- #18 Wire Bytecode Backend Into the Execution Pipeline
- #19 Value Formatting: `<printf>` and `{name}` Print Raw Tagged Unions
- #20 Method Call Drops All Arguments
- #21 Second `<input>` in One Program Fails
- #22 Repo Hygiene: Drop Checked-in `zig/` Distribution and Build Artifacts
- #23 Zig Version Drift Across CI, Dockerfile, and Docs

## Glossary

Terms used by the compiler, tests, and `.ko` source files.

- `.ko` - Source file extension and language name
- AST - Abstract Syntax Tree produced by the parser
- Block - `[ ... ]` delimited statement group
- Bytecode - VM instruction sequence emitted by the compiler
- Catch - `[ <catch>(`Error`) [ ... ] ]` runtime error handler
- Chunk - Container for one function's bytecode and constants
- Class - `class` keyword defining a type with private and public bodies
- Compiler - Module that translates AST into bytecode
- Constant - Value stored in a chunk's constant pool
- Encode - System tag converting a value to its string representation
- Execute - System tag running an external command
- Expression - Grammar node that evaluates to a value
- Function - Named callable unit with params and body
- Identifier - Name token referring to a variable or function
- If/Elif/Else - Control flow keywords
- Import - Keyword loading a shared library module
- Input - System tag reading text from stdin
- Keyword - Reserved token with special meaning
- Len - System tag returning the length of a value
- Loop - `Loop` keyword for optimized iteration
- Memory - System tag exposing memory address info
- Now - System tag assigning a timestamp
- Plugin - Shared library implementing `Import`
- Priority - `{N}` prefix setting statement execution order
- Printf - System tag writing formatted output
- REPL - Read-eval-print loop (`ko repl`)
- Return - Statement exiting a function with a value
- Sigil - `~` token binding an expression result to a name
- Statement - Grammar node performing an action
- String - Text value delimited by `"..."` or `'...'`
- System tag - `<tagname>` runtime built-in
- Token - Lexer output unit
- Tuple - Fixed-size ordered value list
- Type - Named shape of a value (int, freal, string, booling, byte, bytes, tuple, dict)
- Value - Runtime data container
- VarDecl - Statement declaring a typed variable
- VM - Bytecode executor
- Writer - Zig `std.Io.Writer` abstraction for output

## Architecture

### Tier 1: Zig runtime and backend

Zig owns the executable, the CLI, the bytecode VM, and native I/O. It also owns the build system and any future AOT compilation path.

Entry points:
- `src/main.zig` - `main` function
- `src/vm.zig` - `VM.init` and `VM.executeChunk`
- `src/bytecode.zig` - Bytecode type definitions
- `src/compiler.zig` - `Compiler.init` and `Compiler.compileProgram`

### Tier 2: C++ optimizer and IR

C++ owns shared-library subsystems that require high-performance numeric or memory-intensive work.

Current modules:
- `src/module/Os/` - OS interaction shared library
- `src/module/Random/` - Random number generation shared library
- `src/module/Website/` - Website fetching shared library

Future modules:
- Loop optimization engine (`libko_loop.so`)
- Plugin loader and `Import` subsystem (`libko_import.so`)

### Tier 3: Java frontend and tooling

Java owns parser-adjacent tooling, AST visualization, and IDE-facing diagnostics.

Current modules:
- `src/Import.java` - Import subsystem reference implementation

## Execution model

1. Source text -> Lexer -> Token list
2. Token list -> Parser -> AST
3. AST -> VM (`execute`) -> Runtime values and side effects

The compiler (`src/compiler.zig`) and bytecode (`src/bytecode.zig`) modules are defined but not wired into the execution pipeline. `Compiler` has zero importers and `VM.executeChunk` is never called from `main.zig`; the live path is AST walking via `VM.execute`.

## CLI argument resolution

`ko run <arg>` accepts either a file path or inline code. The rule is: `arg` is treated as a
file path when it ends in `.ko` or when it resolves to an existing regular file; otherwise it
is treated as inline source code. A `.ko` argument that does not exist is reported as a missing
file rather than a parse error.

`ko <arg>` (no subcommand) always treats `arg` as a file path.

## Exit codes

- `0` - Success
- `1` - Usage error, file I/O error, or missing argument
- `2` - Compile error (lexer or parser failure)
- `3` - Runtime error (VM execution failure)

## Configuration

- Zig version: 0.16.0
- Build command: `zig build`
- Test command: `zig build test`
- Run command: `zig run` or `./zig-out/bin/ko`
