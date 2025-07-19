#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <spawn.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <objc/runtime.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/utsname.h>
#include <roothide.h>

#import <rootless.h>
// 数据结构定义
typedef struct {
    int32_t ultimateCD;
    int32_t spell1ID;
    int32_t spell1CD;
    int32_t spell2ID;
    int32_t spell2CD;
} HeroSkillInfo;

typedef struct {
    float x;
    float y;
} Vector2;

typedef struct {
    int32_t hero_id;
    float hp_percentage;
    Vector2 screen_pos;
    Vector2 minimap_pos;
} EnemyInfo;

typedef struct {
    bool isValid;     // 标记该数据是否需要发送(死亡状态才发送)
    float respawnTime;
    float miniMapX;
    float miniMapY;
} MonsterData;

typedef struct {
    int32_t wardId;
    int32_t status;
    float screenX;
    float screenY;
    float miniMapX;
    float miniMapY;
} WardData;
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
typedef struct {
    int enemy_count;
    EnemyInfo enemies[5];
    MonsterData monsters[12];
    HeroSkillInfo skills[5];
    int ward_count;          // 眼位数量
    WardData wards[20];      // 眼位数据数组
      BossData boss;           // 新增 Boss 数据字段
} GameData;
// 在文件顶部添加静态变量作为关联对象键



// 替换原来的静态常量定义，使用宏定义进行替代
#define kHeroIconDirectory jbroot(@"/var/jb/tmp/heroicon")
#define kUDIDPath          jbroot(@"/var/jb/tmp/udid.txt")
#define kConfigPath        jbroot(@"/var/jb/tmp/heroicon/xyz.ini")
#define kStartFlagPath     jbroot(@"/var/jb/tmp/start.flag")
#define kHelperPath        jbroot(@"/Library/Helper/FloatingBallHelper")

// 绘制视图类
@interface SecureOverlayView : UIView
@property (nonatomic, strong) UIView *secureView;
@property (nonatomic, strong) NSMutableArray<UIView *> *minimapViews;
@property (nonatomic, assign) int udpSocket;
@property (nonatomic, strong) dispatch_source_t udpSource;
@property (nonatomic, strong) NSCache *imageCache;  // 添加这行
@property (nonatomic, strong) NSMutableDictionary *heroViews;  // 添加这行，用于存储和重用视图
@property (nonatomic, strong) NSMutableArray<UILabel *> *monsterRespawnLabels;  // 野怪刷新时间标签
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) NSMutableDictionary *heroPositions; // 存储英雄位置
@property (nonatomic, strong) NSMutableDictionary *targetPositions; // 存储目标位置
@property (nonatomic, strong) NSMutableArray<UIView *> *wardViews; // 添加眼位视图数组
@property (nonatomic, assign) BOOL socketInitialized;  // 新增属性
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, CAShapeLayer *> *heroLayerDict;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, CAShapeLayer *> *miniHeroLayerDict;

@end

@implementation SecureOverlayView
// SecureOverlayView的初始化方法中添加测试标签
- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        UITextField *textField = [[UITextField alloc] init];
        textField.secureTextEntry = YES;
        
        self.secureView = textField.subviews.firstObject;
        if (self.secureView) {
            [self addSubview:self.secureView];
            
            // 直接使用传入的frame，不再进行旋转
            self.secureView.frame = frame;
            self.secureView.bounds = frame;
            
            self.secureView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
              // 禁用 secureView 的交互，允许点击穿透
            self.secureView.userInteractionEnabled = NO;
            
        }
        
        self.imageCache = [[NSCache alloc] init];
        self.imageCache.countLimit = 50;  // 限制缓存数量
      
        [self ensureHeroIconDirectory];
       
      
        [self setupUDPSocket];
        self.userInteractionEnabled = NO;
         // 禁用 secureView 的交互，允许点击穿透
            self.secureView.userInteractionEnabled = NO;
       
        
        // 优化图层
        self.layer.drawsAsynchronously = YES; // 异步绘制
       
        
        self.wardViews = [NSMutableArray array];
    }
    return self;
}

