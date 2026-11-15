# .ko Language Formal Technical Specification & Architectural Manual (x86-64 NASM Assembly-Level Edition)

> This document is the normalized specification of the `.ko` language and its runtime
> architecture, rewritten at pure x86-64 NASM assembly level: architectures, algorithms,
> full directory/file layout, register and memory maps, instruction encoding, and ABI.
> Goal: future-oriented, independent of the current repository layout. Only two runtime
> components are named explicitly: `import.asm` and `loop.asm`.
>
> Conventions: assembly listings use NASM syntax unless noted; registers are named per
> the x86-64 System V AMD64 ABI. All multi-byte integers are little-endian unless
> stated otherwise. No other language runtimes or toolchains are referenced.

---

## I. RUNTIME ARCHITECTURE & ENGINE TARGET MAPPING

The `.ko` language operates on a **Hybrid Execution Target Engine** model. The central
assembler/runtime (the conductor) receives source code, parses it, and dispatches work to
specialized assembly subsystems underneath for execution.

### 1. Mathematical Pipeline Model and Execution Diagram

$$\mathcal{P}: \text{SourceCode}_{.ko} \xrightarrow{\text{Lexer/Parser}} \text{AST} \xrightarrow{\text{ScopeResolver}} \text{EngineTarget} \xrightarrow{\text{Execution}} \text{State}'$$

```
+-------------------------------------------------------------------+
|                     High-Level Source Code (.ko)                   |
+-------------------------------------------------------------------+
                                   |
                                   v
+-------------------------------------------------------------------+
|        Abstract Syntax Analysis (Conductor / Runtime Core)         |
+-------------------------------------------------------------------+
                    /                                   \
                   /                                     \
                  v                                       v
+--------------------------+           +----------------------------+
|   Subsystem Import Engine|           |    Subsystem Loop Engine   |
|      (import.asm)        |           |         (loop.asm)         |
+--------------------------+           +----------------------------+
| - Dynamic Path Resolution|           | - Low-level Loop Unrolling |
| - Scope Table Ingestion  |           | - Cache Line Optimization  |
| - Module Signature Check |           | - CPU Counter Registers    |
+--------------------------+           +----------------------------+
```

### 2. Mapping Special Keywords to System Execution Files

#### A. Module Import Library: Import Subsystem Target

- **Language Directive:** `Import`
- **Responsible Source File:** `import.asm`
- **Simple Explanation:** Think of `import.asm` as a "Librarian". When you use the `Import`
  keyword or the `ko -install` command, the assembly librarian finds the library package,
  verifies its validity, assembles/links it, and places it in your workspace.

**Mathematical & Technical Semantics:**

$$\text{Import}_{\text{subsystem}}: \text{ModuleName} \times \text{ScopeTag} \to \mathcal{S}_{\text{updated\_scope\_table}}$$

- Dynamic file path resolution
- Source code signature verification
- Dynamic module loading and insertion of identifiers into the Scope Table

**NASM-level execution path (Import):**

```nasm
; import.asm entry (native, System V AMD64 ABI)
; rdi = module name ptr, rsi = scope tag, rdx = out frame ptr
import_entry:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 0x40
    call    http_get_module          ; HTTP GET https://ko-lang.ai.studio/api/module/<name>
    test    rax, rax
    js      .import_fail
    mov     [rbp-0x8], rax           ; metadata JSON
    call    git_clone_repo           ; clone to temp cache
    test    rax, rax
    js      .import_fail
    call    zip_inspect              ; verify .zip present
    test    rax, rax
    jz      .import_fail
    call    compile_and_load         ; assemble/link, insert Scope Table
    mov     rax, 0                  ; success
    leave
    ret
.import_fail:
    mov     rax, -1
    leave
    ret
```

#### B. High-Performance Loop Engine: Loop Subsystem Target

- **Language Directive:** `Loop`
- **Responsible Source File:** `loop.asm`
- **Simple Explanation:** Think of `loop.asm` as an "F1 Racing Car". Repeating an action
  millions of times is handed off to assembly code running directly at the CPU hardware level.

**Mathematical & Technical Semantics:**

$$\text{Loop}_{\text{subsystem}}: \text{IterCondition} \times \text{BodyBlock} \xrightarrow{\text{Native ASM}} \Delta \text{State}$$

- CPU hardware register allocation and optimization
- Bypassing interpreter overhead, instruction cache line optimization

**NASM-level execution path (Loop):**

```nasm
; loop.asm entry (native, C-ABI style)
; rdi = loop IR block ptr, rsi = state delta out ptr
loop_entry:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 0x80
    ; decode IR block header
    mov     eax, [rdi]               ; magic
    cmp     eax, 0x4B4F4C50          ; 'KOPL'
    jne     .loop_bad_magic
    mov     ecx, [rdi+4]             ; iteration count
    mov     rdx, [rdi+8]             ; body ptr
    ; unroll by 4
.loop_unroll4:
    cmp     ecx, 4
    jl      .loop_tail
    ; body x4
    call    exec_body                ; rdx body
    call    exec_body
    call    exec_body
    call    exec_body
    sub     ecx, 4
    jmp     .loop_unroll4
.loop_tail:
    test    ecx, ecx
    jz      .loop_done
    call    exec_body
    dec     ecx
    jmp     .loop_tail
.loop_done:
    mov     rax, 0
    leave
    ret
.loop_bad_magic:
    mov     rax, -2
    leave
    ret
```

---

## II. THEORETICAL MODEL AND GENERAL SYNTAX VOCABULARY

### 1. Command and Data Separation Principle

- **Command Space / Scope Block ($\mathcal{B}_E$):** Uses only square brackets `[ ]`.
- **Data & Parameter Space ($\mathcal{D}_P$):** Uses parentheses `( )` for sets/parameters and curly braces `{ }` for Key-Value mappings.

**Axiom:**

$$\mathcal{B}_E \cap \mathcal{D}_P = \emptyset$$

### 2. Special Recognition Symbols

| Symbol | Name | Meaning | Example |
|--------|------|---------|---------|
| `~` | Identifier Sigil | Marks variable/function/class names | `int(10)~age` |
| `< >` | System Tag | Wraps system commands | `<printf>`, `<input>`, `<len>` |
| `$` | Reference Pointer | Accesses properties/methods in Class | `$p1~take_damage()` |
| `"\n"` | Newline Escape | Newline in double-quoted string | `"Hello\n"` |
| `| |` | Comment Separator | Ignored at compile time | `| comment |` |

### 2.1 Region Type Annotations (`@`)

The `@` symbol is a **region/type role sigil**. It is not a variable name; it declares what kind of region or member a block belongs to. `@` has multiple roles depending on context:

- `@also` — example: marks a `**Loop**` region as sequential.
- `@private` — example in OOP: marks a class member as private/restricted access.
- More `@` roles may be defined for other regions without changing the base meaning: annotate role, not storage.

`@also` is only a visual example for sequential loops, not a rule that `@` means "loop". A `while` loop is resolved by its own control-flow rule; numbered statements such as `{0}`, `{1}` may be used when explicit execution order is required.

**Example:**

```ko
@loop(hp > 0) {
**Loop** <for.f.whle>@also [
    <printf>^("Fighting...\n")
    <now>(hp - 10)>hp
]
}
```

**OOP example:**

```ko
class Player [ 
    @private [
        int(100)~hp
    ]
]
```

### 3. EBNF Syntax

