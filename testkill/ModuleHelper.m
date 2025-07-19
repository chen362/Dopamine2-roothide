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

// 使用roothide内核原语精确搜索模块
uint64_t searchModuleByName(pid_t pid, const char* moduleName) {
#ifdef TARGET_OS_IPHONE
    // 在iOS设备上使用roothide的proc_find
    uint64_t proc = proc_find(pid);
    if (!proc) {
        NSLog(@"[testkill] 无法在内核中找到进程 %d", pid);
        return 0;
    }
    
    // 获取进程的task结构
    uint64_t task = proc_task(proc);
    if (!task) {
        NSLog(@"[testkill] 无法获取进程 %d 的task", pid);
        return 0;
    }
    
    // 获取进程的vm_map
    uint64_t vm_map = kread_ptr(task + koffsetof(task, map));
    if (!vm_map) {
        NSLog(@"[testkill] 无法获取进程 %d 的vm_map", pid);
        return 0;
    }
    
    // 遍历内存映射区域查找模块
    uint64_t entry = kread_ptr(vm_map + koffsetof(vm_map, hdr) + koffsetof(vm_map_header, links) + koffsetof(vm_map_links, next));
    
    while (entry && entry != (vm_map + koffsetof(vm_map, hdr))) {
        uint64_t start = kread64(entry + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, start));
        uint64_t end = kread64(entry + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, end));
        
        // 检查这个区域是否是可执行的
        uint32_t protection = kread32(entry + koffsetof(vm_map_entry, protection));
        if (protection & VM_PROT_EXECUTE) {
            // 读取Mach-O头部
            struct mach_header_64 header;
            if (kreadbuf(start, &header, sizeof(header)) == 0) {
                if (header.magic == MH_MAGIC_64) {
                    // 检查是否包含目标模块名
                    char buffer[4096];
                    if (kreadbuf(start, buffer, sizeof(buffer)) == 0) {
                        if (strstr(buffer, moduleName)) {
                            NSLog(@"[testkill] 找到模块 %s 地址: 0x%llx", moduleName, start);
                            return start;
                        }
                    }
                }
            }
        }
        
        // 移动到下一个entry
        entry = kread_ptr(entry + koffsetof(vm_map_entry, links) + koffsetof(vm_map_links, next));
    }
    
    NSLog(@"[testkill] 在进程 %d 中未找到模块 %s", pid, moduleName);
    return 0;
#else
    // 语法检查模式
    NSLog(@"[testkill] 语法检查模式，模拟搜索模块 %s", moduleName);
    return 0x100000000ULL; // 返回模拟地址
#endif
}

// 使用dyld信息搜索模块（更精确的方法）
uint64_t searchModuleUsingDyldInfo(pid_t pid, const char* moduleName) {
#ifdef TARGET_OS_IPHONE
    uint64_t proc = proc_find(pid);
    if (!proc) {
        NSLog(@"[testkill] 无法找到进程 %d", pid);
        return 0;
    }
    
    uint64_t task = proc_task(proc);
    if (!task) {
        NSLog(@"[testkill] 无法获取task");
        return 0;
    }
    
    // TODO: 实现dyld信息解析来获取模块地址
    // 这需要解析dyld的all_image_infos结构
    NSLog(@"[testkill] dyld信息搜索暂未实现，回退到vm_map搜索");
    return searchModuleByName(pid, moduleName);
#else
    // 语法检查模式
    NSLog(@"[testkill] 语法检查模式，模拟dyld搜索模块 %s", moduleName);
    return 0x100000000ULL;
#endif
}

// 纯内核态搜索lolm模块
uint64_t searchLolmModuleKernel(uint64_t proc) {
    pid_t pid = getLolmPID();
    return searchModuleByName(pid, "lolm");
}

// 纯内核态搜索FEProj模块
uint64_t searchFeProjModuleKernel(uint64_t proc) {
    pid_t pid = getLolmPID();
    return searchModuleByName(pid, "FEProj");
}

// 保留原有的用户态搜索函数作为备用
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

// 写入调试日志函数
void writeDebugLog(NSString *message) {
#ifdef TARGET_OS_IPHONE
    NSLog(@"[testkill] %@", message);
    
    // 可选：写入文件日志
    NSString *logPath = @"/tmp/testkill.log";
    NSString *timestamp = [[NSDate date] description];
    NSString *logEntry = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];
    
    // 追加写入日志文件
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
    if (fileHandle) {
        [fileHandle seekToEndOfFile];
        [fileHandle writeData:[logEntry dataUsingEncoding:NSUTF8StringEncoding]];
        [fileHandle closeFile];
    } else {
        // 文件不存在，创建新文件
        [logEntry writeToFile:logPath 
                   atomically:YES 
                     encoding:NSUTF8StringEncoding 
                        error:nil];
    }
#else
    // 语法检查模式
    printf("[testkill] %s\n", [message UTF8String]);
#endif
} 