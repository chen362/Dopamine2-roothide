#ifndef __TESTKILL_KERNEL_RW_H__
#define __TESTKILL_KERNEL_RW_H__

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// 引入roothide的核心头文件（简化版本）
// 在实际设备上这些头文件应该可以找到
#ifdef __APPLE__
#include <roothide.h>
#include <libjailbreak/libjailbreak.h>
#else
// Linux环境下的声明（用于编译测试）
int jbclient_initialize_primitives(void);
int kreadbuf(uint64_t kaddr, void* buffer, size_t size);
#endif

// 纯内核态初始化
int pure_kernel_init(void);

// 使用roothide的内核原语（直接暴露）
// 这些函数将直接调用libjailbreak的实现

#endif