- (void)ensureHeroIconDirectory {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:kHeroIconDirectory]) {
        [fileManager createDirectoryAtPath:kHeroIconDirectory
               withIntermediateDirectories:YES
                                attributes:nil
                                     error:nil];
    }
}
- (void)setupUDPSocket {
    if (self.socketInitialized) {
        return;
    }
    
    self.udpSocket = socket(AF_INET, SOCK_DGRAM, 0);
    if (self.udpSocket < 0) return;
    
    // 设置socket选项
    int opt = 1;
    setsockopt(self.udpSocket, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_port = htons(36288);
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    
    if (bind(self.udpSocket, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(self.udpSocket);
        return;
    }
    
    fcntl(self.udpSocket, F_SETFL, fcntl(self.udpSocket, F_GETFL, 0) | O_NONBLOCK);
    
    self.udpSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, 
                                          self.udpSocket, 
                                          0, 
                                          dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    
    dispatch_source_set_event_handler(self.udpSource, ^{
        [self handleUDPData];
    });
    
    dispatch_resume(self.udpSource);
    self.socketInitialized = YES;
}
- (void)handleUDPData {
    GameData gameData;
    struct sockaddr_in sender_addr;
    socklen_t addr_len = sizeof(sender_addr);
    
    ssize_t recv_len = recvfrom(self.udpSocket, &gameData, sizeof(GameData), 0,
                               (struct sockaddr *)&sender_addr, &addr_len);
    
    if (recv_len == sizeof(GameData)) {
           dispatch_async(dispatch_get_main_queue(), ^{
       [self drawHeroesUsingCAShapeLayer:gameData];
        [self updateRightSkillPanelWithGameData:gameData];
 [self drawWardsUsingCAShapeLayer:gameData];
    [self updateMonsterCountdownOnMiniMap:gameData];
      [self drawBossInfoUsingCAShapeLayer:gameData.boss];
   });
    }
}
// 添加坐标转换辅助方法
- (CGPoint)convertGameCoordinate:(CGPoint)gameCoord {
    CGFloat screenScale = [UIScreen mainScreen].scale;
    CGFloat x = (gameCoord.x / screenScale);
    CGFloat y = (gameCoord.y / screenScale);
    
    return CGPointMake(x, y);
}
- (void)drawBossInfoUsingCAShapeLayer:(BossData)bossData {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    // 判断设备类型，设置比例
    BOOL isIpad = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
    CGFloat scaleFactor = isIpad ? 1.0 : 0.65;
    
    // 定义文字样式 - 加大字号
    CGFloat fontSize = 32.0 * scaleFactor;  // 更大的字号
    CGFloat textWidth = 80.0 * scaleFactor; // 加宽以适应更大的字号
    CGFloat textHeight = 40.0 * scaleFactor;
    
    // 统一使用醒目的红色
    CGColorRef textColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:1.0].CGColor;
    
    // ===================== 大龙信息 =====================
    if (bossData.bigDragon.isValid && bossData.bigDragon.health > 1.5) {
        CALayer *bossLayer = [self getOrCreateLayerWithName:@"bossLayer_bigDragon"];
        bossLayer.frame = CGRectMake(0, 0, textWidth, textHeight);
        
        CGPoint screenPos = [self convertGameCoordinate:CGPointMake(bossData.bigDragon.screenX, bossData.bigDragon.screenY)];
        bossLayer.position = screenPos;
        
        CATextLayer *textLayer = (CATextLayer *)[self sublayerInLayer:bossLayer withName:@"textLayer" usingClass:[CATextLayer class]];
        textLayer.frame = bossLayer.bounds;
        textLayer.string = [NSString stringWithFormat:@"%d", (int)bossData.bigDragon.health];
        textLayer.fontSize = fontSize;
        textLayer.alignmentMode = kCAAlignmentCenter;
        textLayer.foregroundColor = textColor;
        textLayer.contentsScale = [UIScreen mainScreen].scale;
        
        // 加重阴影效果提高可读性
        textLayer.shadowColor = [UIColor blackColor].CGColor;
        textLayer.shadowOffset = CGSizeMake(0, 2);
        textLayer.shadowOpacity = 1.0;
        textLayer.shadowRadius = 2.0;
    } else {
        [self hideLayerWithName:@"bossLayer_bigDragon"];
    }
    
    // ===================== 小龙信息 =====================
    if (bossData.smallDragon.isValid && bossData.smallDragon.health > 1.5) {
        CALayer *bossLayer = [self getOrCreateLayerWithName:@"bossLayer_smallDragon"];
        bossLayer.frame = CGRectMake(0, 0, textWidth, textHeight);
        
        CGPoint screenPos = [self convertGameCoordinate:CGPointMake(bossData.smallDragon.screenX, bossData.smallDragon.screenY)];
        bossLayer.position = screenPos;
        
        CATextLayer *textLayer = (CATextLayer *)[self sublayerInLayer:bossLayer withName:@"textLayer" usingClass:[CATextLayer class]];
        textLayer.frame = bossLayer.bounds;
        textLayer.string = [NSString stringWithFormat:@"%d", (int)bossData.smallDragon.health];
        textLayer.fontSize = fontSize;
        textLayer.alignmentMode = kCAAlignmentCenter;
        textLayer.foregroundColor = textColor;
        textLayer.contentsScale = [UIScreen mainScreen].scale;
        
        textLayer.shadowColor = [UIColor blackColor].CGColor;
        textLayer.shadowOffset = CGSizeMake(0, 2);
        textLayer.shadowOpacity = 1.0;
        textLayer.shadowRadius = 2.0;
    } else {
        [self hideLayerWithName:@"bossLayer_smallDragon"];
    }
    
    // ===================== 先锋信息 =====================
    if (bossData.vanguard.isValid && bossData.vanguard.health > 1.5) {
        CALayer *bossLayer = [self getOrCreateLayerWithName:@"bossLayer_vanguard"];
        bossLayer.frame = CGRectMake(0, 0, textWidth, textHeight);
        
        CGPoint screenPos = [self convertGameCoordinate:CGPointMake(bossData.vanguard.screenX, bossData.vanguard.screenY)];
        bossLayer.position = screenPos;
        
        CATextLayer *textLayer = (CATextLayer *)[self sublayerInLayer:bossLayer withName:@"textLayer" usingClass:[CATextLayer class]];
        textLayer.frame = bossLayer.bounds;
        textLayer.string = [NSString stringWithFormat:@"%d", (int)bossData.vanguard.health];
        textLayer.fontSize = fontSize;
        textLayer.alignmentMode = kCAAlignmentCenter;
        textLayer.foregroundColor = textColor;
        textLayer.contentsScale = [UIScreen mainScreen].scale;
        
        textLayer.shadowColor = [UIColor blackColor].CGColor;
        textLayer.shadowOffset = CGSizeMake(0, 2);
        textLayer.shadowOpacity = 1.0;
        textLayer.shadowRadius = 2.0;
    } else {
        [self hideLayerWithName:@"bossLayer_vanguard"];
    }
    
    [CATransaction commit];
}

// 辅助方法：获取或创建图层
- (CALayer *)getOrCreateLayerWithName:(NSString *)name {
    CALayer *layer = nil;
    for (CALayer *existingLayer in self.secureView.layer.sublayers) {
        if ([existingLayer.name isEqualToString:name]) {
            layer = existingLayer;
            layer.hidden = NO;
            break;
        }
    }
    if (!layer) {
        layer = [CALayer layer];
        layer.name = name;
        [self.secureView.layer addSublayer:layer];
    }
    return layer;
}

// 辅助方法：隐藏指定名称的图层
- (void)hideLayerWithName:(NSString *)name {
    for (CALayer *layer in self.secureView.layer.sublayers) {
        if ([layer.name isEqualToString:name]) {
            layer.hidden = YES;
            break;
        }
    }
}

// 优化后的 healthRingLayerWithPercentage 方法：根据血量百分比绘制血量环，arc 长度根据百分比变化，线宽加粗
- (CAShapeLayer *)healthRingLayerWithPercentage:(float)percentage frame:(CGRect)frame {
    CAShapeLayer *ringLayer = [CAShapeLayer layer];
    ringLayer.frame = frame;
    
    // 绘制完整圆弧路径（起始角 -90° 到 270°）
    CGFloat radius = MIN(frame.size.width, frame.size.height) / 2 - 2;
    CGPoint center = CGPointMake(frame.size.width / 2, frame.size.height / 2);
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                        radius:radius
                                                    startAngle:-M_PI_2
                                                      endAngle:3 * M_PI_2
                                                     clockwise:YES];
    ringLayer.path = path.CGPath;
    ringLayer.fillColor = [UIColor clearColor].CGColor;
    
    // 线宽加粗，使血量环更明显
    ringLayer.lineWidth = frame.size.width / 8;
    
    // 根据血量百分比动态绘制 arc（strokeEnd 控制显示比例）
    ringLayer.strokeStart = 0.0;
    ringLayer.strokeEnd = percentage / 100.0;
    ringLayer.lineCap = kCALineCapRound;
    
    // 根据血量百分比可选性设置不同颜色（此处保留原逻辑）
    if (percentage >= 70) {
        ringLayer.strokeColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:0.9].CGColor;
    } else if (percentage >= 30) {
        ringLayer.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:0.9].CGColor;
    } else {
        ringLayer.strokeColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.9].CGColor;
    }
    
    return ringLayer;
}
- (void)drawWardsUsingCAShapeLayer:(GameData)gameData {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    // 判断设备类型，设置比例：iPad 保持原样，iPhone 缩小为 65%
    BOOL isIpad = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
    CGFloat scaleFactor = isIpad ? 1.0 : 0.65;
    
    int wardCount = gameData.ward_count;
    for (int i = 0; i < wardCount; i++) {
        WardData ward = gameData.wards[i];
        
        // 根据 wardId 判断眼位颜色，仅处理 820505（黄色）与 820506（红色）
        UIColor *wardColor = nil;
        if (ward.wardId == 820505) {
            wardColor = [UIColor colorWithRed:1.0 green:0.85 blue:0.0 alpha:1.0]; // 小黄眼
        } else if (ward.wardId == 820506) {
            wardColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];  // 小红眼
        } else {
            continue;
        }
        
        // ===================== 屏幕上眼位 =====================
        // 使用固定命名格式便于复用：wardScreenEye_i
        NSString *screenLayerName = [NSString stringWithFormat:@"wardScreenEye_%d", i];
        CALayer *screenEyeLayer = nil;
        for (CALayer *layer in self.secureView.layer.sublayers) {
            if ([layer.name isEqualToString:screenLayerName]) {
                screenEyeLayer = layer;
                break;
            }
        }
        if (!screenEyeLayer) {
            screenEyeLayer = [CALayer layer];
            screenEyeLayer.name = screenLayerName;
            [self.secureView.layer addSublayer:screenEyeLayer];
        }
        screenEyeLayer.hidden = NO;
        
        // 修改屏幕上眼位整体尺寸，原始 18×18，iPhone 缩小 65%
        CGFloat screenEyeSize = 18.0 * scaleFactor;
        screenEyeLayer.frame = CGRectMake(0, 0, screenEyeSize, screenEyeSize);
        CGPoint wardScreenCoord = [self convertGameCoordinate:CGPointMake(ward.screenX, ward.screenY)];
        screenEyeLayer.position = wardScreenCoord;
        
        // 第1层：巩膜（白色背景） – 绘制整个眼球的外圈
        CAShapeLayer *scleraLayer = (CAShapeLayer *)[self sublayerInLayer:screenEyeLayer withName:@"scleraLayer" usingClass:[CAShapeLayer class]];
        scleraLayer.frame = screenEyeLayer.bounds;
        UIBezierPath *scleraPath = [UIBezierPath bezierPathWithOvalInRect:scleraLayer.bounds];
        scleraLayer.path = scleraPath.CGPath;
        scleraLayer.fillColor = [UIColor whiteColor].CGColor;
        scleraLayer.strokeColor = [UIColor colorWithWhite:0.8 alpha:1.0].CGColor;
        scleraLayer.lineWidth = 1.0;
        
        // 第2层：虹膜 – 根据 wardColor 设置颜色，inset 稍小于外层
        CAShapeLayer *irisLayer = (CAShapeLayer *)[self sublayerInLayer:screenEyeLayer withName:@"irisLayer" usingClass:[CAShapeLayer class]];
        CGFloat irisInset = 3.0 * scaleFactor;
        irisLayer.frame = CGRectInset(screenEyeLayer.bounds, irisInset, irisInset);
        UIBezierPath *irisPath = [UIBezierPath bezierPathWithOvalInRect:irisLayer.bounds];
        irisLayer.path = irisPath.CGPath;
        irisLayer.fillColor = wardColor.CGColor;
        irisLayer.strokeColor = nil;
        
        // 第3层：瞳孔 – 再 inset 得到中心黑色圆点
        CAShapeLayer *pupilLayer = (CAShapeLayer *)[self sublayerInLayer:screenEyeLayer withName:@"pupilLayer" usingClass:[CAShapeLayer class]];
        CGFloat pupilInset = 7.0 * scaleFactor;
        pupilLayer.frame = CGRectInset(screenEyeLayer.bounds, pupilInset, pupilInset);
        UIBezierPath *pupilPath = [UIBezierPath bezierPathWithOvalInRect:pupilLayer.bounds];
        pupilLayer.path = pupilPath.CGPath;
        pupilLayer.fillColor = [UIColor blackColor].CGColor;
        pupilLayer.strokeColor = nil;
        
        // 第4层：高光 – 在瞳孔上添加一小块亮点，增强立体感
        CAShapeLayer *highlightLayer = (CAShapeLayer *)[self sublayerInLayer:screenEyeLayer withName:@"highlightLayer" usingClass:[CAShapeLayer class]];
        CGFloat highlightWidth = 4.0 * scaleFactor;
        CGFloat highlightHeight = 3.0 * scaleFactor;
        CGRect highlightFrame = CGRectMake(3.0 * scaleFactor, 3.0 * scaleFactor, highlightWidth, highlightHeight);
        highlightLayer.frame = highlightFrame;
        UIBezierPath *highlightPath = [UIBezierPath bezierPathWithOvalInRect:highlightLayer.bounds];
        highlightLayer.path = highlightPath.CGPath;
        highlightLayer.fillColor = [UIColor whiteColor].CGColor;
        highlightLayer.opacity = 0.8;
        
        // ===================== 小地图上眼位 =====================
        // 命名规则：wardMiniEye_i
        NSString *miniLayerName = [NSString stringWithFormat:@"wardMiniEye_%d", i];
        CALayer *miniEyeLayer = nil;
        for (CALayer *layer in self.secureView.layer.sublayers) {
            if ([layer.name isEqualToString:miniLayerName]) {
                miniEyeLayer = layer;
                break;
            }
        }
        if (!miniEyeLayer) {
            miniEyeLayer = [CALayer layer];
            miniEyeLayer.name = miniLayerName;
            [self.secureView.layer addSublayer:miniEyeLayer];
        }
        miniEyeLayer.hidden = NO;
        
        // 修改小地图上眼位尺寸，原始 10×10，iPhone 缩小 65%
        CGFloat miniEyeSize = 10.0 * scaleFactor;
        miniEyeLayer.frame = CGRectMake(0, 0, miniEyeSize, miniEyeSize);
        CGPoint wardMiniCoord = [self convertGameCoordinate:CGPointMake(ward.miniMapX, ward.miniMapY)];
        miniEyeLayer.position = wardMiniCoord;
        
        // 小地图巩膜
        CAShapeLayer *miniSclera = (CAShapeLayer *)[self sublayerInLayer:miniEyeLayer withName:@"scleraLayer" usingClass:[CAShapeLayer class]];
        miniSclera.frame = miniEyeLayer.bounds;
        UIBezierPath *miniScleraPath = [UIBezierPath bezierPathWithOvalInRect:miniSclera.bounds];
        miniSclera.path = miniScleraPath.CGPath;
        miniSclera.fillColor = [UIColor whiteColor].CGColor;
        miniSclera.strokeColor = [UIColor colorWithWhite:0.8 alpha:1.0].CGColor;
        miniSclera.lineWidth = 0.8 * scaleFactor;
        
        // 小地图虹膜
        CAShapeLayer *miniIris = (CAShapeLayer *)[self sublayerInLayer:miniEyeLayer withName:@"irisLayer" usingClass:[CAShapeLayer class]];
        CGFloat miniIrisInset = 2.0 * scaleFactor;
        miniIris.frame = CGRectInset(miniEyeLayer.bounds, miniIrisInset, miniIrisInset);
        UIBezierPath *miniIrisPath = [UIBezierPath bezierPathWithOvalInRect:miniIris.bounds];
        miniIris.path = miniIrisPath.CGPath;
        miniIris.fillColor = wardColor.CGColor;
        
        // 小地图瞳孔
        CAShapeLayer *miniPupil = (CAShapeLayer *)[self sublayerInLayer:miniEyeLayer withName:@"pupilLayer" usingClass:[CAShapeLayer class]];
        CGFloat miniPupilInset = 4.0 * scaleFactor;
        miniPupil.frame = CGRectInset(miniEyeLayer.bounds, miniPupilInset, miniPupilInset);
        UIBezierPath *miniPupilPath = [UIBezierPath bezierPathWithOvalInRect:miniPupil.bounds];
        miniPupil.path = miniPupilPath.CGPath;
        miniPupil.fillColor = [UIColor blackColor].CGColor;
        
        // 小地图高光
        CAShapeLayer *miniHighlight = (CAShapeLayer *)[self sublayerInLayer:miniEyeLayer withName:@"highlightLayer" usingClass:[CAShapeLayer class]];
        CGFloat miniHighlightWidth = 3.0 * scaleFactor;
        CGFloat miniHighlightHeight = 2.0 * scaleFactor;
        CGRect miniHighlightFrame = CGRectMake(2.0 * scaleFactor, 2.0 * scaleFactor, miniHighlightWidth, miniHighlightHeight);
        miniHighlight.frame = miniHighlightFrame;
        UIBezierPath *miniHighlightPath = [UIBezierPath bezierPathWithOvalInRect:miniHighlight.bounds];
        miniHighlight.path = miniHighlightPath.CGPath;
        miniHighlight.fillColor = [UIColor whiteColor].CGColor;
        miniHighlight.opacity = 0.8;
    }
    
    // 隐藏额外的眼位图层（如果上次创建的数量大于当前 wardCount）
    for (CALayer *layer in self.secureView.layer.sublayers) {
        if ([layer.name hasPrefix:@"wardScreenEye_"]) {
            NSArray *components = [layer.name componentsSeparatedByString:@"_"];
            if (components.count == 2 && [components[1] intValue] >= wardCount) {
                layer.hidden = YES;
            }
        }
        if ([layer.name hasPrefix:@"wardMiniEye_"]) {
            NSArray *components = [layer.name componentsSeparatedByString:@"_"];
            if (components.count == 2 && [components[1] intValue] >= wardCount) {
                layer.hidden = YES;
            }
        }
    }
    
    [CATransaction commit];
}
- (void)updateMonsterCountdownOnMiniMap:(GameData)gameData {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // 根据设备类型确定缩放比例：iPad 为 1.0，iPhone 缩小至 65%
    BOOL isIpad = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
    CGFloat scaleFactor = isIpad ? 1.0 : 0.65;
    
    int monsterCount = 12; // 假设野怪总数为 12

    for (int i = 0; i < monsterCount; i++) {
        MonsterData monster = gameData.monsters[i];
        NSString *layerName = [NSString stringWithFormat:@"monsterMini_%d", i];
        CALayer *monsterLayer = nil;
        for (CALayer *layer in self.secureView.layer.sublayers) {
            if ([layer.name isEqualToString:layerName]) {
                monsterLayer = layer;
                break;
            }
        }
        
        // 计算倒计时数值（复活时间 + 2 秒）
        float countdownValue = monster.respawnTime + 2;
        // 根据倒计时数值动态调整图层尺寸
        CGFloat monsterIndicatorSize = 16.0;
        if (countdownValue >= 100) { // 如果倒计时是三位数，则扩大图层尺寸
            monsterIndicatorSize = 22.0;
        }
        monsterIndicatorSize = monsterIndicatorSize * scaleFactor;
        
        if (monster.isValid) {   // 仅对死亡的野怪显示倒计时（死亡状态 isValid 为 YES）
            if (!monsterLayer) {
                monsterLayer = [CALayer layer];
                monsterLayer.name = layerName;
                [self.secureView.layer addSublayer:monsterLayer];
            }
            monsterLayer.hidden = NO;
            monsterLayer.frame = CGRectMake(0, 0, monsterIndicatorSize, monsterIndicatorSize);
            
            // 坐标转换：将野怪的小地图坐标转换为屏幕坐标，然后更新图层位置
            CGPoint monsterGameCoord = CGPointMake(monster.miniMapX, monster.miniMapY);
            CGPoint monsterScreenCoord = [self convertGameCoordinate:monsterGameCoord];
            monsterLayer.position = monsterScreenCoord;
            
            // 直接在图层上使用透明倒计时文字（图层复用）
            CATextLayer *textLayer = (CATextLayer *)[self sublayerInLayer:monsterLayer withName:@"countdownText" usingClass:[CATextLayer class]];
            textLayer.frame = monsterLayer.bounds;
            textLayer.alignmentMode = kCAAlignmentCenter;
            textLayer.contentsScale = [UIScreen mainScreen].scale;
            
            // 设置加大加粗的字体，根据 scaleFactor 调整字体大小（iPad 12pt，iPhone 缩小为 65%）
            UIFont *font = [UIFont boldSystemFontOfSize:12.0 * scaleFactor];
            NSDictionary *attributes = @{ NSFontAttributeName: font,
                                          NSForegroundColorAttributeName: [UIColor whiteColor] };
            NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%.0f", countdownValue]
                                                                           attributes:attributes];
            textLayer.string = attrStr;
        } else {
            // 野怪存活时，隐藏图层
            if (monsterLayer) {
                monsterLayer.hidden = YES;
            }
        }
    }
    
    [CATransaction commit];
}
// 辅助方法：查找指定索引和类型（主地图或小地图）的英雄图层
- (CALayer *)heroLayerForIndex:(int)index isMain:(BOOL)isMain {
    NSString *prefix = isMain ? @"heroMain_" : @"heroMini_";
    NSString *layerName = [NSString stringWithFormat:@"%@%d", prefix, index];
    for (CALayer *layer in self.secureView.layer.sublayers) {
        if ([layer.name isEqualToString:layerName]) {
            return layer;
        }
    }
    return nil;
}
- (void)drawHeroesUsingCAShapeLayer:(GameData)gameData {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    // 根据设备类型确定缩放比例：iPad 保持原样，iPhone 缩小为 65%
    BOOL isIpad = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
    CGFloat scaleFactor = isIpad ? 1.0 : 0.65;
    
    int enemyCount = gameData.enemy_count;
    // 遍历所有敌人数据（注意：跳过 hpPercentage<=0 的死亡英雄）
    for (int i = 0; i < enemyCount; i++) {
        // 取出单个敌人数据
        int32_t heroId = gameData.enemies[i].hero_id;
        float hpPercentage = gameData.enemies[i].hp_percentage;
        if (hpPercentage <= 0) {
            // 如果该英雄已死亡，则隐藏其主地图和小地图图层（若存在）
            CALayer *mainHeroLayer = [self heroLayerForIndex:i isMain:YES];
            if (mainHeroLayer) { mainHeroLayer.hidden = YES; }
            CALayer *miniHeroLayer = [self heroLayerForIndex:i isMain:NO];
            if (miniHeroLayer) { miniHeroLayer.hidden = YES; }
            continue;
        }
        
        // === 主地图英雄图层（复用或创建） ===
        CALayer *heroMainLayer = [self heroLayerForIndex:i isMain:YES];
        if (!heroMainLayer) {
            heroMainLayer = [CAShapeLayer layer];
            heroMainLayer.name = [NSString stringWithFormat:@"heroMain_%d", i];
            [self.secureView.layer addSublayer:heroMainLayer];
        }
        heroMainLayer.hidden = NO;
        // 坐标转换（屏幕坐标）
        CGPoint screenPos = [self convertGameCoordinate:CGPointMake(gameData.enemies[i].screen_pos.x,
                                                                      gameData.enemies[i].screen_pos.y)];
        // 定义布局：基础头像直径 25*scaleFactor，容器宽度 = (25*scaleFactor)*1.7，容器高度 = (25*scaleFactor)*2.8
        CGFloat heroSize = 25.0 * scaleFactor;
        CGFloat containerWidth = heroSize * 1.7;
        CGFloat containerHeight = heroSize * 2.8;
        heroMainLayer.frame = CGRectMake(0, 0, containerWidth, containerHeight);
        heroMainLayer.position = screenPos;
        
        // 头像区域（复用头像子图层）
        CALayer *avatarLayer = [self sublayerInLayer:heroMainLayer withName:@"avatarLayer" usingClass:[CALayer class]];
        CGRect avatarFrame = CGRectMake((containerWidth - heroSize) / 2,
                                        (containerHeight - heroSize) / 2,
                                        heroSize,
                                        heroSize);
        avatarLayer.frame = avatarFrame;
        avatarLayer.contentsGravity = kCAGravityResizeAspectFill;
        avatarLayer.masksToBounds = YES;
        avatarLayer.cornerRadius = heroSize / 2;
        // 异步加载英雄头像（更新时禁用隐式动画）
        [self loadHeroAvatar:heroId completion:^(UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                avatarLayer.contents = (id)image.CGImage;
                [CATransaction commit];
            });
        }];
        
        // 血量圆环（复用 healthRing 子图层）
        CAShapeLayer *healthRing = (CAShapeLayer *)[self sublayerInLayer:heroMainLayer withName:@"healthRing" usingClass:[CAShapeLayer class]];
        CGRect ringFrame = CGRectInset(avatarFrame, -4 * scaleFactor, -4 * scaleFactor);
        // 绘制完整圆弧：起始角 -90° 到 270°
        CGFloat radius = MIN(ringFrame.size.width, ringFrame.size.height) / 2;
        CGPoint center = CGPointMake(CGRectGetMidX(ringFrame), CGRectGetMidY(ringFrame));
        UIBezierPath *ringPath = [UIBezierPath bezierPathWithArcCenter:center
                                                                radius:radius
                                                            startAngle:-M_PI_2
                                                              endAngle:3*M_PI_2
                                                             clockwise:YES];
        healthRing.path = ringPath.CGPath;
        healthRing.fillColor = [UIColor clearColor].CGColor;
        healthRing.strokeStart = 0.0;
        healthRing.strokeEnd = hpPercentage / 100.0;
        healthRing.lineCap = kCALineCapRound;
        healthRing.lineWidth = ringFrame.size.width / 8;
        // 根据血量设置颜色
        if (hpPercentage >= 70) {
            healthRing.strokeColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:0.9].CGColor;
        } else if (hpPercentage >= 30) {
            healthRing.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:0.9].CGColor;
        } else {
            healthRing.strokeColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.9].CGColor;
        }
        
        // 绿色边框（复用 borderLayer 子图层）
        CAShapeLayer *borderLayer = (CAShapeLayer *)[self sublayerInLayer:heroMainLayer withName:@"borderLayer" usingClass:[CAShapeLayer class]];
        borderLayer.frame = heroMainLayer.bounds;
        UIBezierPath *borderPath = [UIBezierPath bezierPathWithRoundedRect:heroMainLayer.bounds cornerRadius:8.0 * scaleFactor];
        borderLayer.path = borderPath.CGPath;
        borderLayer.strokeColor = [UIColor greenColor].CGColor;
        borderLayer.fillColor = [UIColor clearColor].CGColor;
        borderLayer.lineWidth = 2.0 * scaleFactor;
        
        // === 小地图英雄图层（复用或创建）===
        CALayer *heroMiniLayer = [self heroLayerForIndex:i isMain:NO];
        if (!heroMiniLayer) {
            heroMiniLayer = [CAShapeLayer layer];
            heroMiniLayer.name = [NSString stringWithFormat:@"heroMini_%d", i];
            [self.secureView.layer addSublayer:heroMiniLayer];
        }
        heroMiniLayer.hidden = NO;
        // 坐标转换（小地图坐标）
        CGPoint minimapPos = [self convertGameCoordinate:CGPointMake(gameData.enemies[i].minimap_pos.x,
                                                                       gameData.enemies[i].minimap_pos.y)];
        CGFloat miniHeroSize = 15.6 * scaleFactor;
        heroMiniLayer.frame = CGRectMake(0, 0, miniHeroSize, miniHeroSize);
        heroMiniLayer.position = minimapPos;
        
        // 小地图头像区域（复用 miniAvatarLayer 子图层）
        CALayer *miniAvatarLayer = [self sublayerInLayer:heroMiniLayer withName:@"miniAvatarLayer" usingClass:[CALayer class]];
        CGRect miniAvatarFrame = CGRectMake(0, 0, miniHeroSize, miniHeroSize);
        miniAvatarLayer.frame = miniAvatarFrame;
        miniAvatarLayer.contentsGravity = kCAGravityResizeAspectFill;
        miniAvatarLayer.masksToBounds = YES;
        miniAvatarLayer.cornerRadius = miniHeroSize / 2;
        [self loadHeroAvatar:heroId completion:^(UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                miniAvatarLayer.contents = (id)image.CGImage;
                [CATransaction commit];
            });
        }];
        
        // 小地图血量圆环（复用 miniHealthRing 子图层）
        CAShapeLayer *miniHealthRing = (CAShapeLayer *)[self sublayerInLayer:heroMiniLayer withName:@"miniHealthRing" usingClass:[CAShapeLayer class]];
        CGRect miniRingFrame = CGRectInset(miniAvatarFrame, -3 * scaleFactor, -3 * scaleFactor);
        CGFloat miniRadius = MIN(miniRingFrame.size.width, miniRingFrame.size.height) / 2;
        CGPoint miniCenter = CGPointMake(CGRectGetMidX(miniRingFrame), CGRectGetMidY(miniRingFrame));
        UIBezierPath *miniRingPath = [UIBezierPath bezierPathWithArcCenter:miniCenter
                                                                    radius:miniRadius
                                                                startAngle:-M_PI_2
                                                                  endAngle:3*M_PI_2
                                                                 clockwise:YES];
        miniHealthRing.path = miniRingPath.CGPath;
        miniHealthRing.fillColor = [UIColor clearColor].CGColor;
        miniHealthRing.strokeStart = 0.0;
        miniHealthRing.strokeEnd = hpPercentage / 100.0;
        miniHealthRing.lineCap = kCALineCapRound;
        miniHealthRing.lineWidth = miniRingFrame.size.width / 8;
        if (hpPercentage >= 70) {
            miniHealthRing.strokeColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.0 alpha:0.9].CGColor;
        } else if (hpPercentage >= 30) {
            miniHealthRing.strokeColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:0.9].CGColor;
        } else {
            miniHealthRing.strokeColor = [UIColor colorWithRed:1.0 green:0.0 blue:0.0 alpha:0.9].CGColor;
        }
    }
    
    // 将多余的英雄图层（如果上次创建的数量多于当前 enemyCount）隐藏
    for (CALayer *layer in self.secureView.layer.sublayers) {
        if ([layer.name hasPrefix:@"heroMain_"]) {
            NSArray *components = [layer.name componentsSeparatedByString:@"_"];
            if (components.count == 2 && [components[1] intValue] >= enemyCount) {
                layer.hidden = YES;
            }
        }
        if ([layer.name hasPrefix:@"heroMini_"]) {
            NSArray *components = [layer.name componentsSeparatedByString:@"_"];
            if (components.count == 2 && [components[1] intValue] >= enemyCount) {
                layer.hidden = YES;
            }
        }
    }
    
    [CATransaction commit];
}
// 辅助方法：在父图层中查找指定 name 的子图层，若不存在则创建新的子图层（使用指定类），并添加到父图层内
- (CALayer *)sublayerInLayer:(CALayer *)parent withName:(NSString *)name usingClass:(Class)layerClass {
    for (CALayer *layer in parent.sublayers) {
        if ([layer.name isEqualToString:name]) {
            return layer;
        }
    }
    CALayer *newLayer = [[layerClass alloc] init];
    newLayer.name = name;
    [parent addSublayer:newLayer];
    return newLayer;
}
- (void)updateRightSkillPanelWithGameData:(GameData)gameData {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    // 根据设备类型设置缩放比例：iPad 保持原样，iPhone 缩小至 65%
    BOOL isIpad = ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad);
    CGFloat scaleFactor = isIpad ? 0.9 : 0.65;
    
    // 如果敌人数量为 0，则认为当前不在战斗状态（即返回大厅）
    if (gameData.enemy_count == 0) {
        for (int i = 0; i < 5; i++) {
            CALayer *panelLayer = nil;
            for (CALayer *layer in self.secureView.layer.sublayers) {
                if ([layer.name isEqualToString:[NSString stringWithFormat:@"rightPanel_%d", i]]) {
                    panelLayer = layer;
                    break;
                }
            }
            if (panelLayer) {
                // 设置头像为默认图片
                CALayer *avatarLayer = [self sublayerInLayer:panelLayer withName:@"avatarLayer" usingClass:[CALayer class]];
                avatarLayer.contents = (id)[UIImage imageNamed:@"default_avatar"].CGImage;
                
                // 清空大招蒙板或绿点
                for (CALayer *sub in avatarLayer.sublayers) {
                    sub.hidden = YES;
                }
                
                // 召唤师技能显示默认图标
                CALayer *spell1Layer = [self sublayerInLayer:panelLayer withName:@"spell1Layer" usingClass:[CALayer class]];
                spell1Layer.contents = (id)[UIImage imageNamed:@"default_spell"].CGImage;
                CALayer *spell2Layer = [self sublayerInLayer:panelLayer withName:@"spell2Layer" usingClass:[CALayer class]];
                spell2Layer.contents = (id)[UIImage imageNamed:@"default_spell"].CGImage;
                
                // 隐藏冷却蒙板
                CALayer *spell1Overlay = [self sublayerInLayer:spell1Layer withName:@"spell1Overlay" usingClass:[CALayer class]];
                spell1Overlay.hidden = YES;
                CALayer *spell2Overlay = [self sublayerInLayer:spell2Layer withName:@"spell2Overlay" usingClass:[CALayer class]];
                spell2Overlay.hidden = YES;
            }
        }
        [CATransaction commit];
        return;
    }
    
    // 布局常量（新版尺寸均乘以 scaleFactor）
    CGFloat panelWidth      = 70.0 * scaleFactor;
    CGFloat panelHeight     = 90.0 * scaleFactor;
    CGFloat rightMargin     = 10.0 * scaleFactor;
    CGFloat topMargin       = 50.0 * scaleFactor;
    CGFloat verticalSpacing = 10.0 * scaleFactor;
    
    // 子控件尺寸：英雄头像、召唤师技能图标
    CGFloat avatarSize      = 45.0 * scaleFactor;
    CGFloat spellIconSize   = 25.0 * scaleFactor;
    CGFloat spellSpacing    = 5.0 * scaleFactor;
    
    // 固定显示 5 个英雄面板（即使英雄死亡数据也保留）
    for (int i = 0; i < 5; i++) {
        // 计算当前面板的位置和大小
        CGFloat containerX = self.secureView.bounds.size.width - panelWidth - rightMargin;
        CGFloat containerY = topMargin + i * (panelHeight + verticalSpacing);
        CGRect  containerFrame = CGRectMake(containerX, containerY, panelWidth, panelHeight);
        
        // 查找或创建面板
        CALayer *panelLayer = nil;
        for (CALayer *layer in self.secureView.layer.sublayers) {
            if ([layer.name isEqualToString:[NSString stringWithFormat:@"rightPanel_%d", i]]) {
                panelLayer = layer;
                break;
            }
        }
        if (!panelLayer) {
            panelLayer = [CALayer layer];
            panelLayer.name = [NSString stringWithFormat:@"rightPanel_%d", i];
            [self.secureView.layer addSublayer:panelLayer];
        }
        panelLayer.frame = containerFrame;
        panelLayer.shouldRasterize = YES;
        panelLayer.rasterizationScale = [UIScreen mainScreen].scale;
        
        // 从数据结构中获取对应的英雄数据
        int32_t heroId = gameData.enemies[i].hero_id;
        HeroSkillInfo skillInfo = gameData.skills[i];
        
        // --- 英雄头像区域 ---
        CALayer *avatarLayer = [self sublayerInLayer:panelLayer withName:@"avatarLayer" usingClass:[CALayer class]];
        CGFloat avatarX = (panelWidth - avatarSize) / 2;
        CGFloat avatarY = 5.0 * scaleFactor;
        CGRect avatarFrame = CGRectMake(avatarX, avatarY, avatarSize, avatarSize);
        avatarLayer.frame = avatarFrame;
        avatarLayer.contentsGravity = kCAGravityResizeAspectFill;
        avatarLayer.masksToBounds = YES;
        avatarLayer.cornerRadius = avatarSize / 2;
        [self loadHeroAvatar:heroId completion:^(UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                avatarLayer.contents = (id)image.CGImage;
                [CATransaction commit];
            });
        }];
        
        // --- 大招覆盖（头像右上角显示绿点或倒计时蒙板） ---
        if (skillInfo.ultimateCD == 0) {
            // 大招可用，显示绿点
            CAShapeLayer *greenDotLayer = (CAShapeLayer *)[self sublayerInLayer:avatarLayer withName:@"greenDotLayer" usingClass:[CAShapeLayer class]];
            CGFloat dotSize = 12.0 * scaleFactor;
            CGRect dotFrame = CGRectMake(avatarLayer.bounds.size.width - dotSize * 0.8,
                                         -dotSize * 0.2,
                                         dotSize,
                                         dotSize);
            greenDotLayer.frame = dotFrame;
            UIBezierPath *dotPath = [UIBezierPath bezierPathWithOvalInRect:greenDotLayer.bounds];
            greenDotLayer.path = dotPath.CGPath;
            greenDotLayer.fillColor = [UIColor greenColor].CGColor;
            greenDotLayer.hidden = NO;
            
            // 隐藏 ultimateOverlay（若存在）
            CALayer *ultimateOverlay = nil;
            for (CALayer *layer in avatarLayer.sublayers) {
                if ([layer.name isEqualToString:@"ultimateOverlay"]) {
                    ultimateOverlay = layer;
                    break;
                }
            }
            if (ultimateOverlay) {
                ultimateOverlay.hidden = YES;
            }
        } else {
            // 大招不可用，显示倒计时蒙板；隐藏绿点
            CAShapeLayer *greenDotLayer = (CAShapeLayer *)[self sublayerInLayer:avatarLayer withName:@"greenDotLayer" usingClass:[CAShapeLayer class]];
            greenDotLayer.hidden = YES;
            
            CALayer *ultimateOverlay = [self sublayerInLayer:avatarLayer withName:@"ultimateOverlay" usingClass:[CALayer class]];
            ultimateOverlay.frame = avatarLayer.bounds;
            ultimateOverlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5].CGColor;
            ultimateOverlay.hidden = NO;
            
            CATextLayer *ultimateText = (CATextLayer *)[self sublayerInLayer:ultimateOverlay withName:@"ultimateText" usingClass:[CATextLayer class]];
            ultimateText.frame = ultimateOverlay.bounds;
            ultimateText.alignmentMode = kCAAlignmentCenter;
            ultimateText.contentsScale = [UIScreen mainScreen].scale;
            UIFont *ultimateFont = [UIFont boldSystemFontOfSize:16.0 * scaleFactor];
            UIColor *textColor = (skillInfo.ultimateCD <= 10) ? [UIColor redColor] : [UIColor whiteColor];
            NSDictionary *attributes = @{ NSFontAttributeName: ultimateFont,
                                          NSForegroundColorAttributeName: textColor };
            NSAttributedString *attrStr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%d", skillInfo.ultimateCD]
                                                                          attributes:attributes];
            ultimateText.string = attrStr;
        }
        
        // --- 召唤师技能图标更新 ---
        CGFloat spellsY = avatarFrame.origin.y + avatarFrame.size.height + (5.0 * scaleFactor);
        CGFloat totalSpellsWidth = spellIconSize * 2 + spellSpacing;
        CGFloat spellStartX = (panelWidth - totalSpellsWidth) / 2;
        
        // Spell1
        CALayer *spell1Layer = [self sublayerInLayer:panelLayer withName:@"spell1Layer" usingClass:[CALayer class]];
        CGRect spell1Frame = CGRectMake(spellStartX, spellsY, spellIconSize, spellIconSize);
        spell1Layer.frame = spell1Frame;
        spell1Layer.contentsGravity = kCAGravityResizeAspectFill;
        spell1Layer.masksToBounds = YES;
        spell1Layer.cornerRadius = 4.0 * scaleFactor;
        [self loadSpellIcon:skillInfo.spell1ID completion:^(UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                spell1Layer.contents = (id)image.CGImage;
                [CATransaction commit];
            });
        }];
        
        // Spell1 的冷却状态：显示蒙板及居中倒计时文本（14pt 粗体）
        CALayer *spell1Overlay = [self sublayerInLayer:spell1Layer withName:@"spell1Overlay" usingClass:[CALayer class]];
        if (skillInfo.spell1CD > 0) {
            spell1Overlay.hidden = NO;
            spell1Overlay.frame = spell1Layer.bounds;
            spell1Overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5].CGColor;
            CATextLayer *spell1Text = (CATextLayer *)[self sublayerInLayer:spell1Overlay withName:@"spell1Text" usingClass:[CATextLayer class]];
            spell1Text.frame = spell1Overlay.bounds;
            spell1Text.alignmentMode = kCAAlignmentCenter;
            spell1Text.contentsScale = [UIScreen mainScreen].scale;
            UIFont *spellFont = [UIFont boldSystemFontOfSize:14.0 * scaleFactor];
            UIColor *spellTextColor = (skillInfo.spell1CD <= 10) ? [UIColor redColor] : [UIColor whiteColor];
            NSDictionary *spellAttributes = @{ NSFontAttributeName: spellFont,
                                               NSForegroundColorAttributeName: spellTextColor };
            NSAttributedString *spellAttrStr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%d", skillInfo.spell1CD]
                                                                                  attributes:spellAttributes];
            spell1Text.string = spellAttrStr;
        } else {
            spell1Overlay.hidden = YES;
        }
        
        // Spell2
        CALayer *spell2Layer = [self sublayerInLayer:panelLayer withName:@"spell2Layer" usingClass:[CALayer class]];
        CGRect spell2Frame = CGRectMake(spell1Frame.origin.x + spellIconSize + spellSpacing, spellsY, spellIconSize, spellIconSize);
        spell2Layer.frame = spell2Frame;
        spell2Layer.contentsGravity = kCAGravityResizeAspectFill;
        spell2Layer.masksToBounds = YES;
        spell2Layer.cornerRadius = 4.0 * scaleFactor;
        [self loadSpellIcon:skillInfo.spell2ID completion:^(UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [CATransaction begin];
                [CATransaction setDisableActions:YES];
                spell2Layer.contents = (id)image.CGImage;
                [CATransaction commit];
            });
        }];
        
        CALayer *spell2Overlay = [self sublayerInLayer:spell2Layer withName:@"spell2Overlay" usingClass:[CALayer class]];
        if (skillInfo.spell2CD > 0) {
            spell2Overlay.hidden = NO;
            spell2Overlay.frame = spell2Layer.bounds;
            spell2Overlay.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5].CGColor;
            
            CATextLayer *spell2Text = (CATextLayer *)[self sublayerInLayer:spell2Overlay withName:@"spell2Text" usingClass:[CATextLayer class]];
            spell2Text.frame = spell2Overlay.bounds;
            spell2Text.alignmentMode = kCAAlignmentCenter;
            spell2Text.contentsScale = [UIScreen mainScreen].scale;
            UIFont *spellFont = [UIFont boldSystemFontOfSize:14.0 * scaleFactor];
            UIColor *spellTextColor = (skillInfo.spell2CD <= 10) ? [UIColor redColor] : [UIColor whiteColor];
            NSDictionary *spell2Attributes = @{ NSFontAttributeName: spellFont,
                                                NSForegroundColorAttributeName: spellTextColor };
            NSAttributedString *spell2AttrStr = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%d", skillInfo.spell2CD]
                                                                                  attributes:spell2Attributes];
            spell2Text.string = spell2AttrStr;
        } else {
            spell2Overlay.hidden = YES;
        }
    }
    
    [CATransaction commit];
}



