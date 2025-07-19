#import <Foundation/Foundation.h>
#import <mach/mach.h>
#import <UIKit/UIKit.h>
#import "ModuleHelper.h"
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

// 添加roothide内核原语支持
#include "kernel_rw.h"

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
// 添加血量信息结构体

// 数据结构定义
typedef struct {
    float x;
    float y;
} Vector2;
// 在文件开头的数据结构定义部分
// 在文件开头的数据结构定义部分
typedef struct {
    bool isValid;     // 标记该数据是否需要发送(死亡状态才发送)
    bool isAlive;     // 野怪存活状态
    float respawnTime;
    float screenX;
    float screenY;
    float miniMapX;
    float miniMapY;
} MonsterInfo;
// 在文件开头添加结构体定义
typedef struct {
    int32_t ultimateCD;
    int32_t spell1ID;
    int32_t spell1CD;
    int32_t spell2ID;
    int32_t spell2CD;
} HeroSkillInfo;

// 新建单个 Boss 的信息结构体（简洁版本）
typedef struct {
    bool isValid;     // 若血量为0或无法读取则标记为无效
    float health;     // 当前血量（int32_t除以16384得到真实血量）
    float screenX;    // 固定坐标转换后的屏幕坐标X
    float screenY;    // 固定坐标转换后的屏幕坐标Y
} BossInfo;

// 新建 Boss 数据结构，包含三个 Boss 的数据
typedef struct {
    BossInfo bigDragon;    // 大龙 Boss
    BossInfo smallDragon;  // 小龙 Boss
    BossInfo vanguard;     // 先锋 Boss
} BossData;
// 确保 MonsterData 结构与 MonsterInfo 匹配
typedef struct {
    bool isValid;     // 标记该数据是否需要发送(死亡状态才发送)
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

// 在文件开头的数据结构定义部分添加眼位结构体
typedef struct {
    int32_t wardId;
    int32_t status;
    float screenX;
    float screenY;
    float miniMapX;
    float miniMapY;
} WardData;

// 修改GameData结构体，添加眼位数据
typedef struct {
    int enemy_count;
    EnemyInfo enemies[5];
    MonsterData monsters[12];
    HeroSkillInfo skills[5];
    int ward_count;          // 新增眼位数量
    WardData wards[20];      // 新增眼位数据数组
     BossData boss;           // 新增 Boss 数据字段
} GameData;

// 添加全局变量用于跟踪眼位状态
static NSMutableDictionary *wardIdAddressMap = nil;
static NSMutableDictionary *lastUpdateTime = nil;
static NSString *g_deviceUDID = nil;
static int g_udpSocket = -1;
static struct sockaddr_in g_serverAddr;
// 全局变量定义（不直接初始化）
NSString *g_configPath;
NSString *g_udidFilePath;
NSString *g_killallPath;
NSString *g_localImagePath;

// 使用构造函数进行初始化，该函数在程序加载时运行
__attribute__((constructor))
static void initializeGlobalPaths() {
    g_configPath = jbroot(@"/var/jb/tmp/heroicon/xyz.ini");
    g_udidFilePath = jbroot(@"/var/jb/tmp/udid.txt");
    g_killallPath = jbroot(@"/var/jb/usr/bin/killall");
    g_localImagePath = jbroot(@"/var/jb/tmp/heroicon/1.png");
}
// 纯内核态读取内存函数（直接使用roothide的kreadbuf）
bool readMemory(task_t task, uint64_t address, void *buffer, size_t size) {
    // 直接使用roothide的内核原语读取内存
    return kreadbuf(address, buffer, size) == 0;
}

// 纯内核态指针链读取函数
uint64_t followPointerChain(task_t task, uint64_t baseAddr, NSArray *offsets) {
    uint64_t currentAddr = baseAddr;
    
    for (int i = 0; i < offsets.count; i++) {
        uint64_t targetAddr = currentAddr + [offsets[i] unsignedLongLongValue];
        uint64_t nextAddr = 0;
        if (kreadbuf(targetAddr, &nextAddr, sizeof(nextAddr)) != 0) return 0;
        currentAddr = nextAddr;
    }
    
    return currentAddr;
}
// 修改后的 initTransform 函数
void initTransform(CGSize resolution) {
    W = fmax(resolution.width, resolution.height);
    H = fmin(resolution.width, resolution.height);
    Txdx = H / 38.0f;
    MyDirection = g_matrix[0] < 0 ? -1.0f : 1.0f;  // 修改这里

    // 使用全局变量 g_configPath 获取配置文件内容
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
        // 使用默认值
        w2 = H * 0.165f;
        SmapAbout = H * 0.04f;
        SmapUdown = H * 0.12f;
    }
}

// 世界坐标转小地图坐标
CGPoint toMiniMapPosition(float x, float y) {
    return CGPointMake(
        (x * MyDirection * w2 * 0.00002f) + w2 + SmapAbout,
        (y * MyDirection * w2 * -0.00002f) + w2 + SmapUdown
    );
}

// 世界坐标转屏幕坐标
CGPoint worldToScreen(float x, float y, float *matrix) {
    // 获取屏幕尺寸和缩放比例
    UIScreen *mainScreen = [UIScreen mainScreen];
    CGSize nativeSize = [mainScreen nativeBounds].size;  // 使用原生分辨率
   // CGFloat scale = mainScreen.scale;
    
    // 考虑屏幕方向，确保使用正确的宽高
    float screenWidth = nativeSize.height;  // 横屏模式下交换宽高
    float screenHeight = nativeSize.width;
    
    float w = matrix[3] * x + matrix[11] * y + matrix[15];
    if (w < 0.01f) w = 0.01f;
    
    // 默认值
    float px = 1.0f;
    float py = 0.8867f;
    
   NSString *configPath = jbroot(@"/tmp/heroicon/xyz.ini");
NSString *content = [NSString stringWithContentsOfFile:configPath 
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
    // 考虑缩放的坐标计算
    result.x = ((screenWidth / 2) + (matrix[0] * x + matrix[8] * y + matrix[12]) / w * (screenWidth / 2)) * px;
    result.y = ((screenHeight / 2) - (matrix[1] * x + matrix[9] * y + matrix[13]) / w * (screenHeight / 2)) * py;
    
  
    
    return result;
}
// 读取4x4矩阵
void readMatrix4x4(task_t task, uint64_t lolmBase, uint64_t feBase, float *matrix) {
    static NSArray *offsets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        offsets = @[@(0xB8B2C48), @(0xb0), @(0x0), @(0xe8), @(0x10)]; //0xB8B2C48
    });
    
    uint64_t matrixAddr = followPointerChain(task, lolmBase, offsets);
    if (matrixAddr == 0) return;
    
    matrixAddr += 0xd8;
    kreadbuf( matrixAddr, matrix, sizeof(float) * 16);
}

