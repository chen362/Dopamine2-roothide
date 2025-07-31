# roothide 核心文件详细分析

## 概述

这些文件构成了 roothide 技术的核心，实现了对 iOS 系统的深度隐藏和保护机制。每个文件都有特定的职责和作用范围。

---

## 1. springboard.x - SpringBoard 系统级隐藏

### 主要功能
SpringBoard 是 iOS 的桌面环境和应用启动器，这个文件负责在 SpringBoard 层面隐藏越狱痕迹。

### 核心机制

#### 1.1 应用快照保护
```objective-c
%hookf(int, fcntl, int fildes, int cmd, ...) {
    if (cmd == F_SETPROTECTIONCLASS) {
        char filePath[PATH_MAX];
        if (fcntl(fildes, F_GETPATH, filePath) != -1) {
            // 跳过对越狱应用设置保护类，避免快照保存失败
            if (isSubPathOf(jbroot("/var/mobile/Library/SplashBoard/Snapshots/"), filePath)) {
                return 0;
            }
        }
    }
}
```
**作用**：修复越狱应用的快照保存问题，确保越狱应用在后台切换时正常显示。

#### 1.2 应用快照路径重定向
```objective-c
%hook XBSnapshotContainerIdentity
-(NSString *)snapshotContainerPath {
    NSString* path = %orig;
    if([path hasPrefix:@"/var/mobile/Library/SplashBoard/Snapshots/"] && 
       ![self.bundleIdentifier hasPrefix:@"com.apple."]) {
        path = jbroot(path); // 重定向到越狱根目录
    }
    return path;
}
%end
```
**作用**：将非苹果应用的快照路径重定向到越狱环境，确保路径一致性。

#### 1.3 应用信息查询过滤
```objective-c
%hook FBSApplicationLibrary
-(id)applicationInfoForBundleIdentifier:(NSString*)bundleIdentifier
{
    id result = %orig;
    NSNumber* tag = objc_getAssociatedObject(bundleIdentifier, kDenyQueryTagKey);
    
    if(tag && tag.boolValue) {
        // 如果是敏感应用列表中的应用，拒绝查询
        if([SENSITIVE_APP_LIST containsObject:bundleIdentifier]) {
            return nil;
        }
        
        // 如果是越狱应用，拒绝查询
        if(result && executableURL && isJailbreakBundlePath(executableURL.path.fileSystemRepresentation)) {
            return nil;
        }
    }
    return result;
}
%end
```
**作用**：当受保护的应用查询其他应用信息时，隐藏越狱相关应用。

#### 1.4 应用启动请求监控
```objective-c
%hook FBSystemService
-(void*)openApplication:(NSString*)bundleIdentifier withOptions:(id)options...
{
    // 获取请求者的进程信息
    pid_t pid = _pid.intValue;
    
    // 如果请求者在黑名单中，标记要打开的应用为拒绝查询
    if(jbclient_blacklist_check_pid(pid)==true) {
        objc_setAssociatedObject(bundleIdentifier, kDenyQueryTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return %orig;
}
%end
```
**作用**：监控应用启动请求，对来自受保护应用的请求进行特殊处理。

---

## 2. lsd.x - Launch Services 服务隐藏

### 主要功能
Launch Services (lsd) 负责应用注册、URL scheme 处理、应用查询等核心服务。这个文件在服务层面进行隐藏。

### 核心机制

#### 2.1 URL Scheme 隐藏
```objective-c
BOOL isJailbreakURLScheme(NSString* scheme)
{
    NSArray* apps = [[LSApplicationWorkspace defaultWorkspace] applicationsAvailableForHandlingURLScheme:scheme];
    for(id app in apps) {
        NSURL* bundleURL = [app performSelector:@selector(bundleURL)];
        if(isJailbreakBundlePath(bundleURL.path.fileSystemRepresentation)) {
            return YES; // 是越狱相关的 URL scheme
        }
    }
    return NO;
}
```
**作用**：识别哪些 URL scheme 是由越狱应用处理的。

#### 2.2 URL 打开能力检查
```objective-c
%hook _LSCanOpenURLManager
- (BOOL)canOpenURL:(NSURL*)url publicSchemes:(BOOL)ispublic privateSchemes:(BOOL)isprivate XPCConnection:(NSXPCConnection*)connection error:(NSError*)err
{
    if(connection) {
        pid_t pid = connection.processIdentifier;
        
        // 如果调用者在黑名单中，且要打开的是越狱 URL scheme
        if(jbclient_blacklist_check_pid(pid)==true) {
            if(isJailbreakURLScheme(url.scheme)) {
                // 标记为阻止，返回 NO
                objc_setAssociatedObject(url, kBlockSchemeTagKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                blocked = YES;
            }
        }
    }
    return %orig;
}
%end
```
**作用**：阻止受保护应用打开越狱相关的 URL。

