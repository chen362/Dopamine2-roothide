#include "kernel_rw.h"
#include <dlfcn.h>
#ifdef __APPLE__
#include <mach/mach.h>
#endif

// 动态链接到roothide的内核原语
static int (*_kreadbuf)(uint64_t kaddr, void* output, size_t size) = NULL;
static int (*_kwritebuf)(uint64_t kaddr, const void* input, size_t size) = NULL;
static uint64_t (*_kread64)(uint64_t va) = NULL;
static uint32_t (*_kread32)(uint64_t va) = NULL;
static int (*_kwrite64)(uint64_t va, uint64_t v) = NULL;
static int (*_kwrite32)(uint64_t va, uint32_t v) = NULL;

int kernel_rw_init(void) {
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
    _kread32 = dlsym(handle, "kread32");
    _kwrite64 = dlsym(handle, "kwrite64");
    _kwrite32 = dlsym(handle, "kwrite32");

    if (!_kreadbuf || !_kwritebuf || !_kread64 || !_kread32 || !_kwrite64 || !_kwrite32) {
        printf("Failed to load kernel primitives\n");
        return -1;
    }

    printf("Kernel primitives loaded successfully\n");
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