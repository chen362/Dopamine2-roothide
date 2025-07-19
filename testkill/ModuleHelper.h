#ifndef MODULEHELPER_H
#define MODULEHELPER_H

#ifdef TARGET_OS_IPHONE
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>
#else
// 语法检查模式下的简化声明
#include <stdio.h>
#include <stdint.h>
typedef uint32_t task_t;
#define MH_MAGIC_64 0xfeedfacf
#define VM_PROT_READ 0x01
#define VM_PROT_EXECUTE 0x04
#endif

#include <stdint.h>
#include <sys/sysctl.h>
#include <sys/types.h>

// 英雄信息结构体
typedef struct {
    uint32_t camp;
    uint32_t heroId;
    float posX;
    float posY;
    float posZ;
} HeroInfo;

#ifdef __cplusplus
extern "C" {
#endif

// 获取进程PID
pid_t getLolmPID(void);

// 精确的内核态模块搜索接口
uint64_t searchModuleByName(pid_t pid, const char* moduleName);
uint64_t searchLolmModuleKernel(uint64_t proc);
uint64_t searchFeProjModuleKernel(uint64_t proc);

// 更精确的方法：使用dyld信息搜索
uint64_t searchModuleUsingDyldInfo(pid_t pid, const char* moduleName);

// 兼容性函数（保留原接口）
uint64_t searchLolmModule(task_t task);
uint64_t searchFeProjModule(task_t task);

#ifdef __cplusplus
}
#endif

#endif 