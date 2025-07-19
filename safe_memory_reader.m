#import "safe_memory_reader.h"
#import <sys/sysctl.h>
#import <mach/mach.h>
#import <dlfcn.h>

// 引入工作区中的安全读写接口
#import <libjailbreak/primitives.h>
#import <libjailbreak/kernel.h>
#import <libjailbreak/info.h>
#import <libjailbreak/util.h>

// kfd相关接口（如果可用）
typedef struct kfd_struct {
    uint64_t kslide;
    uint64_t kbase;
    // 其他kfd结构成员...
} kfd_t;

// 外部函数声明（来自kfd）
extern uint64_t kopen(int pages, int puaf_method, int kread_method, int kwrite_method);
extern int kread(uint64_t kfd, uint64_t addr, void* buf, size_t size);
extern int kwrite(uint64_t kfd, void* buf, uint64_t addr, size_t size);
extern void kclose(uint64_t kfd);

// 全局变量
static SafeMemoryReader *g_sharedReader = nil;
static SafeMemoryPrimitives g_primitives = {0};
static uint64_t g_kfd_handle = 0;

@interface SafeMemoryReader ()
@property (nonatomic, assign) ProcessInfo processInfo;
@property (nonatomic, assign) BOOL initialized;
@end

@implementation SafeMemoryReader

+ (instancetype)sharedInstance {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_sharedReader = [[SafeMemoryReader alloc] init];
    });
    return g_sharedReader;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _initialized = NO;
        memset(&_processInfo, 0, sizeof(ProcessInfo));
    }
    return self;
}

- (BOOL)initializeWithProcessName:(NSString *)processName {
    @synchronized(self) {
        if (self.initialized) {
            return YES;
        }
        
        // 1. 首先尝试使用工作区中的libjailbreak接口
        if ([self initializeWithLibjailbreak]) {
            NSLog(@"SafeMemoryReader: 使用 libjailbreak 接口初始化成功");
        }
        // 2. 尝试使用kfd接口
        else if ([self initializeWithKFD]) {
            NSLog(@"SafeMemoryReader: 使用 kfd 接口初始化成功");
        }
        // 3. 最后尝试物理内存映射
        else if ([self initializeWithPhysicalMapping]) {
            NSLog(@"SafeMemoryReader: 使用物理内存映射初始化成功");
        }
        else {
            NSLog(@"SafeMemoryReader: 所有安全方法初始化失败");
            return NO;
        }
        
        // 查找目标进程
        if (![self findTargetProcess:processName]) {
            NSLog(@"SafeMemoryReader: 查找目标进程失败: %@", processName);
            return NO;
        }
        
        _initialized = YES;
        return YES;
    }
}

- (BOOL)initializeWithLibjailbreak {
    // 检查是否已经有可用的内核读写原语
    if (gPrimitives.kreadbuf && gPrimitives.kwritebuf) {
        g_primitives.kreadbuf = gPrimitives.kreadbuf;
        g_primitives.kwritebuf = gPrimitives.kwritebuf;
        return YES;
    }
    return NO;
}

- (BOOL)initializeWithKFD {
    // 检查是否存在kfd框架
    void *kfd_handle = dlopen("/usr/lib/libkfd.dylib", RTLD_LAZY);
    if (!kfd_handle) {
        return NO;
    }
    
    // 获取kfd函数指针
    uint64_t (*kfd_open)(int, int, int, int) = dlsym(kfd_handle, "kopen");
    int (*kfd_read)(uint64_t, uint64_t, void*, size_t) = dlsym(kfd_handle, "kread");
    int (*kfd_write)(uint64_t, void*, uint64_t, size_t) = dlsym(kfd_handle, "kwrite");
    
    if (!kfd_open || !kfd_read || !kfd_write) {
        dlclose(kfd_handle);
        return NO;
    }
    
    // 尝试打开kfd
    g_kfd_handle = kfd_open(512, 1, 1, 1); // 使用默认参数
    if (g_kfd_handle == 0) {
        dlclose(kfd_handle);
        return NO;
    }
    
    // 设置读写函数
    g_primitives.kreadbuf = (int (*)(uint64_t, void*, size_t))^int(uint64_t addr, void* buf, size_t size) {
        return kfd_read(g_kfd_handle, addr, buf, size);
    };
    
    g_primitives.kwritebuf = (int (*)(uint64_t, const void*, size_t))^int(uint64_t addr, const void* buf, size_t size) {
        return kfd_write(g_kfd_handle, (void*)buf, addr, size);
    };
    
    return YES;
}

- (BOOL)initializeWithPhysicalMapping {
    // 尝试使用物理内存映射（需要特殊权限或漏洞利用）
    // 这里只是示例，实际实现需要根据具体的物理内存访问方法
    
    // 检查是否有PPL绕过或其他物理内存访问能力
    if (access("/dev/kmem", R_OK) == 0) {
        // 如果有内核内存设备文件访问权限
        g_primitives.kreadbuf = ^int(uint64_t addr, void* buf, size_t size) {
            int fd = open("/dev/kmem", O_RDONLY);
            if (fd < 0) return -1;
            
            lseek(fd, addr, SEEK_SET);
            ssize_t result = read(fd, buf, size);
            close(fd);
            
            return (result == size) ? 0 : -1;
        };
        
        return YES;
    }
    
    return NO;
}

