# ==============================================================================
# ENTERPRISE AI AGENT SYSTEM CONFIGURATION & ARCHITECTURE SPECIFICATION
# ==============================================================================
# Project: compiler_ko
# Root Workspace: /workspaces/compiler_ko
# Configuration Authority: Kilo CLI Engine v3.x+
# Persistence Scope: Local Native & Containerized Context Isolation
# Target Architecture: Multi-Tiered Polyglot Compiler (Zig, C++, Java)
# ==============================================================================

## 1. PERSISTENCE ENGINE & STATE LIFECYCLE MANAGEMENT

### 1.1 Automated State-Dump Subsystem (On-Every-Response Event Hook)
The AI Agent core must interception the final execution phase of *every single prompt turn*. Prior to rendering the stream response token array to the user terminal console, the background runtime MUST orchestrate a strict synchronization routine to dump current execution context into two telemetry tracking files.

- **Isolation Path:** cùng repo — `MEMORY.md` và `CHECKPOINTS.md` ở gốc repo
- **IO Requirements:** Atomic file writes (`O_TRUNC` with strict sequential lock handling).
- **Format Schema:** Extended Semantic Markdown (Strict structure parsing optimized for RAG injection).

#### Telemetry Target A: `MEMORY.md` (Long-Term Semantic Sync)
- **Primary Function:** Captures systemic insights, accumulated architectural learnings, schema maps, and conceptual state updates.
- **Structural Blueprint Required:**
  ```markdown
  ### [TIMESTAMP] LONG-TERM MEMORY DUMP
  - **Identified Truths:** <Valid logical axioms confirmed during code execution>
  - **Architectural Mutations:** <Structural file edits, compiler pipeline changes>
  - **Technical Debt & Anti-Patterns:** <Discovered bugs, memory leaks, code anti-patterns to avoid>
  - **Shared Variables & Symbols:** <Symbol table updates, abstract data type (ADT) definitions>
  ```
- **Ghi kèm bằng chứng:** mỗi khẳng định phải kèm lệnh đã chạy và output thật. Điều chưa kiểm chứng thì để dưới mục `## Chưa xác minh`, **không** ghi như sự thật.

#### Telemetry Target B: `CHECKPOINTS.md` (Short-Term Reactive Sync)
- **Primary Function:** Captures the immediate task lifecycle state, volatile diagnostic telemetry, active compiler logs, and step-by-step progress tracking.
- **Structural Blueprint Required:**
  ```markdown
  ### LAST KNOWN EXECUTION CHECKPOINT
  - **Task State:** <IN_PROGRESS | COMPILER_ERROR | BLOCKED | SUCCESS>
  - **Active Node/Context:** <The specific file path, function signature, or block currently edited>
  - **Volatile Context Diagnostics:** <Raw terminal stdout/stderr, stack traces, compiler panic output>
  - **Next Execution Phase Vectors:** <Atomic chronological list of what the next turn must compute>
  ```
- **Bắt buộc cập nhật** mỗi khi trạng thái đổi, kể cả khi chuyển sang vòng lặp làm việc mới.

### 1.2 Session Bootstrapping & Warm-Start Sourcing Routine (New Session Init)
Upon trigger event `kilo session-init` or anytime a fresh runtime stack initializes inside the terminal console, the execution context memory layer MUST perform a pre-flight execution bypass hook:

1. **Pre-emption Search:** Đọc `MEMORY.md` và `CHECKPOINTS.md` ở gốc repo (`/workspaces/compiler_ko/`).
2. **Context Reconstruction Phase:** Nạp nội dung hai file đó vào ngữ cảnh trước khi xử lý yêu cầu của người dùng.


---

## 2. POLYGLOT COMPILER ARCHITECTURE SPECIFICATION (ZIG / C++ / JAVA)

The core architecture of `compiler_ko` is an advanced, highly coupled, multi-tier compiler architecture leveraging the distinct computing advantages of the Zig toolchain, high-efficiency C++ memory layout, and structural object handling of Java.

