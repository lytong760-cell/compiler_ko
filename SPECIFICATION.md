# .ko Language Formal Technical Specification & Architectural Manual

> This document is the normalized specification of the `.ko` language and its multi-tier compiler architecture (Zig / C++ / Java).  
> Goal: future-oriented, independent of the current repository layout. Only two runtime components are named explicitly: `Import.java` and `Loop.cpp`.

---

## I. RUNTIME ARCHITECTURE & ENGINE TARGET MAPPING

The `.ko` language operates on a **Hybrid Execution Target Engine** model.

The central compiler/interpreter (the conductor) receives source code, parses it, and dispatches work to specialized subcontractors underneath for execution.

### 1. Mathematical Pipeline Model and Execution Diagram

$$\mathcal{P}: \text{SourceCode}_{.ko} \xrightarrow{\text{Lexer/Parser}} \text{AST} \xrightarrow{\text{ScopeResolver}} \text{EngineTarget} \xrightarrow{\text{Execution}} \text{State}'$$

```
+-------------------------------------------------------------------+
|                     High-Level Source Code (.ko)                   |
+-------------------------------------------------------------------+
                                   |
                                   v
+-------------------------------------------------------------------+
|        Abstract Syntax Analysis (Conductor / Compiler Core)        |
+-------------------------------------------------------------------+
                    /                                   \
                   /                                     \
                  v                                       v
+--------------------------+           +----------------------------+
|   Subsystem Import Engine|           |    Subsystem Loop Engine   |
|      (Import.java)       |           |         (Loop.cpp)         |
+--------------------------+           +----------------------------+
| - Dynamic Path Resolution|           | - Low-level Loop Unrolling |
| - Scope Table Ingestion  |           | - Cache Line Optimization  |
| - Module Signature Check |           | - CPU Counter Registers    |
+--------------------------+           +----------------------------+
```

### 2. Mapping Special Keywords to System Execution Files

#### A. Module Import Library: Import Subsystem Target

- **Language Directive:** `Import`
- **Responsible Source Files:** `Import.java` + installer layer
- **Simple Explanation:** Think of `Import.java` as a "Librarian". When you use the `Import` keyword or the `ko -install` command, the Java librarian finds the library package, verifies its validity, compiles it, and places it in your workspace.

**Mathematical & Technical Semantics:**

$$\text{Import}_{\text{subsystem}}: \text{ModuleName} \times \text{ScopeTag} \to \mathcal{S}_{\text{updated\_scope\_table}}$$

- Dynamic file path resolution
- Source code signature verification
- Dynamic classloading and insertion of identifiers into the Scope Table

#### B. High-Performance Loop Engine: Loop Subsystem Target

- **Language Directive:** `Loop`
- **Responsible Source File:** `Loop.cpp`
- **Simple Explanation:** Think of `Loop.cpp` as an "F1 Racing Car". Repeating an action millions of times is handed off to C++ code running directly at the CPU hardware level.

**Mathematical & Technical Semantics:**

$$\text{Loop}_{\text{subsystem}}: \text{IterCondition} \times \text{BodyBlock} \xrightarrow{\text{Native C++}} \Delta \text{State}$$

- CPU hardware register allocation and optimization
- Bypassing interpreter overhead, instruction cache line optimization

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

### 2. Composite Data Structures

- Tuple / Number array: `(1, 2)~a`
- String array: `('a', 'b')~b`
- Nested list: `(1('a', 'b'))~list`
- Dictionary: `(1{'a'})~dic`

### 3. Null and None Types

- **Null** is a temporary placeholder variable that has not yet been assigned a value:

```ko
()~var
```

- A null variable may later be assigned any compatible value using `<now>`:

```ko
<now>(value)>var
```

- **None** is an immutable empty value that cannot be reassigned to another value:

```ko
none~a
```

### 4. Index Access Syntax

```ko
list<0>           | Get first element
list<1<0>>        | Get element 0 in sub-list at position 1
dic{1{'a'}}       | Get by Dictionary Key
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

### 2. Main Execution Block

Every standalone `.ko` file must have exactly one Main Block `[ ]`.

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

- **Module Store URL:** `https://ko-vietnam.ai.studio/mobule-store`
- **Firestore REST API Endpoints:**

**POST - List All Libraries:**

```
POST https://firestore.googleapis.com/v1/projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents:runQuery?key=YOUR_API_KEY
Content-Type: application/json

{
  "parent": "projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents",
  "query": {
    "from": [{"collectionId": "libraries"}]
  }
}
```

**GET - Load Specific Library:**

```
GET https://firestore.googleapis.com/v1/projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents/libraries/<library>?key=YOUR_API_KEY
```

#### C. Automatic Processing Flow

