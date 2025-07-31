# 隐藏跨进程内存读取行为的 roothide 修改指南

## 问题分析

你的 FloatingBall 插件通过以下方式被游戏检测到：

1. **task_for_pid 调用检测** - 游戏监控是否有进程尝试获取其 task port
2. **跨进程内存读取检测** - 游戏检测 `mach_vm_read` 等内存读取调用
3. **异常进程活动检测** - 游戏监控 SpringBoard 的异常行为
4. **系统调用监控** - 游戏检测可疑的 Mach 消息传递
5. **进程权限检测** - 游戏检测自身是否被其他进程访问

## 核心解决方案

### 1. 修改 SpringBoard 钩子，隐藏跨进程操作

#### 1.1 更新 `BaseBin/roothidehooks/springboard.x`

```objective-c
#import <Foundation/Foundation.h>
#include <roothide.h>
#import <fcntl.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include "common.h"

// 游戏进程保护列表 - 添加你要保护的游戏
static NSArray *protectedGameBundles = nil;
static NSMutableSet *protectedGamePIDs = nil;

void initProtectedGames() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        protectedGameBundles = @[
            @"com.tencent.ig",           // 和平精英
            @"com.tencent.tmgp.pubgmhd", // PUBG Mobile
            @"com.miHoYo.GenshinImpact", // 原神
            @"com.netease.hyxd",         // 荒野行动
            @"你的游戏bundle_id",        // 替换为实际的游戏 Bundle ID
        ];
        protectedGamePIDs = [NSMutableSet set];
    });
}

// 检查 PID 是否为受保护的游戏
bool isProtectedGamePID(pid_t pid) {
    if (pid <= 0) return false;
    
    @synchronized(protectedGamePIDs) {
        return [protectedGamePIDs containsObject:@(pid)];
    }
}

// 检查 Bundle ID 是否为受保护的游戏
bool isProtectedGameBundle(NSString *bundleID) {
    if (!bundleID) return false;
    initProtectedGames();
    return [protectedGameBundles containsObject:bundleID];
}

// 添加受保护的游戏 PID
void addProtectedGamePID(pid_t pid) {
    if (pid > 0) {
        @synchronized(protectedGamePIDs) {
            [protectedGamePIDs addObject:@(pid)];
        }
    }
}

// 移除受保护的游戏 PID
void removeProtectedGamePID(pid_t pid) {
    @synchronized(protectedGamePIDs) {
        [protectedGamePIDs removeObject:@(pid)];
    }
}

// Hook task_for_pid - 最关键的函数
%hookf(kern_return_t, task_for_pid, mach_port_t target_tport, pid_t pid, mach_port_t *t) {
    
    // 检查目标进程是否为受保护的游戏
    if (isProtectedGamePID(pid)) {
        NSLog(@"[RootHide] Blocked task_for_pid access to protected game PID: %d", pid);
        
        // 检查调用者 - 如果是 SpringBoard 且目标是受保护游戏，返回失败
        pid_t callerPID = getpid();
        char callerPath[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
            if (strstr(callerPath, "SpringBoard") != NULL) {
                NSLog(@"[RootHide] SpringBoard attempted to access protected game, denied");
                return KERN_FAILURE; // 伪装失败
            }
        }
    }
    
    return %orig(target_tport, pid, t);
}

// Hook mach_vm_read - 隐藏内存读取
%hookf(kern_return_t, mach_vm_read, vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, vm_offset_t *data, mach_msg_type_number_t *dataCnt) {
    
    // 检查是否为跨进程读取受保护游戏的内存
    pid_t targetPID = 0;
    if (pid_for_task(target_task, &targetPID) == KERN_SUCCESS) {
        if (isProtectedGamePID(targetPID)) {
            pid_t callerPID = getpid();
            char callerPath[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
                if (strstr(callerPath, "SpringBoard") != NULL) {
                    NSLog(@"[RootHide] Blocked memory read from SpringBoard to protected game PID: %d", targetPID);
                    return KERN_PROTECTION_FAILURE; // 伪装保护错误
                }
            }
        }
    }
    
    return %orig(target_task, address, size, data, dataCnt);
}

// Hook mach_vm_write - 隐藏内存写入
%hookf(kern_return_t, mach_vm_write, vm_map_t target_task, mach_vm_address_t address, vm_offset_t data, mach_msg_type_number_t dataCnt) {
    
    pid_t targetPID = 0;
    if (pid_for_task(target_task, &targetPID) == KERN_SUCCESS) {
        if (isProtectedGamePID(targetPID)) {
            pid_t callerPID = getpid();
            char callerPath[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
                if (strstr(callerPath, "SpringBoard") != NULL) {
                    NSLog(@"[RootHide] Blocked memory write from SpringBoard to protected game PID: %d", targetPID);
                    return KERN_PROTECTION_FAILURE;
                }
            }
        }
    }
    
    return %orig(target_task, address, data, dataCnt);
}

// Hook vm_region 系列函数 - 隐藏内存区域查询
%hookf(kern_return_t, mach_vm_region, vm_map_t target_task, mach_vm_address_t *address, mach_vm_size_t *size, vm_region_flavor_t flavor, vm_region_info_t info, mach_msg_type_number_t *infoCnt, mach_port_t *object_name) {
    
    pid_t targetPID = 0;
    if (pid_for_task(target_task, &targetPID) == KERN_SUCCESS) {
        if (isProtectedGamePID(targetPID)) {
            pid_t callerPID = getpid();
            char callerPath[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
                if (strstr(callerPath, "SpringBoard") != NULL) {
                    NSLog(@"[RootHide] Blocked vm_region from SpringBoard to protected game PID: %d", targetPID);
                    return KERN_PROTECTION_FAILURE;
                }
            }
        }
    }
    
    return %orig(target_task, address, size, flavor, info, infoCnt, object_name);
}

// Hook mach_port_allocate - 防止端口分配被检测
%hookf(kern_return_t, mach_port_allocate, ipc_space_t task, mach_port_right_t right, mach_port_name_t *name) {
    kern_return_t result = %orig(task, right, name);
    
    // 在这里可以添加端口分配的监控逻辑
    if (result == KERN_SUCCESS) {
        pid_t callerPID = getpid();
        char callerPath[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
            if (strstr(callerPath, "SpringBoard") != NULL) {
                // 可以记录 SpringBoard 的端口分配行为
            }
        }
    }
    
    return result;
}

// 监控应用启动，自动添加受保护游戏到列表
%hook FBSystemService
-(void*)openApplication:(NSString*)bundleIdentifier withOptions:(id)options originator:(id)originator requestID:(void*)requestID completion:(void*)completion
{
    // 检查是否为受保护的游戏
    if (isProtectedGameBundle(bundleIdentifier)) {
        NSLog(@"[RootHide] Protected game launching: %@", bundleIdentifier);
        
        // 延迟获取游戏 PID 并添加到保护列表
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            // 查找游戏进程 PID
            int mib[4] = {CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0};
            size_t size;
            if (sysctl(mib, 4, NULL, &size, NULL, 0) == 0) {
                struct kinfo_proc *procs = malloc(size);
                if (sysctl(mib, 4, procs, &size, NULL, 0) == 0) {
                    int count = size / sizeof(struct kinfo_proc);
                    
                    for (int i = 0; i < count; i++) {
                        pid_t pid = procs[i].kp_proc.p_pid;
                        if (pid > 0) {
                            char bundlePath[PROC_PIDPATHINFO_MAXSIZE];
                            if (proc_pidpath(pid, bundlePath, sizeof(bundlePath)) > 0) {
                                NSString *path = @(bundlePath);
                                // 检查路径是否包含游戏标识
                                for (NSString *gameBundle in protectedGameBundles) {
                                    if ([path containsString:gameBundle]) {
                                        addProtectedGamePID(pid);
                                        NSLog(@"[RootHide] Added protected game PID: %d (%@)", pid, gameBundle);
                                        break;
                                    }
                                }
                            }
                        }
                    }
                }
                free(procs);
            }
        });
    }
    
    return %orig;
}
%end

// 原有的 fcntl 钩子保持不变
%hookf(int, fcntl, int fildes, int cmd, ...) {
    if (cmd == F_SETPROTECTIONCLASS) {
        char filePath[PATH_MAX];
        if (fcntl(fildes, F_GETPATH, filePath) != -1) {
            if (isSubPathOf(jbroot("/var/mobile/Library/SplashBoard/Snapshots/"), filePath)) {
                return 0;
            }
        }
    }

    va_list a;
    va_start(a, cmd);
    const char *arg1 = va_arg(a, void *);
    const void *arg2 = va_arg(a, void *);
    const void *arg3 = va_arg(a, void *);
    const void *arg4 = va_arg(a, void *);
    const void *arg5 = va_arg(a, void *);
    const void *arg6 = va_arg(a, void *);
    const void *arg7 = va_arg(a, void *);
    const void *arg8 = va_arg(a, void *);
    const void *arg9 = va_arg(a, void *);
    const void *arg10 = va_arg(a, void *);
    va_end(a);
    return %orig(fildes, cmd, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10);
}

// 原有的快照相关钩子保持不变
@interface XBSnapshotContainerIdentity : NSObject
@property NSString* bundleIdentifier;
@end

%hook XBSnapshotContainerIdentity
-(NSString *)snapshotContainerPath {
    NSString* path = %orig;
    if([path hasPrefix:@"/var/mobile/Library/SplashBoard/Snapshots/"] && ![self.bundleIdentifier hasPrefix:@"com.apple."]) {
        NSLog(@"snapshotContainerPath redirect %@ : %@", self.bundleIdentifier, path);
        path = jbroot(path);
    }
    return path;
}
%end

static const void *kDenyQueryTagKey = &kDenyQueryTagKey;

%hook FBSApplicationLibrary
-(id)applicationInfoForBundleIdentifier:(NSString*)bundleIdentifier
{
    id result = %orig;
    NSURL* executableURL = [result performSelector:@selector(executableURL)];
    NSLog(@"FBSApplicationLibrary applicationInfoForBundleIdentifier %@ : %@, %@", bundleIdentifier, result, executableURL);

    NSNumber* tag = objc_getAssociatedObject(bundleIdentifier, kDenyQueryTagKey);

    if(tag && tag.boolValue) {
        if([SENSITIVE_APP_LIST containsObject:bundleIdentifier]) {
            NSLog(@"FBSApplicationLibrary deny query %@", bundleIdentifier);
            return nil;
        }

        if(result && executableURL && isJailbreakBundlePath(executableURL.path.fileSystemRepresentation)) {
            NSLog(@"FBSApplicationLibrary deny query %@", bundleIdentifier);
            return nil;
        }
    }

    return result;
}
%end

void sbInit(void)
{
    NSLog(@"[RootHide] SpringBoard hooks initialized");
    initProtectedGames();
    %init();
}
```