// 遍历英雄结构
void readHeroList(task_t task, uint64_t lolmBase, HeroInfo *heroes, int *count, float *matrix) {
    static NSArray *baseOffsets = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        baseOffsets = @[@(0xBC15100), @(0xB0), @(0x0), @(0x18)]; //"_lolm"+0xBC15100
    });
    
    uint64_t heroListBase = followPointerChain(task, lolmBase, baseOffsets);
    if (heroListBase == 0) return;
    
    *count = 0;
    
    // 根据矩阵[0]判断我方阵营
    int targetCamp = (matrix[0] > 1.0f) ? 2 : 1;  // 蓝方(matrix[0]>1)找蓝方(camp=2)，反之找红方
    
    for (int i = 0; i < 10; i++) {
        uint64_t heroBase = heroListBase + 0x28 + (i * 0x18);
        uint64_t heroPtr = 0;
        if (kreadbuf( heroBase, &heroPtr, sizeof(heroPtr)) != 0) continue;
        
        uint32_t heroId = 0;
        if (kreadbuf( heroPtr + 0x10, &heroId, sizeof(heroId)) != 0) continue;
        if (heroId == 0) continue;
        
        uint32_t camp = 0;
        if (kreadbuf( heroPtr + 0x58, &camp, sizeof(camp)) != 0) continue;
        
        // 只处理敌方英雄
        if (camp != targetCamp) continue;
        
        uint64_t posBase = 0;
        if (kreadbuf( heroPtr + 0xc8, &posBase, sizeof(posBase)) != 0) continue;
        
        int32_t encX = 0, encY = 0, encZ = 0;
        if (kreadbuf( posBase + 0x40, &encX, sizeof(encX)) != 0) continue;
        if (kreadbuf( posBase + 0x50, &encY, sizeof(encY)) != 0) continue;
        if (kreadbuf( posBase + 0x48, &encZ, sizeof(encZ)) != 0) continue;
        
        heroes[*count].camp = camp;
        heroes[*count].heroId = heroId;
        heroes[*count].posX = (float)encX / 16384.0f;
        heroes[*count].posY = (float)encY / 16384.0f;
        heroes[*count].posZ = (float)encZ / 16384.0f;
        
        (*count)++;
    }
}
void readHeroesHP(task_t task, uint64_t lolmBase, float *hpPercentages) {
    // 第一级指针链: lolmBase -> healthListBase
    uint64_t addr1 = lolmBase + 0xBC14CB0; //0xBC14CB0
    uint64_t value1 = 0;
    if (kreadbuf( addr1, &value1, sizeof(value1)) != 0) return;
    
    // 第二级 (+0xB0)
    uint64_t value2 = 0;
    if (kreadbuf( value1 + 0xB0, &value2, sizeof(value2)) != 0) return;
    
    // 第三级 (+0x0)
    uint64_t value3 = 0;
    if (kreadbuf( value2 + 0x0, &value3, sizeof(value3)) != 0) return;
    
    // 第四级 (+0x18)
    uint64_t healthListBase = 0;
    if (kreadbuf( value3 + 0x18, &healthListBase, sizeof(healthListBase)) != 0) return;
    
    // 根据矩阵[0]判断遍历范围
    int startIndex = (g_matrix[0] > 0) ? 5 : 0;
    
    // 遍历5个英雄
    for (int i = 0; i < 5; i++) {
        hpPercentages[i] = -1.0f;  // 默认值为-1表示无效
        
        uint64_t heroOffset = 0x28 + ((i + startIndex) * 0x18);
        uint64_t heroPtr = 0;
        if (kreadbuf( healthListBase + heroOffset, &heroPtr, sizeof(heroPtr)) != 0) continue;
        
        uint64_t healthPtr = 0;
        if (kreadbuf( heroPtr + 0x28, &healthPtr, sizeof(healthPtr)) != 0) continue;
        
        // 读取当前血量
        uint64_t currentHealthPtr = 0;
        if (kreadbuf( healthPtr + 0x8, &currentHealthPtr, sizeof(currentHealthPtr)) != 0) continue;
        
        int32_t encCurrentHealth = 0;
        if (kreadbuf( currentHealthPtr + 0x70, &encCurrentHealth, sizeof(encCurrentHealth)) != 0) continue;
        int32_t currentHealth = encCurrentHealth / 16384;
        
        // 读取最大血量
        uint64_t maxHealthPtr = 0;
        if (kreadbuf( healthPtr + 0x10, &maxHealthPtr, sizeof(maxHealthPtr)) != 0) continue;
        
        int32_t encMaxHealth = 0;
        if (kreadbuf( maxHealthPtr + 0x70, &encMaxHealth, sizeof(encMaxHealth)) != 0) continue;
        int32_t maxHealth = encMaxHealth / 16384;
        
        // 直接计算血量百分比,不做过滤
        if (maxHealth > 0) {
            hpPercentages[i] = (float)currentHealth / maxHealth * 100.0f;
        }
    }
}
void readMonsterData(task_t task, uint64_t lolmBase, MonsterInfo *monsters) {
    // 野怪固定坐标
    static const struct {
        int32_t posX;
        int32_t posY;
    } monsterPos[] = {
        {34729,   -501429},  // 蓝色红buff
        {-407748,  39038},   // 蓝色蓝buff
        {-620685,  105208},  // 蓝色蛤蟆
        {-47713,  -312644},  // 蓝色F4
        {-496738, -194121},  // 蓝色三狼
        {242283, -569098},   // 蓝色石头人
        {-33563,   499297},  // 红色红buff
        {406811,  -47094},   // 红色蓝buff
        {621875, -117533},   // 红色蛤蟆
        {46451,   310951},   // 红色F4
        {488050,  177456},   // 红色三狼
        {-241950,  573591}   // 红色石头人
    };
// 完整的野怪指针链
    static const uint64_t monsterOffsets[][10] = {
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x30, 0x18, 0x18, 0x60}, // 蓝色红buff
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x38, 0x18, 0x18, 0x60}, // 蓝色蓝buff
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x50, 0x18, 0x18, 0x60}, // 蓝色蛤蟆
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x60, 0x18, 0x18, 0x60}, // 蓝色F4
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x70, 0x18, 0x18, 0x60}, // 蓝色三狼
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x80, 0x18, 0x18, 0x60}, // 蓝色石头人
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x28, 0x18, 0x18, 0x60}, // 红色红buff
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x40, 0x18, 0x18, 0x60}, // 红色蓝buff
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x48, 0x18, 0x18, 0x60}, // 红色蛤蟆
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x58, 0x18, 0x18, 0x60}, // 红色F4
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x68, 0x18, 0x18, 0x60}, // 红色三狼
        {0xb0, 0x0, 0xc0, 0x18, 0x20, 0x10, 0x78, 0x18, 0x18, 0x60}  // 红色石头人
    };

    const uint64_t baseOffset = 0xBC11C88;//0x0BC11C88 //"_lolm"+0xBC15338
    uint64_t baseAddress = lolmBase + baseOffset;
    
    for (int i = 0; i < sizeof(monsterPos)/sizeof(monsterPos[0]); i++) {
        uint64_t currentAddr = baseAddress;
        
        // 遍历完整的指针链
        for (int j = 0; j < 10; j++) {
            if (kreadbuf( currentAddr, &currentAddr, sizeof(currentAddr)) != 0) {
                continue;
            }
            currentAddr += monsterOffsets[i][j];
        }
        
        // 读取重生时间
        int32_t respawnTimeRaw = 0;
        if (kreadbuf( currentAddr, &respawnTimeRaw, sizeof(respawnTimeRaw)) == 0) {
            // 只有当野怪死亡(respawnTimeRaw > 0)时才设置isValid和相关数据
            if (respawnTimeRaw > 0) {
                monsters[i].isValid = true;
                monsters[i].respawnTime = respawnTimeRaw / 16384.0f;
                
                float x = monsterPos[i].posX / 16384.0f;
                float y = monsterPos[i].posY / 16384.0f;
                
                CGPoint minimapPos = toMiniMapPosition(x * 1000, y * 1000);
                monsters[i].miniMapX = minimapPos.x;
                monsters[i].miniMapY = minimapPos.y;
            } else {
                // 野怪存活时，标记为无效数据，不需要发送
                monsters[i].isValid = false;
                monsters[i].respawnTime = 0;
                monsters[i].miniMapX = 0;
                monsters[i].miniMapY = 0;
            }
        }
    }

}
void readUltimateCD(task_t task, uint64_t feBase, float *matrix, HeroSkillInfo *skills) {
    uint64_t feProjDataSegment = feBase + 0x3BA0000; //39A8000 //3d18000  //3BA0000  
    uint64_t baseAddress = feProjDataSegment + 0x1063890; //01063890
    
    uint64_t initialPointer = 0;
    if (kreadbuf( baseAddress, &initialPointer, sizeof(initialPointer)) != 0) {
        return;
    }
    
    int startIndex = (matrix[0] > 0) ? 5 : 0;
    int endIndex = startIndex + 5;
    
    static const uint64_t teamOffsets[] = {
        0x0, 0x20, 0x40, 0x60, 0x80,    // 蓝方
        0xa0, 0xc0, 0xe0, 0x100, 0x120  // 红方
    };
    
    static const uint64_t commonOffsets[] = {
        0x28, 0x28, 0x0, 0x0, 0x60
    };
    
    static const uint64_t remainingOffsets[] = {
        0x28, 0x10, 0x0, 0x0, 0x18, 0x20
    };
    
    for (int i = startIndex, skillIndex = 0; i < endIndex; i++, skillIndex++) {
        uint64_t currentAddr = initialPointer;
        BOOL success = YES;
        
        for (int j = 0; j < sizeof(commonOffsets)/sizeof(commonOffsets[0]); j++) {
            if (kreadbuf( currentAddr + commonOffsets[j], &currentAddr, sizeof(currentAddr)) != 0) {
                success = NO;
                break;
            }
        }
        
        if (!success) continue;
        
        if (kreadbuf( currentAddr + teamOffsets[i], &currentAddr, sizeof(currentAddr)) != 0) {
            continue;
        }
        
        for (int j = 0; j < sizeof(remainingOffsets)/sizeof(remainingOffsets[0]); j++) {
            if (kreadbuf( currentAddr + remainingOffsets[j], &currentAddr, sizeof(currentAddr)) != 0) {
                success = NO;
                break;
            }
        }
        
        if (!success) continue;
        
        int32_t cdRaw = 0;
        if (kreadbuf( currentAddr + 0x18, &cdRaw, sizeof(cdRaw)) == 0) {
            skills[skillIndex].ultimateCD = cdRaw / 16384;
        }
    }
}

