#include "kernel_rw.h"
#include <dlfcn.h>
#include <string.h>

// 动态加载的函数指针
static int (*_jbclient_initialize_primitives)(void) = NULL;
static int (*_kreadbuf)(uint64_t kaddr, void* buffer, size_t size) = NULL;
static uint64_t (*_proc_find)(pid_t pid) = NULL;
static uint64_t (*_proc_task)(uint64_t proc) = NULL;
static uint64_t (*_kread_ptr)(uint64_t addr) = NULL;
static uint32_t (*_kread32)(uint64_t addr) = NULL;
static uint64_t (*_kread64)(uint64_t addr) = NULL;

static void *libjailbreak_handle = NULL;

// 包装函数
int kreadbuf(uint64_t kaddr, void* buffer, size_t size) {
    if (_kreadbuf) return _kreadbuf(kaddr, buffer, size);
    return -1;
}

uint64_t proc_find(pid_t pid) {
    if (_proc_find) return _proc_find(pid);
    return 0;
}

uint64_t proc_task(uint64_t proc) {
    if (_proc_task) return _proc_task(proc);
    return 0;
}

uint64_t kread_ptr(uint64_t addr) {
    if (_kread_ptr) return _kread_ptr(addr);
    return 0;
}

uint32_t kread32(uint64_t addr) {
    if (_kread32) return _kread32(addr);
    return 0;
}

uint64_t kread64(uint64_t addr) {
    if (_kread64) return _kread64(addr);
    return 0;
}

// 纯内核态初始化函数
int pure_kernel_init(void) {
#ifdef TARGET_OS_IPHONE
    // 使用roothide的jbroot获取正确的无根路径
    const char *jb_lib_paths[] = {
        jbroot("/usr/lib/libjailbreak.dylib"),
        "/usr/lib/libjailbreak.dylib",  // 备用路径
        "/var/jb/usr/lib/libjailbreak.dylib",  // 备用路径
        NULL
    };
    
    // 尝试多个路径加载libjailbreak
    for (int i = 0; jb_lib_paths[i] != NULL; i++) {
        libjailbreak_handle = dlopen(jb_lib_paths[i], RTLD_LAZY);
        if (libjailbreak_handle) {
            // 加载成功，跳出循环
            break;
        }
    }
    
    if (!libjailbreak_handle) {
        return -1;  // 加载失败
    }
    
    // 获取所有函数指针
    _jbclient_initialize_primitives = dlsym(libjailbreak_handle, "jbclient_initialize_primitives");
    _kreadbuf = dlsym(libjailbreak_handle, "kreadbuf");
    _proc_find = dlsym(libjailbreak_handle, "proc_find");
    _proc_task = dlsym(libjailbreak_handle, "proc_task");
    _kread_ptr = dlsym(libjailbreak_handle, "kread_ptr");
    _kread32 = dlsym(libjailbreak_handle, "kread32");
    _kread64 = dlsym(libjailbreak_handle, "kread64");
    
    if (!_jbclient_initialize_primitives || !_kreadbuf) {
        dlclose(libjailbreak_handle);
        return -1;  // 符号加载失败
    }
    
    // 调用roothide初始化函数
    int ret = _jbclient_initialize_primitives();
    if (ret != 0) {
        dlclose(libjailbreak_handle);
        return -1;  // 初始化失败
    }
    
    return 0;  // 成功
#else
    // 语法检查模式
    return 0;
#endif
}