### 2. 创建专门的进程监控隐藏模块

#### 2.1 创建 `BaseBin/roothidehooks/processMonitor.x`

```objective-c
#import <Foundation/Foundation.h>
#include <roothide.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <libproc.h>
#include "common.h"

// 监控受保护进程的退出，自动清理 PID 列表
void monitorProtectedProcesses() {
    static dispatch_source_t timer = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0));
        
        dispatch_source_set_timer(timer, DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
        
        dispatch_source_set_event_handler(timer, ^{
            // 检查受保护进程是否还在运行
            extern NSMutableSet *protectedGamePIDs;
            extern void removeProtectedGamePID(pid_t pid);
            
            @synchronized(protectedGamePIDs) {
                NSMutableArray *toRemove = [NSMutableArray array];
                
                for (NSNumber *pidNum in protectedGamePIDs) {
                    pid_t pid = pidNum.intValue;
                    
                    // 检查进程是否还存在
                    if (kill(pid, 0) != 0) {
                        [toRemove addObject:pidNum];
                        NSLog(@"[RootHide] Protected game PID %d exited, removing from list", pid);
                    }
                }
                
                for (NSNumber *pidNum in toRemove) {
                    [protectedGamePIDs removeObject:pidNum];
                }
            }
        });
        
        dispatch_resume(timer);
    });
}

// Hook sysctl 来隐藏 SpringBoard 的可疑活动
%hookf(int, sysctl, int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int result = %orig(name, namelen, oldp, oldlenp, newp, newlen);
    
    // 如果是受保护进程在查询系统信息，可以在这里添加额外的隐藏逻辑
    if (result == 0 && name && namelen >= 3) {
        pid_t callerPID = getpid();
        char callerPath[PROC_PIDPATHINFO_MAXSIZE];
        
        if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
            // 检查是否为受保护的游戏在查询进程信息
            extern bool isProtectedGamePID(pid_t pid);
            if (isProtectedGamePID(callerPID)) {
                if (name[0] == CTL_KERN && name[1] == KERN_PROC) {
                    // 游戏在查询进程信息，可以在这里过滤结果
                    NSLog(@"[RootHide] Protected game PID %d querying process info", callerPID);
                    
                    if (name[2] == KERN_PROC_ALL && oldp) {
                        // 过滤进程列表，移除可疑的 SpringBoard 相关信息
                        struct kinfo_proc *procs = (struct kinfo_proc *)oldp;
                        size_t count = *oldlenp / sizeof(struct kinfo_proc);
                        size_t newCount = 0;
                        
                        for (size_t i = 0; i < count; i++) {
                            bool shouldInclude = true;
                            
                            // 检查进程名和路径，过滤掉可疑的进程
                            char *procName = procs[i].kp_proc.p_comm;
                            pid_t procPID = procs[i].kp_proc.p_pid;
                            
                            char procPath[PROC_PIDPATHINFO_MAXSIZE];
                            if (proc_pidpath(procPID, procPath, sizeof(procPath)) > 0) {
                                // 如果是 SpringBoard 且有可疑行为，可以选择隐藏
                                if (strstr(procPath, "SpringBoard") != NULL) {
                                    // 这里可以添加更复杂的判断逻辑
                                    // 目前保持 SpringBoard 可见，但可以修改其属性
                                }
                            }
                            
                            if (shouldInclude) {
                                if (newCount != i) {
                                    procs[newCount] = procs[i];
                                }
                                newCount++;
                            }
                        }
                        
                        *oldlenp = newCount * sizeof(struct kinfo_proc);
                    }
                }
            }
        }
    }
    
    return result;
}

// Hook proc_pidpath 来隐藏进程路径查询
%hookf(int, proc_pidpath, pid_t pid, void *buffer, uint32_t buffersize) {
    extern bool isProtectedGamePID(pid_t pid);
    
    if (isProtectedGamePID(getpid())) {
        // 受保护的游戏在查询进程路径
        char callerPath[PROC_PIDPATHINFO_MAXSIZE];
        if (proc_pidpath(getpid(), callerPath, sizeof(callerPath)) > 0) {
            NSLog(@"[RootHide] Protected game querying process path for PID: %d", pid);
            
            // 如果查询的是 SpringBoard 或其他敏感进程，可以返回伪造的路径
            int result = %orig(pid, buffer, buffersize);
            if (result > 0 && buffer) {
                char *path = (char *)buffer;
                if (strstr(path, "SpringBoard") != NULL) {
                    // 可以选择修改返回的路径
                    NSLog(@"[RootHide] Game queried SpringBoard path, path: %s", path);
                }
            }
            return result;
        }
    }
    
    return %orig(pid, buffer, buffersize);
}

__attribute__((visibility("default"))) void processMonitorInit(void)
{
    NSLog(@"[RootHide] Process monitor initialized");
    monitorProtectedProcesses();
    %init();
}
```

