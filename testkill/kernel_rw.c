#include "kernel_rw.h"
#include <dlfcn.h>
#include <string.h>
#ifdef __APPLE__
#include <mach/mach.h>
#endif

// 动态链接到roothide的内核原语
static int (*_kreadbuf)(uint64_t kaddr, void* output, size_t size) = NULL;
static int (*_kwritebuf)(uint64_t kaddr, const void* input, size_t size) = NULL;
static uint64_t (*_kread64)(uint64_t va) = NULL;
static uint64_t (*_kread_ptr)(uint64_t va) = NULL;
static uint32_t (*_kread32)(uint64_t va) = NULL;
static int (*_kwrite64)(uint64_t va, uint64_t v) = NULL;
static int (*_kwrite32)(uint64_t va, uint32_t v) = NULL;
static uint64_t (*_ksymbol)(const char* symbol) = NULL;

// 内核偏移量和符号（需要根据iOS版本调整）
static uint64_t koffset_proc_pid = 0x60;
static uint64_t koffset_proc_list_next = 0x0;
static uint64_t koffset_proc_task = 0x0;  // iOS 16+: task在proc结构后面
static uint64_t koffset_task_map = 0x28;
static uint64_t koffset_vm_map_pmap = 0x40;
static uint64_t ksizeof_proc = 0x768;  // proc结构大小，iOS版本相关

static uint64_t kernel_allproc = 0;

int kernel_init(void) {
    // 尝试从系统中加载内核原语
    void *handle = dlopen("/var/jb/usr/lib/libjailbreak.dylib", RTLD_NOW);
    if (!handle) {
        handle = dlopen("/usr/lib/libjailbreak.dylib", RTLD_NOW);
    }
    if (!handle) {
        printf("Failed to load libjailbreak.dylib\n");
        return -1;
    }

    _kreadbuf = dlsym(handle, "kreadbuf");
    _kwritebuf = dlsym(handle, "kwritebuf");
    _kread64 = dlsym(handle, "kread64");
    _kread_ptr = dlsym(handle, "kread_ptr");
    _kread32 = dlsym(handle, "kread32");
    _kwrite64 = dlsym(handle, "kwrite64");
    _kwrite32 = dlsym(handle, "kwrite32");
    _ksymbol = dlsym(handle, "ksymbol");

    if (!_kreadbuf || !_kwritebuf || !_kread64 || !_kread32 || !_kwrite64 || !_kwrite32 || !_ksymbol) {
        printf("Failed to load kernel primitives\n");
        return -1;
    }

    // 获取内核符号
    kernel_allproc = _ksymbol("_allproc");
    if (!kernel_allproc) {
        printf("Failed to find allproc symbol\n");
        return -1;
    }

    printf("Pure kernel mode initialized successfully\n");
    return 0;
}

uint32_t kread32(uint64_t kaddr) {
    if (!_kread32) return 0;
    return _kread32(kaddr);
}

uint64_t kread64(uint64_t kaddr) {
    if (!_kread64) return 0;
    return _kread64(kaddr);
}

uint64_t kread_ptr(uint64_t kaddr) {
    if (!_kread_ptr) return 0;
    return _kread_ptr(kaddr);
}

int kreadbuf(uint64_t kaddr, void* buffer, size_t size) {
    if (!_kreadbuf) return -1;
    return _kreadbuf(kaddr, buffer, size);
}

void kwrite32(uint64_t kaddr, uint32_t val) {
    if (_kwrite32) _kwrite32(kaddr, val);
}

void kwrite64(uint64_t kaddr, uint64_t val) {
    if (_kwrite64) _kwrite64(kaddr, val);
}

int kwritebuf(uint64_t kaddr, const void* data, size_t size) {
    if (!_kwritebuf) return -1;
    return _kwritebuf(kaddr, data, size);
}

// 从PID查找proc结构
uint64_t proc_find(pid_t pid) {
    if (!kernel_allproc) return 0;
    
    uint64_t proc = kread_ptr(kernel_allproc);
    while (proc) {
        uint32_t proc_pid = kread32(proc + koffset_proc_pid);
        if (proc_pid == pid) {
            return proc;
        }
        proc = kread_ptr(proc + koffset_proc_list_next);
    }
    return 0;
}

// 从proc获取task结构
uint64_t proc_task(uint64_t proc) {
    if (!proc) return 0;
    
    if (koffset_proc_task != 0) {
        // iOS <= 15: proc有task属性
        return kread_ptr(proc + koffset_proc_task);
    } else {
        // iOS >= 16: task在proc + sizeof(proc)
        return proc + ksizeof_proc;
    }
}

// 从proc获取vm_map
uint64_t proc_vm_map(uint64_t proc) {
    uint64_t task = proc_task(proc);
    if (!task) return 0;
    return kread_ptr(task + koffset_task_map);
}

// 读取目标进程的内存（通过内核态页表转换）
int proc_kreadbuf(uint64_t proc, uint64_t addr, void* buffer, size_t size) {
    // 简化版本：直接尝试读取虚拟地址
    // 在实际实现中需要通过页表转换
    return kreadbuf(addr, buffer, size);
}

// 读取指针链（纯内核态版本）
uint64_t proc_read_ptr_chain(uint64_t proc, uint64_t base, uint64_t *offsets, int count) {
    uint64_t current = base;
    
    for (int i = 0; i < count; i++) {
        uint64_t target = current + offsets[i];
        uint64_t next = 0;
        if (proc_kreadbuf(proc, target, &next, sizeof(next)) != 0) {
            return 0;
        }
        current = next;
    }
    
    return current;
}

// 在目标进程中搜索模块基址
uint64_t proc_find_module_base(uint64_t proc, const char* module_name) {
    // 这里需要遍历进程的内存映射来查找模块
    // 简化实现：尝试常见的基址
    uint64_t test_bases[] = {
        0x100000000ULL,
        0x102000000ULL,
        0x104000000ULL,
        0x106000000ULL,
        0x108000000ULL,
        0x10a000000ULL,
        0x110000000ULL,
        0x120000000ULL,
        0x130000000ULL,
        0x140000000ULL
    };
    
    for (int i = 0; i < sizeof(test_bases)/sizeof(test_bases[0]); i++) {
        char buffer[4096] = {0};
        if (proc_kreadbuf(proc, test_bases[i], buffer, sizeof(buffer)) == 0) {
            if (strstr(buffer, module_name)) {
                return test_bases[i];
            }
        }
    }
    
    return 0;
}