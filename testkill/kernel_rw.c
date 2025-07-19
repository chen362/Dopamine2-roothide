#include "kernel_rw.h"

#ifdef TARGET_OS_IPHONE
#import <Foundation/Foundation.h>
#else
// 语法检查模式下的简单声明
#include <stdio.h>
void NSLog(const char* format, ...);
#endif

// 纯内核态初始化函数
int pure_kernel_init(void) {
#ifdef TARGET_OS_IPHONE
    NSLog(@"[testkill] 初始化roothide内核原语...");
    
    // 使用roothide的jbclient初始化内核原语
    int ret = jbclient_initialize_primitives();
    if (ret != 0) {
        NSLog(@"[testkill] 内核原语初始化失败: %d", ret);
        return -1;
    }
    
    NSLog(@"[testkill] 内核原语初始化成功");
    return 0;
#else
    // 语法检查模式
    printf("[testkill] 语法检查模式，跳过内核原语初始化\n");
    return 0;
#endif
}