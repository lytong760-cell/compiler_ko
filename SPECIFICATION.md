# .ko Language Formal Technical Specification & Architectural Manual

## I. KIẾN TRÚC HẠT NHÂN VÀ THỰC THI CHUẨN HOÁ (RUNTIME ARCHITECTURE & ENGINE TARGET MAPPING)

Ngôn ngữ .ko vận hành dựa trên mô hình thực thi lai (Hybrid Execution Target Engine).

Trình biên dịch/phiên dịch trung tâm (`compiler.zig`) đóng vai trò như một "Nhạc trưởng". Nó nhận mã nguồn, phân tích cú pháp và phân chia công việc cho các "Nhà thầu chuyên biệt" ở bên dưới thực thi.

### 1. Mô hình Toán học Pipeline và Sơ đồ Thực thi

$$\mathcal{P}: \text{SourceCode}_{.ko} \xrightarrow{\text{Lexer/Parser}} \text{AST} \xrightarrow{\text{ScopeResolver}} \text{EngineTarget} \xrightarrow{\text{Execution}} \text{State}'$$

```
+-------------------------------------------------------------------+
|                     Mã Nguồn Cấp Cao (.ko)                        |
+-------------------------------------------------------------------+
                                  |
                                  v
+-------------------------------------------------------------------+
|        Bộ Phân Tích Cú Pháp Trừu Tượng (compiler.zig)              |
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

### 2. Ánh xạ Từ khóa Đặc biệt sang Tệp Thực thi Hệ thống

#### A. Thư viện Nạp Module: Import Subsystem Target

Chỉ thị ngôn ngữ: `Import`

Tệp mã nguồn chịu trách nhiệm: `Import.java` + `installer.zig`

Giải thích đơn giản: Coi Import.java như một "Thủ thư". Khi bạn dùng từ khóa Import hoặc lệnh `ko -install`, thủ thư Java sẽ đi tìm gói thư viện, kiểm tra tính hợp lệ, biên dịch và mang đặt lên bàn làm việc của bạn.

Ngữ nghĩa toán học & kỹ thuật:

$$\text{Import}_{\text{subsystem}}: \text{ModuleName} \times \text{ScopeTag} \to \mathcal{S}_{\text{updated\_scope\_table}}$$

- Phân giải đường dẫn tập tin (Dynamic Path Resolution)
- Xác thực chữ ký mã nguồn (Module Signature Verification)
- Tải lớp động (Dynamic Classloading) và chèn danh sách định danh vào Bảng Tầm Vực (Scope Table)

#### B. Động cơ Vòng lặp Hiệu năng cao: Loop Subsystem Target

Chỉ thị ngôn ngữ: `Loop`

Tệp mã nguồn chịu trách nhiệm: `Loop.cpp`

Giải thích đơn giản: Coi Loop.cpp như một "Tay đua F1". Việc lặp lại hành động hàng triệu lần được chuyển giao cho mã C++ chạy trực tiếp ở cấp phần cứng CPU.

Ngữ nghĩa toán học & kỹ thuật:

$$\text{Loop}_{\text{subsystem}}: \text{IterCondition} \times \text{BodyBlock} \xrightarrow{\text{Native C++}} \Delta \text{State}$$

- Ép kiểu và tối ưu hóa thanh ghi cứng CPU (Hardware Register Allocation)
- Bỏ qua overhead của bộ phiên dịch, tối ưu bộ đệm lệnh (Instruction Cache Line Optimization)

## II. MÔ HÌNH LÝ THUYẾT VÀ TỪ VỰNG CÚ PHÁP TỔNG QUÁT

### 1. Nguyên tắc Tách biệt Lệnh và Dữ liệu

Không gian Lệnh / Scope Block ($\mathcal{B}_E$): Sử dụng duy nhất cặp ngoặc vuông `[ ]`.

Không gian Dữ liệu & Tham số ($\mathcal{D}_P$): Sử dụng cặp ngoặc tròn `( )` cho tập hợp/tham số và ngoặc nhọn `{ }` cho ánh xạ Key-Value.

Tiên đề:

$$\mathcal{B}_E \cap \mathcal{D}_P = \emptyset$$

### 2. Ký hiệu Nhận dạng Đặc biệt

| Ký hiệu | Tên gọi | Ý nghĩa | Ví dụ |
|---------|---------|---------|-------|
| `~` | Toán tử Định danh | Đánh dấu tên biến/hàm/lớp | `int(10)~age` |
| `< >` | Thẻ Hệ thống | Bao bọc lệnh hệ thống | `<printf>`, `<input>`, `<len>` |
| `$` | Con trỏ Tham chiếu | Chỉ thuộc tính/phương thức trong Class | `$p1~take_damage()` |
| `"\n"` | Toán tử Ngắt Dòng | Xuống dòng trong chuỗi kép | `"Hello\n"` |
| `| |` | Dấu Phân Cách Ghi Chú | Bỏ qua khi biên dịch | `| comment |` |

### 3. Cú pháp EBNF

```
Program            ::= ModuleImport* Statement* MainBlock ExceptionHandler* ;
MainBlock          ::= "[" Statement* ExceptionHandler* "]" ;
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

