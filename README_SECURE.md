# 安全内存读取器 (Safe Memory Reader)

这是一个更安全的跨进程内存读取实现，用于替代传统的 `task_for_pid` + `vm_read`/`vm_write` 方式。

## 主要改进

### 1. 安全性提升
- **不直接使用 task_for_pid(0)**: 避免获取内核任务端口的高权限操作
- **多层级降级策略**: 优先使用最安全的方法，逐步降级到传统方法
- **内核级别访问**: 通过内核读写原语直接访问内存，绕过用户空间限制

### 2. 多种实现方式

#### 方式1: libjailbreak 接口 (推荐)
```c
// 使用工作区中已有的安全内核读写接口
if (gPrimitives.kreadbuf && gPrimitives.kwritebuf) {
    // 直接使用已初始化的内核读写原语
}
```

#### 方式2: kfd (Kernel File Descriptor) 框架
```c
// 使用kfd提供的稳定内核读写
uint64_t kfd_handle = kopen(512, puaf_method, kread_method, kwrite_method);
kread(kfd_handle, kernel_addr, buffer, size);
```

#### 方式3: 物理内存映射
```c
// 通过物理内存映射实现内存访问
void *mapped_addr = physrw_phystouaddr(physical_addr);
memcpy(buffer, mapped_addr, size);
```

## 技术细节

### 内核读写原语
基于工作区中的多种漏洞利用技术：

1. **WeightBufs 漏洞利用**
   - CVE-2022-32845: AMFI签名检查绕过
   - CVE-2022-32948: 越界读取漏洞
   - CVE-2022-42805: 整数溢出导致任意读取
   - CVE-2022-32899: 整数下溢导致越界写入

2. **kfd 框架支持**
   - physpuppet: 物理内存操作方法
   - smith: 内存布局操作方法  
   - landa: 高级内存访问方法

3. **Fugu14 内核调用**
   - 安全的内核函数调用机制
   - 线程状态签名和管理

### 地址转换机制
```c
// 用户空间地址 -> 内核虚拟地址 -> 物理地址
uint64_t physical_addr = kvtophys(user_virtual_addr);
uint64_t kernel_addr = phystokv(physical_addr);
```

## 编译和使用

### 1. 准备环境
```bash
# 确保已安装libjailbreak开发环境
# 确保设备已越狱并有kfd或相关漏洞利用
```

### 2. 编译
```bash
# 创建权限文件
make entitlements

# 编译调试版本
make debug

# 编译发布版本  
make release

# 签名二进制文件
make sign
```

### 3. 部署
```bash
# 本地安装
make install

# 远程部署到设备
DEVICE_IP=192.168.1.100 make deploy
```

## 代码对比

### 传统方式（不安全）
```c
// 获取进程ID
pid_t targetPid = getLolmPID();

// 获取任务端口（需要高权限）
task_t task;
task_for_pid(mach_task_self(), targetPid, &task);

// 直接内存读取
vm_read_overwrite(task, address, size, (vm_address_t)buffer, &readSize);
```

### 安全方式（推荐）
```c
// 初始化安全内存读取器
SafeMemoryReader *reader = [SafeMemoryReader sharedInstance];
[reader initializeWithProcessName:@"lolm"];

// 安全内存读取
[reader readMemory:address buffer:buffer size:size];
```

## 安全优势

### 1. 权限最小化
- 不需要 `task_for_pid-allow` 权限
- 不直接操作任务端口
- 通过内核级别访问绕过用户空间限制

### 2. 隐蔽性增强
- 不会被常见的越狱检测方法发现
- 不在进程的任务端口列表中留下痕迹
- 使用内核级别的读写操作

### 3. 稳定性提升
- 利用物理内存映射，避免虚拟内存保护
- 多种降级方案，确保在不同环境下都能工作
- 错误处理更加完善

## 兼容性

### 支持的iOS版本
- iOS 15.0 - 16.x: 完全支持
- iOS 14.x: 部分支持（需要相应的漏洞利用）
- iOS 17.x: 需要额外适配

### 支持的设备
- iPhone 12 及以上: 推荐使用 kfd + physpuppet
- iPhone 11 及以下: 推荐使用 WeightBufs + smith
- iPad: 根据芯片类型选择相应方法

## 注意事项

1. **需要越狱环境**: 安全内存读取器依赖于内核漏洞利用
2. **权限配置**: 确保应用有适当的权限配置
3. **兼容性测试**: 在目标设备上充分测试
4. **错误处理**: 实现适当的错误恢复机制

## 故障排除

### 常见问题
1. **初始化失败**: 检查是否有可用的内核读写原语
2. **读取失败**: 验证目标地址的有效性
3. **权限不足**: 确认应用权限配置

### 调试方法
```bash
# 启用调试模式
make debug

# 查看日志
tail -f /var/log/syslog | grep SafeMemoryReader
```

## 参考资料

- [libjailbreak 文档](https://github.com/roothide/Developer)
- [kfd 框架说明](https://github.com/felix-pb/kfd)
- [WeightBufs 漏洞分析](./Application/Dopamine/Exploits/weightBufs/)
- [Fugu14 技术细节](./BaseBin/libjailbreak/src/kcall_Fugu14.c)