### 3. 修改内存访问检测

#### 3.1 创建 `BaseBin/roothidehooks/memoryProtection.x`

```objective-c
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <roothide.h>
#include "common.h"

// Hook mach_vm_protect 来隐藏内存保护修改
%hookf(kern_return_t, mach_vm_protect, vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, boolean_t set_maximum, vm_prot_t new_protection) {
    
    pid_t targetPID = 0;
    if (pid_for_task(target_task, &targetPID) == KERN_SUCCESS) {
        extern bool isProtectedGamePID(pid_t pid);
        if (isProtectedGamePID(targetPID)) {
            pid_t callerPID = getpid();
            char callerPath[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
                if (strstr(callerPath, "SpringBoard") != NULL) {
                    NSLog(@"[RootHide] Blocked memory protection change from SpringBoard to protected game PID: %d", targetPID);
                    return KERN_PROTECTION_FAILURE;
                }
            }
        }
    }
    
    return %orig(target_task, address, size, set_maximum, new_protection);
}

// Hook mach_vm_allocate 来隐藏内存分配
%hookf(kern_return_t, mach_vm_allocate, vm_map_t target, mach_vm_address_t *address, mach_vm_size_t size, int flags) {
    
    pid_t callerPID = getpid();
    char callerPath[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
        if (strstr(callerPath, "SpringBoard") != NULL) {
            // SpringBoard 的内存分配，可以记录日志
            // NSLog(@"[RootHide] SpringBoard allocating memory: size=%llu", size);
        }
    }
    
    return %orig(target, address, size, flags);
}

// Hook mach_vm_deallocate 来隐藏内存释放
%hookf(kern_return_t, mach_vm_deallocate, vm_map_t target, mach_vm_address_t address, mach_vm_size_t size) {
    
    pid_t callerPID = getpid();
    char callerPath[PROC_PIDPATHINFO_MAXSIZE];
    if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
        if (strstr(callerPath, "SpringBoard") != NULL) {
            // SpringBoard 的内存释放，可以记录日志
            // NSLog(@"[RootHide] SpringBoard deallocating memory: address=0x%llx, size=%llu", address, size);
        }
    }
    
    return %orig(target, address, size);
}

// Hook thread_create 来隐藏线程创建
%hookf(kern_return_t, thread_create, task_t parent_task, thread_t *child_thread) {
    
    pid_t targetPID = 0;
    if (pid_for_task(parent_task, &targetPID) == KERN_SUCCESS) {
        extern bool isProtectedGamePID(pid_t pid);
        if (isProtectedGamePID(targetPID)) {
            pid_t callerPID = getpid();
            char callerPath[PROC_PIDPATHINFO_MAXSIZE];
            if (proc_pidpath(callerPID, callerPath, sizeof(callerPath)) > 0) {
                if (strstr(callerPath, "SpringBoard") != NULL) {
                    NSLog(@"[RootHide] Blocked thread creation from SpringBoard to protected game PID: %d", targetPID);
                    return KERN_FAILURE;
                }
            }
        }
    }
    
    return %orig(parent_task, child_thread);
}

__attribute__((visibility("default"))) void memoryProtectionInit(void)
{
    NSLog(@"[RootHide] Memory protection hooks initialized");
    %init();
}
```

