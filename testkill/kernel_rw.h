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
#include <libjailbreak/libjailbreak.h>

// 内核偏移量定义（这些应该从libjailbreak获取）
#define koffsetof(type, member) ksizeof_##type##_##member
#define ksizeof(type) ksizeof_##type

// 常用的内核偏移量（需要根据iOS版本调整）
extern uint64_t ksizeof_proc;
extern uint64_t koffsetof_proc_pid;
extern uint64_t koffsetof_proc_list_next;
extern uint64_t koffsetof_task_map;
extern uint64_t koffsetof_vm_map_hdr;
extern uint64_t koffsetof_vm_map_header_links;
extern uint64_t koffsetof_vm_map_links_next;
extern uint64_t koffsetof_vm_map_links_start;
extern uint64_t koffsetof_vm_map_entry_links;
extern uint64_t koffsetof_vm_map_entry_protection;

// 声明roothide的内核函数
uint64_t proc_find(pid_t pid);
uint64_t proc_task(uint64_t proc);
uint64_t kread_ptr(uint64_t addr);
uint32_t kread32(uint64_t addr);
uint64_t kread64(uint64_t addr);

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
#endif

// 纯内核态初始化
int pure_kernel_init(void);

#endif