# 隐藏 FloatingBall 插件的 roothide 修改指南

## 问题分析

你的插件 `c0m.hg4sd.f1oat1ngba11` 通过以下方式被游戏检测到：

1. **插件文件路径检测** - 游戏扫描插件目录
2. **dylib 注入检测** - 游戏检测注入的动态库
3. **task_for_pid 行为检测** - 游戏检测进程注入行为
4. **Helper 进程检测** - 游戏检测 FloatingBallHelper 进程
5. **内存特征检测** - 游戏扫描内存中的插件特征

## 解决方案

### 1. 修改黑名单系统，添加游戏保护

#### 1.1 修改 `BaseBin/roothidehooks/common.h`

```objective-c
#include <stdbool.h>

#include <libjailbreak/libjailbreak.h>
#include <libjailbreak/jbclient_xpc.h>
#include <libjailbreak/roothider.h>
#include <libjailbreak/codesign.h>

bool isJailbreakBundlePath(const char* path);
bool isFloatingBallRelated(const char* path);

// 添加游戏应用到敏感列表
#define SENSITIVE_APP_LIST   @[ \
    @"com.icraze.gtatracker", \
    @"com.Alfie.TrollInstallerX", \
    @"com.opa334.Dopamine", \
    @"com.opa334.Dopamine.roothide", \
    @"com.opa334.Dopamine-roothide", \
    @"你的游戏bundle_id", \
]

// 添加要隐藏的插件列表
#define HIDDEN_TWEAK_LIST @[ \
    @"c0m.hg4sd.f1oat1ngba11", \
    @"TestFloatingBall", \
    @"FloatingBallHelper", \
]

// 要隐藏的文件路径
#define HIDDEN_PATHS @[ \
    @"/Library/MobileSubstrate/DynamicLibraries/TestFloatingBall.dylib", \
    @"/Library/Helper/FloatingBallHelper", \
    @"/var/jb/Library/MobileSubstrate/DynamicLibraries/TestFloatingBall.dylib", \
    @"/var/jb/Library/Helper/FloatingBallHelper", \
    @"/Library/TweakInject/TestFloatingBall.dylib", \
    @"/var/jb/Library/TweakInject/TestFloatingBall.dylib", \
]
```

#### 1.2 修改 `BaseBin/roothidehooks/common.m`

```objective-c
#import <Foundation/Foundation.h>
#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <roothide.h>
#include <sys/mount.h>
#include "common.h"

bool isFloatingBallRelated(const char* path)
{
    if(!path) return false;
    
    NSString *pathStr = @(path);
    NSArray *hiddenPaths = HIDDEN_PATHS;
    
    for(NSString *hiddenPath in hiddenPaths) {
        if([pathStr containsString:hiddenPath] || 
           [pathStr containsString:@"TestFloatingBall"] ||
           [pathStr containsString:@"FloatingBallHelper"] ||
           [pathStr containsString:@"f1oat1ngba11"]) {
            return true;
        }
    }
    return false;
}

bool isJailbreakBundlePath(const char* path)
{
    if(!path) return false;

    // 首先检查是否为 FloatingBall 相关
    if(isFloatingBallRelated(path)) {
        return true; // 标记为越狱文件，将被隐藏
    }

    struct statfs fs;
    if(statfs(path, &fs) != 0) {
        return true;
    }

    if(strcmp(fs.f_mntonname, "/") == 0) {
        return false;
    }

    if(isRemovableBundlePath(path)) {
        if(!hasTrollstoreMarker(path)) {
            return false;
        }
    }

    return true;
}
```

### 2. 增强路径隐藏机制

#### 2.1 修改 `BaseBin/roothidehooks/pathhook.x`