```
+-----------------------------------------------------------------------------------+
| 1. Terminal Call: ko -install "<Library>"                                         |
+-----------------------------------------------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------+
| 2. Firestore GET API Query:                                                       |
|    GET /documents/libraries/<library>?key=...                                     |
|    -> Retrieve Metadata & GitHub Repository link of the library                  |
+-----------------------------------------------------------------------------------+
                                           |
                                           v
+-----------------------------------------------------------------------------------+
| 3. Subsystem Import.java performs `git clone` of entire Repo                     |
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

- [x] FullLexer
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
- [x] `ko -install` with Firestore API
- [x] `ko -list` - List all libraries (POST runQuery)
- [x] `ko -search` - Search libraries
- [x] Git clone and zip inspection
- [x] Multi-language compile/link pipeline (Java, C, C++, Zig, Node.js, .ko)
- [x] Scope registration (file-based)
- [x] Complete Import.java subsystem with HTTP client, git clone, zip inspection, compile/link
- [x] Loop.cpp loop optimization engine
- [x] API Server (api_server.py) for Module Store

### Not Yet Implemented

- [ ] Runtime module loading (Import.java integration into Zig VM)
- [ ] Default standard library (stdlib)
- [ ] Loop.cpp integration into Zig VM
- [ ] JNI/JNA bridge between Zig VM and native libraries
- [ ] Bytecode backend wired into execution pipeline
- [ ] Token source positions and multi-error diagnostics
- [ ] Dict literals and `bytes(<expr>)`
- [ ] Method call arguments and method access without call
- [ ] Second `<input>` in one program
- [ ] Generics / type parameters (`@girc(T)`)
- [ ] Shell completion verification for zsh/fish

### Known Sync Notes

- Spec previously overstated Import/Loop integration; those remain open issues.
- Leaked Firestore API key removed from this document; use `KO_FIRESTORE_API_KEY`.

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
6. **Optimization** — optimize IR (loops delegated to `Loop.cpp`).
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
| `Loop` (`**Loop**`) | TypeCheck → Lower → Opt | **Loop.cpp** | CPU-level loop optimization |
| `Import` (`**Import**`) | Resolve → Lower | **Import.java** | Load module, update Scope Table |
| `Catch` | Resolve → Lower (handler) | Runtime VM | Scan errors by scope |
| `System Tag` (`<printf>`, `<input>`, `<len>`, `<encode>`, `<memory>`) | Lower → Dispatch | Runtime VM / Native | I/O, encoding, memory |
| `Return` | Lower | Runtime VM | Exit function, return value |
| `Priority Stmt` `{n}` | Parse → Schedule | Runtime VM | Schedule by priority |

### 3. EngineTarget Dispatch Rules

- If the statement is `Loop`, the entire loop block is packaged as IR and handed to `Loop.cpp` for unroll/optimization; the resulting state delta is returned to the VM.
- If the statement is `Import`, the entire module-loading process is handed to `Import.java`; new identifiers are inserted into the Scope Table.
- All other statements are executed by the Runtime VM.

### 4. Error Handling in the Pipeline

- Syntax errors: stop at Parse, report token position.
- Type errors: stop at TypeCheck.
- Runtime errors: trigger `<catch>` mechanism per scope.
- Import/Loop errors: propagate standardized error codes to the VM.

---

## XVII. OPTIMAL ALGORITHMIC FILE STRUCTURE AND CROSS-LANGUAGE DATA EXCHANGE

This section defines the **optimal algorithmic file structure** and the **powerful data-exchange mechanism** among the three tiers Java (Frontend) / C++ (Middleware) / Zig (Backend), independent of the current repository layout.

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

### 2. Multi-Language Architecture Tiers

```
┌──────────────────────────────────────────────────────┐
│                 JAVA FRONTEND TIER                   │
│   Lexical Analysis -> Parsing -> Concrete AST        │
└──────────────────────────┬───────────────────────────┘
                           │ [IPC / Protocol Serialization]
                           ▼
┌──────────────────────────────────────────────────────┐
│                 C++ MIDDLEWARE ENGINE                │
│   Semantic Analysis -> Symbol Table -> Optimizations │
└──────────────────────────┬───────────────────────────┘
                           │ [Direct C-ABI Binding]
                           ▼