#### 2.3 插件查询过滤
```objective-c
%hook _LSQueryContext
-(NSMutableDictionary*)_resolveQueries:(NSMutableSet*)queries XPCConnection:(NSXPCConnection*)connection error:(NSError*)err 
{
    NSMutableDictionary* result = %orig;
    
    if(jbclient_blacklist_check_pid(pid)==false) {
        return result; // 不是受保护应用，不过滤
    }
    
    // 遍历查询结果，移除越狱相关的插件
    for(id key in result) {
        if([key isKindOfClass:NSClassFromString(@"LSPlugInQueryWithUnits")]) {
            NSMutableArray* plugins = result[key];
            NSMutableIndexSet* removed = [[NSMutableIndexSet alloc] init];
            
            for (int i=0; i<[plugins count]; i++) {
                id plugin = plugins[i];
                id appbundle = [plugin performSelector:@selector(containingBundle)];
                NSURL* bundleURL = [appbundle performSelector:@selector(bundleURL)];
                
                // 如果是越狱应用的插件，标记为移除
                if(isJailbreakBundlePath(bundleURL.path.fileSystemRepresentation)) {
                    [removed addIndex:i];
                }
            }
            
            [plugins removeObjectsAtIndexes:removed]; // 移除越狱插件
        }
    }
    return result;
}
%end
```
**作用**：当受保护应用查询系统插件时，过滤掉所有越狱相关的插件。

#### 2.4 应用数据路径重定向
```objective-c
NSURL* new_LSGetInboxURLForBundleIdentifier(NSString* bundleIdentifier)
{
    NSURL* pathURL = orig_LSGetInboxURLForBundleIdentifier(bundleIdentifier);
    
    if(![bundleIdentifier hasPrefix:@"com.apple."] && 
       [pathURL.path hasPrefix:@"/var/mobile/Library/Application Support/Containers/"]) {
        pathURL = [NSURL fileURLWithPath:jbroot(pathURL.path)];
    }
    return pathURL;
}
```
**作用**：重定向应用的 Inbox 目录到越狱环境。

#### 2.5 应用数据库重建处理
```objective-c
int new_LSServer_RebuildApplicationDatabases()
{
    int r = orig_LSServer_RebuildApplicationDatabases();
    
    if(access(jbroot("/.disable_auto_uicache"), F_OK) == 0) return r;
    
    // 异步执行 uicache 确保越狱应用重新添加到图标缓存
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        char* const args[] = {"/usr/bin/uicache", "-a", NULL};
        const char *uicachePath = jbroot(args[0]);
        if (access(uicachePath, F_OK) == 0) {
            posix_spawn(NULL, uicachePath, NULL, NULL, args, environ);
        }
    });
    return r;
}
```
**作用**：在系统重建应用数据库后，自动运行 uicache 恢复越狱应用。

---

## 3. blacklist.cpp - 黑名单管理系统

### 主要功能
管理哪些进程需要受到保护（即对这些进程隐藏越狱痕迹）。

### 核心数据结构
```cpp
static std::set<pid_t*> uncachedBlacklistedProcesses;  // 未缓存的黑名单进程
static std::map<pid_t, int> blacklistedProcessesState; // 已缓存的黑名单进程状态
static pthread_rwlock_t stateLock = {0};               // 读写锁
```

### 核心机制

#### 3.1 线程安全的状态管理
```cpp
void stateReadLock()   { pthread_rwlock_rdlock(&stateLock); }
void stateWriteLock()  { pthread_rwlock_wrlock(&stateLock); }
void stateReadUnlock() { pthread_rwlock_unlock(&stateLock); }
void stateWriteUnlock(){ pthread_rwlock_unlock(&stateLock); }
```
**作用**：确保多线程环境下黑名单状态的一致性。

