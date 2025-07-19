#ifndef SAFE_MEMORY_READER_H
#define SAFE_MEMORY_READER_H

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <UIKit/UIKit.h>

// 安全内存读写接口
typedef struct {
    int (*kreadbuf)(uint64_t kaddr, void* output, size_t size);
    int (*kwritebuf)(uint64_t kaddr, const void* input, size_t size);
    uint64_t (*kvtophys)(uint64_t va);
    uint64_t (*phystokv)(uint64_t pa);
    void* (*kmap)(uint64_t pa, uint64_t size);
} SafeMemoryPrimitives;

// 进程信息结构
typedef struct {
    pid_t pid;
    uint64_t task_kaddr;    // 内核中task结构地址
    uint64_t proc_kaddr;    // 内核中proc结构地址
    uint64_t vm_map_kaddr;  // 内核中vm_map结构地址
    uint64_t pmap_kaddr;    // 内核中pmap结构地址
} ProcessInfo;

// 安全内存读写器
@interface SafeMemoryReader : NSObject

@property (nonatomic, readonly) BOOL isInitialized;
@property (nonatomic, readonly) ProcessInfo *targetProcess;

// 初始化安全内存读写器
- (BOOL)initializeWithProcessName:(NSString *)processName;

// 安全内存读取
- (BOOL)readMemory:(uint64_t)address buffer:(void *)buffer size:(size_t)size;
- (uint64_t)readUInt64:(uint64_t)address;
- (uint32_t)readUInt32:(uint64_t)address;
- (float)readFloat:(uint64_t)address;

// 指针链读取
- (uint64_t)followPointerChain:(uint64_t)baseAddr offsets:(NSArray<NSNumber *> *)offsets;

// 虚拟地址转换
- (uint64_t)virtualToPhysical:(uint64_t)virtualAddr;
- (void *)mapPhysicalMemory:(uint64_t)physAddr size:(size_t)size;

// 查找进程基址
- (uint64_t)findModuleBase:(NSString *)moduleName;

// 清理资源
- (void)cleanup;

@end

// 全局函数声明
BOOL initializeSafeMemoryReader(void);
SafeMemoryReader* getSharedMemoryReader(void);

#endif /* SAFE_MEMORY_READER_H */