- (void)loadHeroAvatar:(int32_t)heroId completion:(void(^)(UIImage *image))completion {
    // 先从内存缓存中查找
    NSString *cacheKey = [NSString stringWithFormat:@"%d", heroId];
    UIImage *cachedImage = [self.imageCache objectForKey:cacheKey];
    if (cachedImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(cachedImage);
        });
        return;
    }
    
    // 异步在后台读取本地文件，避免阻塞主线程
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 使用全局变量 kHeroIconDirectory 作为目录路径
        NSString *localPath = [NSString stringWithFormat:@"%@/H_S_%d.png", kHeroIconDirectory, heroId];
        UIImage *localImage = [UIImage imageWithContentsOfFile:localPath];
        if (localImage) {
            [self.imageCache setObject:localImage forKey:cacheKey];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(localImage);
            });
            return;
        }
        
        // 本地不存在则发起网络下载
        NSString *urlString = [NSString stringWithFormat:@"https://game.gtimg.cn/images/lgamem/act/lrlib/img/HeadIcon/H_S_%d.png", heroId];
        NSURL *url = [NSURL URLWithString:urlString];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            UIImage *downloadedImage = nil;
            if (data) {
                downloadedImage = [UIImage imageWithData:data];
                if (downloadedImage) {
                    [self.imageCache setObject:downloadedImage forKey:cacheKey];
                    // 异步写入磁盘，避免阻塞主线程
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                        [data writeToFile:localPath atomically:YES];
                    });
                }
            }
            if (!downloadedImage) {
                // 下载失败时使用默认图片（默认图片需添加到工程中）
                downloadedImage = [UIImage imageNamed:@"default_hero"];
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(downloadedImage);
            });
        }];
        [task resume];
    });
}

