#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <UIKit/UIKit.h>
#import "ModuleHelper.h"
#import "safe_memory_reader.h"
// 添加网络相关头文件
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <fcntl.h>
#include <roothide.h>
#include <rootless.h>
#import <CommonCrypto/CommonDigest.h>
#import <spawn.h>

// 全局变量存储矩阵
float g_matrix[16];
// 全局变量存储矩阵

static NSDate *g_expiryDate = nil;            // 存储授权到期时间
static int g_authCheckCounter = 0;            // 验证计数器
// 坐标转换相关变量
static float W, H;          // 屏幕分辨率
static float w2;            // 小地图宽度的一半
static float Txdx;         // 小地图缩放比例
static float MyDirection;   // 方向修正
static float SmapAbout;    // 小地图X偏移
static float SmapUdown;    // 小地图Y偏移

// 数据结构定义（保持不变）
typedef struct {
    float x;
    float y;
} Vector2;

typedef struct {
    bool isValid;
    bool isAlive;
    float respawnTime;
    float screenX;
    float screenY;
    float miniMapX;
    float miniMapY;
} MonsterInfo;

typedef struct {
    int32_t ultimateCD;
    int32_t spell1ID;
    int32_t spell1CD;
    int32_t spell2ID;
    int32_t spell2CD;
} HeroSkillInfo;

typedef struct {
    bool isValid;
    float health;
    float screenX;
    float screenY;
} BossInfo;

typedef struct {
    BossInfo bigDragon;
    BossInfo smallDragon;
    BossInfo vanguard;
} BossData;

typedef struct {
    bool isValid;
    float respawnTime;
    float miniMapX;
    float miniMapY;
} MonsterData;

typedef struct {
    int32_t hero_id;
    float hp_percentage;
    Vector2 screen_pos;
    Vector2 minimap_pos;
} EnemyInfo;

typedef struct {
    int32_t wardId;
    int32_t status;
    float screenX;
    float screenY;
    float miniMapX;
    float miniMapY;
} WardData;

typedef struct {
    int enemy_count;
    EnemyInfo enemies[5];
    MonsterData monsters[12];
    HeroSkillInfo skills[5];
    int ward_count;
    WardData wards[20];
    BossData boss;
} GameData;

// 全局变量
static NSMutableDictionary *wardIdAddressMap = nil;
static NSMutableDictionary *lastUpdateTime = nil;
static NSString *g_deviceUDID = nil;
static int g_udpSocket = -1;
static struct sockaddr_in g_serverAddr;
static SafeMemoryReader *g_memoryReader = nil;

// 全局路径变量
NSString *g_configPath;
NSString *g_udidFilePath;
NSString *g_killallPath;
NSString *g_localImagePath;

__attribute__((constructor))
static void initializeGlobalPaths() {
    g_configPath = jbroot(@"/var/jb/tmp/heroicon/xyz.ini");
    g_udidFilePath = jbroot(@"/var/jb/tmp/udid.txt");
    g_killallPath = jbroot(@"/var/jb/usr/bin/killall");
    g_localImagePath = jbroot(@"/var/jb/tmp/heroicon/1.png");
}

// 安全内存读取函数 - 替代原来的 readMemory
bool readMemorySafe(uint64_t address, void *buffer, size_t size) {
    if (!g_memoryReader || !g_memoryReader.isInitialized) {
        return false;
    }
    return [g_memoryReader readMemory:address buffer:buffer size:size];
}

// 安全指针链读取函数 - 替代原来的 followPointerChain
uint64_t followPointerChainSafe(uint64_t baseAddr, NSArray *offsets) {
    if (!g_memoryReader || !g_memoryReader.isInitialized) {
        return 0;
    }
    return [g_memoryReader followPointerChain:baseAddr offsets:offsets];
}

// 修改后的 initTransform 函数（保持不变）
void initTransform(CGSize resolution) {
    W = fmax(resolution.width, resolution.height);
    H = fmin(resolution.width, resolution.height);
    Txdx = H / 38.0f;
    MyDirection = g_matrix[0] < 0 ? -1.0f : 1.0f;

    NSString *content = [NSString stringWithContentsOfFile:g_configPath
                                                  encoding:NSUTF8StringEncoding 
                                                     error:nil];
    if (content) {
        NSArray *lines = [content componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            NSArray *parts = [line componentsSeparatedByString:@"="];
            if (parts.count == 2) {
                float value = [parts[1] floatValue];
                if ([parts[0] isEqualToString:@"x"]) {
                    w2 = value;
                } else if ([parts[0] isEqualToString:@"y"]) {
                    SmapAbout = value;
                } else if ([parts[0] isEqualToString:@"z"]) {
                    SmapUdown = value;
                }
            }
        }
    } else {
        w2 = H * 0.165f;
        SmapAbout = H * 0.04f;
        SmapUdown = H * 0.12f;
    }
}