- (BOOL)findTargetProcess:(NSString *)processName {
    // 使用内核读写查找进程
    if (!g_primitives.kreadbuf) {
        return NO;
    }
    
    // 获取allproc链表头
    uint64_t allproc = ksymbol(allproc);
    if (allproc == 0) {
        return NO;
    }
    
    uint64_t proc = 0;
    if (g_primitives.kreadbuf(allproc, &proc, sizeof(proc)) != 0) {
        return NO;
    }
    
    // 遍历进程链表
    while (proc != 0) {
        // 读取进程名
        char proc_name[256] = {0};
        if (g_primitives.kreadbuf(proc + koffsetof(proc, name), proc_name, sizeof(proc_name)) == 0) {
            if (strcmp(proc_name, [processName UTF8String]) == 0) {
                // 找到目标进程
                _processInfo.proc_kaddr = proc;
                
                // 读取pid
                pid_t pid = 0;
                g_primitives.kreadbuf(proc + koffsetof(proc, pid), &pid, sizeof(pid));
                _processInfo.pid = pid;
                
                // 读取task地址
                uint64_t task = 0;
                g_primitives.kreadbuf(proc + koffsetof(proc, task), &task, sizeof(task));
                _processInfo.task_kaddr = task;
                
                // 读取vm_map地址
                uint64_t vm_map = 0;
                g_primitives.kreadbuf(task + koffsetof(task, map), &vm_map, sizeof(vm_map));
                _processInfo.vm_map_kaddr = vm_map;
                
                // 读取pmap地址
                uint64_t pmap = 0;
                g_primitives.kreadbuf(vm_map + koffsetof(vm_map, pmap), &pmap, sizeof(pmap));
                _processInfo.pmap_kaddr = pmap;
                
                return YES;
            }
        }
        
        // 移动到下一个进程
        uint64_t next_proc = 0;
        if (g_primitives.kreadbuf(proc + koffsetof(proc, list_next), &next_proc, sizeof(next_proc)) != 0) {
            break;
        }
        proc = next_proc;
    }
    
    return NO;
}

- (BOOL)readMemory:(uint64_t)address buffer:(void *)buffer size:(size_t)size {
    if (!self.initialized || !g_primitives.kreadbuf) {
        return NO;
    }
    
    // 将用户空间地址转换为内核空间地址
    uint64_t kernel_addr = [self translateUserToKernelAddress:address];
    if (kernel_addr == 0) {
        return NO;
    }
    
    return g_primitives.kreadbuf(kernel_addr, buffer, size) == 0;
}

- (uint64_t)translateUserToKernelAddress:(uint64_t)userAddr {
    // 简化的地址转换，实际需要根据页表进行转换
    if (!self.initialized) {
        return 0;
    }
    
    // 这里需要实现虚拟地址到物理地址的转换
    // 然后再转换为内核虚拟地址
    // 具体实现取决于使用的内存访问方法
    
    return userAddr; // 临时返回，实际需要实现地址转换
}

- (uint64_t)readUInt64:(uint64_t)address {
    uint64_t value = 0;
    [self readMemory:address buffer:&value size:sizeof(value)];
    return value;
}

- (uint32_t)readUInt32:(uint64_t)address {
    uint32_t value = 0;
    [self readMemory:address buffer:&value size:sizeof(value)];
    return value;
}

- (float)readFloat:(uint64_t)address {
    float value = 0;
    [self readMemory:address buffer:&value size:sizeof(value)];
    return value;
}

- (uint64_t)followPointerChain:(uint64_t)baseAddr offsets:(NSArray<NSNumber *> *)offsets {
    uint64_t currentAddr = baseAddr;
    
    for (NSNumber *offset in offsets) {
        uint64_t targetAddr = currentAddr + [offset unsignedLongLongValue];
        uint64_t nextAddr = 0;
        if (![self readMemory:targetAddr buffer:&nextAddr size:sizeof(nextAddr)]) {
            return 0;
        }
        currentAddr = nextAddr;
    }
    
    return currentAddr;
}

- (uint64_t)virtualToPhysical:(uint64_t)virtualAddr {
    if (!g_primitives.kvtophys) {
        return 0;
    }
    return g_primitives.kvtophys(virtualAddr);
}

- (void *)mapPhysicalMemory:(uint64_t)physAddr size:(size_t)size {
    if (!g_primitives.kmap) {
        return NULL;
    }
    return g_primitives.kmap(physAddr, size);
}

- (uint64_t)findModuleBase:(NSString *)moduleName {
    // 通过内核读写查找模块基址
    // 这里需要实现模块查找逻辑
    return 0;
}

- (void)cleanup {
    @synchronized(self) {
        if (g_kfd_handle != 0) {
            kclose(g_kfd_handle);
            g_kfd_handle = 0;
        }
        
        memset(&g_primitives, 0, sizeof(g_primitives));
        memset(&_processInfo, 0, sizeof(_processInfo));
        _initialized = NO;
    }
}

- (void)dealloc {
    [self cleanup];
}

- (ProcessInfo *)targetProcess {
    return &_processInfo;
}

@end

// 全局函数实现
BOOL initializeSafeMemoryReader(void) {
    return [[SafeMemoryReader sharedInstance] initializeWithProcessName:@"lolm"];
}

SafeMemoryReader* getSharedMemoryReader(void) {
    return [SafeMemoryReader sharedInstance];
}