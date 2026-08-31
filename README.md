# .ko Programming Language

A multi-paradigm programming language with a compiler written in Zig, featuring a complete module store API, high-performance loop optimization, and Java-based module import subsystem.

## Classification

Multi-Paradigm: Imperative, Object-Oriented, Low-Level Memory Direct Manipulation, Structural Sequential Upward Exception Handling

## Architecture

The .ko compiler follows a hybrid execution target engine model:

```
Source Code (.ko) -> Lexer (Zig) -> Parser (Zig) -> AST -> VM (Zig) -> Output
                                              |
                                              v
                                    +------------------+
                                    | Import.java      |  Module Import Subsystem
                                    | - Dynamic Path  |
                                    |   Resolution    |
                                    | - Scope Table   |
                                    |   Ingestion     |
                                    | - Classloading  |
                                    +------------------+
                                              |
                                    +------------------+
                                    | Loop.cpp         |  Loop Optimization Subsystem
                                    | - Loop Unrolling |
                                    | - Cache Line Opt |
                                    | - CPU Registers  |
                                    +------------------+
```

### Components

- `src/main.zig` - Entry point and CLI dispatcher
- `src/lexer.zig` - Tokenizer
- `src/parser.zig` - Syntax analyzer
- `src/ast.zig` - Abstract Syntax Tree definitions
- `src/vm.zig` - Runtime execution engine
- `src/value.zig` - Value types and scoping
- `src/installer.zig` - Package manager and Firestore API client
- `src/Loop.cpp` - High-performance C++ loop optimization engine
- `src/Import.java` - Java module import subsystem
- `src/api_server.py` - Local Module Store REST API server

## Building

```bash
zig build
```

## Running

```bash
./zig-out/bin/ko <file.ko>
```

## CLI Commands

```bash
./zig-out/bin/ko <file.ko>                # Run a .ko program
./zig-out/bin/ko -install <library>       # Install a library from the Module Store
./zig-out/bin/ko -list                    # List all available libraries
./zig-out/bin/ko -search <query>          # Search libraries by name
```

## Module Store API

The .ko ecosystem includes a Firestore-compatible REST API for the Module Store.

### API Endpoints

#### POST List All Libraries

```
POST https://firestore.googleapis.com/v1/projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents:runQuery?key=AIzaSyDcW3_plpZompdSlSYFr832A-Vq1TyQxvE
Content-Type: application/json

{
  "parent": "projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents",
  "query": {
    "from": [{"collectionId": "libraries"}]
  }
}
```

Response:
```json
{
  "document": [
    {
      "name": "projects/.../documents/libraries/Random",
      "fields": {
        "githubLink": {"stringValue": "https://github.com/ko-studio/ko-random"},
        "description": {"stringValue": "Random number generation module"},
        "version": {"stringValue": "1.0.0"},
        "author": {"stringValue": "ko-studio"}
      }
    }
  ]
}
```

#### GET Library Metadata

```
GET https://firestore.googleapis.com/v1/projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents/libraries/{library}?key=AIzaSyDcW3_plpZompdSlSYFr832A-Vq1TyQxvE
```

Response:
```json
{
  "name": "projects/.../documents/libraries/Random",
  "fields": {
    "githubLink": {"stringValue": "https://github.com/ko-studio/ko-random"},
    "description": {"stringValue": "Random number generation module"},
    "version": {"stringValue": "1.0.0"},
    "author": {"stringValue": "ko-studio"}
  }
}
```

#### PUT Register Library (API Server)

```
PUT https://firestore.googleapis.com/v1/projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents/libraries/{library}?key=AIzaSyDcW3_plpZompdSlSYFr832A-Vq1TyQxvE
Content-Type: application/json

{
  "fields": {
    "githubLink": {"stringValue": "https://github.com/org/ko-lib"},
    "description": {"stringValue": "My library"},
    "version": {"stringValue": "1.0.0"},
    "author": {"stringValue": "author"}
  }
}
```

### Local Module Store Server

For local development and testing, run the built-in API server:

```bash
python3 src/api_server.py --port 8080 --data-dir ./module_store_data
```

The server implements the same Firestore-compatible endpoints and supports library registration.

## Installing Libraries

```bash
./zig-out/bin/ko -install <library>
```

The `-install` command:
1. Queries the .ko Module Store for library metadata
2. Clones the library's GitHub repository
3. Inspects for a `.zip` package (purging if missing)
4. Auto-detects the implementation language
5. Compiles and links the library
6. Registers the library scope

On failure, the system automatically purges all downloaded files to avoid conflicts.

## Package Management Pipeline

When `ko -install <Library>` is executed:

```
CLI Request -> GET API -> Fetch GitHub URL -> Git Clone Repo
    -> Zip Filter & Inspection -> Compile / Link -> Register Scope
```

### Supported Languages

Library source code can be written in:
- Java (`.java`) - compiled with `javac`
- C (`.c`) - compiled with `gcc -shared -fPIC`
- C++ (`.cpp`) - compiled with `g++ -shared -fPIC`
- Node.js (`.js`) - npm install
- Zig (`.zig`) - compiled with `zig build-lib`
- .ko (`.ko`) - loaded directly
- Python (`.py`) / Lua (`.lua`) - loaded directly

### Package Format