```
Statement          ::= VarDecl | Assignment | FuncDecl | ClassDecl | ControlFlow | MemoryOp | EncodingOp | LenOp | ExceptionHandler ;
Sigil              ::= "~" ;
SystemTagOpen      ::= "<" ;
SystemTagClose     ::= ">" ;
Comment            ::= "|" [^|]* "|" ;
NewlineEscape      ::= '"\n"' ;
Identifier         ::= [a-zA-Z_][a-zA-Z0-9_]* ;
VarDecl            ::= PrimitiveType "(" Expression ")" Sigil Identifier ;
PrimitiveType      ::= "int" | "freal" | "string" | "booling" | "byte" | "bytes" ;
EncodingOp         ::= SystemTagOpen "encode(" EncodingType ")" SystemTagClose "^(" Expression ")" ;
EncodingType       ::= "`ASCII`" | "`UTF-8`" | "`UTF-16`" ;
LenOp              ::= SystemTagOpen "len" SystemTagClose "^(" Expression ")" ;
```

### 4. Operator System

- **Arithmetic Operators:** `+`, `-`, `*`, `/`, `%`
- **Logical Operators:**
  - `&&` : Logical AND
  - `%%` : Logical OR

### 5. Global Execution Scope Axiom

Execution statements must not float freely outside the global scope. They are required to be inside a Function or Main Execution Block `[ ]`. The global scope only accepts: Import statements, Function declarations, and Class declarations.

---

## III. DATA TYPE SYSTEM

### 1. Primitive Data Types

| Type | Value Domain | Example |
|------|---------------|---------|
| `int` | $\mathbb{Z} \cap [-2^{63}, 2^{63}-1]$ | `int(100)~hp` |
| `freal` | $\mathbb{R}$ Double Precision | `freal(3.14159)~pi` |
| `string` | UTF-8 character string | `string("Phong\n")~name` |
| `booling` | $\mathbb{B} = \{\mathtt{\backslash True\backslash}, \mathtt{\backslash False\backslash}\}$ | `booling(\True\)~is_active` |
| `byte` | Binary representation | `byte("A")~b_val` |
| `bytes` | Hex buffer area | `bytes(16)~empty_buf` |

**NASM representation of primitives:**

```nasm
; Value tagged union (assembly-level)
; layout in memory (16 bytes aligned):
;   offset 0:  tag    (u8)   0=int 1=freal 2=string 3=bool 4=byte 5=bytes 6=null 7=none 8=list 9=dict 10=class
;   offset 1:  pad    (7 bytes)
;   offset 8:  payload (u64)  immediate for int/bool/byte; pointer for heap kinds
struc Value
    .tag:     resb 1
    .pad:     resb 7
    .payload: resq 1
endstruc
```

### 2. Composite Data Structures

- Tuple / Number array: `(1, 2)~a`
- String array: `('a', 'b')~b`
- Nested list: `(1('a', 'b'))~list`
- Dictionary: `(1{'a'})~dic`

### 3. Null and None Types

- **Null** is a temporary placeholder for a variable that has **not yet been assigned** a value:

```ko
()~var
```

**Rules for Null:**
- A `null` variable **must** be assigned a value or converted to `none` before it can be used in any operation.
- While still `null`, the variable is **unusable**: it cannot be compared (`==`, `!=`, `<`, `>`, ...), cannot participate in arithmetic, cannot be printed as a value, and cannot be passed to functions.
- Any attempt to use an unassigned `null` raises a runtime `TypeError` (or `UnassignedError`).
- If a variable has a null value and remains unassigned until the end of the program, the system will throw a `Null Unassigned` error.
- Assignment or conversion must happen explicitly via `<now>`:

```ko
<now>(value)>var        | assign a value
<now>(none)>var          | convert to none
```

- **None** is an immutable empty value that **cannot be reassigned** to another value:

```ko
none~a
```

**Rules for None:**
- `none` is a final, immutable sentinel; once bound, it cannot be overwritten.
- `none` supports equality comparison (`none == none` is true; `none == <other>` is false) but no arithmetic or ordering operations.

### 4. Index Access Syntax

Indexing reads a value from a container without mutating it. The brackets choose the container kind:

- **List / tuple / string** — angle brackets `< >`, 0-based integer index:
  - `list<0>` — first element
  - `list<i>` — element at index `i`
  - `list<1<0>>` — element `0` of the sub-list stored at index `1`
  - Out-of-range or negative index raises `IndexError`
- **Dictionary** — braces `{ }`, key expression:
  - `dic{'key'}` — value stored under the string key `"key"`
  - `dic{1}` — value stored under the integer key `1` (for a dict declared as `(1{'a'})~dic`, this yields `'a'`)
  - A missing key raises `KeyError`; the key type must match the dict's key type
- **Nesting / chaining** (left to right):
  - `matrix<row<col>>` — nested list access
  - `table{'users'}{'name'}` — nested dict access
  - `records<0>{'id'}` — list then dict
- **Compact legacy form** `dic{1{'a'}}` is shorthand for the entry above; the canonical form is `dic{1}`.

```ko
('a', 'b', 'c')~letters
letters<0>                       | 'a'
letters<2>                       | 'c'

(1{'a'}, 2{'b'})~dic
dic{1}                           | 'a'
dic{2}                           | 'b'
dic{'missing'}                   | KeyError

matrix = ( (1, 2), (3, 4) )
matrix<1<0>>                     | 3
```

**NASM-level index access:**

```nasm
; evaluateIndexAccess(container, index)
; rdi = container Value*, rsi = index Value*
evaluateIndexAccess:
    push    rbp
    mov     rbp, rsp
    mov     al, [rdi]                ; container tag
    cmp     al, 8                    ; list/tuple?
    je      .idx_list
    cmp     al, 2                    ; string?
    je      .idx_string
    cmp     al, 9                    ; dict?
    je      .idx_dict
    ; else error
    mov     rax, ERR_TYPE
    leave
    ret
.idx_list:
    mov     r8, [rdi+8]              ; payload = ArrayList*
    mov     r9, [rsi+8]              ; index int
    ; bounds check
    cmp     r9, [r8+0]               ; size
    jae     .idx_oob
    mov     rax, [r8+8]              ; data ptr
    mov     rax, [rax + r9*16]       ; Value (16 bytes)
    leave
    ret
.idx_string:
    ; byte offset = index, return byte Value
    mov     rax, 0
    leave
    ret
.idx_dict:
    ; hashmap lookup by key
    mov     rax, 0
    leave
    ret
.idx_oob:
    mov     rax, ERR_INDEX
    leave
    ret
```

### 5. Type Introspection

- `type(format)` evaluates the runtime type of a value and prints it automatically.

```ko
type("Hello")          # output: string
type(123)~a
<printf>^(a)            # output: int
```

---

## IV. INPUT/OUTPUT SYSTEM, MEMORY, ENCODING, LENGTH

### 1. Data Output Structure

```ko
<print>string^("Xin chao\n")
<print>[data_type]^
<printf>^("Player HP: {hp}\n")
```

### 2. System Encoding Tag (`<encode>`)

```ko
<encode(`ASCII`)>^("Hello World\n")
<encode(`UTF-8`)>^("Xin chào .ko\n")
bytes(<encode(`UTF-8`)>^("Secure data\n"))~encoded_data
```

### 3. System Length Tag (`<len>`)

```ko
int(<len>^("Xin chào .ko\n"))~str_length
int(<len>^(buffer))~buf_size
int(<len>^(inventory))~item_count
```

### 4. Data Input Structure (`<input>`)

```ko
<input>("Enter info: \n")

string("")~x
<input>(x)

<input>("Enter name: \n")&=string("")~name
```

### 5. Low-Level Memory Operations (`<memory>`)

```ko
int(0)~h
<memory>^h              | Returns memory cell address

<memory>dete(h)         | Frees memory
```

### 6. Instant State Mutation (`<now>`)

```ko
<now>(100)>hp
<now>(hp - damage)>hp
```

### 7. Algorithmic Core and Memory Model (Optimal Design, Repo-Independent)