// 坐标转换函数（保持不变）
CGPoint toMiniMapPosition(float x, float y) {
    return CGPointMake(
        (x * MyDirection * w2 * 0.00002f) + w2 + SmapAbout,
        (y * MyDirection * w2 * -0.00002f) + w2 + SmapUdown
    );
}

CGPoint worldToScreen(float x, float y, float *matrix) {
    UIScreen *mainScreen = [UIScreen mainScreen];
    CGSize nativeSize = [mainScreen nativeBounds].size;
    
    float screenWidth = nativeSize.height;
    float screenHeight = nativeSize.width;
    
    float w = matrix[3] * x + matrix[11] * y + matrix[15];
    if (w < 0.01f) w = 0.01f;
    
    float px = 1.0f;
    float py = 0.8867f;
    
    NSString *content = [NSString stringWithContentsOfFile:g_configPath 
                                                encoding:NSUTF8StringEncoding 
                                                   error:nil];
    if (content) {
        NSArray *lines = [content componentsSeparatedByString:@"\n"];
        for (NSString *line in lines) {
            NSArray *parts = [line componentsSeparatedByString:@"="];
            if (parts.count == 2) {
                float value = [parts[1] floatValue];
                if ([parts[0] isEqualToString:@"px"]) {
                    px = value;
                } else if ([parts[0] isEqualToString:@"py"]) {
                    py = value;
                }
            }
        }
    }
    
    CGPoint result;
    result.x = ((screenWidth / 2) + (matrix[0] * x + matrix[8] * y + matrix[12]) / w * (screenWidth / 2)) * px;
    result.y = ((screenHeight / 2) - (matrix[1] * x + matrix[9] * y + matrix[13]) / w * (screenHeight / 2)) * py;
    
    return result;
}

// 安全的4x4矩阵读取 - 使用模块基址
void readMatrix4x4Safe(uint64_t lolmBase, uint64_t feBase, float *matrix) {
    static NSArray *offsets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        offsets = @[@(0xB8B2C48), @(0xb0), @(0x0), @(0xe8), @(0x10)];
    });
    
    uint64_t matrixAddr = followPointerChainSafe(lolmBase, offsets);
    if (matrixAddr == 0) return;
    
    matrixAddr += 0xd8;
    readMemorySafe(matrixAddr, matrix, sizeof(float) * 16);
}

// 安全的英雄列表读取
void readHeroListSafe(uint64_t lolmBase, HeroInfo *heroes, int *count, float *matrix) {
    static NSArray *baseOffsets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        baseOffsets = @[@(0xBC15100), @(0xB0), @(0x0), @(0x18)];
    });
    
    uint64_t heroListBase = followPointerChainSafe(lolmBase, baseOffsets);
    if (heroListBase == 0) return;
    
    *count = 0;
    int targetCamp = (matrix[0] > 1.0f) ? 2 : 1;
    
    for (int i = 0; i < 10; i++) {
        uint64_t heroBase = heroListBase + 0x28 + (i * 0x18);
        uint64_t heroPtr = 0;
        if (!readMemorySafe(heroBase, &heroPtr, sizeof(heroPtr))) continue;
        
        uint32_t heroId = 0;
        if (!readMemorySafe(heroPtr + 0x10, &heroId, sizeof(heroId))) continue;
        if (heroId == 0) continue;
        
        uint32_t camp = 0;
        if (!readMemorySafe(heroPtr + 0x58, &camp, sizeof(camp))) continue;
        
        if (camp != targetCamp) continue;
        
        uint64_t posBase = 0;
        if (!readMemorySafe(heroPtr + 0xc8, &posBase, sizeof(posBase))) continue;
        
        int32_t encX = 0, encY = 0, encZ = 0;
        if (!readMemorySafe(posBase + 0x40, &encX, sizeof(encX))) continue;
        if (!readMemorySafe(posBase + 0x50, &encY, sizeof(encY))) continue;
        if (!readMemorySafe(posBase + 0x48, &encZ, sizeof(encZ))) continue;
        
        heroes[*count].camp = camp;
        heroes[*count].heroId = heroId;
        heroes[*count].posX = (float)encX / 16384.0f;
        heroes[*count].posY = (float)encY / 16384.0f;
        heroes[*count].posZ = (float)encZ / 16384.0f;
        
        (*count)++;
    }
}

