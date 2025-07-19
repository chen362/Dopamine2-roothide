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
    int camp;       // 阵营: 2=蓝方, 1=红方
    int heroId;     // 英雄ID
    float hpPercentage;  // 添加这行
    float posX;     // X坐标(解密后)
    float posY;     // Y坐标(解密后)
    float posZ;     // Z坐标(解密后)
} HeroInfo;

#ifdef __cplusplus
extern "C" {
#endif

// 纯内核态的模块搜索接口
pid_t getLolmPID(void);
uint64_t searchLolmModuleKernel(uint64_t proc);
uint64_t searchFeProjModuleKernel(uint64_t proc);

// 兼容性函数（仍保留原接口）
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