#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <dlfcn.h>
#include <errno.h>

// Structure to hold symbol information
typedef struct {
    const char *library_path;
    const char *symbol_name;
    const char *expected_type;
    void **out_ptr;
} SymbolCheck;

// Function to check if a symbol exists in a shared library
int check_symbol(const SymbolCheck *check) {
    void *handle = dlopen(check->library_path, RTLD_LAZY);
    if (!handle) {
        fprintf(stderr, "ERROR: Không thể tải thư viện %s: %s\n", 
                check->library_path, dlerror());
        return 1;
    }

    // Reset error state
    dlerror();

    void *symbol = dlsym(handle, check->symbol_name);
    const char *error = dlerror();
    dlclose(handle);

    if (error != NULL) {
        fprintf(stderr, "ERROR: Không tìm thấy symbol %s trong %s: %s\n", 
                check->symbol_name, check->library_path, error);
        return 1;
    }

    // If we got here, symbol exists
    if (check->out_ptr) {
        *check->out_ptr = symbol;
    }

    printf("OK: Tìm thấy %s trong %s\n", check->symbol_name, check->library_path);
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Cách dùng: %s <thư viện.so> <tên_symbol> [type]\n", argv[0]);
        fprintf(stderr, "  <thư viện.so>: Đường dẫn đến file shared library\n");
        fprintf(stderr, "  <tên_symbol>: Tên symbol cần kiểm tra (có thể có tiền tố ko_)\n");
        fprintf(stderr, "  [type]: Kiểu mong đợi (ví dụ: 'int', 'void*'), không bắt buộc\n");
        return 1;
    }

    const char *lib_path = argv[1];
    const char *sym_name = argv[2];
    const char *expected_type = (argc > 3) ? argv[3] : NULL;

    SymbolCheck check = {
        .library_path = lib_path,
        .symbol_name = sym_name,
        .expected_type = expected_type,
        .out_ptr = NULL
    };

    int result = check_symbol(&check);
    return result;
}