#### 3.2 进程黑名单检查
```cpp
bool _isBlacklistedProcess(pid_t pid, int pidversion)
{
    bool blacklisted = false;
    stateReadLock();
    
    // 1. 先检查未缓存的进程
    for(auto it = uncachedBlacklistedProcesses.begin(); it != uncachedBlacklistedProcesses.end(); ++it) {
        pid_t uncachedPid = *(*it);
        if(uncachedPid>0 && uncachedPid==pid) {
            if(pidversion==proc_get_pidversion(uncachedPid)) {
                blacklisted = true;
            }
            break;
        }
    }
    
    // 2. 再检查已缓存的进程
    if(!blacklisted) {
        auto it = blacklistedProcessesState.find(pid);
        if(it != blacklistedProcessesState.end()) {
            int cached_pidversion = it->second;
            if(cached_pidversion == pidversion) {
                blacklisted = true;
            }
        }
    }
    
    stateReadUnlock();
    return blacklisted;
}
```
**作用**：检查指定 PID 的进程是否在黑名单中，使用 pidversion 确保进程唯一性。

#### 3.3 动态黑名单管理
```cpp
// 分配黑名单进程 ID
extern "C" pid_t* allocBlacklistProcessId()
{
    pid_t* pidp = (pid_t*)malloc(sizeof(pid_t));
    *pidp = 0;
    
    stateWriteLock();
    uncachedBlacklistedProcesses.insert(pidp);
    stateWriteUnlock();
    
    return pidp;
}

// 提交黑名单进程 ID
extern "C" void commitBlacklistProcessId(pid_t* pidp)
{
    stateWriteLock();
    
    pid_t pid = *pidp;
    if(pid > 0) {
        int pidversion = proc_get_pidversion(pid);
        if (pidversion > 0) {
            blacklistedProcessesState[pid] = pidversion; // 移动到已缓存状态
        }
    }
    
    uncachedBlacklistedProcesses.erase(pidp);
    free(pidp);
    
    stateWriteUnlock();
}
```
**作用**：提供动态添加/移除黑名单进程的机制。

---

## 4. common.h - 通用定义

### 主要功能
定义全局常量和函数声明。

### 核心定义
```objective-c
// 敏感应用列表（这些应用可能使用伪造证书签名）
#define SENSITIVE_APP_LIST   @[ \
    @"com.icraze.gtatracker", \
    @"com.Alfie.TrollInstallerX", \
    @"com.opa334.Dopamine", \
    @"com.opa334.Dopamine.roothide", \
    @"com.opa334.Dopamine-roothide", \
]

// 核心函数声明
bool isJailbreakBundlePath(const char* path);
```

**作用**：
- 定义需要特殊处理的应用列表
- 提供通用的头文件包含
- 声明核心判断函数

---

## 5. common.m - 路径判断核心

### 主要功能
实现判断应用路径是否为越狱相关的核心逻辑。

### 核心算法
```objective-c
bool isJailbreakBundlePath(const char* path)
{
    if(!path) return false; // 无路径可能是系统应用
    
    struct statfs fs;
    if(statfs(path, &fs) != 0) {
        return true; // 路径不存在，可能是越狱应用
    }
    
    if(strcmp(fs.f_mntonname, "/") == 0) {
        return false; // 在根文件系统上的不是越狱应用
    }
    
    if(isRemovableBundlePath(path)) {
        if(!hasTrollstoreMarker(path)) {
            return false; // 可移动但无 TrollStore 标记的是普通应用
        }
    }
    
    return true; // 其他情况视为越狱应用
}
```

**判断逻辑**：
1. **无路径** → 系统应用（不隐藏）
2. **路径不存在** → 越狱应用（隐藏）
3. **挂载点是根目录** → 系统应用（不隐藏）
4. **可移动路径但无 TrollStore 标记** → 普通应用（不隐藏）
5. **其他情况** → 越狱应用（隐藏）

---

## 工作流程总结

### 1. 系统启动时
- `main.x` 根据进程名初始化对应的钩子
- `blacklist.cpp` 初始化黑名单管理系统

### 2. 应用启动时
- `springboard.x` 监控应用启动请求
- 检查启动者是否在黑名单中
- 决定是否对目标应用进行隐藏

### 3. 应用查询时
- `lsd.x` 拦截所有应用查询请求
- 使用 `isJailbreakBundlePath` 判断应用类型
- 对黑名单中的应用隐藏越狱相关结果

### 4. URL 操作时
- `lsd.x` 检查 URL scheme 是否为越狱相关
- 阻止黑名单应用打开越狱 URL

### 5. 文件操作时
- `pathhook.x`（其他文件）重定向路径
- `common.m` 提供路径判断逻辑

这个系统实现了多层次、全方位的越狱隐藏，从系统服务层到应用层都有相应的保护机制。