┌──────────────────────────────────────────────────────┐
│                  ZIG RUNTIME & CODES                │
│   Memory Safety Management -> Native Backend CodeGen │
└──────────────────────────────────────────────────────┘
```

- **Java Tier:** Lexer, Parser, AST, diagnostic/GUI tooling. Uses `java.base` modular patterns. Decouples error reporting from AST mutation. Serializes via file descriptors or high-speed IPC.
- **C++ Tier:** Middle-end, SSA, HIR/LIR, global symbol table. ISO C++17/C++20. STL smart pointers for ownership. Avoid undefined behavior.
- **Zig Tier:** Backend codegen, arena allocators, runtime memory protection, native C-ABI bridging. Explicit `std.mem.Allocator`. `comptime` for static optimization. Clean native output.

Known exception: `testing/mod_check.c` is an independent C binary intentionally linking `libdl`, used to verify ABI of `.so` modules without pulling `libdl` into Zig test binaries. It is a testing tool, not part of compiler runtime.

### 3. Cross-Language Data Exchange (Powerful Mechanism)

#### 3.1 Canonical Data Exchange Layer (CDEL)

All data crossing language boundaries must pass through **CDEL**, a normalized binary format:

- **Frame:** `[Magic(4)] [Version(2)] [TypeTag(2)] [Length(4)] [Payload(Length)] [CRC32(4)]`
- **Endianness:** Little-endian.
- **String encoding:** UTF-8, length-prefixed.
- **Versioning:** Schema version increments; backward compatibility via "ignore unknown fields".

#### 3.2 Type Mapping

| `.ko` Type | Java | C++ | Zig |
|------------|------|-----|-----|
| `int` (i64) | `long` | `int64_t` | `i64` |
| `freal` (f64) | `double` | `double` | `f64` |
| `string` | `String` (UTF-8) | `std::string` (UTF-8) | `[]const u8` |
| `booling` | `boolean` | `bool` | `bool` |
| `byte` | `byte` | `int8_t` / `uint8_t` | `u8` |
| `bytes` | `byte[]` | `std::vector<uint8_t>` | `[]u8` |
| `Null` | `null` reference | `std::optional<T>` empty | `null` (optional) |
| `None` | immutable sentinel | `std::monostate` | `void`/sentinel |
| Tuple/List | `List<Object>` | `std::vector<Variant>` | `std.ArrayList(Value)` |
| Dict | `Map<String,Object>` | `std::unordered_map<std::string,Variant>` | `std.StringHashMap(Value)` |

#### 3.3 Ownership & Memory Rules

- **Zig → C++/Java:** Zig owns original memory via arena; pass `[*]const u8` + length; receiver must NOT `free`. Lifetime tied to arena scope.
- **C++ → Zig:** C++ allocates via allocator provided by Zig (callback allocator); or passes `std::shared_ptr` via C-ABI handle (opaque pointer).
- **Java → C++:** Java allocates off-heap (direct ByteBuffer) or passes JNI reference; C++ accesses via pointer + length, does not free Java heap.
- **Principle:** No `malloc/free` in C++; use arena/smart pointers. No hidden global memory state in Zig.

#### 3.4 ABI Bridge

- **Zig ↔ C++:** Direct C-ABI binding. Zig exports `export fn` with `callconv(.C)`; C++ declares `extern "C"`. Structs passed with `extern struct` / `#[repr(C)]` layout.
- **C++ ↔ Java:** JNI or JNA. Java calls native method; C++ provides `JavaVM*` context. Alternatively IPC via socket/pipe with CDEL frames.
- **Java ↔ Zig (indirect):** Via C++ middleware or direct JNI if Zig exports C-ABI.

#### 3.5 Error Propagation Across Boundaries

- **Zig:** Uses error union `!T`; exports to C as error code `int32` + out-parameter.
- **C++:** Uses `std::expected<T, ErrorCode>` or exception; at C-ABI boundary converts to error code.
- **Java:** Converts error code into typed `Exception`.
- **Rule:** Never swallow errors (empty `_ = catch {}` forbidden). All errors propagate via CDEL error frame.

#### 3.6 AST/IR Serialization (Schema Versioning)

- AST/IR serialized via CDEL frames with dedicated TypeTags (`AST_NODE`, `IR_BLOCK`, `SYMBOL_ENTRY`).
- Java serializes AST → CDEL → C++ deserializes → semantic check → serializes IR → Zig deserializes → codegen.
- CRC32 checksum ensures integrity.

#### 3.7 Performance & Exchange Optimization

- Zero-copy where possible (shared memory / mmap).
- Batch symbol entries into a single frame.
- Optional payload compression for large modules (zstd).
- Cache digest of loaded modules to avoid re-parsing.

### 4. Roles of `Import.java` and `Loop.cpp` in Data Exchange

- **`Import.java`:** Entry point at the Java boundary. Performs HTTP (Firestore), git clone, zip inspection, compiles/loads module, serializes metadata into CDEL frame, sends down to C++ middleware to update Scope Table.
- **`Loop.cpp`:** Entry point at the C++ boundary. Receives loop IR block from middleware, optimizes (unroll, register allocation, cache line), executes natively, returns state delta to Zig runtime via C-ABI.

---

## XVIII. FUTURE DIRECTION

- Full runtime module loading (Import.java ↔ Zig VM).
- Loop.cpp integration into Zig VM.
- JNI/JNA bridge between Zig VM and native libraries.
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

- No `malloc/free` in the C++ tier.
- No swallowed errors in Zig loops.
- No modifications without reviewing latest execution state.
- Technical documentation follows project language policy.

---
```

This is English. Good. Final response concise.<|end|><|start|> assistant to=bash<|channel|>analysis <|constrain|>xml<|message|><rfl:parameter name="command">
wc -l /content/compiler_ko/SPECIFICATION.md