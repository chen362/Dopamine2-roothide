# testkill 纯内核态版本编译说明

## 🎯 修复内容

### 1. 头文件问题修复
- ✅ 移除了对 `libjailbreak/libjailbreak.h` 的直接依赖
- ✅ 使用动态加载方式获取 roothide 函数
- ✅ 添加了条件编译保护

### 2. 编译配置简化
```makefile
# 简化的编译标志
FloatingBallHelper_CFLAGS = -fobjc-arc $(OBFUSCATE_FLAGS) -DTARGET_OS_IPHONE=1
# 只链接系统框架，运行时动态加载 libjailbreak
FloatingBallHelper_LDFLAGS = -framework Foundation -framework UIKit
```

### 3. 动态加载实现
```c
// kernel_rw.c 中的动态加载
void *libjailbreak_handle = dlopen("/usr/lib/libjailbreak.dylib", RTLD_LAZY);
_kreadbuf = dlsym(libjailbreak_handle, "kreadbuf");
_proc_find = dlsym(libjailbreak_handle, "proc_find");
// ... 其他函数
```

## 🔧 在 macOS 上编译

1. **确保环境**：
   ```bash
   # 确保 Theos 已安装
   echo $THEOS
   # 确保在项目目录
   cd /path/to/testkill
   ```

2. **编译命令**：
   ```bash
   make clean
   make package
   ```

3. **如果仍有头文件错误**，可以尝试：
   ```bash
   # 查找 libjailbreak 头文件位置
   find $THEOS -name "libjailbreak.h" 2>/dev/null
   # 或者查找系统位置
   find /usr -name "libjailbreak.h" 2>/dev/null
   ```

## ⚠️ 常见问题

### 问题1：找不到 libjailbreak.h
**解决方案**：已修复 - 使用动态加载，不再需要编译时头文件

### 问题2：Foundation 头文件错误 
**解决方案**：已修复 - 从 kernel_rw.c 中移除了 Foundation 包含

### 问题3：mach 相关常量未定义
**解决方案**：这些常量在用户态函数中仍然需要，但已通过条件编译保护

## 🎯 核心修改文件

1. **kernel_rw.h** - 移除直接头文件依赖
2. **kernel_rw.c** - 实现动态加载
3. **Makefile** - 简化编译配置
4. **ModuleHelper.m** - 添加条件编译保护

## 📱 部署到设备

编译成功后：
```bash
# 安装到设备
make install
# 或者手动安装 deb 包
dpkg -i packages/testkill_*.deb
```

## ✅ 验证功能

程序启动时会：
1. 调用 `pure_kernel_init()` 初始化 roothide
2. 动态加载 libjailbreak.dylib
3. 获取内核原语函数指针
4. 使用纯内核态方式搜索模块和读取内存

## 🔍 调试

如果运行时有问题，检查：
1. 设备是否安装了 roothide 越狱
2. `/usr/lib/libjailbreak.dylib` 是否存在
3. 程序是否有正确的权限和签名