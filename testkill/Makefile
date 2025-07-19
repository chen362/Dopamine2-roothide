TARGET = iphone:clang:latest:14.0
ARCHS = arm64e

THEOS_DEVICE_IP = 192.168.1.5
THEOS_PACKAGE_SCHEME = roothide
include $(THEOS)/makefiles/common.mk
# LLVM混淆设置
export DEVELOPER_DIR = /Applications/Xcode.app/Contents/Developer
export PATH := $(DEVELOPER_DIR)/Toolchains/XcodeDefault.xctoolchain/usr/bin:$(PATH)
export THEOS_PLATFORM_SDK_ROOT = /usr/local/hkollvm
export TARGET_CC = $(THEOS_PLATFORM_SDK_ROOT)/bin/clang
export TARGET_CXX = $(THEOS_PLATFORM_SDK_ROOT)/bin/clang++
export TARGET_LD = $(THEOS_PLATFORM_SDK_ROOT)/bin/clang++
export XCRUN = /usr/bin/xcrun
export LIPO = /usr/bin/lipo

# 定义混淆参数
OBFUSCATE_FLAGS = -O0 -mllvm -enable-bcfobf -mllvm -enable-cffobf -mllvm -enable-splitobf -mllvm -split_num=3 -mllvm -enable-subobf -mllvm -enable-indibran -mllvm -enable-funcwra -mllvm -enable-strcry -mllvm -bcf_junkasm -mllvm -bcf_junkasm_minnum=4 -mllvm -bcf_junkasm_maxnum=7 -mllvm -bcf_onlyjunkasm -mllvm -ah_antirebind -mllvm -indibran-use-stack -mllvm -acd-rename-methodimp -mllvm -enable-adb -mllvm -sub_loop=2 -mllvm -bcf_cond_compl=3 -mllvm -bcf_prob=40 -mllvm -strcry_prob=100 -mllvm -fw_prob=100 -mllvm -fw_times=2 -mllvm -bcf_loop=2



# 保持完美运行的核心配置
TWEAK_NAME = TestFloatingBall
TestFloatingBall_FILES = 5.25.xm
TestFloatingBall_CFLAGS = -fobjc-arc $(OBFUSCATE_FLAGS)  # 只添加混淆标志

TOOL_NAME = FloatingBallHelper
FloatingBallHelper_FILES = bf32026.m ModuleHelper.m kernel_rw.c
FloatingBallHelper_CFLAGS = -fobjc-arc $(OBFUSCATE_FLAGS) -I../BaseBin/libjailbreak/src  # 添加roothide头文件路径
FloatingBallHelper_LDFLAGS = -framework Foundation ../BaseBin/libjailbreak/libjailbreak.dylib  # 链接roothide库
FloatingBallHelper_CODESIGN_FLAGS = -Sentitlements.plist
FloatingBallHelper_INSTALL_PATH = /Library/Helper

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk

# 安装后的权限设置脚本
after-install::
	install.exec "chown root:wheel /var/jb/Library/Helper/FloatingBallHelper"
	install.exec "chmod 6755 /var/jb/Library/Helper/FloatingBallHelper"
	install.exec "killall SpringBoard"