This subsection describes the **optimal algorithmic and memory-management design** for the `.ko`
runtime. It is intentionally **not** a 1:1 mirror of the current repository layout; it states
the idealized model and then maps each concept to its current implementation location for reference.

#### 7.1 Algorithm Inventory and Effect

| # | Algorithm / Mechanism | Purpose (Effect) | Optimal Complexity | Current Location (reference) |
|---|------------------------|------------------|--------------------|------------------------------|
| 1 | **Lexical Scanning (DFA-based)** | Convert source text into a token stream; classify sigils, system tags, comments, escapes. | O(n) time, O(n) tokens | `src/lexer.asm` (`tokenize`) |
| 2 | **Recursive-Descent Parsing** | Build AST from token stream according to EBNF and priority rules; precedence climbing for expressions. | O(n) time, O(depth) stack | `src/parser.asm` (`parse`, `parseExpr`) |
| 3 | **Scope Resolution (Hash-Table Symbol Table)** | Register identifiers into nested scopes (global/main/func/class); resolve names via parent-chain lookup. | O(1) avg lookup, O(scope depth) worst | `src/vm.asm` (`Scope`, `getVariable`) |
| 4 | **Stack-Based VM Execution** | Evaluate AST/IR with an explicit evaluation stack; dispatch statements and expressions. | O(n) per program, O(stack depth) space | `src/vm.asm` (`execute`, `evaluateExpression`, `evaluateBinary`) |
| 5 | **Value Algebra (Unified Binary Ops)** | Single source of truth for all binary operations: arithmetic, comparison, equality, logical. Checked overflow for integer ops; strict typing (no implicit int↔freal coercion). | O(1) per op (O(n) for concat) | `src/value.asm` (`add`, `sub`, `mul`, `div`, `rem`, `equals`, `less`, `greater`, `lessOrEqual`, `greaterOrEqual`) |
| 6 | **Truthiness Coercion (`toBool`)** | Convert any value to boolean for logical/control-flow contexts (non-strict, matches AST behavior). | O(1) (O(n) for containers) | `src/value.asm` (`toBool`) |
| 7 | **Memory Ownership (Arena + GPA)** | Arena for parse-time/short-lived allocations; GeneralPurposeAllocator for long-lived owned values; explicit `deinit` chains. | O(1) alloc, O(n) bulk free | `src/main.asm` (arena), `src/vm.asm`/`src/value.asm` (allocator) |
| 8 | **Value Cloning** | Deep-copy owned values (strings, lists, dicts, class instances) when crossing scope boundaries. | O(size of value) | `src/value.asm` (`clone`) |
| 9 | **Bytecode Compilation (optional backend)** | Lower AST to a compact instruction stream (opcodes 0..12 for binary ops) for faster dispatch. | O(n) compile, O(n) exec | `src/compiler.asm`, `src/bytecode.asm`, `src/vm.asm` (`binaryOp`) |
| 10 | **Exception Scanning by Scope** | Scan backward within function/main/global scope for matching `<catch>` handler; chain priority top-to-bottom. | O(handlers) per throw | `src/vm.asm` (`dispatchCatchBlocks`) |
| 11 | **Index/Key Access** | Random access into tuples/lists/strings and dict lookup by key. | O(1) avg (dict), O(1) (list index) | `src/vm.asm` (`evaluateIndexAccess`) |
| 12 | **String Interpolation** | Substitute `{var}` placeholders in printf templates with runtime values. | O(n + m) | `src/vm.asm` (`printInterpolated`) |

#### 7.2 Memory Management Strategy (Optimal)

**Principle:** Memory is **explicitly owned**; no hidden global state. Every allocation is tied to an allocator passed down the call chain.

- **Arena Allocator (short-lived):** Used for the entire parse phase. All AST nodes, tokens' derived data, and temporary strings are allocated in one arena; `arena.deinit()` frees everything in O(1) bulk at end of compilation/execution. This eliminates per-node `free` and prevents leaks during error paths.
- **GeneralPurposeAllocator (long-lived values):** Runtime values that outlive the parse arena (variables in scopes, cloned values, class instances) are allocated with a GPA. Each `Value` implements `deinit(allocator)` to recursively release owned memory.
- **Ownership Rules:**
  - **Creator owns:** The function that allocates a value owns it; transfer occurs via explicit `clone` or move.
  - **No implicit sharing:** Strings, lists, and dicts are never shared by reference across scope boundaries without cloning.
  - **Allocator injection:** Every function that allocates takes `allocator: std.mem.Allocator` as a parameter; no module-level allocator global.
  - **Error safety:** `errdefer` is used to roll back partial allocations on failure (e.g., class declaration, function creation).
- **Memory Tagging for Debug:** In debug builds, the GPA detects leaks and double-frees; arena frees are bulk-verified.

#### 7.3 Algorithmic Data Structures (Optimal)

| Structure | Used For | Rationale |
|-----------|----------|-----------|
| **Hash Map (`StringHashMap`)** | Scope variables, class fields/methods, dict values | O(1) average lookup; natural key-based access |
| **Dynamic Array (`[]Value`, ArrayList)** | Tuples, lists, evaluation stack, bytecode chunks | Contiguous memory, cache-friendly, O(1) amortized append |
| **Tagged Union (`union(enum)`)** | `Value` type | Single type representing all runtime values; exhaustive switch ensures type safety |
| **Arena-allocated AST nodes** | Parse tree | Bulk allocation/deallocation; no per-node lifetime tracking |
| **Evaluation Stack (`[]Value`)** | VM expression evaluation | LIFO discipline matches expression evaluation order |

#### 7.4 Effect Analysis (What Each Algorithm Achieves)

- **Lexer/Parser:** Transforms unstructured text into a structured, type-checked AST; enables all downstream analysis.
- **Scope Resolution:** Ensures variables are declared before use and isolated by scope; prevents name collisions.
- **VM Execution:** Interprets AST directly (AST-walker path) or dispatches bytecode (bytecode path); maintains runtime state.
- **Value Algebra:** Centralizes all binary operations; guarantees consistent behavior across both execution paths; checked overflow prevents silent wraparound; strict typing catches type mismatches at runtime.
- **Memory Model:** Prevents use-after-free and leaks via explicit ownership; arena bulk-free makes error paths safe and fast.
- **Exception Handling:** Provides scoped error recovery; allows graceful degradation.

#### 7.5 Where (Current Repo Reference, Not Optimal Layout)

The current repository places all core logic in `src/`:
- `src/lexer.asm` — lexical analysis
- `src/parser.asm` — parsing
- `src/ast.asm` — AST definitions
- `src/vm.asm` — VM, scope, execution, bytecode dispatch
- `src/value.asm` — value algebra and memory ownership
- `src/compiler.asm` — bytecode compiler
- `src/bytecode.asm` — bytecode format
- `src/main.asm` — entry point, arena setup, orchestration
- `src/builtins.asm` — built-in functions
- `src/installer.asm` — module installation
- `src/module/` — native modules

**Optimal (future) layout** would separate into:
```
frontend/   (assembly: lexer, parser, AST)
middleware/ (assembly: semantic analysis, optimization, symbol table)
backend/    (assembly: codegen, runtime, memory, ABI)
core/       (shared: Value, AST/IR definitions)
```
with cross-language data exchange via CDEL (Section XVII.3).

---

## V. FUNCTION STRUCTURE, RETURN VALUES, AND MAIN EXECUTION BLOCK

### 1. Function Definition and Call

```ko
calculate_power(int~base) [
    <return>(base * 2)
]

int(~calculate_power(10))~total
<now>(~calculate_power(20))>total
```

**NASM-level call frame (function call):**

