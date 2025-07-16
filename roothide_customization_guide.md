# roothide Dopamine 2 定制指南：隐藏特定 dylib 和屏蔽越狱检测

## 概述

roothide Dopamine 2 是一个先进的 iOS 越狱工具，其核心特性是使用 roothide 技术来隐藏越狱痕迹。这个指南将详细说明如何修改存储库来：

1. **隐藏特定的 dylib 文件**
2. **屏蔽应用程序的越狱检测能力**
3. **自定义黑名单机制**

## roothide 技术原理

### 核心组件

1. **roothidehooks.dylib** - 主要的隐藏钩子库
2. **黑名单系统** - 动态管理哪些应用受到保护
3. **路径重定向** - 隐藏越狱相关路径
4. **dyld 补丁** - 在动态库级别进行隐藏

### 关键文件位置

```
BaseBin/roothidehooks/          # 主要的隐藏钩子实现
├── main.x                      # 入口点
├── pathhook.x                  # 路径隐藏
├── lsd.x                       # LaunchServices 隐藏
├── springboard.x               # SpringBoard 隐藏
├── cfprefsd.x                  # 偏好设置隐藏
└── common.h/m                  # 通用功能

BaseBin/libjailbreak/src/roothider/  # roothide 核心实现
├── blacklist.cpp               # 黑名单管理
├── dyld_patch.m               # 动态库补丁
├── common.m                   # 通用 roothide 功能
└── exec_patch.m               # 执行补丁
```

## 修改方案

### 1. 隐藏特定 dylib

#### 方案 A：修改 dyld_patch.m

在 `BaseBin/libjailbreak/src/roothider/dyld_patch.m` 中添加特定 dylib 的隐藏逻辑：

```objective-c
// 在文件顶部添加要隐藏的 dylib 列表
static NSArray *hiddenDylibs = @[
    @"libsubstrate.dylib",
    @"libhooker.dylib", 
    @"CydiaSubstrate.framework",
    @"你要隐藏的dylib名称"
];

// 修改 dyld 镜像枚举函数
bool shouldHideDylib(const char* imagePath) {
    if (!imagePath) return false;
    
    NSString *path = @(imagePath);
    for (NSString *hiddenDylib in hiddenDylibs) {
        if ([path containsString:hiddenDylib]) {
            return true;
        }
    }
    return false;
}
```

#### 方案 B：修改 common.m 中的路径检查

在 `BaseBin/roothidehooks/common.m` 中扩展 `isJailbreakBundlePath` 函数：

```objective-c
bool isJailbreakBundlePath(const char* path)
{
    if(!path) return false;
    
    // 添加特定 dylib 的检查
    NSString *pathStr = @(path);
    NSArray *dylibsToHide = @[
        @"libsubstrate.dylib",
        @"libhooker.dylib",
        @"你的自定义dylib"
    ];
    
    for (NSString *dylibName in dylibsToHide) {
        if ([pathStr containsString:dylibName]) {
            return true; // 标记为越狱文件，将被隐藏
        }
    }
    
    // 原有逻辑...
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

### 2. 自定义应用黑名单

#### 修改 common.h 中的敏感应用列表

```objective-c
// 在 BaseBin/roothidehooks/common.h 中修改
#define SENSITIVE_APP_LIST   @[ \
    @"com.icraze.gtatracker", \
    @"com.Alfie.TrollInstallerX", \
    @"com.opa334.Dopamine", \
    @"com.opa334.Dopamine.roothide", \
    @"com.opa334.Dopamine-roothide", \
    @"你要保护免受检测的应用bundle_id", \
    @"com.example.protected.app", \
]
```

#### 添加动态黑名单管理

在 `BaseBin/libjailbreak/src/roothider/blacklist.cpp` 中添加：

```cpp
// 添加包名黑名单检查
extern "C" bool isBlacklistedBundle(const char* bundleId)
{
    if (!bundleId) return false;
    
    NSArray *protectedApps = @[
        @"com.yourapp.bundle.id",
        @"com.another.protected.app"
    ];
    
    NSString *bundle = @(bundleId);
    for (NSString *protectedBundle in protectedApps) {
        if ([bundle isEqualToString:protectedBundle]) {
            return true;
        }
    }
    
    return false;
}
```

### 3. 强化检测屏蔽

#### 修改 lsd.x 增强应用隐藏

```objective-c
// 在 BaseBin/roothidehooks/lsd.x 中添加更强的过滤
%hook _LSQueryContext