```objective-c
#import <Foundation/Foundation.h>
#import <substrate.h>
#include <roothide.h>
#include "common.h"

#ifndef DEBUG
#define NSLog(args...)	
#endif

// Hook 文件系统访问函数
%hookf(int, access, const char *path, int mode) {
    if(shouldHideFloatingBall(path)) {
        errno = ENOENT;
        return -1;
    }
    return %orig(path, mode);
}

%hookf(int, stat, const char *path, struct stat *buf) {
    if(shouldHideFloatingBall(path)) {
        errno = ENOENT; 
        return -1;
    }
    return %orig(path, buf);
}

%hookf(int, lstat, const char *path, struct stat *buf) {
    if(shouldHideFloatingBall(path)) {
        errno = ENOENT; 
        return -1;
    }
    return %orig(path, buf);
}

%hookf(FILE*, fopen, const char *path, const char *mode) {
    if(shouldHideFloatingBall(path)) {
        errno = ENOENT;
        return NULL;
    }
    return %orig(path, mode);
}

%hookf(int, open, const char *path, int flags, ...) {
    if(shouldHideFloatingBall(path)) {
        errno = ENOENT;
        return -1;
    }
    
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, mode_t);
    va_end(args);
    
    return %orig(path, flags, mode);
}

bool shouldHideFloatingBall(const char *path) {
    if(!path) return false;
    
    // 检查调用者是否为受保护应用
    pid_t callerPid = getpid();
    if(!jbclient_blacklist_check_pid(callerPid)) {
        return false; // 不是受保护应用，不隐藏
    }
    
    return isFloatingBallRelated(path);
}

// 原有的路径钩子代码...
CFURLRef (*orig__CFCopyHomeDirURLForUser)(const char *username, bool fallBackToHome) = NULL;
CFURLRef new__CFCopyHomeDirURLForUser(const char *username, bool fallBackToHome)
{
    CFURLRef url = orig__CFCopyHomeDirURLForUser(username, fallBackToHome);

    char path[PATH_MAX]={0};
    if(CFURLGetFileSystemRepresentation(url, 0, (UInt8*)path, sizeof(path)))
    {
        const char* jbpath = rootfs(path);
        if(strncmp(jbpath, "/rootfs/", sizeof("/rootfs/")-1) == 0)
        {
            CFRelease(url);
            const char* newpath = jbroot(path);
            url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8*)newpath, strlen(newpath), true);
        }
    }

    return url;
}

__attribute__((visibility("default"))) void pathhook()
{
    NSLog(@"pathhook..");

    MSImageRef coreFoundationImage = MSGetImageByName("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation");
    void* _CFCopyHomeDirURLForUser_ptr = MSFindSymbol(coreFoundationImage, "__CFCopyHomeDirURLForUser");
    if(_CFCopyHomeDirURLForUser_ptr)
    {
        MSHookFunction(_CFCopyHomeDirURLForUser_ptr, (void *)&new__CFCopyHomeDirURLForUser, (void **)&orig__CFCopyHomeDirURLForUser);
        NSLog(@"hook __CFCopyHomeDirURLForUser %p => %p : %p", _CFCopyHomeDirURLForUser_ptr, new__CFCopyHomeDirURLForUser, orig__CFCopyHomeDirURLForUser);
    }
}
```

### 3. 隐藏动态库注入

#### 3.1 修改 `BaseBin/libjailbreak/src/roothider/dyld_patch.m`

在文件开头添加：

```objective-c
// 要隐藏的动态库列表
static NSArray *hiddenDylibs = nil;

static void initHiddenDylibs() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        hiddenDylibs = @[
            @"TestFloatingBall.dylib",
            @"libfloatingball",
            @"FloatingBallHelper",
            // 添加其他要隐藏的 dylib
        ];
    });
}

bool shouldHideDylibFromFloatingBall(const char* imagePath) {
    if (!imagePath) return false;
    
    initHiddenDylibs();
    
    NSString *path = @(imagePath);
    for (NSString *hiddenDylib in hiddenDylibs) {
        if ([path containsString:hiddenDylib]) {
            return true;
        }
    }
    
    return isFloatingBallRelated(imagePath);
}
```

