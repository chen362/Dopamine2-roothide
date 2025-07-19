#ifndef MODULEHELPER_H
#define MODULEHELPER_H

#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <string.h>
#import <stdlib.h>
#import <sys/sysctl.h>
#import <UIKit/UIKit.h>

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

// 获取进程PID
pid_t getLolmPID(void);

// 搜索lolm模块
uint64_t searchLolmModule(task_t task);

// 搜索FEProj模块
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