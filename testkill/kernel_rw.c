#include "kernel_rw.h"

#ifdef TARGET_OS_IPHONE
// 直接使用libjailbreak的函数，不需要动态加载
extern int jbclient_initialize_primitives(void);
#endif

// 纯内核态初始化函数
int pure_kernel_init(void) {
#ifdef TARGET_OS_IPHONE
    // 直接调用libjailbreak的初始化函数
    int ret = jbclient_initialize_primitives();
    if (ret != 0) {
        return -1;  // 初始化失败
    }
    
    return 0;  // 成功
#else
    // 语法检查模式
    return 0;
#endif
}