// 验证召唤师技能ID是否有效
BOOL isValidSpellID(int32_t spellID) {
    static const int32_t validSpellIDs[] = {
        81010101, 81020101, 81030101, 81041011, 81050101,
        81060101, 81070101, 81090101, 81100101, 81110101,
        81120101, 81130101
    };
    
    for (int i = 0; i < sizeof(validSpellIDs)/sizeof(validSpellIDs[0]); i++) {
        if (spellID == validSpellIDs[i]) return YES;
    }
    return NO;
}

void readHeroSkillCD(task_t task, uint64_t feBase, float *matrix, HeroSkillInfo *skills) {
    uint64_t feProjDataSegment = feBase + 0x3BA0000; //3BA0000
    uint64_t baseAddress = feProjDataSegment + 0x01063890;  //01063890
    
    uint64_t initialPointer = 0;
    if (kreadbuf( baseAddress, &initialPointer, sizeof(initialPointer)) != 0) {
        return;
    }
    
    int startIndex = (matrix[0] > 0) ? 5 : 0;
    int endIndex = startIndex + 5;
    
    static const uint64_t teamOffsets[] = {
        0x0, 0x20, 0x40, 0x60, 0x80,    // 蓝方
        0xa0, 0xc0, 0xe0, 0x100, 0x120  // 红方
    };
    
    static const uint64_t commonOffsets[] = {
        0x28, 0x28, 0x0, 0x0, 0x60
    };
    
    static const uint64_t remainingOffsets[] = {
        0x28, 0x10, 0x0, 0x0, 0x18
    };
    
    static const uint64_t searchOffsets[] = {
        0x3c, 0x40, 0x44, 0x48, 0x4c, 0x50, 0x54, 0x58, 0x5c, 0x60
    };
    
    for (int i = startIndex, skillIndex = 0; i < endIndex; i++, skillIndex++) {
        uint64_t currentAddr = initialPointer;
        BOOL success = YES;
        
        for (int j = 0; j < sizeof(commonOffsets)/sizeof(commonOffsets[0]); j++) {
            if (kreadbuf( currentAddr + commonOffsets[j], &currentAddr, sizeof(currentAddr)) != 0) {
                success = NO;
                break;
            }
        }
        
        if (!success) continue;
        
        if (kreadbuf( currentAddr + teamOffsets[i], &currentAddr, sizeof(currentAddr)) != 0) {
            continue;
        }
        
        for (int j = 0; j < sizeof(remainingOffsets)/sizeof(remainingOffsets[0]); j++) {
            if (kreadbuf( currentAddr + remainingOffsets[j], &currentAddr, sizeof(currentAddr)) != 0) {
                success = NO;
                break;
            }
        }
        
        if (!success) continue;
        
        uint64_t baseSpellAddr = currentAddr;
        BOOL found = NO;
        
        for (int j = 0; j < sizeof(searchOffsets)/sizeof(searchOffsets[0]); j++) {
            uint64_t testAddr = baseSpellAddr + searchOffsets[j];
            uint64_t spellAddr = 0;
            
            if (kreadbuf( testAddr, &spellAddr, sizeof(spellAddr)) == 0) {
                int32_t identifier = 0;
                if (kreadbuf( spellAddr + 0x14, &identifier, sizeof(identifier)) == 0 && 
                    identifier == 10000001) {
                    currentAddr = spellAddr + 0x14;
                    found = YES;
                    break;
                }
            }
        }
        
        if (!found) continue;
        
        for (int j = 0; j < 2; j++) {
            uint64_t spellOffset = j == 0 ? 0x60 : 0xC0;
            uint64_t spellAddr = currentAddr + spellOffset;
            
            int32_t spellId = 0;
            if (kreadbuf( spellAddr, &spellId, sizeof(spellId)) == 0) {
                if (!isValidSpellID(spellId)) {
                    spellId = 81060101;
                }
                
                int32_t cdRaw = 0;
                if (kreadbuf( spellAddr + 4, &cdRaw, sizeof(cdRaw)) == 0) {
                    if (j == 0) {
                        skills[skillIndex].spell1ID = spellId;
                        skills[skillIndex].spell1CD = cdRaw / 16384;
                    } else {
                        skills[skillIndex].spell2ID = spellId;
                        skills[skillIndex].spell2CD = cdRaw / 16384;
                    }
                }
            }
        }
    }
}
void readWardsData(task_t task, uint64_t lolmBase, GameData *gameData, float *matrix) {
    static const uint64_t BASE_OFFSET = 0xBC14CC8;  //"_lolm"+0xBC14CC8
    static const uint64_t HERO_OFFSETS[] = {
        0x28, 0x40, 0x58, 0x70, 0x88,  // 所有英雄偏移
        0xA0, 0xB8, 0xD0, 0xE8, 0x100
    };
    
    uint64_t baseAddr = lolmBase + BASE_OFFSET;
    uint64_t addr;
    size_t size = sizeof(uint64_t);
    if (kreadbuf( baseAddr, &addr, size) != 0) return;
    
    // 判断当前阵营
    BOOL isRedTeam = matrix[0] < 0;
    gameData->ward_count = 0;
    
    // 基础指针链读取
    uint64_t currentAddr = addr;
    for (int i = 0; i < 3; i++) {
        uint64_t nextAddr;
        uint64_t offset = (i == 0 ? 0xB0 : (i == 1 ? 0x0 : 0x18));
        if (kreadbuf( currentAddr + offset, &nextAddr, size) != 0) {
            return;
        }
        currentAddr = nextAddr;
    }
    
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    // 遍历所有英雄
    for (int heroIndex = 0; heroIndex < 10; heroIndex++) {
        uint64_t heroAddr = currentAddr + HERO_OFFSETS[heroIndex];
        uint64_t heroBaseAddr;
        if (kreadbuf( heroAddr, &heroBaseAddr, size) != 0) continue;
        
        // 眼位指针链读取
        uint64_t wardBaseAddr = heroBaseAddr;
        for (int i = 0; i < 2; i++) {
            uint64_t nextAddr;
            uint64_t offset = (i == 0 ? 0xe8 : 0x48);
            if (kreadbuf( wardBaseAddr + offset, &nextAddr, size) != 0) {
                continue;
            }
            wardBaseAddr = nextAddr;
        }
        
        // 读取四个眼位
        for (int wardIndex = 0; wardIndex < 4; wardIndex++) {
            uint64_t wardAddr;
            uint64_t offset = wardIndex * 0x8;
            if (kreadbuf( wardBaseAddr + offset, &wardAddr, size) != 0 || 
                wardAddr == 0 || wardAddr == 0x1f0) continue;
            
            // 读取眼位ID
            int32_t wardId;
            size_t idSize = sizeof(int32_t);
            if (kreadbuf( wardAddr + 0x2c, &wardId, idSize) != 0 || 
                (wardId != 820505 && wardId != 820506)) continue;
            
            // 读取阵营标记
            int32_t teamFlag;
            if (kreadbuf( wardAddr + 0x78, &teamFlag, idSize) != 0 || 
                ((isRedTeam && teamFlag != 1) || (!isRedTeam && teamFlag != 2))) continue;
            
            // 读取眼位状态
            int32_t currentStatus;
            if (kreadbuf( wardAddr + 0x40, &currentStatus, idSize) != 0) continue;
            
            NSNumber *idAddrKey = @(wardAddr + wardIndex);
            NSNumber *lastStatus = [wardIdAddressMap objectForKey:idAddrKey];
            NSNumber *lastTime = [lastUpdateTime objectForKey:idAddrKey];
            
            BOOL shouldUpdateWard = NO;
            if (!lastStatus || currentStatus > [lastStatus intValue]) {
                [wardIdAddressMap setObject:@(currentStatus) forKey:idAddrKey];
                [lastUpdateTime setObject:@(currentTime) forKey:idAddrKey];
                shouldUpdateWard = YES;
            } else if (lastTime) {
                NSTimeInterval timeSinceLastUpdate = currentTime - [lastTime doubleValue];
                if (timeSinceLastUpdate <= 1.4) {
                    shouldUpdateWard = YES;
                }
            }
            
            if (shouldUpdateWard && gameData->ward_count < 20) {
                // 读取坐标
                uint64_t coordBase;
                if (kreadbuf( wardAddr + 0x20, &coordBase, size) != 0) continue;
                
                int32_t xPos, yPos;
                if (kreadbuf( coordBase + 0x18, &xPos, idSize) != 0 ||
                    kreadbuf( coordBase + 0x28, &yPos, idSize) != 0) continue;
                
                float x = (float)xPos / 16384.0f;
                float y = (float)yPos / 16384.0f;
                
                CGPoint screenPos = worldToScreen(x, y, matrix);
                CGPoint miniMapPos = toMiniMapPosition(x * 1000, y * 1000);
                
                WardData *ward = &gameData->wards[gameData->ward_count];
                ward->wardId = wardId;
                ward->status = currentStatus;
                ward->screenX = screenPos.x;
                ward->screenY = screenPos.y;
                ward->miniMapX = miniMapPos.x;
                ward->miniMapY = miniMapPos.y;
                
                gameData->ward_count++;
            }
        }
    }
}

