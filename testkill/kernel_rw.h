#ifndef __TESTKILL_KERNEL_RW_H__
#define __TESTKILL_KERNEL_RW_H__

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

// 内核读写函数声明
int kernel_rw_init(void);
uint32_t kread32(uint64_t kaddr);
uint64_t kread64(uint64_t kaddr);
int kreadbuf(uint64_t kaddr, void* buffer, size_t size);
void kwrite32(uint64_t kaddr, uint32_t val);
void kwrite64(uint64_t kaddr, uint64_t val);
int kwritebuf(uint64_t kaddr, const void* data, size_t size);

#endif