```nasm
; call calculate_power(base)
; args on eval stack: [base Value]
calculate_power:
    push    rbp
    mov     rbp, rsp
    sub     rsp, 0x20
    ; load arg into local slot 0
    mov     rax, [eval_sp]            ; pop base
    sub     eval_sp, 16
    mov     [rbp-0x10], rax
    ; body: return base*2
    mov     rax, [rbp-0x10]
    imul    rax, 2                    ; checked: jo .overflow
    ; push return value
    mov     [eval_sp], rax
    add     eval_sp, 16
    leave
    ret
.overflow:
    mov     rax, ERR_OVERFLOW
    leave
    ret
```

### 2. Main Execution Block

Every standalone `.ko` file must have exactly one Main Block `[ ]`.

**Process manager visibility:** when executing a `.ko` file, the runtime exposes the current
execution process in the process manager using the format `file:main-function`.

```
test.ko:main
test.ko:main-test_func
```

---

## VI. CONTROL FLOW STRUCTURE

### 1. Conditional Branching

```ko
<if>(hp > 0 && is_active == \True\) [
    <printf>^("Character is alive!\n")
]
<elif>(hp <= 0 %% is_active == \False\) [
    <printf>^("Character is exhausted!\n")
]
<else> [
    <printf>^("Status unknown!\n")
]
```

**NASM-level branch:**

```nasm
; if (cond) branch
    call    evaluateExpression        ; -> rax Value (bool)
    test    rax, rax
    jz      .elif_branch
    ; then-block
    call    exec_block
    jmp     .if_end
.elif_branch:
    ; elif cond
    call    evaluateExpression
    test    rax, rax
    jz      .else_branch
    call    exec_block
    jmp     .if_end
.else_branch:
    call    exec_block
.if_end:
```

### 2. Loop System

Make sure you have two `**` markers around Loop.

```ko
**Loop** <for>(~x=1&=5) [
    <printf>^("x = {x}\n")
]

**Loop** <for>(~x=1(2)&=5) [
    <printf>^("Odd: {x}\n")
]

@loop(hp > 0) {
**Loop** <for.f.whle>@also [
    <printf>^("Fighting...\n")
    <now>(hp - 10)>hp
]
}
```

**NASM-level loop (counter-driven, unrolled):**

```nasm
; for (x=1; x<=5; x++)
    mov     rcx, 1                   ; counter
.for_cond:
    cmp     rcx, 5
    jg      .for_end
    ; body
    push    rcx
    call    exec_body
    pop     rcx
    inc     rcx
    jmp     .for_cond
.for_end:
```

---

## VII. MODULE IMPORT AND SCOPE SYSTEM

### 1. Module Import Syntax

Make sure you use `**` to wrap Import.

```ko
**Import**($Random)@also%~random!`global`:random
int(<$random>(1, 100))~rand_val
```

### 2. Scope Tag Regulations

| Scope Tag | Scope of Effect |
|-----------|-----------------|
| `global` | Global |
| `main` or `a` | Main Block |
| `func` | Function |
| `class` | Class |
| `function_name` | Specific function |

### 3. Built-in Standard Library

```ko
**Import**($Random)@also%~random!`global`:random
int(<$random>(1, 100))~rand_val

**Import**($Os)@also%~os!`global`:os
<$os>("data.txt")~file_var

**Import**($Website)@also%~web!`global`:web
<$web>("https://api.example.com")
```

### 4. External Library Management System

#### A. Install Commands

```bash
ko -install "<Library>"
ko -list
ko -search "<query>"
```

#### B. Library Registry Gateway and API

- **Module Store URL:** `https://ko-lang.ai.studio`
- **REST API Endpoints (JSON):**

**GET - List All Libraries (`ko -list`):**

```
GET https://ko-lang.ai.studio/api/module
Content-Type: application/json

Response (JSON array):
[
  {
    "name": "<name>",
    "githubLink": "<url>",
    "description": "<description>",
    "tags": ["<tag>"],
    "userId": "<userId>",
    "createdAt": "<timestamp>",
    "detail": { ... }
  }
]
```

**GET - Load Specific Library (`ko -install <name>`):**

```
GET https://ko-lang.ai.studio/api/module/<name>
Content-Type: application/json

Response (JSON object):
{
  "name": "<name>",
  "detail": {
    "name": "<name>",
    "githubLink": "<url>",
    "description": "<description>",
    "tags": ["<tag>"],
    "userId": "<userId>",
    "createdAt": "<timestamp>"
  }
}
```

#### C. Automatic Processing Flow

```
+-----------------------------------------------------------------------------------+
| 1. Terminal Call: ko -install "<Library>"                                         |
+-----------------------------------------------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------+
| 2. Module Store REST API Query:                                                       |
|    GET https://ko-lang.ai.studio/api/module/<library>                                 |
|    -> Retrieve Metadata & GitHub Repository link of the library                      |
+-----------------------------------------------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------+
| 3. Subsystem import.asm performs `git clone` of entire Repo                     |
|    to system temp cache directory                                                 |
+-----------------------------------------------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------+
| 4. Package File Check (.zip Inspection):                                          |
|    - [CASE 1]: `.zip` file found in Repo                                         |
|      -> Keep ONLY the `.zip` file, DELETE ALL other files/directories.          |
|    - [CASE 2]: NO `.zip` file found                                              |
|      -> Cancel process immediately, DELETE ALL cloned data.                     |
+-----------------------------------------------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------+
| 5. Extract `.zip` & Automatic Language Analysis                                   |
+-----------------------------------------------------------------------------------+
                  /                                       \
                 /                                         \
[Success]  v                                           v [Failure]
+----------------------------------+     +----------------------------------+
| Scope Table Integration         |     | 1. Print detailed error to CLI   |
| Ready for `Import` directive    |     | 2. AUTO-CLEAN the library       |
+----------------------------------+     +----------------------------------+
```

---

## VIII. OBJECT-ORIENTED PROGRAMMING

### 1. Class Structure

```ko
Monster !class [
    @private [
        string("Dragon")~name
        int(100)~hp

        take_damage() [
            int(<$random>(15, 35))~damage
            <now>(hp - damage)>hp
            <printf>^("Monster {name} was hit! HP remaining: {hp}\n")
            <return>(hp)
        ]
    ]
]

~Monster~m1
int($m1~take_damage())~remaining_hp
```

**NASM-level class instance layout:**

```nasm
; Class instance object (heap, GPA-owned)
struc ClassInstance
    .class_id:    resq 1          ; index into class table
    .field_count: resq 1
    .fields:      resb 0          ; flexible array, field_count entries (Value)
endstruc
; method dispatch: vtable pointer stored in class table
struc ClassDef
    .name:         resq 1         ; char*
    .field_count:  resq 1
    .method_count: resq 1
    .methods:      resb 0         ; Method* (name ptr + fn ptr)
endstruc
; $m1~take_damage() dispatch:
;   rdi = instance ptr
;   lookup method by name hash in ClassDef.methods
;   call method fn(instance, args...)
```

---

## IX. ERROR AND EXCEPTION HANDLING MECHANISM

### 1. `<catch>` Syntax

```ko
<catch>(`ErrorCode`) [ Processing_Block ]
```

### 2. Error Scanning Scope Rules

- **A. Internal Catch:** Only scans backward within the Function/Main Block containing it.
- **B. Global Catch:** Scans backward protecting all Functions/Main Blocks preceding it.
- **C. Chain Priority Rule:** Checks from top to bottom, first matching error is processed.

### 3. Intrinsic Exception Variables

```ko
<catch>(`DivideByZeroError`) [
    <printf>^("Error {error<"type">} at line {error<"line">}: {error<"code">'}\n")
]
```

**NASM-level exception dispatch:**