void readBossHealth(task_t task, uint64_t lolmBase, BossData *bossData, float *matrix) {
    // Boss特定的偏移路径（从共同基础地址分支后的路径）
    const uint64_t bossSpecificOffsets[3] = {
        0x148, // 大龙
        0x70,  // 小龙  
        0x28   // 先锋
    };
    
    const float bossWorldPos[3][2] = {
        {-286067.0f / 16384.0f,  355962.0f / 16384.0f}, // 大龙
        { 289998.0f / 16384.0f, -354063.0f / 16384.0f}, // 小龙
        {-286067.0f / 16384.0f,  355962.0f / 16384.0f}  // 先锋
    };

    BossInfo* bossArr[3] = { &bossData->bigDragon, &bossData->smallDragon, &bossData->vanguard };
    //const char* bossName[3] = { "大龙", "小龙", "先锋" };

    // 一次性读取共同的基础指针链: lolmBase+0xB7D0708 -> 0xB0 -> 0x0 -> 0x18
    uint64_t commonAddr = 0;
    if (kreadbuf( lolmBase + 0xB7D0708, &commonAddr, sizeof(commonAddr)) != 0) {
       // NSLog(@"9527 readBossHealth: 读取基础地址0xB7D0708失败");
        goto set_all_invalid;
    }

    // 继续读取共同路径: 0xB0 -> 0x0 -> 0x18
    const uint64_t commonOffsets[] = {0xB0, 0x0, 0x18};
    for (int i = 0; i < 3; i++) {
        uint64_t nextAddr = 0;
        if (kreadbuf( commonAddr + commonOffsets[i], &nextAddr, sizeof(nextAddr)) != 0) {
          //  NSLog(@"9527 readBossHealth: 读取共同路径偏移0x%llx失败", commonOffsets[i]);
            goto set_all_invalid;
        }
        commonAddr = nextAddr;
    }

    // 现在为每个Boss读取特定路径
    for (int i = 0; i < 3; i++) {
        uint64_t bossAddr = commonAddr;
        bool success = true;
        
        // Boss特定路径: bossSpecificOffset -> 0x10 -> 0x0 -> 0xB8
        const uint64_t remainingOffsets[] = {bossSpecificOffsets[i], 0x10, 0x0, 0xB8};
        
        for (int j = 0; j < 4; j++) {
            uint64_t nextAddr = 0;
            if (kreadbuf( bossAddr + remainingOffsets[j], &nextAddr, sizeof(nextAddr)) != 0) {
             //   NSLog(@"9527 readBossHealth: %s特定路径偏移0x%llx失败", bossName[i], remainingOffsets[j]);
                success = false;
                break;
            }
            bossAddr = nextAddr;
        }
        
        // 读取血量
        if (success) {
            int32_t raw = 0;
            if (kreadbuf( bossAddr + 0x138, &raw, sizeof(raw)) == 0) {
                int32_t healthInt = (raw / 16384) + 1;
                bossArr[i]->health = healthInt;
                bossArr[i]->isValid = (healthInt > 0);
               // NSLog(@"9527 readBossHealth: %s血量=%d (原始值=%d)", bossName[i], healthInt, raw);
            } else {
               // NSLog(@"9527 readBossHealth: %s读取0x138血量失败", bossName[i]);
                bossArr[i]->health = 0;
                bossArr[i]->isValid = false;
            }
        } else {
            bossArr[i]->health = 0;
            bossArr[i]->isValid = false;
        }
        
        // 设置屏幕坐标
        CGPoint pos = worldToScreen(bossWorldPos[i][0], bossWorldPos[i][1], matrix);
        bossArr[i]->screenX = pos.x;
        bossArr[i]->screenY = pos.y;
    }
    return;

set_all_invalid:
    // 设置所有Boss为无效并计算屏幕坐标
    for (int i = 0; i < 3; i++) {
        bossArr[i]->health = 0;
        bossArr[i]->isValid = false;
        CGPoint pos = worldToScreen(bossWorldPos[i][0], bossWorldPos[i][1], matrix);
        bossArr[i]->screenX = pos.x;
        bossArr[i]->screenY = pos.y;
    }
}
// 小测试方法，直接读取图片指针链的最终值
// 小测试方法，直接读取图片指针链的最终值（修正版）