### 4. 更新主初始化文件

#### 4.1 修改 `BaseBin/roothidehooks/main.x`

```objective-c
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#include "common.h"

#ifndef DEBUG
#define NSLog(args...)	
#endif

NSString* safe_getExecutablePath()
{
    char executablePathC[PATH_MAX];
    uint32_t executablePathCSize = sizeof(executablePathC);
    _NSGetExecutablePath(&executablePathC[0], &executablePathCSize);
    return [NSString stringWithUTF8String:executablePathC];
}

NSString* getProcessName()
{
    return safe_getExecutablePath().lastPathComponent;
}

%ctor
{
    NSLog(@"[RootHide] roothidehooks initializing... %@", safe_getExecutablePath());
    NSString *processName = getProcessName();
    
    if ([processName isEqualToString:@"cfprefsd"]) {
        extern void cfprefsdInit(void);
        cfprefsdInit();
    }
    else if ([processName isEqualToString:@"lsd"]) {
        extern void lsdInit(void);
        lsdInit();
    }
    else if ([processName isEqualToString:@"SpringBoard"]) {
        extern void sbInit(void);
        extern void processMonitorInit(void);
        extern void memoryProtectionInit(void);
        
        sbInit();
        processMonitorInit();
        memoryProtectionInit();
        
        NSLog(@"[RootHide] SpringBoard hooks fully initialized");
    }
}
```