All libraries must be packaged as a single `.zip` archive inside the GitHub repository. The zip must contain all source files, executables, and configuration files.

## Language Features

### Data Types

| Type | Description | Example |
|------|-------------|---------|
| `int` | 64-bit signed integer | `int(10)~x` |
| `freal` | Double precision floating point | `freal(3.14)~pi` |
| `string` | UTF-8 string | `string("text")~s` |
| `booling` | Boolean (`\True\`, `\False\`) | `booling(\True\)~flag` |
| `byte` | Single byte binary value | `byte("A")~b` |
| `bytes` | Byte buffer | `bytes(16)~buf` |
| `tuple` / `list` | Composite data | `(1, 2)~t` |
| `dict` | Key-value mappings | `({'key': 'value'})~d` |

### Variables

```ko
int(10)~x
string("Hello")~name
freal(3.14159)~pi
booling(\True\)~is_active
byte("A")~binary_char
bytes(32)~buffer
```

### Operators

- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Logical: `&&` (AND), `%%` (OR)
- Comparison: `<`, `>`, `==`, `!=`

### Control Flow

```ko
<if>(hp > 0 && is_active == \True\) [
    <printf>^("Alive!\n")
]
<elif>(hp <= 0 %% is_active == \False\) [
    <printf>^("Defeated!\n")
]
<else> [
    <printf>^("Unknown state!\n")
]
```

### Loops

Counting loops (optimized by Loop.cpp):

```ko
Loop <for>(~i=1&=5) [
    <printf>^("Turn {i}\n")
]

Loop <for>(~i=1(2)&=5) [
    <printf>^("Odd: {i}\n")
]
```

Conditional loops:

```ko
@loop(hp > 0)
Loop <for.f.whle>@also [
    <printf>^("Fighting...\n")
    <now>(hp - 10)>hp
]
```

### Output

```ko
<printf>^("Hello World\n")
<printf>^("HP: {hp}\n")
<print>string^(x"\n")
```

### Input

```ko
<string("")~name
<input>(name)

| Or using &= operator:
<input>("Enter name: \n")&=string("")~name
```

### Memory Operations

```ko
<memory>^variable           | Get memory address
<memory>dete(variable)      | Free memory
```

### Encoding

```ko
<encode(`ASCII`)>^("Hello")
<encode(`UTF-8`)>^("Xin chào")
bytes(<encode(`UTF-8`)>^("data"))~encoded
```

### Length

```ko
int(<len>^("hello"))~len
int(<len>^(buffer))~size
```

### Functions

```ko
safe_divide(int~a, int~b) [
    int(a / b)~result
    <return>(result)
    
    <catch>(`DivideByZeroError`) [
        <printf>^("Cannot divide by zero!\n")
        <return>(0)
    ]
]
```

### Classes

```ko
Hero !class [
    @private [
        string("")~name
        int(100)~hp
        ('Kiem', 'Khien', 'Binh mau')~inventory
        
        setup_player() [
            <input>("Nhap ten: \n")&=name
            <return>(name)
        ]
    ]
]

~Hero~p1
string($p1~setup_player())~player_name
```

### Exception Handling

```ko
| Catch inside function - catches errors in that function only |
process_data(int~a, int~b) [
    int(a / b)~result
    <catch>(`DivideByZeroError`) [
        <printf>^("Error: {error<"type">} at line {error<"line">}\n")
        <return>(0)
    ]
]

| Global catch - protects all functions above it |
<catch>(`SystemException`) [
    <printf>^("Fatal error: {error<"type">}\n")
]
```

### Immediate Mutation

```ko
<now>(100)>hp
<now>(hp - damage)>hp
```

### Module Import

```ko
Import($Random)@also%~random!`global`:random
int(<$random>(1, 100))~rand_val

Import($Os)@also%~os!`global`:os
<$os>("data.txt")~file_var

Import($Website)@also%~web!`global`:web
<$web>("https://api.example.com")
```

## Examples

See the `examples/` directory for sample .ko programs.

## Testing

```bash
zig test src/test_3600.zig
zig test src/test_harness.zig
zig test src/test_lexer_extended.zig
zig test src/test_parser_extended.zig
```

## Benchmark

```bash
bash benchmark.sh
```

## Project Structure

```
compiler_ko/
├── src/
│   ├── main.zig              # Entry point
│   ├── lexer.zig             # Tokenizer
│   ├── parser.zig            # Parser
│   ├── ast.zig               # AST definitions
│   ├── vm.zig                # Runtime VM
│   ├── value.zig             # Value types, Scope, Function, Class
│   ├── installer.zig         # Package manager + Firestore API client
│   ├── builtins.zig          # Built-in system tags
│   ├── Loop.cpp              # C++ loop optimization engine
│   ├── Import.java           # Java module import subsystem
│   ├── api_server.py         # Local Module Store API server
│   ├── test_3600.zig         # Stress test
│   ├── test_harness.zig      # Integration tests
│   ├── test_lexer_extended.zig
│   └── test_parser_extended.zig
├── examples/
│   ├── simple.ko
│   ├── test.ko
│   └── medium.ko
├── SPECIFICATION.md
├── build.zig
└── README.md
```
# This is a new version rewritten in zig 
you can review **[old version](https://github.com/lytong760-cell/compiler-ko-)** rewritten in python