### 4. Hệ thống Toán tử

Toán tử Số học: `+`, `-`, `*`, `/`, `%`

Toán tử Logic:
- `&&` : Phép VÀ logic
- `%%` : Phép HOẶC logic

### 5. Tiên đề Tầm vực Thực thi Toàn cục

Các câu lệnh thực thi không được nằm tự do bên ngoài toàn cục. Chúng bắt buộc phải nằm bên trong Hàm hoặc Khối Thực thi Chính `[ ]`. Phạm vi toàn cục chỉ chấp nhận: Lệnh Import, Khai báo Hàm, và Khai báo Lớp.

## III. HỆ THỐNG KIỂU DỮ LIỆU

### 1. Kiểu Dữ liệu Nguyên thủy

| Kiểu | Miền giá trị | Ví dụ |
|------|---------------|-------|
| `int` | $\mathbb{Z} \cap [-2^{63}, 2^{63}-1]$ | `int(100)~hp` |
| `freal` | $\mathbb{R}$ Double Precision | `freal(3.14159)~pi` |
| `string` | Chuỗi ký tự UTF-8 | `string("Phong\n")~name` |
| `booling` | $\mathbb{B} = \{\mathtt{\backslash True\backslash}, \mathtt{\backslash False\backslash}\}$ | `booling(\True\)~is_active` |
| `byte` | Biểu diễn Nhị phân | `byte("A")~b_val` |
| `bytes` | Vùng đệm Hex | `bytes(16)~empty_buf` |

### 2. Cấu trúc Dữ liệu Phức hợp

- Tuple / Mảng số: `(1, 2)~a`
- Mảng Chuỗi: `('a', 'b')~b`
- Danh sách Lồng nhau: `(1('a', 'b'))~list`
- Từ điển: `(1{'a'})~dic`

### 3. Cú pháp Truy xuất Chỉ mục

```ko
list<0>           | Lấy phần tử đầu tiên
list<1<0>>        | Lấy phần tử thứ 0 trong danh sách con tại vị trí 1
dic{1{'a'}}       | Lấy theo Key của Từ điển
```

## IV. HỆ THỐNG NHẬP/XUẤT, BỘ NHỚ, MÃ HÓA, ĐO ĐỘ DÀI

### 1. Cấu trúc Xuất Dữ liệu

```ko
<print>string^("Xin chao\n")
<print>[kiểu dữ liệu]^
<printf>^("Player HP: {hp}\n")
```

### 2. Thẻ Hệ thống Mã hóa (`<encode>`)

```ko
<encode(`ASCII`)>^("Hello World\n")
<encode(`UTF-8`)>^("Xin chào .ko\n")
bytes(<encode(`UTF-8`)>^("Dữ liệu bảo mật\n"))~encoded_data
```

### 3. Thẻ Hệ thống Đo Độ Dài (`<len>`)