// 安全的血量读取
void readHeroesHPSafe(uint64_t lolmBase, float *hpPercentages) {
    uint64_t addr1 = lolmBase + 0xBC14CB0;
    uint64_t value1 = 0;
    if (!readMemorySafe(addr1, &value1, sizeof(value1))) return;
    
    uint64_t value2 = 0;
    if (!readMemorySafe(value1 + 0xB0, &value2, sizeof(value2))) return;
    
    uint64_t value3 = 0;
    if (!readMemorySafe(value2 + 0x0, &value3, sizeof(value3))) return;
    
    uint64_t healthListBase = 0;
    if (!readMemorySafe(value3 + 0x18, &healthListBase, sizeof(healthListBase))) return;
    
    int startIndex = (g_matrix[0] > 0) ? 5 : 0;
    
    for (int i = 0; i < 5; i++) {
        hpPercentages[i] = -1.0f;
        
        uint64_t heroOffset = 0x28 + ((i + startIndex) * 0x18);
        uint64_t heroPtr = 0;
        if (!readMemorySafe(healthListBase + heroOffset, &heroPtr, sizeof(heroPtr))) continue;
        
        uint64_t healthPtr = 0;
        if (!readMemorySafe(heroPtr + 0x28, &healthPtr, sizeof(healthPtr))) continue;
        
        uint64_t currentHealthPtr = 0;
        if (!readMemorySafe(healthPtr + 0x8, &currentHealthPtr, sizeof(currentHealthPtr))) continue;
        
        int32_t encCurrentHealth = 0;
        if (!readMemorySafe(currentHealthPtr + 0x70, &encCurrentHealth, sizeof(encCurrentHealth))) continue;
        int32_t currentHealth = encCurrentHealth / 16384;
        
        uint64_t maxHealthPtr = 0;
        if (!readMemorySafe(healthPtr + 0x10, &maxHealthPtr, sizeof(maxHealthPtr))) continue;
        
        int32_t encMaxHealth = 0;
        if (!readMemorySafe(maxHealthPtr + 0x70, &encMaxHealth, sizeof(encMaxHealth))) continue;
        int32_t maxHealth = encMaxHealth / 16384;
        
        if (maxHealth > 0) {
            hpPercentages[i] = (float)currentHealth / maxHealth * 100.0f;
        }
    }
}

// 继续实现其他读取函数...（野怪数据、技能CD等）
// 由于篇幅限制，这里只展示核心的安全内存读取替换

