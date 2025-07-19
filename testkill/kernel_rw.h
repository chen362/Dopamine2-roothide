#ifndef __TESTKILL_KERNEL_RW_H__
#define __TESTKILL_KERNEL_RW_H__

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>

// 在iOS设备上编译时包含roothide头文件
#ifdef TARGET_OS_IPHONE
#include <roothide.h>

// roothide相关的函数声明
extern int jbclient_initialize_primitives(void);
extern int kreadbuf(uint64_t kaddr, void* buffer, size_t size);
extern uint64_t proc_find(pid_t pid);
extern uint64_t proc_task(uint64_t proc);
extern uint64_t kread_ptr(uint64_t addr);
extern uint32_t kread32(uint64_t addr);
extern uint64_t kread64(uint64_t addr);

// 内核偏移量定义（需要根据iOS版本调整）
#define koffsetof(type, member) 0x0  // 实际使用时需要正确的偏移值
#define ksizeof(type) 0x0

#else
// 语法检查模式下的声明
int jbclient_initialize_primitives(void);
int kreadbuf(uint64_t kaddr, void* buffer, size_t size);
uint64_t proc_find(pid_t pid);
uint64_t proc_task(uint64_t proc);
uint64_t kread_ptr(uint64_t addr);
uint32_t kread32(uint64_t addr);
uint64_t kread64(uint64_t addr);

// 模拟的偏移量
#define koffsetof(type, member) 0x0
#define ksizeof(type) 0x0

// 模拟jbroot函数
#define jbroot(path) path
#endif

// 纯内核态初始化
int pure_kernel_init(void);

#endif