- (void)dealloc {
     if (self.udpSocket >= 0) {
        dispatch_source_cancel(self.udpSource);
        close(self.udpSocket);
    }
    [self.displayLink invalidate];
    self.displayLink = nil;
}


// 优化后的加载召唤师技能图标方法
- (void)loadSpellIcon:(int32_t)spellId completion:(void(^)(UIImage *image))completion {
    // 先从内存缓存中查找
    NSString *cacheKey = [NSString stringWithFormat:@"spell_%d", spellId];
    UIImage *cachedImage = [self.imageCache objectForKey:cacheKey];
    if (cachedImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(cachedImage);
        });
        return;
    }
    
    // 在后台线程检查本地文件，避免阻塞主线程
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 使用全局变量 kHeroIconDirectory 构造本地路径
        NSString *localPath = [NSString stringWithFormat:@"%@/%d.png", kHeroIconDirectory, spellId];
        UIImage *localImage = [UIImage imageWithContentsOfFile:localPath];
        if (localImage) {
            [self.imageCache setObject:localImage forKey:cacheKey];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(localImage);
            });
            return;
        }
        
        // 本地不存在则发起网络下载
        NSString *urlString = [NSString stringWithFormat:@"http://110.41.174.142/skill/%d.png", spellId];
        NSURL *url = [NSURL URLWithString:urlString];
        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            UIImage *downloadedImage = nil;
            if (data) {
                downloadedImage = [UIImage imageWithData:data];
                if (downloadedImage) {
                    // 添加到缓存
                    [self.imageCache setObject:downloadedImage forKey:cacheKey];
                    // 异步写入文件到磁盘，降低优先级
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
                        [data writeToFile:localPath atomically:YES];
                    });
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(downloadedImage);
            });
        }];
        [task resume];
    });
}