// 初始化socket（保持不变）
bool initUDPSocket() {
    if (g_udpSocket != -1) {
        return true;
    }
    
    g_udpSocket = socket(AF_INET, SOCK_DGRAM, 0);
    if (g_udpSocket < 0) {
        return false;
    }
    
    int opt = 1;
    setsockopt(g_udpSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    memset(&g_serverAddr, 0, sizeof(g_serverAddr));
    g_serverAddr.sin_family = AF_INET;
    g_serverAddr.sin_port = htons(36288);
    g_serverAddr.sin_addr.s_addr = inet_addr("127.0.0.1");
    
    return true;
}

// 安全的游戏数据发送
void sendGameDataSafe(uint64_t lolmBase, uint64_t feBase, HeroInfo *heroes, int count, float *matrix) {
    float hpPercentages[5] = {-1.0f, -1.0f, -1.0f, -1.0f, -1.0f};
    readHeroesHPSafe(lolmBase, hpPercentages);
    
    GameData gameData;
    memset(&gameData, 0, sizeof(GameData));
    
    for (int i = 0; i < count; i++) {
        CGPoint screenPos = worldToScreen(heroes[i].posX, heroes[i].posY, matrix);
        CGPoint minimapPos = toMiniMapPosition(heroes[i].posX * 1000, heroes[i].posY * 1000);
        
        gameData.enemies[i].hero_id = heroes[i].heroId;
        gameData.enemies[i].screen_pos.x = screenPos.x;
        gameData.enemies[i].screen_pos.y = screenPos.y;
        gameData.enemies[i].minimap_pos.x = minimapPos.x;
        gameData.enemies[i].minimap_pos.y = minimapPos.y;
        gameData.enemies[i].hp_percentage = hpPercentages[i];
    }
    
    gameData.enemy_count = count;
    
    // 这里继续添加野怪、技能、眼位、Boss数据的安全读取...
    
    if (g_udpSocket != -1) {
        sendto(g_udpSocket, &gameData, sizeof(GameData), 0, 
               (struct sockaddr *)&g_serverAddr, sizeof(g_serverAddr));
    }
}

// 授权验证函数（保持不变）
NSString* generate_and_write_udid() {
    // ... 保持原来的实现不变
    return nil; // 简化显示
}

bool check_device_authorization(NSString *deviceUDID) {
    // ... 保持原来的实现不变
    return NO; // 简化显示
}

NSDate* check_device_authorization_with_expiry(NSString *deviceUDID) {
    // ... 保持原来的实现不变
    return nil; // 简化显示
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 初始化全局变量
        if (!wardIdAddressMap) {
            wardIdAddressMap = [[NSMutableDictionary alloc] init];
        }
        if (!lastUpdateTime) {
            lastUpdateTime = [[NSMutableDictionary alloc] init];
        }
        
        // 初始化安全内存读取器
        g_memoryReader = [SafeMemoryReader sharedInstance];
        if (![g_memoryReader initializeWithProcessName:@"lolm"]) {
            NSLog(@"Failed to initialize SafeMemoryReader");
            return 1;
        }
        
        NSLog(@"SafeMemoryReader initialized successfully");
        
        // 验证设备授权
        g_deviceUDID = generate_and_write_udid();
        g_expiryDate = check_device_authorization_with_expiry(g_deviceUDID);
        if (!g_deviceUDID || !g_expiryDate) {
            return 1;
        }
        
        // 获取模块基址（现在通过安全方式）
        uint64_t lolmBase = [g_memoryReader findModuleBase:@"lolm"];
        uint64_t feBase = [g_memoryReader findModuleBase:@"FE_Proj"];
        
        if (lolmBase == 0 || feBase == 0) {
            NSLog(@"Failed to find module bases");
            return 1;
        }
        
        // 初始化socket
        if (!initUDPSocket()) {
            return 1;
        }
        
        // 获取屏幕分辨率
        CGSize resolution = [UIScreen mainScreen].bounds.size;
        
        // 主循环
        while (true) {
            @autoreleasepool {
                initTransform(resolution);
                readMatrix4x4Safe(lolmBase, feBase, g_matrix);
                
                if (g_matrix[0] != 0) {
                    // 游戏对局中
                    HeroInfo heroes[10];
                    int heroCount = 0;
                    readHeroListSafe(lolmBase, heroes, &heroCount, g_matrix);
                    
                    // 发送游戏数据
                    sendGameDataSafe(lolmBase, feBase, heroes, heroCount, g_matrix);
                } else {
                    // 游戏对局外，发送空数据包
                    GameData emptyData = {0};
                    if (g_udpSocket != -1) {
                        sendto(g_udpSocket, &emptyData, sizeof(emptyData), 0, 
                               (struct sockaddr *)&g_serverAddr, sizeof(g_serverAddr));
                    }
                    
                    // 授权检查
                    g_authCheckCounter++;
                    if (g_authCheckCounter >= 30) {
                        g_authCheckCounter = 0;
                        
                        NSDate *currentDate = [NSDate date];
                        NSDate *beijingCurrentDate = [currentDate dateByAddingTimeInterval:8*3600];
                        
                        NSTimeInterval beijingCurrentTimestamp = [beijingCurrentDate timeIntervalSince1970];
                        NSTimeInterval expiryTimestamp = [g_expiryDate timeIntervalSince1970];
                        
                        if (beijingCurrentTimestamp >= expiryTimestamp) {
                            pid_t pid;
                            const char *args[] = {"killall", "-9", "SpringBoard", NULL};
                            posix_spawn(&pid, [g_killallPath UTF8String], NULL, NULL, (char* const*)args, NULL);
                            exit(0);
                        }
                    }
                }
                
                usleep(12333); // 约120fps
            }
        }
        
        // 清理资源
        [g_memoryReader cleanup];
        if (g_udpSocket != -1) {
            close(g_udpSocket);
            g_udpSocket = -1;
        }
        
        return 0;
    }
}