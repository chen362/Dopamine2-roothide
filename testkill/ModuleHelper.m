#import "ModuleHelper.h"
#include "kernel_rw.h"

// 获取进程PID
pid_t getLolmPID(void) {
    int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
    size_t size;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) < 0) return -1;
    
    struct kinfo_proc *proc = (struct kinfo_proc *)malloc(size);
    if (!proc) return -1;
    
    if (sysctl(mib, 4, proc, &size, NULL, 0) < 0) {
        free(proc);
        return -1;
    }
    
    pid_t targetPid = -1;
    int procCount = size / sizeof(struct kinfo_proc);
    for (int i = 0; i < procCount; i++) {
        if (strcmp(proc[i].kp_proc.p_comm, "lolm") == 0) {
            targetPid = proc[i].kp_proc.p_pid;
            break;
        }
    }
    free(proc);
    
    return targetPid;
}

// 纯内核态搜索lolm模块（使用roothide内核原语）
uint64_t searchLolmModuleKernel(uint64_t proc) {
    // 在纯内核态下，我们可以直接遍历进程的内存映射
    // 这里暂时使用简化的搜索方法
    uint64_t testBases[] = {
        0x100000000ULL,
        0x102000000ULL,
        0x104000000ULL,
        0x106000000ULL,
        0x108000000ULL,
        0x10a000000ULL
    };
    
    for (int i = 0; i < sizeof(testBases)/sizeof(testBases[0]); i++) {
        char buffer[4096] = {0};
        if (kreadbuf(testBases[i], buffer, sizeof(buffer)) == 0) {
            if (strstr(buffer, "lolm")) {
                return testBases[i];
            }
        }
    }
    return 0;
}

// 纯内核态搜索FEProj模块
uint64_t searchFeProjModuleKernel(uint64_t proc) {
    uint64_t testBases[] = {
        0x110000000ULL,
        0x120000000ULL,
        0x130000000ULL,
        0x140000000ULL,
        0x150000000ULL,
        0x160000000ULL,
        0x170000000ULL,
        0x180000000ULL
    };
    
    for (int i = 0; i < sizeof(testBases)/sizeof(testBases[0]); i++) {
        char buffer[4096] = {0};
        if (kreadbuf(testBases[i], buffer, sizeof(buffer)) == 0) {
            if (strstr(buffer, "FEProj")) {
                return testBases[i];
            }
        }
    }
    return 0;
}

uint64_t searchLolmModule(task_t task) {
    vm_address_t address = 0;
    vm_size_t size;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName;
    
    while (true) {
        if (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, 
                        (vm_region_info_t)&info, &infoCount, &objectName) != KERN_SUCCESS) break;
        
        if ((info.protection & VM_PROT_READ)) {
            char buffer[4096];
            vm_size_t bytesRead;
            if (vm_read_overwrite(task, address, sizeof(buffer), (vm_address_t)buffer, &bytesRead) == KERN_SUCCESS) {
                struct mach_header_64 *header = (struct mach_header_64 *)buffer;
                if (header->magic == MH_MAGIC_64) {
                    char *cmds = malloc(header->sizeofcmds);
                    if (cmds) {
                        if (vm_read_overwrite(task, address + sizeof(struct mach_header_64), 
                                            header->sizeofcmds, (vm_address_t)cmds, &bytesRead) == KERN_SUCCESS) {
                            struct load_command *lc = (struct load_command *)cmds;
                            for (uint32_t i = 0; i < header->ncmds; i++) {
                                if (lc->cmd == LC_SEGMENT_64) {
                                    struct segment_command_64 *seg = (struct segment_command_64 *)lc;
                                    if (strcmp(seg->segname, "__TEXT") == 0) {
                                        char *text = malloc(seg->filesize);
                                        if (text) {
                                            if (vm_read_overwrite(task, address + seg->fileoff, 
                                                                seg->filesize, (vm_address_t)text, &bytesRead) == KERN_SUCCESS) {
                                                if (memmem(text, seg->filesize, "lolm", 4)) {
                                                    free(text);
                                                    free(cmds);
                                                    return address;
                                                }
                                            }
                                            free(text);
                                        }
                                    }
                                }
                                lc = (struct load_command *)((char *)lc + lc->cmdsize);
                            }
                        }
                        free(cmds);
                    }
                }
            }
        }
        address += size;
    }
    return 0;
}

uint64_t searchFeProjModule(task_t task) {
    vm_address_t address = 0;
    vm_size_t size;
    vm_region_basic_info_data_64_t info;
    mach_msg_type_number_t infoCount = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t objectName;
    
    while (true) {
        if (vm_region_64(task, &address, &size, VM_REGION_BASIC_INFO_64, 
                        (vm_region_info_t)&info, &infoCount, &objectName) != KERN_SUCCESS) break;
        
        if ((info.protection & VM_PROT_READ) && (info.protection & VM_PROT_EXECUTE)) {
            char buffer[4096];
            vm_size_t bytesRead;
            if (vm_read_overwrite(task, address, sizeof(buffer), (vm_address_t)buffer, &bytesRead) == KERN_SUCCESS) {
                if (memmem(buffer, bytesRead, "FEProj", 6)) return address;
            }
        }
        address += size;
    }
    return 0;
} 