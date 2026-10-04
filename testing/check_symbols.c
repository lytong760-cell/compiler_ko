#include <stdlib.h>
#include <dlfcn.h>

int main(int argc, char *argv[]) {
    if (argc < 3) {
        fprintf(stderr, "ERROR: Thiếu đối số. Cách dùng: %s <thư viện.so> <tên_symbol>\n", argv[0]);
        return 1;
    }

    const char *lib_path = argv[1];
    const char *sym_name = argv[2];

    void *handle = dlopen(lib_path, RTLD_LAZY);
    if (!handle) {
        fprintf(stderr, "ERROR: Không thể tải thư viện %s: %s\n", lib_path, dlerror());
        return 1;
    }

    dlerror();
    void *symbol = dlsym(handle, sym_name);
    const char *error = dlerror();
    
    dlclose(handle);

    if (error != NULL) {
        fprintf(stderr, "ERROR: Không tìm thấy symbol %s trong %s: %s\n", 
                sym_name, lib_path, error);
        return 1;
    }

    printf("SUCCESS: Tìm thấy %s trong %s\n", sym_name, lib_path);
    return 0;
}