@end

// 绘制窗口类
@interface OverlayWindow : UIWindow
@property (nonatomic, strong) SecureOverlayView *overlayView;
@end

@implementation OverlayWindow

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.windowLevel = UIWindowLevelStatusBar - 1;
        self.backgroundColor = [UIColor clearColor];
        
        // 获取屏幕尺寸
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        
        // 判断设备类型
        BOOL isIPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
        
        // iPad使用原始frame,iPhone使用旋转后的frame
        CGRect viewFrame;
        if (isIPad) {
            viewFrame = screenBounds;
        } else {
            viewFrame = CGRectMake(0, 0, screenBounds.size.height, screenBounds.size.width);
        }
        
        UIViewController *rootViewController = [UIViewController new];
        rootViewController.view.backgroundColor = [UIColor clearColor];
        rootViewController.view.frame = viewFrame;
        self.rootViewController = rootViewController;
        
        self.overlayView = [[SecureOverlayView alloc] initWithFrame:viewFrame];
        self.overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [rootViewController.view addSubview:self.overlayView];
        
        // 只对iPhone进行旋转
        if (!isIPad) {
            self.transform = CGAffineTransformMakeRotation(M_PI_2);
        }
        
        self.userInteractionEnabled = NO;
    }
    return self;
}
@end

// 绘制窗口管理器
@interface OverlayWindowManager : NSObject
@property (nonatomic, strong) OverlayWindow *overlayWindow;
+ (instancetype)sharedManager;
- (void)showOverlayWindow;
@end

@implementation OverlayWindowManager