```ko
int(<len>^("Xin chào .ko\n"))~str_length
int(<len>^(buffer))~buf_size
int(<len>^(inventory))~item_count
```

### 4. Cấu trúc Nhập Dữ liệu (`<input>`)

```ko
<input>("Nhập thông tin: \n")

string("")~x
<input>(x)

<input>("Nhập tên: \n")&=string("")~name
```

### 5. Thao tác Bộ nhớ Cấp thấp (`<memory>`)

```ko
int(0)~h
<memory>^h              | Trả về địa chỉ ô nhớ

<memory>dete(h)         | Giải phóng bộ nhớ
```

### 6. Đột biến Trạng thái Tức thì (`<now>`)

```ko
<now>(100)>hp
<now>(hp - damage)>hp
```

## V. CẤU TRÚC HÀM, GIÁ TRỊ TRẢ VỀ VÀ KHỐI THỰC THI CHÍNH

### 1. Định nghĩa và Gọi Hàm

```ko
calculate_power(int~base) [
    <return>(base * 2)
]

int(~calculate_power(10))~total
<now>(~calculate_power(20))>total
```

### 2. Khối Thực thi Chính

Mọi tệp .ko chạy độc lập bắt buộc phải có đúng 1 Khối Main `[ ]`.

## VI. CẤU TRÚC ĐIỀU KHIỂN LUỒNG

### 1. Rẽ nhánh Điều kiện

```ko
<if>(hp > 0 && is_active == \True\) [
    <printf>^("Nhân vật còn sống!\n")
]
<elif>(hp <= 0 %% is_active == \False\) [
    <printf>^("Nhân vật kiệt sức!\n")
]
<else> [
    <printf>^("Trạng thái không xác định!\n")
]
```

### 2. Hệ thống Vòng lặp
chắc chăn rằng bạn có hai dấu ** bao Loop
```ko
**Loop** <for>(~x=1&=5) [
    <printf>^("x = {x}\n")
]

**Loop** <for>(~x=1(2)&=5) [
    <printf>^("Odd: {x}\n")
]

@loop(hp > 0)
**Loop** <for.f.whle>@also [
    <printf>^("Fighting...\n")
    <now>(hp - 10)>hp
]
```

## VII. MÔ-ĐUN NẠP VÀ HỆ THỐNG PHẠM VI

### 1. Cú pháp Nạp Mô-đun
chắc chắn là bạn dùng ** bao từ Import
```ko
**Import**($Random)@also%~random!`global`:random
int(<$random>(1, 100))~rand_val
```

### 2. Quy định Thẻ Phạm vi

| Thẻ Scope | Phạm vi tác dụng |
|-----------|------------------|
| `global` | Toàn cục |
| `main` hoặc `a` | Khối Main |
| `func` | Hàm |
| `class` | Lớp |
| `tên_hàm` | Hàm cụ thể |

### 3. Thư viện Chuẩn Built-in

```ko
**Import**($Random)@also%~random!`global`:random
int(<$random>(1, 100))~rand_val

**Impor**t($Os)@also%~os!`global`:os
<$os>("data.txt")~file_var

**Import**($Website)@also%~web!`global`:web
<$web>("https://api.example.com")
```

### 4. Hệ thống Quản lý Thư viện Ngoại vi

#### A. Lệnh Cài đặt

```bash
ko -install "<Thư viện>"
ko -list
ko -search "<query>"
```

#### B. Cổng Đăng ký Thư viện và API

Module Store URL: `https://ko-studio.ai.studio/mobule-store`

Firestore REST API Endpoints:

**POST - Liệt kê toàn bộ Thư viện:**

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

**GET - Tải Thư viện cụ thể:**

```
GET https://firestore.googleapis.com/v1/projects/argon-shine-w40ks/databases/ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198/documents/libraries/<thư viện>?key=AIzaSyDcW3_plpZompdSlSYFr832A-Vq1TyQxvE
```

#### C. Quy trình Xử lý Tự động