```nasm
; dispatchCatchBlocks(scope, errcode)
; rdi = scope ptr, esi = errcode
dispatchCatchBlocks:
    push    rbp
    mov     rbp, rsp
    mov     r8, [rdi+catch_list]     ; handler array
    mov     r9, [rdi+catch_count]
    xor     rcx, rcx
.scan:
    cmp     rcx, r9
    jae     .no_handler
    mov     rax, [r8 + rcx*8]        ; handler
    cmp     [rax+errcode_field], esi
    je      .found
    inc     rcx
    jmp     .scan
.found:
    call    [rax+handler_fn]         ; execute handler block
    mov     rax, 0
    leave
    ret
.no_handler:
    mov     rax, -1                  ; propagate
    leave
    ret
```

---

## X. COMPLETE SAMPLE PROGRAM

```ko
**Import**($Random)@also%~random!`global`:random
**Import**($Os)@also%~os!`global`:os
**Import**($Website)@also%~web!`global`:web

init_system_logs() [
    <printf>^("=== .KO SYSTEM INITIALIZATION ===\n")
    <$os>("log.txt")~log_file
    <$web>domain("mygame.com")@app_server
    <$web>("https://api.mygame.com/status")
    <return>(\True\)
]

safe_divide(int~dividend, int~divisor) [
    int(dividend / divisor)~result
    int(dividend % divisor)~remainder
    <printf>^("Quotient: {result}, Remainder: {remainder}\n")
    <return>(result)

    <catch>(`DivideByZeroError`) [
        <printf>^("Division by zero error!\n")
        <return>(0)
    ]
]

calculate_crit_damage(int~base_dmg, int~bonus_dmg) [
    int((base_dmg + bonus_dmg) * 2)~crit_dmg
    <return>(crit_dmg)
]

<catch>(`SystemException`) [
    <printf>^("General system error!\n")
    <return>(-1)
]

Hero !class [
    @private [
        string("")~name
        int(100)~hp
        ('Sword', 'Shield', 'Potion')~inventory

        setup_player() [
            <input>("Enter name: \n")&=name
            <printf>^("Welcome {name}!\n")
            <return>(name)
        ]

        use_random_item() [
            int(<len>^(inventory))~inv_len
            int(<$random>(0, inv_len - 1))~item_index
            <printf>^("Used: {inventory<{item_index}>}\n")
            <return>(inventory<{item_index}>)
        ]

        check_status() [
            <if>(hp >= 80 && hp <= 100) [
                <printf>^("Status: Very healthy\n")
            ]
            <elif>(hp >= 30 %% hp < 80) [
                <printf>^("Status: Normal\n")
            ]
            <else> [
                <printf>^("Status: Dangerous!\n")
            ]
            <return>(hp)
        ]
    ]
]

[
    booling(~init_system_logs())~is_ready

    ~Hero~p1
    string($p1~setup_player())~player_name

    byte("A")~binary_char
    bytes(8)~hex_buffer
    <printf>^("Binary char: {binary_char}\n")

    int(<len>^("Hello .ko\n"))~str_len
    int(<len>^(hex_buffer))~buf_len
    <printf>^("String length: {str_len}, Buffer size: {buf_len}\n")

    <encode(`UTF-8`)>^("Direct UTF-8 encoding\n")
    bytes(<encode(`ASCII`)>^("Hello .ko"))~asc_bytes
    int(<len>^(asc_bytes))~encoded_len
    <printf>^("ASCII encoding length: {encoded_len}\n")

    int(~safe_divide(100, 0))~calc_test
    <printf>^("Safe division check: {calc_test}\n")

    **Loop** <for>(~i=1(2)&=5) [
        <printf>^("--- Turn {i} ---\n")
        string($p1~use_random_item())~used_item
    ]

    int($p1~check_status())~current_hp
    int(~calculate_crit_damage(50, 10))~final_strike
    <printf>^("Critical damage dealt: {final_strike}\n")

    int(999)~temp_data
    <printf>^("Memory address: {<memory>^temp_data}\n")
    <memory>dete(temp_data)

    <catch>(`GlobalError`) [
        <printf>^("Caught exception in Main at line {error<"line">}: {error<"code">\n}")
    ]
]
```

---

## XI. CURRENT IMPLEMENTATION STATUS

### Implemented

- [x] Full Lexer
- [x] Expression and statement Parser
- [x] AST representation
- [x] VM execution engine
- [x] Variable declaration and assignment
- [x] Arithmetic and logical expressions
- [x] Flow control (if/elif/else)
- [x] System tags: printf, input, len, encode, memory, now
- [x] Class declarations
- [x] Exception handling (catch)
- [x] Instant mutation (<now>)
- [x] Import statement with scope registration
- [x] Function definition and call
- [x] Loops (for/while)
- [x] Method calls on class instances
- [x] Index access operators
- [x] Return statement
- [x] String interpolation in printf
- [x] Bytes buffer allocation
- [x] `ko -install` with Module Store REST API
- [x] `ko -list` - List all libraries (POST runQuery)
- [x] `ko -search` - Search libraries
- [x] Git clone and zip inspection
- [x] Multi-language compile/link pipeline (assembly modules)
- [x] Scope registration (file-based)
- [x] Complete import.asm subsystem with HTTP client, git clone, zip inspection, assemble/link
- [x] loop.asm loop optimization engine
- [x] API Server (api_server.asm) for Module Store

### Not Yet Implemented

- [ ] Runtime module loading (import.asm integration into VM)
- [ ] Default standard library (stdlib)
- [ ] loop.asm integration into VM
- [ ] ABI bridge between VM and native libraries
- [ ] Bytecode backend wired into execution pipeline
- [ ] Token source positions and multi-error diagnostics
- [ ] Dict literals and `bytes(<expr>)`
- [ ] Method call arguments and method access without call
- [ ] Second `<input>` in one program
- [ ] Generics / type parameters (`@girc(T)`)
- [ ] Shell completion verification for zsh/fish

### Known Sync Notes

- Spec previously overstated Import/Loop integration; those remain open issues.
- Leaked Firestore API key removed from this document; Module Store now uses `https://ko-lang.ai.studio/api/module` without API key.

---

## XII. SYNTAX SUMMARY

```
program         -> statement*
statement       -> var_decl | func_decl | class_decl | if_stmt | catch_stmt | expr
var_decl        -> type '(' expr ')' '~' identifier
type            -> 'int' | 'freal' | 'string' | 'booling' | 'byte' | 'bytes'
func_decl       -> identifier '(' param_list? ')' '[' statement* ']'
param_list      -> param (',' param)*
param           -> type '~' identifier
class_decl      -> 'class' identifier '[' class_body ']'
class_body      -> ( '@private' '[' statement* ']' )* statement*
if_stmt         -> '<' 'if' '>' '(' expr ')' '[' statement* ']'
elif_stmt       -> '<' 'elif' '>' '(' expr ')' '[' statement* ']'
else_stmt       -> '<' 'else> '[' statement* ']'
catch_stmt      -> '<' 'catch' '>' '(' error_type ')' '[' statement* ']'
error_type      -> '`' identifier '`'
expr            -> or_expr
or_expr         -> and_expr ('%%' and_expr)*
and_expr        -> equality_expr ('&&' equality_expr)*
equality_expr   -> relational_expr ('==' | '!=' relational_expr)*
relational_expr -> add_expr ('<' | '>' add_expr)*
add_expr        -> mul_expr ('+' | '-' mul_expr)*
mul_expr        -> unary_expr ('*' | '/' | '%' unary_expr)*
unary_expr      -> '-' unary_expr | primary_expr
primary_expr    -> identifier | literal | '(' expr ')' | system_tag | func_call
literal         -> INT | FLOAT | STRING | '\\True\\' | '\\False\\'
system_tag      -> '<' identifier '>' '^' '(' expr ')'
func_call       -> identifier '(' arg_list? ')'
arg_list        -> expr (',' expr)*
priority_stmt   -> '{' NUMBER '}' statement ;
NUMBER          -> [0-9]+ ;
```

