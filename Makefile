# Makefile for Safe Memory Reader
TARGET = SafeGameReader
SOURCES = main_secure.m safe_memory_reader.m ModuleHelper.m

# 编译器和标志
CC = clang
CFLAGS = -fobjc-arc -fmodules -O2 -Wall
FRAMEWORKS = -framework Foundation -framework UIKit -framework CoreGraphics
INCLUDES = -I. -I/usr/include/libjailbreak

# 链接库
LIBS = -ljailbreak -lkfd -lssl -lcrypto

# 架构
ARCHS = arm64

# 输出目录
OUTDIR = build

# 目标设备IP（用于远程编译和部署）
DEVICE_IP ?= 192.168.1.100

.PHONY: all clean install deploy

all: $(OUTDIR)/$(TARGET)

$(OUTDIR):
	mkdir -p $(OUTDIR)

$(OUTDIR)/$(TARGET): $(SOURCES) | $(OUTDIR)
	$(CC) $(CFLAGS) -arch $(ARCHS) $(INCLUDES) $(FRAMEWORKS) $(LIBS) \
		-o $@ $(SOURCES)
	@echo "Build completed: $@"

# 清理编译产物
clean:
	rm -rf $(OUTDIR)
	@echo "Clean completed"

# 本地安装（需要root权限）
install: $(OUTDIR)/$(TARGET)
	@echo "Installing $(TARGET)..."
	cp $(OUTDIR)/$(TARGET) /usr/local/bin/
	chmod +x /usr/local/bin/$(TARGET)
	@echo "Installation completed"

# 远程部署到越狱设备
deploy: $(OUTDIR)/$(TARGET)
	@echo "Deploying to device $(DEVICE_IP)..."
	scp $(OUTDIR)/$(TARGET) root@$(DEVICE_IP):/var/jb/usr/bin/
	ssh root@$(DEVICE_IP) "chmod +x /var/jb/usr/bin/$(TARGET)"
	@echo "Deployment completed"

# 签名（如果需要）
sign: $(OUTDIR)/$(TARGET)
	ldid -Sentitlements.plist $(OUTDIR)/$(TARGET)
	@echo "Signing completed"

# 创建权限文件
entitlements:
	@echo "Creating entitlements.plist..."
	@cat > entitlements.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>platform-application</key>
	<true/>
	<key>com.apple.private.memorystatus</key>
	<true/>
	<key>com.apple.private.kext-management</key>
	<true/>
	<key>get-task-allow</key>
	<true/>
	<key>task_for_pid-allow</key>
	<true/>
</dict>
</plist>
EOF
	@echo "entitlements.plist created"

# 调试版本
debug: CFLAGS += -g -DDEBUG=1
debug: $(OUTDIR)/$(TARGET)

# 发布版本
release: CFLAGS += -DNDEBUG -Os
release: $(OUTDIR)/$(TARGET)

# 帮助信息
help:
	@echo "Available targets:"
	@echo "  all       - Build the target (default)"
	@echo "  clean     - Remove build artifacts"
	@echo "  install   - Install to local system"
	@echo "  deploy    - Deploy to remote device"
	@echo "  sign      - Sign the binary"
	@echo "  debug     - Build debug version"
	@echo "  release   - Build release version"
	@echo "  help      - Show this help"
	@echo ""
	@echo "Environment variables:"
	@echo "  DEVICE_IP - Target device IP for deployment"