```
+-----------------------------------------------------------------------------------+
| 1. Terminal Call: ko -install "<Thư viện>"                                        |
+-------------------------------------------s----------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 2. Gọi Firestore GET API Query:                                                   |
|    GET /documents/libraries/<thư viện>?key=...                                    |
|    -> Lấy Metadata & Liên kết Repository GitHub của thư viện                     |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 3. Subsystem Import.java thực hiện `git clone` toàn bộ Repo                       |
|    về thư mục tạm (temp cache) của hệ thống                                       |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 4. Kiểm tra Tệp Đóng gói (.zip Inspection):                                       |
|    - [TRƯỜNG HỢP 1]: Tìm thấy tệp `.zip` trong Repo                               |
|      -> Giữ lại DUY NHẤT tệp `.zip`, XÓA TẤT CẢ các file/thư mục khác.         |
|    - [TRƯỜNG HỢP 2]: KHÔNG tìm thấy tệp `.zip` nào                                |
|      -> Hủy tiến trình ngay lập tức, XÓA TOÀN BỘ dữ liệu vừa clone.           |
+-----------------------------------------------------------------------------------+
                                          |
                                          v
+-----------------------------------------------------------------------------------+
| 5. Giải nén `.zip` & Tự động Phân tích Ngôn ngữ                                   |
+-----------------------------------------------------------------------------------+
                /                                       \
               /                                         \
[Thành công]  v                                           v [Thất bại]
+----------------------------------+     +----------------------------------+
| Tích hợp Bảng Tầm Vực (Scope)    |     | 1. In báo lỗi chi tiết ra CLI    |
| Sẵn sàng cho chỉ thị `Import`    |     | 2. TỰ ĐỘNG XÓA SẠCH thư viện    |
+----------------------------------+     +----------------------------------+
```

## VIII. LẬP TRÌNH HƯỚNG ĐỐI TƯỢNG

### 1. Cấu trúc Lớp

```ko
Monster !class [
    @private [
        string("Dragon")~name
        int(100)~hp

        take_damage() [
            int(<$random>(15, 35))~damage
            <now>(hp - damage)>hp
            <printf>^("Monster {name} bị đánh! HP còn: {hp}\n")
            <return>(hp)
        ]
    ]
]

~Monster~m1
int($m1~take_damage())~remaining_hp
```

## IX. CƠ CHẾ XỬ LÝ LỖI VÀ NGOẠI LỆ

### 1. Cú pháp `<catch>`

```ko
<catch>(`ErrorCode`) [ Khối_Lệnh_Xử_Lý ]
```

### 2. Quy tắc Phạm vi Quét Lỗi

A. **Catch Nội Cục**: Chỉ quét ngược trong phạm vi Hàm/Khối Main chứa nó.

B. **Catch Toàn Cục**: Quét ngược bảo vệ tất cả Hàm/Khối Main nằm trước nó.

C. **Quy tắc Ưu tiên Chuỗi**: Kiểm tra từ trên xuống dưới, lỗi khớp đầu tiên được xử lý.

### 3. Biến Ngoại lệ Nội tại

```ko
<catch>(`DivideByZeroError`) [
    <printf>^("Lỗi {error<"type">} tại dòng {error<"line">}: {error<"code">'}\n")
]
```

## X. CHƯƠNG TRÌNH MẪU HOÀN CHỈNH