---

## XIII. PROCESS MANAGER VISIBILITY

When executing a `.ko` file, the runtime exposes the current execution process in the process manager using the format:

```
file:main-function
```

**Examples:**

```
test.ko:main
test.ko:main-test_func
```

This allows external tools and debuggers to track which file, main block, or function is currently executing.

---

## XIV. PRIORITY ORDER SYNTAX

Statements can be prefixed with a priority number in curly braces `{number}` to control execution order. Lower numbers execute first.

**Examples:**

```ko
{1}<print>string^("test")
{0} <printf>^("hello")
```

In the example above, `{0} <printf>^("hello")` runs before `{1}<print>string^("test")` because `0` has higher priority.

**Priority rules:**

- Statements without an explicit priority default to priority `0`.
- When multiple statements share the same priority, their relative order follows source order.
- Priority affects statement scheduling within the same block scope.

**NASM-level scheduling:**

```nasm
; priority scheduler: bucket statements by priority key
; input: array of Stmt* with .priority field
; output: ordered execution list
    ; sort by priority asc, then source_index asc  (stable sort, O(n log n))
    ; dispatch:
    ; for each stmt in ordered_list:
    ;     call exec_stmt(stmt)
```

---

## XV. GENERICS (TYPE PARAMETERS) (FUTURE EXTENSION — NOT IMPLEMENTED)

> Status: not implemented in the compiler source. Syntax is reserved for future work.

### 1. Declaration

A generic function is declared by attaching a type-parameter clause to a function definition. `@girc(T)` introduces `T` as a type parameter for the following function:

```ko
@girc(T)
identity(T~value) [
    <return>(value)
]
```

`T` is a type-level parameter, not a runtime value. It ranges over valid `.ko` types (primitive or composite) as permitted by the call context.

### 2. Usage

```ko
int(~identity(100))~number
string(~identity("Phong"))~name
```

The concrete type is supplied by the surrounding type context or inferred from the argument. The compiler must derive `T` from either:

1. An explicit expected type at the call site (for example `int(...)` or `string(...)`), or
2. The static type of the argument passed to the generic parameter.

### 3. Type Rules

- The return value of a generic function must have a type compatible with the inferred type parameter `T`.
- If `T` cannot be inferred unambiguously from the call site and its arguments, compilation fails with a type error.
- A generic function may be instantiated (monomorphized) once per distinct concrete type; the implementation may defer this to compile time or runtime, but observable typing must follow the rules above.
- Type compatibility follows the standard `.ko` assignment rules: a value of type `T` may be returned where `T` is expected, and no implicit conversion beyond the language's defined conversions is permitted.

---

## XVI. COMPILER EXECUTION MODEL: HOW EACH STATEMENT IS RUN

This section defines **how the compiler processes each statement** through a normalized pipeline, independent of repository layout.

### 1. Standard Pipeline (Conductor)

$$\text{Source} \xrightarrow{\text{Lex}} \text{TokenStream} \xrightarrow{\text{Parse}} \text{AST} \xrightarrow{\text{Resolve}} \text{TypedAST} \xrightarrow{\text{Lower}} \text{IR} \xrightarrow{\text{Opt}} \text{IR}' \xrightarrow{\text{Dispatch}} \text{EngineTarget} \xrightarrow{\text{Exec}} \text{State}'$$

Phases:

1. **Lexical Analysis** — split source into tokens per the symbol table (Sigil, System Tag, Comment, Escape).
2. **Parsing** — build AST per EBNF and priority rules `{n}`.
3. **Scope Resolution** — register identifiers into the Scope Table per scope tag.
4. **Type Checking** — infer types, check compatibility, handle generics (future).
5. **Lowering** — lower AST to canonical IR.
6. **Optimization** — optimize IR (loops delegated to `loop.asm`).
7. **Dispatch** — choose EngineTarget (Import / Loop / Runtime).
8. **Execution** — execute and update state.

### 2. Processing per Statement Type

| Statement Type | Processing Phase | EngineTarget | Notes |
|----------------|------------------|--------------|-------|
| `VarDecl` | Parse → Resolve → TypeCheck → Lower | Runtime VM | Allocate cell, register scope |
| `Assignment` (`<now>`) | TypeCheck → Lower | Runtime VM | Instant state mutation |
| `FuncDecl` | Resolve → Lower | Runtime VM | Register function, defer body |
| `ClassDecl` | Resolve → Lower | Runtime VM | Create class blueprint, members per `@private` |
| `If/Elif/Else` | TypeCheck → Lower (branch) | Runtime VM | Evaluate condition, select branch |
| `Loop` (`**Loop**`) | TypeCheck → Lower → Opt | **loop.asm** | CPU-level loop optimization |
| `Import` (`**Import**`) | Resolve → Lower | **import.asm** | Load module, update Scope Table |
| `Catch` | Resolve → Lower (handler) | Runtime VM | Scan errors by scope |
| `System Tag` (`<printf>`, `<input>`, `<len>`, `<encode>`, `<memory>`) | Lower → Dispatch | Runtime VM / Native | I/O, encoding, memory |
| `Return` | Lower | Runtime VM | Exit function, return value |
| `Priority Stmt` `{n}` | Parse → Schedule | Runtime VM | Schedule by priority |

### 3. EngineTarget Dispatch Rules

- If the statement is `Loop`, the entire loop block is packaged as IR and handed to `loop.asm` for unroll/optimization; the resulting state delta is returned to the VM.
- If the statement is `Import`, the entire module-loading process is handed to `import.asm`; new identifiers are inserted into the Scope Table.
- All other statements are executed by the Runtime VM.

### 4. Error Handling in the Pipeline

- Syntax errors: stop at Parse, report token position.
- Type errors: stop at TypeCheck.
- Runtime errors: trigger `<catch>` mechanism per scope.
- Import/Loop errors: propagate standardized error codes to the VM.

---

## XVII. OPTIMAL ALGORITHMIC FILE STRUCTURE AND CROSS-LANGUAGE DATA EXCHANGE

This section defines the **optimal algorithmic file structure** and the **powerful data-exchange
mechanism** among the assembly tiers (Frontend / Middleware / Backend), independent of the
current repository layout.

### 1. Optimal Algorithmic File Structure (Normalized)

Every `.ko` file follows the standard layout:

```
[SECTION A] Import Declarations
[SECTION B] Function Declarations
[SECTION C] Class Declarations
[SECTION D] Global Exception Handlers (catch)
[SECTION E] Main Execution Block [ ... ]
```

Rules:

- Imports appear only in SECTION A (global scope).
- Function/class declarations in SECTION B/C.
- Exactly one main block in SECTION E.
- Free execution statements outside function/class/main block are invalid.

### 2. Multi-Tier Architecture

```
┌──────────────────────────────────────────────────────┐
│                 FRONTEND TIER (assembly)             │
│   Lexical Analysis -> Parsing -> Concrete AST        │
└──────────────────────────┬───────────────────────────┘
                           │ [IPC / Protocol Serialization]
                           ▼
┌──────────────────────────────────────────────────────┐
│                 MIDDLEWARE ENGINE (assembly)         │
│   Semantic Analysis -> Symbol Table -> Optimizations │
└──────────────────────────┬───────────────────────────┘
                           │ [Direct C-ABI Binding]
                           ▼
┌──────────────────────────────────────────────────────┐
│                  BACKEND RUNTIME (assembly)         │
│   Memory Safety Management -> Native Backend CodeGen │
└──────────────────────────────────────────────────────┘
```

