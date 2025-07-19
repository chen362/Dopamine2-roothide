#ifndef MODULEHELPER_H
#define MODULEHELPER_H

#import <Foundation/Foundation.h>
#include <stdint.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <mach/mach.h>
#include <mach-o/loader.h>
#include <mach-o/dyld.h>

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

// 读取4x4矩阵
void readMatrix4x4(task_t task, uint64_t lolmBase, uint64_t feBase, float *matrix);

// 遍历英雄结构
void readHeroList(task_t task, uint64_t lolmBase, HeroInfo *heroes, int *count, float *matrix);

// 坐标转换相关函数

CGPoint worldToScreen(float x, float y, float *matrix);
CGPoint toMiniMapPosition(float x, float y);

// 写入调试日志
void writeDebugLog(NSString *message);

#ifdef __cplusplus
}
#endif

#endif /* MODULEHELPER_H */ 