```ko
**Import**($Random)@also%~random!`global`:random
**Import**($Os)@also%~os!`global`:os
**Import**($Website)@also%~web!`global`:web

init_system_logs() [
    <printf>^("=== KHOI TAO HE THONG .KO ===\n")
    <$os>("log.txt")~log_file
    <$web>domain("mygame.com")@app_server
    <$web>("https://api.mygame.com/status")
    <return>(\True\)
]

safe_divide(int~dividend, int~divisor) [
    int(dividend / divisor)~result
    int(dividend % divisor)~remainder
    <printf>^("Thuong: {result}, Du: {remainder}\n")
    <return>(result)

    <catch>(`DivideByZeroError`) [
        <printf>^("Loi chia cho 0!\n")
        <return>(0)
    ]
]

calculate_crit_damage(int~base_dmg, int~bonus_dmg) [
    int((base_dmg + bonus_dmg) * 2)~crit_dmg
    <return>(crit_dmg)
]

<catch>(`SystemException`) [
    <printf>^("Loi he thong tong quat!\n")
    <return>(-1)
]

Hero !class [
    @private [
        string("")~name
        int(100)~hp
        ('Kiem', 'Khien', 'Binh mau')~inventory

        setup_player() [
            <input>("Nhap ten: \n")&=name
            <printf>^("Chao mung {name}!\n")
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
                <printf>^("Trang thai: Rat khoe\n")
            ]
            <elif>(hp >= 30 %% hp < 80) [
                <printf>^("Trang thai: Binh thuong\n")
            ]
            <else> [
                <printf>^("Trang thai: Nguy hiem!\n")
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
    <printf>^("Ma nhi phan: {binary_char}\n")
    
    int(<len>^("Xin chao .ko\n"))~str_len
    int(<len>^(hex_buffer))~buf_len
    <printf>^("Do dai chuoi: {str_len}, Kich thuoc bo dem: {buf_len}\n")

    <encode(`UTF-8`)>^("Ma hoa UTF-8 truc tiep\n")
    bytes(<encode(`ASCII`)>^("Hello .ko"))~asc_bytes
    int(<len>^(asc_bytes))~encoded_len
    <printf>^("Do dai ma hoa ASCII: {encoded_len}\n")
    
    int(~safe_divide(100, 0))~calc_test
    <printf>^("Kiem tra chia an toan: {calc_test}\n")

    **Loop** <for>(~i=1(2)&=5) [
        <printf>^("--- Turn {i} ---\n")
        string($p1~use_random_item())~used_item
    ]
    
    int($p1~check_status())~current_hp
    int(~calculate_crit_damage(50, 10))~final_strike
    <printf>^("Sat thuong chi mang: {final_strike}\n")

    int(999)~temp_data
    <printf>^("Dia chi o nho: {<memory>^temp_data}\n")
    <memory>dete(temp_data)

    <catch>(`GlobalError`) [
        <printf>^("Bat loi ngoai le trong Main tai dong {error<"line">}: {error<"code">\n}")
    ]
]
```

## XI. TRẠNG THÁI TRIỂN KHAI HIỆN TẠI

### Đã Triển khai

- [x] Lexer đầy đủ
- [x] Parser biểu thức và câu lệnh
- [x] AST representation
- [x] VM execution engine
- [x] Khai báo biến và gán giá trị
- [x] Biểu thức số học và logic
- [x] Điều khiển luồng (if/elif/else)
- [x] System tags: printf, input, len, encode, memory, now
- [x] Khai báo Lớp (Class declarations)
- [x] Xử lý ngoại lệ (catch)
- [x] Đột biến tức thì (<now>)
- [x] Import statement với scope registration
- [x] Định nghĩa và gọi Hàm
- [x] Vòng lặp (for/while)
- [x] Gọi phương thức trên class instance
- [x] Toán tử truy xuất chỉ mục
- [x] Return statement
- [x] String interpolation trong printf
- [x] Bytes buffer allocation
- [x] `ko -install` với Firestore API
- [x] `ko -list` - Liệt kê tất cả thư viện (POST runQuery)
- [x] `ko -search` - Tìm kiếm thư viện
- [x] Git clone và zip inspection
- [x] Đa ngôn ngữ compile/link pipeline (Java, C, C++, Zig, Node.js, .ko)
- [x] Scope registration (file-based)
- [x] Import.java subsystem hoàn chỉnh với HTTP client, git clone, zip inspection, compile/link
- [x] Loop.cpp loop optimization engine
- [x] API Server (api_server.py) cho Module Store

### Chưa Triển khai

- [ ] Tải module thực thời tại runtime (Import.java integration vào Zig VM)
- [ ] Thư viện chuẩn (stdlib) mặc định
- [ ] Tích hợp Loop.cpp vào Zig VM
- [ ] JNI/JNA bridge giữa Zig VM và native libraries

## XII. TỔNG KẾT NGỮ PHÁP

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
