# .ko Programming Language

A multi-paradigm programming language with a compiler written in Zig.

## Classification

Multi-Paradigm: Imperative, Object-Oriented, Low-Level Memory Direct Manipulation, Structural Sequential Upward Exception Handling

## Architecture

The .ko compiler is implemented in Zig and follows a classic pipeline:

```
Source Code (.ko) -> Lexer -> Parser -> AST -> VM -> Output
```

### Components

- `src/main.zig` - Entry point
- `src/lexer.zig` - Tokenizer
- `src/parser.zig` - Syntax analyzer
- `src/ast.zig` - Abstract Syntax Tree definitions
- `src/vm.zig` - Runtime execution engine
- `src/value.zig` - Value types and scoping

## Building

```bash
zig build
```

## Running

```bash
./zig-out/bin/ko <file.ko>
```

## Language Features

### Data Types

- `int` - 64-bit signed integers
- `freal` - Double precision floating point
- `string` - UTF-8 strings
- `booling` - Boolean values (`\True\`, `\False\`)
- `byte` - Single byte binary value
- `bytes` - Byte buffer
- `tuple` / `list` - Composite data
- `dict` - Key-value mappings

### Variables

```ko
int(10)~x
string("Hello")~name
```

### Operators

- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Logical: `&&` (AND), `%%` (OR)
- Comparison: `<`, `>`, `==`, `!=`

### Control Flow

```ko
<if>(condition) [
    ...
]
<elif>(condition) [
    ...
]
<else> [
    ...
]
```

### Loops

```ko
Loop <for>(~i=1(2)&=5) [
    <printf>^("Turn {i}\n")
]
```

### Output

```ko
<printf>^("Hello World\n")
<printf>^(variable)
```

### Input

```ko
<input>("Prompt")&=variable
```

### Memory Operations

```ko
<memory>^variable     | Get address
<memory>dete(variable) | Free memory
```

### Encoding

```ko
<encode(`UTF-8`)>^("text")
```

### Length

```ko
int(<len>^(variable))~length
```

### Functions

```ko
my_func(int~a, int~b) [
    <return>(a + b)
]

int(~my_func(10, 20))~result
```

### Classes

```ko
Hero !class [
    @private [
        string("")~name
        int(100)~hp
    ]
]

~Hero~player
```

### Exception Handling

```ko
<catch>(`ErrorType`) [
    <printf>^("Error caught!\n")
]
```

### Immediate Mutation

```ko
<int(10)~x>
<now>(20)>x  | x is now 20
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