-(NSMutableDictionary*)_resolveQueries:(NSMutableSet*)queries XPCConnection:(NSXPCConnection*)connection error:(NSError*)err 
{
    NSMutableDictionary* result = %orig;
    
    if(!result || !connection) {
        return result;
    }

    pid_t pid = connection.processIdentifier;
    
    // 检查是否为受保护的应用
    if(jbclient_blacklist_check_pid(pid)==false) {
        return result;
    }
    
    // 添加额外的过滤逻辑
    NSMutableDictionary *filteredResult = [result mutableCopy];
    
    for(id key in result) {
        if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithUnits")]
           || [key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithIdentifier")]) {
            
            NSMutableArray* plugins = result[key];
            NSMutableArray* filteredPlugins = [NSMutableArray array];
            
            for (id plugin in plugins) {
                id appbundle = [plugin performSelector:@selector(containingBundle)];
                NSURL* bundleURL = [appbundle performSelector:@selector(bundleURL)];
                
                if(bundleURL && !isJailbreakBundlePath(bundleURL.path.fileSystemRepresentation)) {
                    [filteredPlugins addObject:plugin];
                }
            }
            
            filteredResult[key] = filteredPlugins;
        }
    }
    
    return filteredResult;
}

%end
```

#### 修改 SpringBoard 钩子

```objective-c
// 在 BaseBin/roothidehooks/springboard.x 中增强隐藏
%hook SBApplicationController

- (id)applicationWithBundleIdentifier:(NSString*)bundleIdentifier
{
    // 检查调用者是否为受保护应用
    pid_t callerPid = getpid(); // 或者通过其他方式获取调用者PID
    
    if(jbclient_blacklist_check_pid(callerPid)) {
        // 隐藏所有越狱相关应用
        NSArray *jailbreakApps = @[
            @"com.saurik.Cydia",
            @"org.coolstar.SileoStore", 
            @"com.tigisoftware.Filza",
            @"你要隐藏的应用bundle_id"
        ];
        
        if([jailbreakApps containsObject:bundleIdentifier]) {
            return nil; // 假装应用不存在
        }
    }
    
    return %orig;
}

%end
```

### 4. 文件系统级别隐藏

#### 扩展路径钩子

```objective-c
// 在 BaseBin/roothidehooks/pathhook.x 中添加更多路径隐藏
static NSArray *hiddenPaths = nil;

%ctor {
    hiddenPaths = @[
        @"/Applications/Cydia.app",
        @"/Applications/Sileo.app", 
        @"/var/lib/cydia",
        @"/var/lib/dpkg",
        @"/Library/MobileSubstrate",
        @"/usr/libexec/cydia",
        @"你要隐藏的路径"
    ];
}

// Hook更多文件系统函数
%hookf(int, access, const char *path, int mode) {
    if(shouldHidePath(path)) {
        errno = ENOENT;
        return -1;
    }
    return %orig(path, mode);
}

%hookf(int, stat, const char *path, struct stat *buf) {
    if(shouldHidePath(path)) {
        errno = ENOENT; 
        return -1;
    }
    return %orig(path, buf);
}

bool shouldHidePath(const char *path) {
    if(!path) return false;
    
    // 检查调用者
    pid_t callerPid = getpid();
    if(!jbclient_blacklist_check_pid(callerPid)) {
        return false; // 不是受保护应用，不隐藏
    }
    
    NSString *pathStr = @(path);
    for(NSString *hiddenPath in hiddenPaths) {
        if([pathStr hasPrefix:hiddenPath]) {
            return true;
        }
    }
    return false;
}
```

## 构建和部署

### 1. 修改 Makefile

确保编译包含你的修改：

```makefile
# 在 BaseBin/roothidehooks/Makefile 中
roothidehooks_FILES = $(wildcard *.x) $(wildcard *.c) $(wildcard *.m) your_custom_file.m
```

### 2. 重新编译

```bash
cd BaseBin
make clean
make roothidehooks
```

### 3. 测试修改

```bash
# 编译完整项目
cd Application  
make
```

## 高级定制技巧

### 1. 动态配置系统

创建配置文件 `/var/jb/etc/roothide.conf`：

```json
{
    "hidden_dylibs": [
        "libsubstrate.dylib",
        "your_custom.dylib"
    ],
    "protected_apps": [
        "com.yourapp.bundle.id"
    ],
    "hidden_paths": [
        "/your/custom/path"
    ]
}
```

### 2. 运行时切换

添加控制开关来动态启用/禁用隐藏：

```objective-c
// 在 common.m 中
static bool roothide_enabled = true;

void setRoothideEnabled(bool enabled) {
    roothide_enabled = enabled;
}

bool isRoothideEnabled() {
    return roothide_enabled;
}
```

### 3. 日志和调试

添加详细的日志记录：

```objective-c
#ifdef DEBUG
#define RHLog(fmt, ...) NSLog(@"[RootHide] " fmt, ##__VA_ARGS__)
#else  
#define RHLog(fmt, ...)
#endif
```

## 注意事项

1. **兼容性**：修改时要考虑不同 iOS 版本的兼容性
2. **稳定性**：过度的隐藏可能导致系统不稳定
3. **检测对抗**：检测技术在不断演进，需要持续更新
4. **法律风险**：确保使用符合当地法律法规

## 总结

通过修改 roothide Dopamine 2 的核心组件，你可以：

- 在系统级别隐藏特定的 dylib 文件
- 对特定应用程序屏蔽越狱检测
- 自定义黑名单和白名单机制  
- 实现更强的隐藏效果

记住，这些修改需要深入理解 iOS 系统架构和越狱技术。建议在测试设备上进行充分测试后再部署到主要设备。