然后在适当的位置添加过滤逻辑。

### 4. 隐藏进程和注入行为

#### 4.1 创建新文件 `BaseBin/roothidehooks/processHide.x`

```objective-c
#import <Foundation/Foundation.h>
#include <roothide.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include "common.h"

// Hook task_for_pid 来隐藏注入行为
%hookf(kern_return_t, task_for_pid, mach_port_t target_tport, pid_t pid, mach_port_t *t) {
    // 检查调用者是否为受保护应用
    pid_t callerPid = getpid();
    if(jbclient_blacklist_check_pid(callerPid)) {
        // 检查目标进程是否为 FloatingBallHelper
        char targetPath[PROC_PIDPATHINFO_MAXSIZE];
        if(proc_pidpath(pid, targetPath, sizeof(targetPath)) > 0) {
            if(strstr(targetPath, "FloatingBallHelper") || 
               strstr(targetPath, "TestFloatingBall")) {
                // 伪装失败
                return KERN_FAILURE;
            }
        }
    }
    return %orig(target_tport, pid, t);
}

// Hook sysctl 来隐藏进程列表中的相关进程
%hookf(int, sysctl, int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    int result = %orig(name, namelen, oldp, oldlenp, newp, newlen);
    
    // 检查是否为进程列表查询
    if (result == 0 && name && namelen >= 3 && 
        name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_ALL) {
        
        pid_t callerPid = getpid();
        if(jbclient_blacklist_check_pid(callerPid)) {
            // 过滤进程列表，移除 FloatingBallHelper
            struct kinfo_proc *procs = (struct kinfo_proc *)oldp;
            size_t count = *oldlenp / sizeof(struct kinfo_proc);
            size_t newCount = 0;
            
            for (size_t i = 0; i < count; i++) {
                char *procName = procs[i].kp_proc.p_comm;
                if (strstr(procName, "FloatingBall") == NULL &&
                    strstr(procName, "TestFloating") == NULL) {
                    if (newCount != i) {
                        procs[newCount] = procs[i];
                    }
                    newCount++;
                }
            }
            
            *oldlenp = newCount * sizeof(struct kinfo_proc);
        }
    }
    
    return result;
}

// Hook dlopen 来隐藏动态库加载
%hookf(void*, dlopen, const char* path, int mode) {
    if(path && isFloatingBallRelated(path)) {
        pid_t callerPid = getpid();
        if(jbclient_blacklist_check_pid(callerPid)) {
            // 返回空指针，伪装加载失败
            return NULL;
        }
    }
    return %orig(path, mode);
}

__attribute__((visibility("default"))) void processHideInit(void)
{
    NSLog(@"processHideInit...");
    %init();
}
```

### 5. 增强 SpringBoard 隐藏

#### 5.1 修改 `BaseBin/roothidehooks/springboard.x`

在文件末尾添加：

```objective-c
// 隐藏 FloatingBall 相关应用
%hook SBApplicationController

- (id)applicationWithBundleIdentifier:(NSString*)bundleIdentifier
{
    pid_t callerPid = getpid();
    
    if(jbclient_blacklist_check_pid(callerPid)) {
        NSArray *hiddenTweaks = HIDDEN_TWEAK_LIST;
        if([hiddenTweaks containsObject:bundleIdentifier]) {
            return nil; // 假装应用不存在
        }
    }
    
    return %orig;
}

%end

// 修改 sbInit 函数
void sbInit(void)
{
    NSLog(@"sbInit...");
    
    // 初始化进程隐藏
    extern void processHideInit(void);
    processHideInit();
    
    %init();
}
```

### 6. 修改 Makefile

#### 6.1 更新 `BaseBin/roothidehooks/Makefile`