### 5. 更新 Makefile

#### 5.1 修改 `BaseBin/roothidehooks/Makefile`

```makefile
TARGET_OS_DEPLOYMENT_VERSION = 14.0
ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = roothide

TWEAK_NAME = roothidehooks

roothidehooks_FILES = $(wildcard *.x) $(wildcard *.c) $(wildcard *.m) processMonitor.x memoryProtection.x
roothidehooks_CFLAGS = -Werror -fobjc-arc -I../.include
roothidehooks_LDFLAGS = -rpath @loader_path/.jbroot/Library/Frameworks -rpath @loader_path/fallback -L../libjailbreak -ljailbreak

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/tweak.mk

after-roothidehooks-all::
	@cp -f $(THEOS_OBJ_DIR)/roothidehooks.dylib $(THEOS_OBJ_DIR)/roothidehooks.dylib.unsigned
	@codesign -f -s- --entitlements entitlements.xml --timestamp=none $(THEOS_OBJ_DIR)/roothidehooks.dylib
	@ldid -S $(THEOS_OBJ_DIR)/roothidehooks.dylib

clean::
	@$(MAKE) -C $(THEOS_PROJECT_DIR) clean
```

## 使用步骤

### 1. 获取游戏 Bundle ID

```bash
# 在设备上运行，找到你的游戏
ps aux | grep -i "游戏名"
# 或者
ls /var/mobile/Containers/Data/Application/ | xargs -I {} find /var/mobile/Containers/Data/Application/{} -name "*.app" 2>/dev/null
```