- **Frontend Tier:** Lexer, Parser, AST, diagnostic/GUI tooling. Assembly-level, modular. Decouples error reporting from AST mutation. Serializes via file descriptors or high-speed IPC.
- **Middleware Tier:** Middle-end, SSA, HIR/LIR, global symbol table. Assembly-level. Smart ownership via explicit allocator handles. Avoid undefined behavior.
- **Backend Tier:** Backend codegen, arena allocators, runtime memory protection, native ABI bridging. Explicit allocator passing. Static optimization via `comptime`-equivalent macros. Clean native output.

Known exception: `testing/mod_check.c` is an independent C binary intentionally linking `libdl`, used to verify ABI of `.so` modules without pulling `libdl` into assembly test binaries. It is a testing tool, not part of compiler runtime.

### 3. Cross-Tier Data Exchange (Powerful Mechanism)

#### 3.1 Canonical Data Exchange Layer (CDEL)

All data crossing tier boundaries must pass through **CDEL**, a normalized binary format:

- **Frame:** `[Magic(4)] [Version(2)] [TypeTag(2)] [Length(4)] [Payload(Length)] [CRC32(4)]`
- **Endianness:** Little-endian.
- **String encoding:** UTF-8, length-prefixed.
- **Versioning:** Schema version increments; backward compatibility via "ignore unknown fields".

**CDEL frame byte layout (memory map):**

```
Offset  Size  Field
0       4     Magic        = 0x4344454C ('CDEL')
4       2     Version      (u16)
6       2     TypeTag      (u16)  see TypeTag table
8       4     Length       (u32)  payload byte count
12      N     Payload      (N bytes)
12+N    4     CRC32        (IEEE 802.3, over bytes 0..12+N-1)
Total frame size = 16 + N
```

**TypeTag table:**

| Tag | Value | Meaning |
|-----|-------|---------|
| `AST_NODE` | 0x0001 | AST node payload |
| `IR_BLOCK` | 0x0002 | IR block payload |
| `SYMBOL_ENTRY` | 0x0003 | Symbol table entry |
| `VALUE` | 0x0004 | Runtime value |
| `ERROR_FRAME` | 0x0005 | Error propagation frame |
| `MODULE_META` | 0x0006 | import.asm module metadata |
| `LOOP_IR` | 0x0007 | loop.asm loop IR block |

#### 3.2 Type Mapping

| `.ko` Type | Frontend | Middleware | Backend |
|------------|----------|------------|---------|
| `int` (i64) | `i64` | `i64` | `i64` |
| `freal` (f64) | `f64` | `f64` | `f64` |
| `string` | `ptr+len` | `ptr+len` | `ptr+len` |
| `booling` | `u8` | `u8` | `u8` |
| `byte` | `u8` | `u8` | `u8` |
| `bytes` | `ptr+len` | `ptr+len` | `ptr+len` |
| `Null` | empty optional | empty optional | empty optional |
| `None` | immutable sentinel | immutable sentinel | immutable sentinel |
| Tuple/List | `ptr+len` | `ptr+len` | `ptr+len` |
| Dict | hashmap handle | hashmap handle | hashmap handle |

#### 3.3 Ownership & Memory Rules

- **Backend → Middleware/Frontend:** Backend owns original memory via arena; pass `ptr + length`; receiver must NOT free. Lifetime tied to arena scope.
- **Middleware → Backend:** Middleware allocates via allocator provided by Backend (callback allocator); or passes handle (opaque pointer).
- **Frontend → Middleware:** Frontend allocates off-heap (direct buffer) or passes reference; Middleware accesses via pointer + length, does not free Frontend heap.
- **Principle:** No raw `malloc/free` in Middleware; use arena/smart handles. No hidden global memory state in Backend.

#### 3.4 ABI Bridge

- **Backend ↔ Middleware:** Direct C-ABI binding. Backend exports `export` symbols with C calling convention; Middleware declares `extern`. Structs passed with C-layout (explicit padding); both sides agree on layout.
- **Middleware ↔ Frontend:** JNI-equivalent or IPC. Frontend calls native method; Middleware provides context. Alternatively IPC via socket/pipe with CDEL frames.
- **Frontend ↔ Backend (indirect):** Via Middleware or direct ABI if Backend exports C-ABI.

#### 3.5 Error Propagation Across Boundaries

- **Backend:** Uses error code `i32` + out-parameter.
- **Middleware:** Uses error code; at ABI boundary converts to error code.
- **Frontend:** Converts error code into typed `Exception`.
- **Rule:** Never swallow errors (empty catch forbidden). All errors propagate via CDEL error frame.

#### 3.6 AST/IR Serialization (Schema Versioning)

- AST/IR serialized via CDEL frames with dedicated TypeTags (`AST_NODE`, `IR_BLOCK`, `SYMBOL_ENTRY`).
- Frontend serializes AST → CDEL → Middleware deserializes → semantic check → serializes IR → Backend deserializes → codegen.
- CRC32 checksum ensures integrity.

#### 3.7 Performance & Exchange Optimization

- Zero-copy where possible (shared memory / mmap).
- Batch symbol entries into a single frame.
- Optional payload compression for large modules.
- Cache digest of loaded modules to avoid re-parsing.

### 4. Roles of `import.asm` and `loop.asm` in Data Exchange

- **`import.asm`:** Entry point at the Frontend boundary. Performs HTTP (Module Store REST API), git clone, zip inspection, assembles/loads module, serializes metadata into CDEL frame, sends down to Middleware to update Scope Table.
- **`loop.asm`:** Entry point at the Middleware boundary. Receives loop IR block from Middleware, optimizes (unroll, register allocation, cache line), executes natively, returns state delta to Backend runtime via ABI.

---

## XVIII. FUTURE DIRECTION

- Full runtime module loading (import.asm ↔ VM).
- loop.asm integration into VM.
- ABI bridge between VM and native libraries.
- Bytecode backend wired into execution pipeline.
- Token source positions and multi-error diagnostics.
- Dict literals and `bytes(<expr>)` support.
- Method calls with arguments and method access without call.
- Second `<input>` in one program.
- Generics / type parameters (`@girc(T)`).
- Shell completion verification for zsh/fish.
- Data-exchange optimization: shared memory, zero-copy, compression.
- IR standardization and schema versioning for long-term compatibility.

---

## XIX. COMPLIANCE NOTES

- No raw `malloc/free` in the Middleware tier.
- No swallowed errors in Backend loops.
- No modifications without reviewing latest execution state.
- Technical documentation follows project language policy.

---

## XX. FULL DIRECTORY / FILE LAYOUT (OPTIMAL)

```
compiler_ko/
├── frontend/                          # assembly tier
│   ├── src/
│   │   ├── lexer.asm
│   │   ├── parser.asm
│   │   ├── ast.asm
│   │   ├── import.asm                # module import subsystem (entry)
│   │   └── main.asm
│   └── build.asm / Makefile.asm
├── middleware/                        # assembly tier
│   ├── include/ko/
│   │   ├── cdel.inc
│   │   ├── value.inc
│   │   └── abi.inc
│   ├── src/
│   │   ├── semantic/
│   │   ├── optimizer/
│   │   ├── symbol_table.asm
│   │   └── loop.asm                   # loop engine (entry)
│   └── Makefile.asm
├── backend/                           # assembly tier
│   ├── src/
│   │   ├── main.asm
│   │   ├── lexer.asm
│   │   ├── parser.asm
│   │   ├── ast.asm
│   │   ├── vm.asm
│   │   ├── value.asm
│   │   ├── compiler.asm
│   │   ├── bytecode.asm
│   │   ├── builtins.asm
│   │   ├── installer.asm
│   │   └── module/
│   ├── build.asm
│   └── build.asm.zon
├── core/                              # shared definitions
│   ├── cdel_schema.json
│   └── type_map.inc
├── testing/
│   └── mod_check.c                    # independent C binary, links libdl
├── docs/
│   ├── SPECIFICATION.md
│   └── agents/
├── MEMORY.md
└── CHECKPOINTS.md
```