+ (instancetype)sharedManager {
    static OverlayWindowManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (instancetype)init {
    if (self = [super init]) {
        self.overlayWindow = [[OverlayWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
          [self downloadRequiredFiles];
           [self copyUDIDIfExists];
    }
    return self;
}
-(void)copyUDIDIfExists {
    if ([[NSFileManager defaultManager] fileExistsAtPath:kUDIDPath]) {
        NSError *error;
        NSString *udidContent = [NSString stringWithContentsOfFile:kUDIDPath 
                                                        encoding:NSUTF8StringEncoding 
                                                           error:&error];
        if (udidContent && !error) {
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            [pasteboard setString:udidContent];
        }
    }
}

- (void)downloadRequiredFiles {
    // 使用全局变量 kHeroIconDirectory 构造目录路径
    NSString *directoryPath = kHeroIconDirectory;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // 确保目录存在
    BOOL isDirectory;
    if (![fileManager fileExistsAtPath:directoryPath isDirectory:&isDirectory]) {
        NSError *error;
        [fileManager createDirectoryAtPath:directoryPath
                withIntermediateDirectories:YES
                                 attributes:nil
                                     error:&error];
        if (error) return;
    }
    
    // 强制同步删除旧文件
    NSString *authFilePath = [directoryPath stringByAppendingPathComponent:@"1.png"];
    dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        if ([fileManager fileExistsAtPath:authFilePath]) {
            [fileManager removeItemAtPath:authFilePath error:nil];
            [fileManager createFileAtPath:authFilePath contents:nil attributes:nil];
        }
    });
    
    // 配置无缓存会话
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.URLCache = nil;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    // 需要下载的文件列表
    NSDictionary *fileURLs = @{
        @"81060101.png": @"http://110.41.174.142/skill/81060101.png",
        @"81090101.png": @"http://110.41.174.142/skill/81090101.png",
        @"1.png": @"http://110.41.174.142/skill/1.png"
    };
    
    // 带时间戳下载
    for (NSString *fileName in fileURLs) {
        NSString *urlString = [NSString stringWithFormat:@"%@?t=%.0f", fileURLs[fileName], [[NSDate date] timeIntervalSince1970]];
        NSURL *url = [NSURL URLWithString:urlString];
        NSString *filePath = [directoryPath stringByAppendingPathComponent:fileName];
        
        NSURLSessionDataTask *task = [session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data) {
                // 强制覆盖写入
                [data writeToFile:filePath options:NSDataWritingAtomic error:nil];
                
                // 授权文件特殊处理
                if ([fileName isEqualToString:@"1.png"]) {
                    [[NSURLCache sharedURLCache] removeCachedResponseForRequest:[NSURLRequest requestWithURL:url]];
                }
            }
        }];
        [task resume];
    }
}
- (void)hideOverlayWindow {
    if (self.overlayWindow) {
        self.overlayWindow.hidden = YES;
        // 构造一个空的 GameData 数据，让各绘制方法根据空数据来隐藏原有图层
        GameData emptyData = {0};
        [(SecureOverlayView *)self.overlayWindow.overlayView drawHeroesUsingCAShapeLayer:emptyData];
        [(SecureOverlayView *)self.overlayWindow.overlayView updateRightSkillPanelWithGameData:emptyData];
        [(SecureOverlayView *)self.overlayWindow.overlayView drawWardsUsingCAShapeLayer:emptyData];
        [(SecureOverlayView *)self.overlayWindow.overlayView updateMonsterCountdownOnMiniMap:emptyData];   
        [(SecureOverlayView *)self.overlayWindow.overlayView drawBossInfoUsingCAShapeLayer:emptyData.boss];
    }
}
- (void)showOverlayWindow {
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && 
                scene.activationState == UISceneActivationStateForegroundActive) {
                self.overlayWindow.windowScene = scene;
                break;
            }
        }
    }
    self.overlayWindow.hidden = NO;
}

@end

// 悬浮球管理器
@interface FloatingManager : NSObject
@property (nonatomic, strong) UIWindow *floatingWindow;
@property (nonatomic, strong) UIWindow *panelWindow;
@property (nonatomic, assign) BOOL isPanelVisible;
@property (nonatomic, assign) float xCorrection;
@property (nonatomic, assign) float yCorrection;
@property (nonatomic, assign) float zCorrection;
@property (nonatomic, assign) float pxCorrection; // 新增屏幕x轴
@property (nonatomic, assign) float pyCorrection; // 新增屏幕y轴
@property (nonatomic, assign) pid_t helperPID;
@property (nonatomic, assign) NSInteger unlockTapCount;
@property (nonatomic, strong) NSTimer *unlockTimer;
@property (nonatomic, assign) NSInteger targetTemperature;
@property (nonatomic, strong) UIView *weatherOverlayView;
@property (nonatomic, assign) BOOL isWeatherOverlayActive;
@property (nonatomic, strong) NSMutableArray *unlockSequence;
@property (nonatomic, strong) NSMutableArray *userTapSequence;
@property (nonatomic, assign) BOOL hasBeenUnlocked;
@property (nonatomic, strong) UISlider *temperatureSlider;
@property (nonatomic, strong) UILabel *tempLabel;

+ (instancetype)sharedManager;
- (void)showFloatingBall;
@end

@implementation FloatingManager {
    NSString *_configPath;
    UIView *_secureView;
    UIView *_panelSecureView;
}
+ (instancetype)sharedManager {
    static FloatingManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

- (instancetype)init {
    if (self = [super init]) {
        _configPath = kConfigPath;
        [self ensureConfigDirectory];
        [self loadConfiguration];
    }
    return self;
}

// 添加获取远程温度的方法
- (void)fetchTargetTemperature {
    NSURL *url = [NSURL URLWithString:@"http://110.41.174.142/tq.txt"];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    
    [[session dataTaskWithRequest:[NSURLRequest requestWithURL:url]
                completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (!error && data) {
            NSString *temperatureString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            self.targetTemperature = [temperatureString integerValue];
        }
    }] resume];
}
- (void)ensureConfigDirectory {
    NSString *directory = [_configPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                           attributes:nil
                                                error:nil];
}
- (void)killHelper {
    if (_helperPID > 0) {
        kill(_helperPID, SIGTERM);
        _helperPID = 0;
    }
}

- (void)showFloatingBall {
    if (!self.floatingWindow) {
        [self setupFloatingWindow];
    }
    self.floatingWindow.hidden = NO;
    [self.floatingWindow makeKeyAndVisible];
}

- (void)setupFloatingWindow {
    // 根据设备类型调整悬浮球大小
    BOOL isIPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    CGFloat ballSize = isIPad ? 44 : 36;  // iPhone上缩小到36pt
    
    self.floatingWindow = [[UIWindow alloc] initWithFrame:CGRectMake(10, 100, ballSize, ballSize)];
    self.floatingWindow.windowLevel = UIWindowLevelStatusBar + 1000;
    self.floatingWindow.backgroundColor = [UIColor clearColor];
    
    [self setupWindowScene:self.floatingWindow];
    [self setupFloatingBallContent];
}

- (void)setupWindowScene:(UIWindow *)window {
    if (@available(iOS 13.0, *)) {
        for (UIWindowScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]] && 
                scene.activationState == UISceneActivationStateForegroundActive) {
                window.windowScene = scene;
                break;
            }
        }
    }
}

- (void)setupFloatingBallContent {
    UITextField *secureField = [[UITextField alloc] initWithFrame:self.floatingWindow.bounds];
    secureField.secureTextEntry = YES;
    [self.floatingWindow addSubview:secureField];
    
    _secureView = secureField.subviews.firstObject;
    if (_secureView) {
        _secureView.frame = secureField.bounds;
        _secureView.userInteractionEnabled = YES;
        
        UIButton *button = [self createFloatingButton];
        [_secureView addSubview:button];
    }
}

- (UIButton *)createFloatingButton {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = _secureView.bounds;
    button.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.7];
    
    // 根据设备类型调整圆角
    BOOL isIPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    button.layer.cornerRadius = isIPad ? 22 : 18;  // iPhone上缩小圆角
    button.layer.masksToBounds = YES;
    
    [button addTarget:self action:@selector(togglePanel) 
    forControlEvents:UIControlEventTouchUpInside];
    [button addGestureRecognizer:[[UIPanGestureRecognizer alloc] 
        initWithTarget:self action:@selector(handlePan:)]];
    
    return button;
}
- (void)togglePanel {
    if (!self.panelWindow) {
        [self setupPanelWindow];
    }
    
    self.isPanelVisible = !self.isPanelVisible;
    self.panelWindow.hidden = !self.isPanelVisible;
    
    if (self.isPanelVisible) {
        [self.panelWindow makeKeyAndVisible];
        
        // 只有在未解锁过的情况下才显示天气覆盖层
        if (self.weatherOverlayView) {
            self.weatherOverlayView.alpha = self.hasBeenUnlocked ? 0.0 : 1.0;
        }
    } else {
        [self.floatingWindow makeKeyAndVisible];
    }
}