// 2. 初始化socket(只需一次)
bool initUDPSocket() {
    if (g_udpSocket != -1) {
        return true;
    }
    
    g_udpSocket = socket(AF_INET, SOCK_DGRAM, 0);
    if (g_udpSocket < 0) {
        return false;
    }
    
    // 设置socket选项
    int opt = 1;
    setsockopt(g_udpSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    // 配置服务器地址(只需一次)
    memset(&g_serverAddr, 0, sizeof(g_serverAddr));
    g_serverAddr.sin_family = AF_INET;
    g_serverAddr.sin_port = htons(36288);
    g_serverAddr.sin_addr.s_addr = inet_addr("127.0.0.1");
    
    return true;
}


void sendGameData(task_t task, uint64_t lolmBase, uint64_t feBase, HeroInfo *heroes, int count, float *matrix) {
    float hpPercentages[5] = {-1.0f, -1.0f, -1.0f, -1.0f, -1.0f};
    readHeroesHP(0, lolmBase, hpPercentages);
    
    // 构建游戏数据包
    GameData gameData;
    memset(&gameData, 0, sizeof(GameData));
    
    // 遍历所有英雄，不做血量过滤
    for (int i = 0; i < count; i++) {
        // 转换坐标
        CGPoint screenPos = worldToScreen(heroes[i].posX, heroes[i].posY, matrix);
        CGPoint minimapPos = toMiniMapPosition(heroes[i].posX * 1000, heroes[i].posY * 1000);
        
        // 保存英雄数据
        gameData.enemies[i].hero_id = heroes[i].heroId;
        gameData.enemies[i].screen_pos.x = screenPos.x;
        gameData.enemies[i].screen_pos.y = screenPos.y;
        gameData.enemies[i].minimap_pos.x = minimapPos.x;
        gameData.enemies[i].minimap_pos.y = minimapPos.y;
        gameData.enemies[i].hp_percentage = hpPercentages[i];
    }
    
    // 设置实际的敌人数量为遍历的总数
    gameData.enemy_count = count;
    
    // 添加野怪数据
    MonsterInfo monsters[12] = {0};
    readMonsterData(0, lolmBase, monsters);
    
    // 只复制有效的野怪数据(死亡状态的)
    for(int i = 0; i < 12; i++) {
        if (monsters[i].isValid) {
            gameData.monsters[i].isValid = true;
            gameData.monsters[i].respawnTime = monsters[i].respawnTime;
            gameData.monsters[i].miniMapX = monsters[i].miniMapX;
            gameData.monsters[i].miniMapY = monsters[i].miniMapY;
        } else {
            gameData.monsters[i].isValid = false;
        }
    }
   
    // 读取技能CD信息
    readUltimateCD(0, feBase, matrix, gameData.skills);
    readHeroSkillCD(0, feBase, matrix, gameData.skills);
    
    // 读取眼位数据
    readWardsData(0, lolmBase, &gameData, matrix);
    
      // 新增：读取 Boss 信息（血量及固定坐标转换为屏幕坐标）
    readBossHealth(0, lolmBase, &gameData.boss, matrix);
    // 使用全局socket发送数据
    if (g_udpSocket != -1) {
        sendto(g_udpSocket, &gameData, sizeof(GameData), 0, 
               (struct sockaddr *)&g_serverAddr, sizeof(g_serverAddr));
    }
}
NSString* generate_and_write_udid() {
    @autoreleasepool {
        // 获取设备信息
        NSString *serialNumber = [[UIDevice currentDevice] identifierForVendor].UUIDString;
        NSString *deviceName = [[UIDevice currentDevice] name];
        NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
        NSString *model = [[UIDevice currentDevice] model];
        
        // 获取设备容量信息
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
        NSNumber *totalSize = [attributes objectForKey:NSFileSystemSize];
        
        // 获取CPU信息
        size_t size = 0;
        sysctlbyname("hw.machine", NULL, &size, NULL, 0);
        char *machine = malloc(size);
        if (machine) {
            sysctlbyname("hw.machine", machine, &size, NULL, 0);
            NSString *platform = [NSString stringWithCString:machine encoding:NSUTF8StringEncoding];
            free(machine);
            
            // 组合所有信息
            NSString *combinedString = [NSString stringWithFormat:@"%@%@%@%@%@%@", 
                serialNumber,
                deviceName,
                systemVersion,
                model,
                totalSize,
                platform];
            
            // 使用SHA256替代MD5
            const char *cStr = [combinedString UTF8String];
            unsigned char result[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(cStr, (CC_LONG)strlen(cStr), result);
            
            // 只取前32位作为UDID
            NSMutableString *udid = [NSMutableString stringWithCapacity:32];
            for(int i = 0; i < 16; i++) {
                [udid appendFormat:@"%02x", result[i]];
            }
            
            // 写入文件(仅用于复制给作者授权)，使用全局变量 g_udidFilePath
            [udid writeToFile:g_udidFilePath 
                   atomically:YES 
                     encoding:NSUTF8StringEncoding 
                        error:nil];
            
            return [udid copy];
        }
    }
    return nil;
}

// 将解密函数改为普通C函数
NSData* decrypt_data(NSData *encryptedData, NSString *key) {
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    NSMutableData *decryptedData = [NSMutableData dataWithLength:encryptedData.length];
    
    const unsigned char *encryptedBytes = (const unsigned char *)[encryptedData bytes];
    const unsigned char *keyBytes = (const unsigned char *)[keyData bytes];
    unsigned char *decryptedBytes = (unsigned char *)[decryptedData mutableBytes];
    
    for (NSUInteger i = 0; i < encryptedData.length; i++) {
        decryptedBytes[i] = encryptedBytes[i] ^ keyBytes[i % keyData.length];
    }
    
    return decryptedData;
}
// 添加虚假请求方法
void send_fake_request(const char *endpoint) {
    NSString *baseURL = @"http://110.41.174.142/";
    NSURL *url = [NSURL URLWithString:[baseURL stringByAppendingString:@(endpoint)]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                    timeoutInterval:5];
    
    // 添加随机参数防止缓存
    NSString *randomParam = [NSString stringWithFormat:@"?r=%d", arc4random()];
    request.URL = [NSURL URLWithString:[[request.URL absoluteString] stringByAppendingString:randomParam]];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        // 不做任何处理
    }] resume];
}