---

## XXI. REGISTER MAP (x86-64 System V AMD64 ABI)

### General-purpose registers (VM interpreter)

| Register | Role | Callee-saved? |
|----------|------|---------------|
| `rax` | scratch / return value | no |
| `rbx` | eval stack pointer base (callee-saved) | yes |
| `rcx` | scratch / counter | no |
| `rdx` | scratch / 2nd arg | no |
| `rsi` | 2nd arg | no |
| `rdi` | 1st arg | no |
| `rbp` | frame base | yes |
| `rsp` | stack pointer | yes (implicit) |
| `r8`–`r11` | scratch | no |
| `r12` | VM context ptr (callee-saved) | yes |
| `r13` | current scope ptr (callee-saved) | yes |
| `r14` | arena allocator ptr (callee-saved) | yes |
| `r15` | GPA allocator ptr (callee-saved) | yes |

### loop.asm hot registers

| Register | Role |
|----------|------|
| `rcx` | loop counter |
| `rdx` | body IR ptr |
| `r8` | iteration limit |
| `r9` | stride |

### Floating point / SIMD

| Register | Role |
|----------|------|
| `xmm0`–`xmm3` | scratch / float args/returns |
| `xmm4`–`xmm15` | caller-saved scratch |

---

## XXII. MEMORY MAP

### VM process address space (logical)

```
0x0000_0000_0000_0000  ┌────────────────────────────┐
                        │ (unmapped, guard)          │
0x0000_0040_0000        ├────────────────────────────┤
                        │ code segment (.text)       │  loop.asm, backend
0x0000_0060_0000        ├────────────────────────────┤
                        │ data segment (.data/.bss)  │
0x0000_1000_0000        ├────────────────────────────┤
                        │ heap (GPA-managed Values)  │  grows up
                        │   ClassInstance, strings,  │
                        │   lists, dicts             │
0x0000_7000_0000        ├────────────────────────────┤
                        │ arena (parse-time)         │  bulk freed
0x0000_7fff_0000        ├────────────────────────────┤
                        │ eval stack (VM)            │  grows down
0x0000_7fff_f000        ├────────────────────────────┤
                        │ (guard page)               │
0x0000_7fff_ffff_ffff   └────────────────────────────┘
```

### Value heap object layout

```
struc StringObj
    .len:  resq 1
    .data: resq 1
endstruc          ; 16 bytes
struc ListObj
    .cap:  resq 1
    .len:  resq 1
    .data: resq 1
endstruc          ; 24 bytes
; DictObj: hashmap handle (opaque)
; ClassObj: class_id, nfields, fields[]
```

### Arena layout

```
struc Arena
    .base: resq 1
    .used: resq 1
    .cap:  resq 1
endstruc
; alloc: base+used, used += size (aligned 8)
; free all: used = 0  (O(1))
```

---

## XXIII. INSTRUCTION ENCODING (BYTECODE)

Optional backend lowers AST to a compact instruction stream. Opcodes 0..12 for binary ops.

| Opcode | Mnemonic | Operand | Effect |
|--------|----------|---------|--------|
| 0 | `NOP` | none | no-op |
| 1 | `PUSH_CONST` | u32 const_idx | push constants[const_idx] |
| 2 | `PUSH_VAR` | u32 slot | push locals[slot] |
| 3 | `POP_VAR` | u32 slot | pop -> locals[slot] |
| 4 | `ADD` | none | pop b,a; push a+b |
| 5 | `SUB` | none | pop b,a; push a-b |
| 6 | `MUL` | none | pop b,a; push a*b |
| 7 | `DIV` | none | pop b,a; push a/b (DivideByZeroError on 0) |
| 8 | `REM` | none | pop b,a; push a%b |
| 9 | `EQ` | none | pop b,a; push a==b |
| 10 | `LT` | none | pop b,a; push a<b |
| 11 | `GT` | none | pop b,a; push a>b |
| 12 | `CALL` | u32 fn_idx, u8 argc | call functions[fn_idx] |
| 13 | `RET` | none | return top of stack |
| 14 | `JMP` | i32 offset | pc += offset |
| 15 | `JZ` | i32 offset | if top==0 (falsy) pc += offset |
| 16 | `PRINT` | none | pop and print interpolated |
| 17 | `HALT` | none | stop execution |

**Instruction word layout (32-bit fixed):**

```
bits 31..24: opcode (8)
bits 23..0 : operand (24)  [or two operands packed for CALL]
```

**binaryOp dispatch (assembly):**

```nasm
; binaryOp(op, a, b) -> Value
; al = op, rdi = a ptr, rsi = b ptr
binaryOp:
    cmp     al, 4
    je      do_add
    cmp     al, 5
    je      do_sub
    cmp     al, 6
    je      do_mul
    cmp     al, 7
    je      do_div
    cmp     al, 8
    je      do_rem
    cmp     al, 9
    je      do_eq
    cmp     al, 10
    je      do_lt
    cmp     al, 11
    je      do_gt
    mov     rax, ERR_INVALIDOPCODE
    ret
do_add:
    ; add(a,b)
    ret
do_sub:
    ; sub(a,b)
    ret
do_mul:
    ; mul(a,b)
    ret
do_div:
    ; div(a,b)
    ret
do_rem:
    ; rem(a,b)
    ret
do_eq:
    ; equals(a,b)
    ret
do_lt:
    ; less(a,b)
    ret
do_gt:
    ; greater(a,b)
    ret
```

---

## XXIV. ABI (CALLING CONVENTIONS)

### Backend ↔ Middleware (C-ABI)

- Backend exports: `export` symbol with C calling convention.
- Middleware declares: `extern` symbol.
- Structs: C layout with explicit padding; both sides agree on layout.
- Error returns: Backend returns `i32` error code + out-parameter.

### Middleware ↔ Frontend (IPC)

- Frontend declares native method.
- Middleware implements handler.
- Pass context pointer as first arg; obtain callback handle for callbacks.
- Strings: UTF-8 `ptr+len`.
- Arrays: `ptr+len`.

### import.asm ↔ middleware (CDEL over IPC)

- IPC channel: Unix domain socket or named pipe; framing via CDEL.
- import.asm writes CDEL frame → middleware reads → updates scope table → writes ACK frame.

### loop.asm ↔ Backend runtime (direct call)

- Backend calls `loop_exec(ir, len, state)`.
- loop.asm returns 0 on success, negative error code on failure.
- State delta written into `state` by loop.asm.

### Error code table

| Code | Name | Meaning |
|------|------|---------|
| 0 | OK | success |
| -1 | ERR_GENERIC | unspecified |
| -2 | ERR_BAD_MAGIC | bad CDEL magic |
| -3 | ERR_TYPE | type mismatch |
| -4 | ERR_INDEX | out of range |
| -5 | ERR_KEY | missing key |
| -6 | ERR_OVERFLOW | integer overflow |
| -7 | ERR_DIVZERO | division by zero |
| -8 | ERR_NULL | null usage |
| -9 | ERR_UNASSIGNED | unassigned null |
| -10 | ERR_NOTFOUND | module not found |

---

## XXV. COMPLIANCE NOTES (ASM-LEVEL)

- No raw `malloc/free` in Middleware tier; use arenas/handles.
- No swallowed errors in Backend loops; propagate via error codes.
- All cross-tier data via CDEL frames with CRC32.
- Register/memory maps are authoritative for ABI; changes require spec update.
- Technical documentation follows project language policy.

---

*End of specification.*