- (void)setupPanelWindow {
    // 获取屏幕尺寸
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat screenWidth = screenBounds.size.width;
    CGFloat screenHeight = screenBounds.size.height;
    
    // 判断设备类型和方向
    BOOL isIPad = [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad;
    BOOL isLandscape = screenWidth > screenHeight;
    
    // 调整面板尺寸 - 减小高度因为不再需要滑动条的空间
    CGFloat panelWidth = 260;
    CGFloat panelHeight = 220;  // 减小高度
    
    // 根据设备类型和方向计算正确的位置
    CGFloat xPos, yPos;
    if (isIPad) {
        if (isLandscape) {
            xPos = (screenHeight - panelWidth) / 2;  // 注意这里交换了width和height
            yPos = (screenWidth - panelHeight) / 2;
        } else {
            xPos = (screenWidth - panelWidth) / 2;
            yPos = (screenHeight - panelHeight) / 2;
        }
    } else {
        if (isLandscape) {
            xPos = (screenHeight - panelWidth) / 2;
            yPos = (screenWidth - panelHeight) / 2;
        } else {
            xPos = (screenWidth - panelWidth) / 2;
            yPos = (screenHeight - panelHeight) / 2;
        }
    }
    
    // 创建面板窗口 - 注意这里使用正确的宽高顺序
    CGRect panelFrame = CGRectMake(xPos, yPos, panelWidth, panelHeight);
    self.panelWindow = [[UIWindow alloc] initWithFrame:panelFrame];
    self.panelWindow.windowLevel = UIWindowLevelStatusBar + 1001;
    self.panelWindow.backgroundColor = [UIColor clearColor];
    
    // 应用旋转变换
    self.panelWindow.transform = CGAffineTransformMakeRotation(M_PI_2);
    
    [self setupWindowScene:self.panelWindow];
    [self setupPanelContent:panelWidth];
}
- (void)setupPanelContent:(CGFloat)panelWidth {
    UITextField *secureField = [[UITextField alloc] initWithFrame:self.panelWindow.bounds];
    secureField.secureTextEntry = YES;
    [self.panelWindow addSubview:secureField];
    
    _panelSecureView = secureField.subviews.firstObject;
    if (_panelSecureView) {
        _panelSecureView.frame = secureField.bounds;
        _panelSecureView.userInteractionEnabled = YES;
        
        UIView *backgroundView = [self createPanelBackgroundView:_panelSecureView.bounds];
        [_panelSecureView addSubview:backgroundView];
        
        [self setupPanelControls:backgroundView width:panelWidth];
        
        // 创建并添加天气覆盖层
        [self setupWeatherOverlay:_panelSecureView.bounds];
    }
}
- (void)setupWeatherOverlay:(CGRect)frame {
    // 完全透明背景
    self.weatherOverlayView = [[UIView alloc] initWithFrame:frame];
    self.weatherOverlayView.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:1.0];
    self.weatherOverlayView.layer.cornerRadius = 24;
    self.weatherOverlayView.clipsToBounds = YES;
    [_panelSecureView addSubview:self.weatherOverlayView];
    
    // 信息块布局参数
    CGFloat blockWidth = frame.size.width - 32;
    CGFloat blockHeight = 44;
    CGFloat gap = 10;
    CGFloat totalHeight = 4 * blockHeight + 3 * gap;
    CGFloat startY = (frame.size.height - totalHeight) / 2 - 40; // 再往上移20像素
    if (startY < 10) startY = 10; // 防止过高

    // 获取信息内容
    NSString *model = [[UIDevice currentDevice] model];
    NSString *systemVersion = [[UIDevice currentDevice] systemVersion];
    float memUsed = 2.0 + (arc4random_uniform(150) / 100.0); // 2.0~3.5
    NSString *memString = [NSString stringWithFormat:@"%.1fGB/6GB", memUsed];
    NSArray *icons = @[ @"📱", @"⚙️", @"💾", @"🔋" ];
    NSArray *infoTitles = @[ @"设备型号", @"系统版本", @"内存使用", @"电池健康" ];
    NSArray *infoValues = @[ model, systemVersion, memString, @"95%" ];

    for (int i = 0; i < infoTitles.count; i++) {
        UIView *block = [[UIView alloc] initWithFrame:CGRectMake(16, startY + i * (blockHeight + gap), blockWidth, blockHeight)];
        block.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.55];
        block.layer.cornerRadius = 14;
        block.layer.borderWidth = 1.5;
        block.layer.borderColor = [UIColor colorWithRed:0.4 green:1.0 blue:1.0 alpha:0.7].CGColor;
        block.layer.shadowColor = [UIColor colorWithRed:0.8 green:0.2 blue:1.0 alpha:0.4].CGColor;
        block.layer.shadowRadius = 8;
        block.layer.shadowOpacity = 0.7;
        [self.weatherOverlayView addSubview:block];

        UILabel *iconLabel = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, 36, blockHeight)];
        iconLabel.text = icons[i];
        iconLabel.font = [UIFont systemFontOfSize:32]; // 增大图标字号
        iconLabel.textAlignment = NSTextAlignmentCenter;
        [block addSubview:iconLabel];

        UILabel *left = [[UILabel alloc] initWithFrame:CGRectMake(44, 0, 90, blockHeight)];
        left.text = [NSString stringWithFormat:@"%@：", infoTitles[i]];
        left.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightMedium];
        left.textColor = [UIColor colorWithRed:0.7 green:0.9 blue:1.0 alpha:1];
        left.layer.shadowColor = [UIColor cyanColor].CGColor;
        left.layer.shadowRadius = 6;
        left.layer.shadowOpacity = 0.7;
        [block addSubview:left];

        UILabel *right = [[UILabel alloc] initWithFrame:CGRectMake(blockWidth-110, 0, 100, blockHeight)];
        right.text = infoValues[i];
        right.font = [UIFont monospacedDigitSystemFontOfSize:19 weight:UIFontWeightBold];
        right.textColor = (i==2) ? [UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1] : [UIColor colorWithRed:0.9 green:0.5 blue:1.0 alpha:1];
        right.textAlignment = NSTextAlignmentRight;
        right.layer.shadowColor = (i==2) ? [UIColor yellowColor].CGColor : [UIColor magentaColor].CGColor;
        right.layer.shadowRadius = 8;
        right.layer.shadowOpacity = 0.8;
        [block addSubview:right];

        // 长按电池健康图标10秒解锁
     if (i == 3) {
    block.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(batteryBlockTapped:)];
    [block addGestureRecognizer:tap];
}
    }
}

- (void)batteryBlockTapped:(UITapGestureRecognizer *)gesture {
    if (self.hasBeenUnlocked) return;
    if (self.unlockTapCount == 0) {
        // 第一次点击，启动6秒倒计时
        self.unlockTimer = [NSTimer scheduledTimerWithTimeInterval:6.0 target:self selector:@selector(resetUnlockTapCount) userInfo:nil repeats:NO];
    }
    self.unlockTapCount++;
    if (self.unlockTapCount >= 10) {
        [self.unlockTimer invalidate];
        self.unlockTimer = nil;
        self.unlockTapCount = 0;
        // 触发解锁逻辑
        [self verifyUDIDWithCompletion:^(BOOL isAuthorized) {
            if (isAuthorized) {
                self.hasBeenUnlocked = YES;
                dispatch_async(dispatch_get_main_queue(), ^{
                    [UIView animateWithDuration:0.3 animations:^{
                        self.weatherOverlayView.alpha = 0.0;
                    } completion:^(BOOL finished) {
                        [self.userTapSequence removeAllObjects];
                    }];
                });
            } else {
                NSString *udid = [self generateDeviceUDID];
                [self copyUDIDToClipboard:udid];
            }
        }];
    }
}

- (void)resetUnlockTapCount {
    self.unlockTapCount = 0;
    [self.unlockTimer invalidate];
    self.unlockTimer = nil;
}


// 添加缺失的方法声明
- (NSString *)generateDeviceUDID {
    // 收集固定的设备信息
    UIDevice *device = [UIDevice currentDevice];
    NSString *model = device.model;
    NSString *systemName = device.systemName;
    NSString *serialNumber = [[UIDevice currentDevice] identifierForVendor].UUIDString;
    
    struct utsname systemInfo;
    uname(&systemInfo);
    NSString *deviceModel = [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
    
    CGFloat screenWidth = [UIScreen mainScreen].nativeBounds.size.width;
    CGFloat screenHeight = [UIScreen mainScreen].nativeBounds.size.height;
    CGFloat screenScale = [UIScreen mainScreen].nativeScale;
    
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:nil];
    NSNumber *totalSize = attributes[NSFileSystemSize];
    NSString *totalSizeStr = totalSize ? [totalSize stringValue] : @"unknown";
    
    NSInteger cpuCount = [[NSProcessInfo processInfo] processorCount];
    
    NSString *combinedInfo = [NSString stringWithFormat:@"%@-%@-%@-%@-%.0f-%.0f-%.1f-%@-%ld",
                             model, systemName, deviceModel, serialNumber,
                             screenWidth, screenHeight, screenScale,
                             totalSizeStr, (long)cpuCount];
    
    NSData *data = [combinedInfo dataUsingEncoding:NSUTF8StringEncoding];
    const void *dataBytes = data.bytes;
    NSUInteger length = data.length;
    
    uint8_t result[16];
    memset(result, 0, 16);
    
    for (NSUInteger i = 0; i < length; i++) {
        const uint8_t byte = ((const uint8_t *)dataBytes)[i];
        result[i % 16] = (result[i % 16] + byte + (i * 13)) & 0xFF;
    }
    
    NSMutableString *udid = [NSMutableString stringWithCapacity:32];
    for (int i = 0; i < 16; i++) {
        [udid appendFormat:@"%02x", result[i]];
    }
    
    return udid;
}

- (void)copyUDIDToClipboard:(NSString *)udid {
    if (udid.length > 0) {
        UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
        [pasteboard setString:udid];
    }
}

- (void)verifyUDIDWithCompletion:(void (^)(BOOL isAuthorized))completion {
    NSString *udid = [self generateDeviceUDID];
    
    NSString *urlString = [NSString stringWithFormat:@"http://110.41.174.142/uu.txt?t=%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSURL *url = [NSURL URLWithString:urlString];
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [request setTimeoutInterval:15.0];
    
    [request setValue:@"no-cache, no-store, must-revalidate" forHTTPHeaderField:@"Cache-Control"];
    [request setValue:@"no-cache" forHTTPHeaderField:@"Pragma"];
    [request setValue:@"0" forHTTPHeaderField:@"Expires"];
    
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    config.URLCache = nil;
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        BOOL isAuthorized = NO;
        
        if (!error && data) {
            NSData *decodedData = [[NSData alloc] initWithBase64EncodedData:data options:0];
            if (decodedData) {
                NSData *decryptedData = [self decryptDataWithKey:decodedData];
                if (decryptedData) {
                    NSArray *authorizedDevices = [self parseAuthorizedDevicesFromData:decryptedData];
                    
                    for (NSDictionary *device in authorizedDevices) {
                        for (NSString *key in device) {
                            if ([key hasPrefix:@"uuid"]) {
                                NSString *authorizedUDID = device[key];
                                if ([authorizedUDID isEqualToString:udid]) {
                                    isAuthorized = YES;
                                    break;
                                }
                            }
                        }
                        if (isAuthorized) break;
                    }
                }
            }
        }
        
        if (response) {
            [[NSURLCache sharedURLCache] removeCachedResponseForRequest:request];
        }
        
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(isAuthorized);
            });
        }
    }];
    
    [task resume];
}

- (NSData *)decryptDataWithKey:(NSData *)encryptedData {
    NSString *key = @"wocaonimawodejibazhendehenda";
    NSData *keyData = [key dataUsingEncoding:NSUTF8StringEncoding];
    
    NSMutableData *keyHash = [NSMutableData dataWithLength:32];
    uint8_t *hashBytes = (uint8_t *)keyHash.mutableBytes;
    
    const void *bytes = keyData.bytes;
    for (NSUInteger i = 0; i < keyData.length; i++) {
        const uint8_t byte = ((const uint8_t *)bytes)[i];
        hashBytes[i % 32] ^= byte;
    }
    
    if (encryptedData.length <= 16) {
        return nil;
    }
    
    NSData *encryptedContent = [encryptedData subdataWithRange:NSMakeRange(16, encryptedData.length - 16)];
    
    const void *encryptedBytes = encryptedContent.bytes;
    uint8_t *keyBytes = (uint8_t *)keyHash.bytes;
    NSMutableData *decryptedData = [NSMutableData dataWithLength:encryptedContent.length];
    uint8_t *decryptedBytes = (uint8_t *)decryptedData.mutableBytes;
    
    for (NSInteger i = 0; i < encryptedContent.length; i++) {
        uint8_t encByte = ((const uint8_t *)encryptedBytes)[i];
        uint8_t originalByte = ((encByte - (i % 7)) & 0xFF) ^ keyBytes[i % keyHash.length];
        decryptedBytes[i] = originalByte;
    }
    
    return decryptedData;
}

- (NSArray *)parseAuthorizedDevicesFromData:(NSData *)decryptedData {
    NSError *error = nil;
    NSDictionary *jsonDict = [NSJSONSerialization JSONObjectWithData:decryptedData options:0 error:&error];
    
    if (error || !jsonDict) {
        return nil;
    }
    
    NSArray *authorizedDevices = jsonDict[@"authorized_devices"];
    return authorizedDevices;
}

