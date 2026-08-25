# .ko Language Formal Specification

## 1. Overview

.ko is a multi-paradigm programming language with:
- Imperative programming
- Object-oriented programming
- Low-level memory manipulation
- Structural sequential upward exception handling

The reference compiler is implemented in Zig.

## 2. Lexical Structure

### 2.1 Tokens

- Identifiers: `[a-zA-Z_][a-zA-Z0-9_]*`
- Integers: `[0-9]+`
- Floats: `[0-9]+\.[0-9]+`
- Strings: `"..."` or `'...'`
- Booleans: `\True\`, `\False\`

### 2.2 Keywords

`Import`, `Loop`, `if`, `elif`, `else`, `return`, `for`, `while`, `private`, `class`, `int`, `freal`, `string`, `booling`, `byte`, `bytes`, `catch`, `now`, `input`, `memory`, `encode`, `len`, `printf`, `Execute`

### 2.3 Operators

- Arithmetic: `+`, `-`, `*`, `/`, `%`
- Logical: `&&`, `%%`
- Comparison: `<`, `>`, `==`, `!=`
- Delimiters: `[`, `]`, `(`, `)`, `{`, `}`
- Sigil: `~`
- System tags: `<...>`
- Member access: `$`

## 3. Syntax

### 3.1 Program Structure

```
Program := Statement*
Statement := VarDecl | FuncDecl | ClassDecl | ControlFlow | SystemTag | Expr
```

### 3.2 Variable Declaration

```
VarDecl := Type '(' Expression ')' '~' Identifier
Type := 'int' | 'freal' | 'string' | 'booling' | 'byte' | 'bytes'
```

Example:
```ko
int(10)~x
string("Hello")~name
```

### 3.3 Functions

```
FuncDecl := Identifier '(' ParamList ')' '[' Statement* ']'
ParamList := Param (',' Param)*
Param := Type '~' Identifier
```

Example:
```ko
add(int~a, int~b) [
    <return>(a + b)
]
```

### 3.4 Classes

```
ClassDecl := 'class' Identifier '[' ClassBody ']'
ClassBody := ('@private' '[' Statement* ']')* Statement*
```

### 3.5 Control Flow

```
IfStmt := '<' 'if' '>' '(' Expression ')' '[' Statement* ']'
ElifStmt := '<' 'elif' '>' '(' Expression ')' '[' Statement* ']'
ElseStmt := '<' 'else> '[' Statement* ']'
```

### 3.6 System Tags

```
SystemTag := '<' Identifier '>' '^' '(' Expression ')'
SystemCall := '<' Identifier '(' Expression ')' '>'
```

Examples:
```ko
<printf>^("Hello\n")
<len>^(variable)
<int>(<len>^(string))~length
```

## 4. Type System

### 4.1 Primitive Types

| Type | Description | Example |
|------|-------------|---------|
| int | 64-bit signed integer | `int(10)~x` |
| freal | Double precision float | `freal(3.14)~pi` |
| string | UTF-8 string | `string("text")~s` |
| booling | Boolean | `booling(\True\)~flag` |
| byte | Single byte | `byte(65)~b` |
| bytes | Byte buffer | `bytes(16)~buf` |

### 4.2 Composite Types

- Tuple: `(1, 2, 3)~t`
- List: `(1, 2, 3)~l`
- Dict: `({'key': 'value'})~d`

## 5. Runtime Model

The VM executes AST nodes directly:
- Variables stored in scoped hash maps
- Functions stored in global scope
- Classes stored in global scope
- Exception handlers attached to scopes

### 5.1 Scoping

Scope hierarchy:
1. Global scope
2. Function scope
3. Class scope

### 5.2 Evaluation

Expressions are evaluated recursively:
- Literals return their value
- Identifiers look up in current scope
- Binary operations evaluate operands then apply operator
- Function calls evaluate arguments then execute body

## 6. Built-in Operations

### 6.1 I/O

- `<printf>^("text")` - Print to stdout
- `<input>(prompt)` - Read from stdin

### 6.2 System

- `<len>^(x)` - Get length/size
- `<encode fmt>^("text")` - Encode string to bytes
- `<memory>^x` - Get memory address
- `<memory>dete(x)` - Free memory

### 6.3 Mutation

- `<now>(expr)>x` - Immediate assignment

## 7. Exception Handling

```
CatchStmt := '<' 'catch' '>' '(' ErrorType ')' '[' Statement* ']'
ErrorType := '`' Identifier '`'
```

Catch blocks execute when an error of the specified type is raised.

## 8. Current Implementation Status

### Implemented

- [x] Lexer for all tokens
- [x] Parser for expressions and statements
- [x] AST representation
- [x] VM execution engine
- [x] Variable declarations and assignments
- [x] Arithmetic and logical expressions
- [x] Control flow (if/elif/else)
- [x] System tags: printf, input, len, encode, memory
- [x] Class declarations
- [x] Exception handling (catch)
- [x] Immediate mutation (<now>)
- [x] Import statement stub
- [x] Function definitions and calls
- [x] Loop constructs (for/while)
- [x] Method invocation on class instances
- [x] Index access operator
- [x] Return statement

### Not Yet Implemented

- [ ] Real module loading (Import.java integration)
- [ ] Standard library
- [ ] Loop optimization subsystem (Loop.cpp integration)

## 9. Grammar Summary

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
```