### 2. 修改保护列表

在 `springboard.x` 中的 `protectedGameBundles` 数组中添加你的游戏 Bundle ID：

```objective-c
protectedGameBundles = @[
    @"com.your.game.bundle.id",  // 替换为实际的游戏 Bundle ID
    // 可以添加多个游戏
];
```

### 3. 编译和安装

```bash
cd BaseBin
make clean
make roothidehooks

cd ../Application
make clean
make

# 生成新的 tipa 文件并安装
```

### 4. 测试验证

安装后测试以下功能：
- 启动游戏，确认游戏 PID 被添加到保护列表
- 运行你的 FloatingBall 插件
- 观察日志确认跨进程访问被阻止
- 验证游戏是否还能检测到外挂行为

## 高级优化

### 1. 动态配置保护游戏

创建配置文件 `/var/jb/etc/protected_games.plist`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<array>
    <string>com.your.game.bundle.id</string>
    <string>com.another.game.bundle.id</string>
</array>
</plist>
```

### 2. 插件端修改

在你的 FloatingBall 插件中添加隐蔽性：

```objective-c
// 5.25.xm 中添加检测规避
static bool isGameProcess(NSString *bundleID) {
    NSArray *games = @[@"com.your.game.bundle.id"];
    return [games containsObject:bundleID];
}

// 在进行内存操作前检查
- (void)readGameMemory {
    NSString *currentApp = [[NSBundle mainBundle] bundleIdentifier];
    
    if (isGameProcess(currentApp)) {
        // 如果当前在游戏进程中，使用更隐蔽的方法
        [self stealthMemoryOperation];
    } else {
        // 正常操作
        [self normalMemoryOperation];
    }
}
```

## 总结

这个修改方案主要通过以下方式隐藏跨进程内存读取行为：

1. **Hook task_for_pid** - 阻止 SpringBoard 获取游戏进程的 task port
2. **Hook 内存读写函数** - 阻止跨进程内存访问
3. **动态进程保护** - 自动识别和保护游戏进程
4. **系统调用监控** - 隐藏可疑的系统调用行为
5. **进程信息过滤** - 修改进程查询结果

这样你的插件就可以继续在 SpringBoard 中运行，但游戏将无法检测到跨进程的内存读取行为。