- (UIView *)createPanelBackgroundView:(CGRect)frame {
    UIView *backgroundView = [[UIView alloc] initWithFrame:frame];
    backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.85];
    backgroundView.layer.cornerRadius = 20;
    
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    blurView.frame = backgroundView.bounds;
    blurView.layer.cornerRadius = 20;
    blurView.layer.masksToBounds = YES;
    [backgroundView addSubview:blurView];
    
    return backgroundView;
}

- (void)setupPanelControls:(UIView *)container width:(CGFloat)width {
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 10, container.bounds.size.width, 25)];
    titleLabel.text = @"设置";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor whiteColor];
    [container addSubview:titleLabel];
    
    // 开关
    [self addToggleSwitchWithLabel:container yPosition:45];
    
    // 替换滑块为加减按钮控制面板
    [self addAdjustmentControls:container width:width startY:85];
}

- (void)addAdjustmentControls:(UIView *)container width:(CGFloat)width startY:(CGFloat)startY {
    NSArray *titles = @[@"X 轴偏移", @"Y 轴偏移", @"Z 轴偏移", @"屏X轴", @"屏Y轴"];
    float *values[5] = {&_xCorrection, &_yCorrection, &_zCorrection, &_pxCorrection, &_pyCorrection};
    
    for (int i = 0; i < 5; i++) {
        CGFloat yOffset = startY + i * 25;
        
        // 标签
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, yOffset, 80, 20)];
        label.text = titles[i];
        label.font = [UIFont systemFontOfSize:15];
        label.textColor = [UIColor whiteColor];
        [container addSubview:label];
        
        // 减号按钮
        UIButton *minusButton = [self createAdjustmentButton:@"－" frame:CGRectMake(100, yOffset, 30, 20)];
        minusButton.tag = i * 2;
        [container addSubview:minusButton];
        
        // 数值标签
        UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(135, yOffset, 70, 20)];
        valueLabel.text = [NSString stringWithFormat:@"%.3f", *values[i]];
        valueLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        valueLabel.textColor = [UIColor whiteColor];
        valueLabel.textAlignment = NSTextAlignmentCenter;
        valueLabel.tag = i + 100;
        [container addSubview:valueLabel];
        
        // 加号按钮
        UIButton *plusButton = [self createAdjustmentButton:@"＋" frame:CGRectMake(210, yOffset, 30, 20)];
        plusButton.tag = i * 2 + 1;
        [container addSubview:plusButton];
    }
}

- (UIButton *)createAdjustmentButton:(NSString *)title frame:(CGRect)frame {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.frame = frame;
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.6];
    button.layer.cornerRadius = 5;
    button.titleLabel.font = [UIFont systemFontOfSize:15];
    
    // 添加点击和长按手势
    [button addTarget:self action:@selector(adjustmentButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    [button addGestureRecognizer:longPress];
    
    return button;
}

- (void)adjustmentButtonTapped:(UIButton *)sender {
    [self adjustValueForButton:sender];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self startContinuousAdjustment:(UIButton *)gesture.view];
    } else if (gesture.state == UIGestureRecognizerStateEnded || 
               gesture.state == UIGestureRecognizerStateCancelled) {
        [self stopContinuousAdjustment];
    }
}

- (void)startContinuousAdjustment:(UIButton *)button {
    [self adjustValueForButton:button];
    
    // 创建定时器持续调整
    [self performSelector:@selector(continuousAdjustment:) 
               withObject:button 
               afterDelay:0.1];
}

- (void)continuousAdjustment:(UIButton *)button {
    [self adjustValueForButton:button];
    [self startContinuousAdjustment:button];
}

- (void)stopContinuousAdjustment {
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
}

- (void)adjustValueForButton:(UIButton *)button {
    int index = button.tag / 2;
    BOOL isPlus = button.tag % 2 == 1;
    float adjustment;
    
    float *valuePtr;
    switch(index) {
        case 0: // x轴
            valuePtr = &_xCorrection;
            adjustment = 0.788f;
            break;
        case 1: // y轴
            valuePtr = &_yCorrection;
            adjustment = 0.788f;
            break;
        case 2: // z轴
            valuePtr = &_zCorrection;
            adjustment = 0.788f;
            break;
        case 3: // px轴
            valuePtr = &_pxCorrection;
            adjustment = 0.0078f;
            break;
        case 4: // py轴
            valuePtr = &_pyCorrection;
            adjustment = 0.0078f;
            break;
        default: 
            return;
    }
    
    *valuePtr += isPlus ? adjustment : -adjustment;
    
    // 更新显示
    UILabel *valueLabel = [button.superview viewWithTag:index + 100];
    valueLabel.text = [NSString stringWithFormat:@"%.3f", *valuePtr];
    
    // 保存配置
    [self saveConfiguration];
}
- (void)addToggleSwitchWithLabel:(UIView *)container yPosition:(CGFloat)yPos {
    CGFloat spacing = 120; // 两组开关之间的间距
    
    // 第一组：显示开关
    UILabel *switchLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, yPos + 5, 100, 20)];
    switchLabel.text = @"显示";
    switchLabel.font = [UIFont systemFontOfSize:15];
    switchLabel.textColor = [UIColor whiteColor];
    [container addSubview:switchLabel];
    
    UISwitch *toggleSwitch = [[UISwitch alloc] init];
    toggleSwitch.frame = CGRectMake(container.bounds.size.width - 70 - spacing, yPos, 51, 31);
    [toggleSwitch addTarget:self action:@selector(switchValueChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:toggleSwitch];
    
    // 第二组：CJ开关
    UILabel *cjLabel = [[UILabel alloc] initWithFrame:CGRectMake(container.bounds.size.width - spacing + 10, yPos + 5, 40, 20)];
    cjLabel.text = @"CJ";
    cjLabel.font = [UIFont systemFontOfSize:15];
    cjLabel.textColor = [UIColor whiteColor];
    [container addSubview:cjLabel];
    
    UISwitch *cjSwitch = [[UISwitch alloc] init];
    cjSwitch.frame = CGRectMake(container.bounds.size.width - 70, yPos, 51, 31);
    [cjSwitch addTarget:self action:@selector(cjSwitchValueChanged:) forControlEvents:UIControlEventValueChanged];
    [container addSubview:cjSwitch];
}

// 添加CJ开关的事件处理方法
- (void)cjSwitchValueChanged:(UISwitch *)sender {
    // 在这里处理CJ开关的状态变化
    if (sender.isOn) {
        // CJ功能开启时的处理
    } else {
        // CJ功能关闭时的处理
    }
}
- (void)switchValueChanged:(UISwitch *)sender {
    // 使用全局常量变量 kStartFlagPath 作为文件路径
    NSString *flagPath = kStartFlagPath;
    
    if (sender.isOn) {
        // 创建 start.flag 文件
        [[NSFileManager defaultManager] createFileAtPath:flagPath 
                                              contents:nil 
                                            attributes:nil];
        
        [self launchHelper:sender];
        [[OverlayWindowManager sharedManager] showOverlayWindow];
    } else {
        // 删除 start.flag 文件
        if ([[NSFileManager defaultManager] fileExistsAtPath:flagPath]) {
            [[NSFileManager defaultManager] removeItemAtPath:flagPath error:nil];
        }
        
        [[OverlayWindowManager sharedManager] hideOverlayWindow];
    }
}

// 新增辅助方法：判断 FloatingBallHelper 是否正在运行
- (BOOL)isFloatingBallHelperRunning {
    // 如果 _helperPID 非 0，并且 kill(_helperPID, 0) 返回 0，说明进程依然存在
    if (_helperPID > 0 && kill(_helperPID, 0) == 0) {
        return YES;
    }
    _helperPID = 0;
    return NO;
}
// 修改 launchHelper 方法

// 修改 launchHelper 方法
- (void)launchHelper:(UISwitch *)sender {
    // 如果 FloatingBallHelper 已经在运行，则直接返回，避免重复启动
    if ([self isFloatingBallHelperRunning]) {
        return;
    }
    
    // 判断辅助程序是否存在，使用全局变量 kHelperPath
    if (![[NSFileManager defaultManager] fileExistsAtPath:kHelperPath]) {
        sender.on = NO;
        return;
    }
    
    pid_t pid;
    char *argv[] = {(char *)[kHelperPath UTF8String], NULL};
    char *envp[] = {NULL};
    if (posix_spawn(&pid, [kHelperPath UTF8String], NULL, NULL, argv, envp) == 0) {
        _helperPID = pid;
    } else {
        sender.on = NO;
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    CGPoint translation = [gesture translationInView:gesture.view];
    CGRect newFrame = self.floatingWindow.frame;
    newFrame.origin.x += translation.x;
    newFrame.origin.y += translation.y;
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    newFrame.origin.x = MAX(0, MIN(newFrame.origin.x, screenBounds.size.width - newFrame.size.width));
    newFrame.origin.y = MAX(0, MIN(newFrame.origin.y, screenBounds.size.height - newFrame.size.height));
    
    self.floatingWindow.frame = newFrame;
    [gesture setTranslation:CGPointZero inView:gesture.view];
}

- (void)loadConfiguration {
    if ([[NSFileManager defaultManager] fileExistsAtPath:_configPath]) {
        NSString *content = [NSString stringWithContentsOfFile:_configPath 
                                                    encoding:NSUTF8StringEncoding 
                                                       error:nil];
        [self parseConfiguration:content];
    } else {
        [self resetToDefaultConfiguration];
    }
}

- (void)parseConfiguration:(NSString *)content {
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    for (NSString *line in lines) {
        NSArray *parts = [line componentsSeparatedByString:@"="];
        if (parts.count == 2) {
            float value = [parts[1] floatValue];
            if ([parts[0] isEqualToString:@"x"]) {
                self.xCorrection = value;
            } else if ([parts[0] isEqualToString:@"y"]) {
                self.yCorrection = value;
            } else if ([parts[0] isEqualToString:@"z"]) {
                self.zCorrection = value;
            } else if ([parts[0] isEqualToString:@"px"]) {
                self.pxCorrection = value;
            } else if ([parts[0] isEqualToString:@"py"]) {
                self.pyCorrection = value;
            }
        }
    }
}

- (void)resetToDefaultConfiguration {
    self.xCorrection = 0;
    self.yCorrection = 0;
    self.zCorrection = 0;
    self.pxCorrection = 1.0; // 默认值设为1.0
    self.pyCorrection = 0.8867f; // 默认值设为1.0
    [self saveConfiguration];
}

- (void)saveConfiguration {
    NSString *content = [NSString stringWithFormat:@"x=%.3f\ny=%.3f\nz=%.3f\npx=%.3f\npy=%.3f",
                        self.xCorrection, self.yCorrection, self.zCorrection,
                        self.pxCorrection, self.pyCorrection];
    [content writeToFile:_configPath 
              atomically:YES 
                encoding:NSUTF8StringEncoding 
                   error:nil];
}

@end

%hook SpringBoard

- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[OverlayWindowManager sharedManager] showOverlayWindow];
        [[FloatingManager sharedManager] showFloatingBall];
    });
}

%end

%ctor {
    @autoreleasepool {
        if ([[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"]) {
            %init;
        }
    }
}