```makefile
TARGET_OS_DEPLOYMENT_VERSION = 14.0
ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = roothide

TWEAK_NAME = roothidehooks

roothidehooks_FILES = $(wildcard *.x) $(wildcard *.c) $(wildcard *.m) processHide.x
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

### 7. 内存特征隐藏

#### 7.1 创建 `BaseBin/roothidehooks/memoryHide.x`

```objective-c
#import <Foundation/Foundation.h>
#include <mach/mach.h>
#include <roothide.h>
#include "common.h"

// Hook vm_region 系列函数来隐藏内存区域
%hookf(kern_return_t, vm_region, vm_map_t target_task, vm_address_t *address, vm_size_t *size, vm_region_flavor_t flavor, vm_region_info_t info, mach_msg_type_number_t *infoCnt, mach_port_t *object_name) {
    
    kern_return_t result = %orig(target_task, address, size, flavor, info, infoCnt, object_name);
    
    if (result == KERN_SUCCESS) {
        pid_t callerPid = getpid();
        if(jbclient_blacklist_check_pid(callerPid)) {
            // 检查内存区域是否包含 FloatingBall 相关内容
            // 这里可以添加更复杂的内存内容检查逻辑
        }
    }
    
    return result;
}

// Hook mach_vm_read 来隐藏内存读取
%hookf(kern_return_t, mach_vm_read, vm_map_t target_task, mach_vm_address_t address, mach_vm_size_t size, vm_offset_t *data, mach_msg_type_number_t *dataCnt) {
    
    pid_t callerPid = getpid();
    if(jbclient_blacklist_check_pid(callerPid)) {
        // 可以在这里修改读取的内存内容，移除敏感字符串
        kern_return_t result = %orig(target_task, address, size, data, dataCnt);
        
        if (result == KERN_SUCCESS && data && *data) {
            // 在读取的内存中查找并替换敏感字符串
            char *memData = (char*)*data;
            for (mach_msg_type_number_t i = 0; i < *dataCnt; i++) {
                // 简单的字符串替换示例
                if (memData[i] == 'F' && strncmp(&memData[i], "FloatingBall", 12) == 0) {
                    memset(&memData[i], 'X', 12); // 用 X 替换
                }
            }
        }
        
        return result;
    }
    
    return %orig(target_task, address, size, data, dataCnt);
}

__attribute__((visibility("default"))) void memoryHideInit(void)
{
    NSLog(@"memoryHideInit...");
    %init();
}
```

### 8. 编译和部署

#### 8.1 编译修改后的 roothide

```bash
cd BaseBin
make clean
make roothidehooks

cd ../Application
make clean
make

# 生成新的 tipa 文件
```

#### 8.2 安装和测试

1. 安装修改后的 roothide Dopamine
2. 将目标游戏添加到黑名单中
3. 测试插件是否被成功隐藏

### 9. 高级隐藏技巧

#### 9.1 动态字符串混淆

在你的插件中使用字符串混淆：

```objective-c
// 不要直接使用明文字符串
NSString *tweakName = @"TestFloatingBall";

// 使用混淆后的字符串
NSString *tweakName = [self decodeString:@"VGVzdEZsb2F0aW5nQmFsbA=="];
```

#### 9.2 进程名伪装

修改 FloatingBallHelper 的进程名：

```objective-c
// 在 main 函数开始时
int main(int argc, char **argv) {
    // 伪装进程名
    strcpy(argv[0], "systemhelperd");
    prctl(PR_SET_NAME, "systemhelperd", 0, 0, 0);
    
    // 原有代码...
}
```

## 总结

通过以上修改，你的 FloatingBall 插件将在以下几个层面被隐藏：

1. **文件系统层面** - 隐藏插件文件路径
2. **进程层面** - 隐藏 Helper 进程
3. **内存层面** - 隐藏内存中的特征
4. **系统服务层面** - 在 SpringBoard 和 LaunchServices 中隐藏
5. **动态库层面** - 隐藏 dylib 注入痕迹

这样可以大大降低被游戏检测到的概率。记住要在测试设备上充分测试后再在主设备上使用。