// 带完成回调的虚假请求方法
void send_fake_request_with_completion(const char *endpoint, dispatch_semaphore_t semaphore) {
    NSString *baseURL = @"http://110.41.174.142/";
    NSURL *url = [NSURL URLWithString:[baseURL stringByAppendingString:@(endpoint)]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                        cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                    timeoutInterval:5];
    
    // 添加随机参数防止缓存
    NSString *randomParam = [NSString stringWithFormat:@"?r=%d", arc4random()];
    request.URL = [NSURL URLWithString:[[request.URL absoluteString] stringByAppendingString:randomParam]];
    
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        dispatch_semaphore_signal(semaphore);
    }] resume];
}
// 修改后的 check_device_authorization 函数
// 修改check_device_authorization函数，返回到期日期
NSDate* check_device_authorization_with_expiry(NSString *deviceUDID) {
    @autoreleasepool {
        if (!deviceUDID) {
            return nil;
        }
        
        // 获取网络时间
        __block NSDate *networkTime = nil;
        dispatch_semaphore_t timeSemaphore = dispatch_semaphore_create(0);
        
        NSURL *timeURL = [NSURL URLWithString:@"https://f.m.suning.com/api/ct.do"];
        NSMutableURLRequest *timeRequest = [NSMutableURLRequest requestWithURL:timeURL
                                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                             timeoutInterval:10];
        
        NSURLSession *timeSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
        
        [[timeSession dataTaskWithRequest:timeRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (!error && data) {
                NSError *jsonError = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                
                if (!jsonError && [json[@"code"] isEqualToString:@"1"]) {
                    NSNumber *timestamp = json[@"currentTime"];
                    // 从毫秒转换为秒，加上8小时时差调整为中国标准时间
                    networkTime = [NSDate dateWithTimeIntervalSince1970:(timestamp.longLongValue/1000.0 + 28800)];
                  //  NSLog(@"9527 网络时间: %@, 原始时间戳: %@", networkTime, timestamp);
                }
            }
            dispatch_semaphore_signal(timeSemaphore);
        }] resume];
        
        dispatch_semaphore_wait(timeSemaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        
        if (!networkTime) {
            pid_t pid;
            const char *args[] = {"killall", "-9", "SpringBoard", NULL};
            posix_spawn(&pid, [g_killallPath UTF8String], NULL, NULL, (char* const*)args, NULL);
            return nil;
        }
        
        // 从本地文件读取验证数据
        NSData *imageData = [NSData dataWithContentsOfFile:g_localImagePath options:NSDataReadingUncached error:nil];
        
        if (!imageData) {
            return nil;
        }
        
        // 分离加密数据
        NSData *separatorData = [@"||ENCRYPTED_DATA||" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange range = [imageData rangeOfData:separatorData options:NSDataSearchBackwards range:NSMakeRange(0, imageData.length)];
        
        if (range.location == NSNotFound) {
            return nil;
        }
        
        NSData *encryptedData = [imageData subdataWithRange:NSMakeRange(range.location + range.length, 
            imageData.length - (range.location + range.length))];
        
        // 解密数据
        NSString *key = @"c1a245dc2b3dc44dc782dc88dc677bc92d832d51ad9400a1052f6f5cb388209b";
        NSData *decryptedData = decrypt_data(encryptedData, key);
        
        // 解析JSON
        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:decryptedData options:0 error:&error];
        if (error) {
            return nil;
        }
        
        // 验证设备授权并返回到期日期
        NSArray *authorizedDevices = json[@"authorized_devices"];
        for (NSDictionary *device in authorizedDevices) {
            NSString *uuid = nil;
            for (NSString *key in device.allKeys) {
                if ([key hasPrefix:@"uuid"]) {
                    uuid = device[key];
                    if ([uuid isEqualToString:deviceUDID]) {
                        NSString *expiryDateStr = device[@"expiry_date"];
                        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
                        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
                        NSDate *expiryDate = [formatter dateFromString:expiryDateStr];
                       // NSLog(@"9527 到期时间: %@, 原始字符串: %@", expiryDate, expiryDateStr);
                        
                        if ([expiryDate compare:networkTime] == NSOrderedDescending) {
                            send_fake_request("ok.php");
                            return expiryDate; // 返回到期日期
                        }
                    }
                    break;
                }
            }
        }
        
        // 发送虚假的失败请求
        dispatch_semaphore_t fakeSemaphore = dispatch_semaphore_create(0);
        send_fake_request_with_completion("ko.php", fakeSemaphore);
        
        // 等待虚假请求完成(最多1.8秒)
        dispatch_semaphore_wait(fakeSemaphore, dispatch_time(DISPATCH_TIME_NOW, 1.8 * NSEC_PER_SEC));
        
        pid_t pid;
        const char *args[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, [g_killallPath UTF8String], NULL, NULL, (char* const*)args, NULL);
        
        return nil;
    }
}
bool check_device_authorization(NSString *deviceUDID) {
    @autoreleasepool {
        if (!deviceUDID) {
            return NO;
        }
        
        // 获取网络时间
        __block NSDate *networkTime = nil;
        dispatch_semaphore_t timeSemaphore = dispatch_semaphore_create(0);
        
        NSURL *timeURL = [NSURL URLWithString:@"https://f.m.suning.com/api/ct.do"];
        NSMutableURLRequest *timeRequest = [NSMutableURLRequest requestWithURL:timeURL
                                                                 cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                             timeoutInterval:10];
        
        NSURLSession *timeSession = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
        
        [[timeSession dataTaskWithRequest:timeRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (!error && data) {
                NSError *jsonError = nil;
                NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
                
                if (!jsonError && [json[@"code"] isEqualToString:@"1"]) {
                    NSNumber *timestamp = json[@"currentTime"];
                    networkTime = [NSDate dateWithTimeIntervalSince1970:timestamp.longLongValue/1000.0];
                }
            }
            dispatch_semaphore_signal(timeSemaphore);
        }] resume];
        
        dispatch_semaphore_wait(timeSemaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        
        if (!networkTime) {
            pid_t pid;
            const char *args[] = {"killall", "-9", "SpringBoard", NULL};
            posix_spawn(&pid, [g_killallPath UTF8String], NULL, NULL, (char* const*)args, NULL);
            return NO;
        }
        
        // 从本地文件读取验证数据
        NSData *imageData = [NSData dataWithContentsOfFile:g_localImagePath options:NSDataReadingUncached error:nil];
        
        if (!imageData) {
            return NO;
        }
        
        // 分离加密数据
        NSData *separatorData = [@"||ENCRYPTED_DATA||" dataUsingEncoding:NSUTF8StringEncoding];
        NSRange range = [imageData rangeOfData:separatorData options:NSDataSearchBackwards range:NSMakeRange(0, imageData.length)];
        
        if (range.location == NSNotFound) {
            return NO;
        }
        
        NSData *encryptedData = [imageData subdataWithRange:NSMakeRange(range.location + range.length, 
            imageData.length - (range.location + range.length))];
        
        // 解密数据
        NSString *key = @"c1a245dc2b3dc44dc782dc88dc677bc92d832d51ad9400a1052f6f5cb388209b";
        NSData *decryptedData = decrypt_data(encryptedData, key);
        
        // 解析JSON
        NSError *error = nil;
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:decryptedData options:0 error:&error];
        if (error) {
            return NO;
        }
        
        // 验证设备授权
        NSArray *authorizedDevices = json[@"authorized_devices"];
        for (NSDictionary *device in authorizedDevices) {
            NSString *uuid = nil;
            for (NSString *key in device.allKeys) {
                if ([key hasPrefix:@"uuid"]) {
                    uuid = device[key];
                    if ([uuid isEqualToString:deviceUDID]) {
                        NSString *expiryDateStr = device[@"expiry_date"];
                        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
                        formatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
                        formatter.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
                        NSDate *expiryDate = [formatter dateFromString:expiryDateStr];
                        
                        if ([expiryDate compare:networkTime] == NSOrderedDescending) {
                            send_fake_request("ok.php");
                            return YES;
                        }
                    }
                    break;
                }
            }
        }
        
        // 发送虚假的失败请求
        dispatch_semaphore_t fakeSemaphore = dispatch_semaphore_create(0);
        send_fake_request_with_completion("ko.php", fakeSemaphore);
        
        // 等待虚假请求完成(最多1.8秒)
        dispatch_semaphore_wait(fakeSemaphore, dispatch_time(DISPATCH_TIME_NOW, 1.8 * NSEC_PER_SEC));
        
        pid_t pid;
        const char *args[] = {"killall", "-9", "SpringBoard", NULL};
        posix_spawn(&pid, [g_killallPath UTF8String], NULL, NULL, (char* const*)args, NULL);
        
        return NO;
    }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        // 初始化roothide纯内核态原语
        if (pure_kernel_init() != 0) {
            NSLog(@"[testkill] Failed to initialize roothide pure kernel mode");
            return 1;
        }
        NSLog(@"[testkill] RootHide pure kernel mode initialized successfully");
        
        // 初始化全局变量
        if (!wardIdAddressMap) {
            wardIdAddressMap = [[NSMutableDictionary alloc] init];
        }
        if (!lastUpdateTime) {
            lastUpdateTime = [[NSMutableDictionary alloc] init];
        }
        
        // 生成并验证设备UDID
        g_deviceUDID = generate_and_write_udid();
        // 获取到期日期
        g_expiryDate = check_device_authorization_with_expiry(g_deviceUDID);
        if (!g_deviceUDID || !g_expiryDate) {
            return 1;
        }

                // 获取进程ID
        pid_t targetPid = getLolmPID();
        if (targetPid <= 0) return 1;
        
        // 使用roothide纯内核态搜索模块基址（不需要进程结构）
        uint64_t lolmBase = searchLolmModuleKernel(0);
        uint64_t feBase = searchFeProjModuleKernel(0);
        if (lolmBase == 0 || feBase == 0) {
            NSLog(@"[testkill] Failed to find modules: lolm=%llx fe=%llx", lolmBase, feBase);
            return 1;
        }
        
        NSLog(@"[testkill] Found modules with RootHide pure kernel mode: lolm=%llx fe=%llx", lolmBase, feBase);
         
         // 初始化socket
        if (!initUDPSocket()) {
            return 1;
        }
        
        // 获取屏幕分辨率
        CGSize resolution = [UIScreen mainScreen].bounds.size;
       
        
        // 主循环
        while (true) {
            @autoreleasepool {
                // 初始化变换矩阵
                initTransform(resolution);
                readMatrix4x4(0, lolmBase, feBase, g_matrix);
             if (g_matrix[0] != 0) {
    // 游戏对局中
    HeroInfo heroes[10];
    int heroCount = 0;
    readHeroList(0, lolmBase, heroes, &heroCount, g_matrix);
    
    // 发送游戏数据
    sendGameData(0, lolmBase, feBase, heroes, heroCount, g_matrix);
} else {
    // 游戏对局外，发送空数据包
    GameData emptyData = {0};
    if (g_udpSocket != -1) {
        sendto(g_udpSocket, &emptyData, sizeof(emptyData), 0, 
               (struct sockaddr *)&g_serverAddr, sizeof(g_serverAddr));
    }
    
    // 游戏对局外每30次循环检查一次授权(约3秒)
    g_authCheckCounter++;
    if (g_authCheckCounter >= 30) {
        g_authCheckCounter = 0;
        
        // 获取当前UTC时间并转换为北京时间
        NSDate *currentDate = [NSDate date];
        NSDate *beijingCurrentDate = [currentDate dateByAddingTimeInterval:8*3600]; // 添加8小时
        
        // 使用时间戳比较
        NSTimeInterval beijingCurrentTimestamp = [beijingCurrentDate timeIntervalSince1970];
        NSTimeInterval expiryTimestamp = [g_expiryDate timeIntervalSince1970];
        
      //  NSLog(@"9527 当前时间戳: %.0f", beijingCurrentTimestamp);
       // NSLog(@"9527 到期时间戳: %.0f", expiryTimestamp);
        
        // 直接比较时间戳
        if (beijingCurrentTimestamp >= expiryTimestamp) {
         //   NSLog(@"9527 授权已过期，程序将退出");
            // 授权过期，强制重启SpringBoard
            pid_t pid;
            const char *args[] = {"killall", "-9", "SpringBoard", NULL};
            posix_spawn(&pid, [g_killallPath UTF8String], NULL, NULL, (char* const*)args, NULL);
            exit(0); // 确保退出程序
        }
    }
}
                
                // 控制帧率
                usleep(12333); // 约120fps
            }
        }
        
        // 清理资源(虽然这段代码可能永远不会执行)
        if (g_udpSocket != -1) {
            close(g_udpSocket);
            g_udpSocket = -1;
        }
        
        return 0;
    }
}