┌──────────────────────────────────────────────────────┐│                 JAVA FRONTEND TIER                   ││   Lexical Analysis -> Parsing -> Concrete AST        │└──────────────────────────┬───────────────────────────┘│▼ [IPC / Protocol Serialization]┌──────────────────────────────────────────────────────┐│                 C++ MIDDLEWARE ENGINE                ││   Semantic Analysis -> Symbol Table -> Optimizations │└──────────────────────────┬───────────────────────────┘│▼ [Direct C-ABI Binding]┌──────────────────────────────────────────────────────┐│                  ZIG RUNTIME & CODES                 ││   Memory Safety Management -> Native Backend CodeGen │└──────────────────────────────────────────────────────┘
### 2.1 Java Architecture Tier (Frontend Analysis & Tooling Interface)
- **Designated Subsystem Scope:** Lexical analyzers (Lexer), Abstract Syntax Tree (AST) parsing nodes, and developer-facing diagnostic tools/GUIs.
- **Architectural Invariant Rules:**
  - Leverage `java.base` modular patterns for high performance.
  - Strictly enforce decoupling of compiler error reporting from AST mutation logic.
  - Serialization to the middle tier must occur through structured file descriptors or high-speed IPC (Inter-Process Communication).

### 2.2 C++ Architecture Tier (Optimizer, Intermediate Representation & Core Processing)
- **Designated Subsystem Scope:** Middle-end pipeline, Static Single Assignment (SSA) transformations, High-level/Low-level Intermediate Representation (HIR/LIR) optimizations, Global Symbol Tables.
- **Architectural Invariant Rules:**
  - Modern ISO Standard compliance: **C++17 / C++20 minimum core features**.
  - Standard Template Library (STL) smart pointers (`std::unique_ptr`, `std::shared_ptr`) must manage object ownership graph chains explicitly to avoid raw allocations.
  - Avoid undefined behaviors by forcing comprehensive data type checks on symbol evaluations.

### 2.3 Zig Architecture Tier (Modern System Backend & Runtime Engine)
- **Designated Subsystem Scope:** Low-level Target Backend Generation, Memory Pool/Arena Allocator optimization layers, Runtime Memory Protection primitives, Native C-ABI Bridging.
- **Architectural Invariant Rules:**
  - Use Zig's native `std.mem.Allocator` patterns (explicit allocation passing). No hidden or implicit global memory state shifts are permitted.
  - Utilize `comptime` constructs heavily to perform translation optimizations and static data evaluations during the compiler build time itself rather than execution runtime.
  - Maintain a strict zero-dependency linking matrix targeting clean native executable output formats.

---

## 3. STRICT AI AGENT COMPLIANCE CODING PROTOCOLS

When writing, refactoring, or generating code blocks within the `/workspaces/compiler_ko` domain, the AI agent MUST execute instructions in alignment with this matrix:

| Functional Goal | Preferred Language Tier | Constraint Boundary |
| :--- | :--- | :--- |
| **AST Traversal & Text Parsing** | `Java` (Object graphs) | Avoid high-frequency allocations; manage GC pressure profiles. |
| **Data Representation & IR Opt** | `C++` (Pointer/Value mix) | Enforce `const` correctness; minimize deep reference copying. |
| **System Bindings & Native I/O** | `Zig` (Explicit errors) | Handle every failure case pattern via `try`/`catch` or error union handling. |

### 3.1 Global Execution Anti-Patterns (Forbidden Tasks)
1. **NEVER** write raw `malloc`/`free` calls inside the C++ layer. Use memory arenas or standard object lifetime templates.
2. **NEVER** suppress errors inside Zig loops via empty `_ = catch {}` blocks; all panic paths must trace down through explicit logging pipelines.
3. **NEVER** generate code modifications without reviewing the latest target output blocks defined in `/root/.config/kilo/CHECKPOINT.md`.

alway  use VietNamese

## Agent skills

### Issue tracker

Issues and specs live in GitHub Issues, accessed via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical roles mapped to default labels: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context. See `docs/agents/domain.md`.
