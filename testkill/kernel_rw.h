#ifndef __TESTKILL_KERNEL_RW_H__
#define __TESTKILL_KERNEL_RW_H__

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

// 直接包含libjailbreak头文件
#ifdef TARGET_OS_IPHONE
#include <roothide.h>
#include "libjailbreak.h"
#include "primitives.h"
#include "kernel.h"
#include "info.h"
#include "util.h"

#else
// 语法检查模式下的声明
int jbclient_initialize_primitives(void);
int kreadbuf(uint64_t kaddr, void* buffer, size_t size);
uint64_t proc_find(pid_t pid);
uint64_t proc_task(uint64_t proc);
uint64_t kread_ptr(uint64_t addr);
uint32_t kread32(uint64_t addr);
uint64_t kread64(uint64_t addr);

// 模拟jbroot函数
#define jbroot(path) path
#endif

// 纯内核态初始化
int pure_kernel_init(void);

#endif