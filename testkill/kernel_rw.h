#ifndef __TESTKILL_KERNEL_RW_H__
#define __TESTKILL_KERNEL_RW_H__

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

// 内核读写函数声明
int kernel_init(void);
uint64_t proc_find(pid_t pid);
uint64_t proc_task(uint64_t proc);
uint64_t proc_vm_map(uint64_t proc);

// 纯内核态的内存读写函数
uint32_t kread32(uint64_t kaddr);
uint64_t kread64(uint64_t kaddr);
uint64_t kread_ptr(uint64_t kaddr);
int kreadbuf(uint64_t kaddr, void* buffer, size_t size);

void kwrite32(uint64_t kaddr, uint32_t val);
void kwrite64(uint64_t kaddr, uint64_t val);
int kwritebuf(uint64_t kaddr, const void* data, size_t size);

// 进程内存读写函数
int proc_kreadbuf(uint64_t proc, uint64_t addr, void* buffer, size_t size);
uint64_t proc_read_ptr_chain(uint64_t proc, uint64_t base, uint64_t *offsets, int count);

// 模块搜索函数
uint64_t proc_find_module_base(uint64_t proc, const char* module_name);

#endif