
#import "IDCCommandEngine.h"
#import "IDCItemCatalog.h"
#import "IDCNativeBridge.h"

static NSString *const IDCVersion = @"0.4.0";

static NSString *IDCKindLabelZH(NSString *kind) {
    NSDictionary<NSString *, NSString *> *labels = @{
        @"passive": @"被动", @"active": @"主动", @"familiar": @"跟班",
        @"trinket": @"饰品", @"card": @"卡牌", @"rune": @"符文",
        @"pill": @"药丸", @"unknown": @"未知"
    };
    return labels[kind] ?: kind;
}

@implementation IDCCommandResult
@end

@implementation IDCCommandSuggestion
@end

@interface IDCCommandEngine ()
@property(nonatomic, strong) IDCNativeBridge *bridge;
@property(nonatomic, strong) IDCItemCatalog *catalog;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, id> *> *commands;
@end

@implementation IDCCommandEngine

- (instancetype)initWithBridge:(IDCNativeBridge *)bridge catalog:(IDCItemCatalog *)catalog {
    self = [super init];
    if (self) {
        _bridge = bridge;
        _catalog = catalog;

        _commands = @[
            @{ @"name": @"help", @"aliases": @[@"?"], @"usage": @"help [command]",
               @"summary": @"显示全部命令，或某个命令的详细说明" },
            @{ @"name": @"status", @"aliases": @[], @"usage": @"status",
               @"summary": @"显示原生桥接、当前游戏和目录状态" },
            @{ @"name": @"seed", @"aliases": @[], @"usage": @"seed",
               @"summary": @"显示本局种子" },
            @{ @"name": @"room", @"aliases": @[], @"usage": @"room",
               @"summary": @"显示当前房间类型" },
            @{ @"name": @"position", @"aliases": @[@"pos"], @"usage": @"position",
               @"summary": @"显示玩家类型和坐标" },
            @{ @"name": @"inventory", @"aliases": @[@"inv"], @"usage": @"inventory",
               @"summary": @"列出已拥有的道具" },
            @{ @"name": @"items", @"aliases": @[@"find"], @"usage": @"items <name|id>",
               @"summary": @"按名称或 ID 搜索道具" },
            @{ @"name": @"trinkets", @"aliases": @[], @"usage": @"trinkets [name|id]",
               @"summary": @"列出或搜索饰品" },
            @{ @"name": @"cards", @"aliases": @[], @"usage": @"cards [name|id]",
               @"summary": @"列出或搜索卡牌" },
            @{ @"name": @"runes", @"aliases": @[], @"usage": @"runes [name|id]",
               @"summary": @"列出或搜索符文和灵魂石" },
            @{ @"name": @"pilleffects", @"aliases": @[@"pills"],
               @"usage": @"pilleffects [name|id]",
               @"summary": @"列出或搜索药丸效果" },
            @{ @"name": @"giveitem", @"aliases": @[@"g"],
               @"usage": @"giveitem <cID|name>",
               @"summary": @"直接给玩家一个道具" },
            @{ @"name": @"remove", @"aliases": @[@"r"],
               @"usage": @"remove <cID|name>",
               @"summary": @"移除玩家身上的一个道具" },
            @{ @"name": @"spawn", @"aliases": @[@"s"],
               @"usage": @"spawn <type.variant.subtype>",
               @"summary": @"在玩家旁边生成原生实体" },
            @{ @"name": @"spawnpickup", @"aliases": @[@"pickup"],
               @"usage": @"spawnpickup <variant.subtype>",
               @"summary": @"在玩家旁边生成拾取物" },
            @{ @"name": @"spawnitem", @"aliases": @[@"si"],
               @"usage": @"spawnitem <cID|name>",
               @"summary": @"在房间里生成一个道具底座" },
            @{ @"name": @"spawntrinket", @"aliases": @[@"st"],
               @"usage": @"spawntrinket <tID|name>",
               @"summary": @"在房间里生成一个饰品" },
            @{ @"name": @"spawncard", @"aliases": @[@"sc"],
               @"usage": @"spawncard <ID|name>",
               @"summary": @"在房间里生成一张卡牌" },
            @{ @"name": @"spawnrune", @"aliases": @[@"sr", @"spawnrun"],
               @"usage": @"spawnrune <ID|1-10|name>",
               @"summary": @"在房间里生成一个符文或灵魂石" },
            @{ @"name": @"spawnpill", @"aliases": @[@"sp"],
               @"usage": @"spawnpill <color|effect> [horse]",
               @"summary": @"从本局药丸池中生成一颗药丸" },
            @{ @"name": @"rewind", @"aliases": @[@"hourglass"], @"usage": @"rewind",
               @"summary": @"通过发光沙漏（Glowing Hourglass）的逻辑回溯" },
            @{ @"name": @"restart", @"aliases": @[@"rs"], @"usage": @"restart",
               @"summary": @"用相同角色和难度开始新的一局（别名：rs）" },
            @{ @"name": @"history", @"aliases": @[], @"usage": @"history",
               @"summary": @"显示本次使用过的命令" },
            @{ @"name": @"clear", @"aliases": @[@"cls"], @"usage": @"clear",
               @"summary": @"清空控制台输出" },
            @{ @"name": @"version", @"aliases": @[], @"usage": @"version",
               @"summary": @"显示控制台版本" },
            @{ @"name": @"close", @"aliases": @[@"exit"], @"usage": @"close",
               @"summary": @"关闭控制台面板" },
        ];
    }
    return self;
}

- (IDCCommandResult *)result:(NSString *)output action:(IDCCommandAction)action {
    IDCCommandResult *result = [IDCCommandResult new];
    result.output = output ?: @"";
    result.action = action;
    return result;
}

- (NSDictionary<NSString *, id> *)commandForToken:(NSString *)token {
    NSString *needle = token.lowercaseString;
    for (NSDictionary<NSString *, id> *command in self.commands) {
        if ([command[@"name"] isEqualToString:needle] ||
            [command[@"aliases"] containsObject:needle]) {
            return command;
        }
    }
    return nil;
}

- (NSArray<NSString *> *)commandAndArgument:(NSString *)input {
    NSString *trimmed = [input stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSRange whitespace = [trimmed rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet];

    if (whitespace.location == NSNotFound) {
        return @[trimmed.lowercaseString, @""];
    }

    NSString *command = [[trimmed substringToIndex:whitespace.location] lowercaseString];
    NSString *argument = [[trimmed substringFromIndex:NSMaxRange(whitespace)]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    if ([argument hasPrefix:@"\""] && [argument hasSuffix:@"\""] && argument.length >= 2) {
        argument = [argument substringWithRange:NSMakeRange(1, argument.length - 2)];
    }

    return @[command, argument];
}

- (NSString *)roomName:(NSInteger)type {
    NSDictionary<NSNumber *, NSString *> *names = @{
        @1: @"普通房", @2: @"商店", @3: @"错误房", @4: @"宝藏房",
        @5: @"Boss 房", @6: @"小 Boss 房", @7: @"隐藏房", @8: @"超级隐藏房",
        @9: @"游戏房", @10: @"诅咒房", @11: @"挑战房", @12: @"图书馆",
        @13: @"献祭房", @14: @"恶魔房", @15: @"天使房", @16: @"地牢",
        @17: @"Boss Rush", @18: @"卧室", @19: @"空卧室", @20: @"宝箱房",
        @21: @"骰子房", @22: @"黑市", @23: @"贪婪模式出口", @24: @"天文馆",
        @25: @"传送房", @26: @"传送出口", @27: @"隐藏出口",
        @28: @"蓝房", @29: @"究极隐藏房"
    };
    return names[@(type)] ?: @"未知";
}

- (NSString *)itemLabel:(IDCItemRecord *)record {
    return [NSString stringWithFormat:@"c%ld — %@（%@）",
            (long)record.identifier, record.name, IDCKindLabelZH(record.kind)];
}

- (NSString *)labelForRecord:(IDCItemRecord *)record prefix:(NSString *)prefix {
    return [NSString stringWithFormat:@"%@%ld — %@",
            prefix, (long)record.identifier, record.name];
}

- (BOOL)parseUnsignedComponents:(NSString *)argument
                          count:(NSUInteger)expectedCount
                         values:(NSArray<NSNumber *> * _Nullable * _Nullable)values {
    NSString *normalized = argument;
    for (NSString *separator in @[@".", @":", @","]) {
        normalized = [normalized stringByReplacingOccurrencesOfString:separator
                                                           withString:@" "];
    }

    NSArray<NSString *> *raw = [normalized componentsSeparatedByCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableArray<NSNumber *> *parsed = [NSMutableArray array];

    for (NSString *component in raw) {
        if (!component.length) continue;
        if ([component rangeOfCharacterFromSet:
                NSCharacterSet.decimalDigitCharacterSet.invertedSet].location != NSNotFound) {
            return NO;
        }
        [parsed addObject:@(component.integerValue)];
    }

    if (parsed.count != expectedCount) return NO;
    if (values) *values = parsed.copy;
    return YES;
}

- (NSArray<IDCItemRecord *> *)recordsForListCommand:(NSString *)command
                                               query:(NSString *)query
                                               limit:(NSUInteger)limit {
    if ([command isEqualToString:@"items"]) {
        return [self.catalog recordsMatching:query limit:limit];
    }
    if ([command isEqualToString:@"trinkets"]) {
        return [self.catalog trinketsMatching:query limit:limit];
    }
    if ([command isEqualToString:@"cards"] || [command isEqualToString:@"runes"]) {
        NSString *kind = [command isEqualToString:@"cards"] ? @"card" : @"rune";
        return [self.catalog pocketItemsMatching:query kind:kind limit:limit];
    }
    return [self.catalog pillEffectsMatching:query limit:limit];
}

- (NSString *)prefixForListCommand:(NSString *)command {
    if ([command isEqualToString:@"items"]) return @"c";
    if ([command isEqualToString:@"trinkets"]) return @"t";
    if ([command isEqualToString:@"cards"]) return @"卡牌 ";
    if ([command isEqualToString:@"runes"]) return @"符文 ";
    return @"效果 ";
}

- (NSString *)localizedBridgeError:(NSString *)error {
    static NSDictionary<NSString *, NSString *> *table;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        table = @{
            @"The native spawn context is unavailable.": @"原生生成环境不可用。",
            @"The active Game object is unavailable.": @"无法获取当前的 Game 对象。",
            @"Isaac's spawn context is not ready in this room.": @"当前房间的生成环境还没有准备好。",
            @"Isaac's spawn context failed memory validation.": @"生成环境的内存校验失败。",
            @"Unsupported Isaac executable; mutation disabled.": @"不支持当前的以撒版本，已禁用修改功能。",
            @"No active player was found.": @"没有找到当前玩家。",
            @"Wait for the transition or cutscene to finish.": @"请等待过场或动画结束。",
            @"Pause the run before using modifying commands.": @"请先暂停游戏，再使用会修改游戏的命令。",
            @"Collectible ID must be between 1 and 732.": @"道具 ID 必须在 1 到 732 之间。",
            @"Native command signature failed validation; mutation disabled.": @"原生命令的特征校验失败，已禁用修改功能。",
            @"The native AddCollectible call completed, but inventory verification failed.": @"原生 AddCollectible 调用已完成，但背包校验未通过。",
            @"The player does not own that collectible.": @"玩家没有这个道具。",
            @"The native RemoveCollectible call completed, but inventory verification failed.": @"原生 RemoveCollectible 调用已完成，但背包校验未通过。",
            @"Supported entity types are 2 through 9 and 1000.": @"支持的实体类型为 2 到 9 以及 1000。",
            @"Entity variant must be between 0 and 9999.": @"实体 variant 必须在 0 到 9999 之间。",
            @"Entity subtype must be between 0 and 9999.": @"实体 subtype 必须在 0 到 9999 之间。",
            @"Native spawn signature failed validation; spawning disabled.": @"原生生成函数的特征校验失败，已禁用生成。",
            @"Isaac rejected the spawn request.": @"游戏拒绝了这次生成请求。",
            @"The entity was created, but identity verification failed.": @"实体已创建，但身份校验未通过。",
            @"Pill effect ID must be between 0 and 49.": @"药丸效果 ID 必须在 0 到 49 之间。",
            @"That pill effect is not present in this run's pill pool.": @"这个药丸效果不在本局的药丸池中。",
            @"Native active-item signature failed validation; rewind disabled.": @"原生主动道具函数的特征校验失败，已禁用回溯。",
            @"Restart must run on the game's main thread.": @"重开必须在游戏主线程运行。",
            @"Native restart signature failed validation.": @"原生重开函数的特征校验失败。",
            @"Restart is unavailable during menus, transitions or a restricted run.": @"在菜单、过渡动画或受限的游戏中无法重开。",
            @"The native restart path requires an Eden token.": @"原生重开流程需要伊甸代币。",
        };
    });
    return table[error] ?: error;
}

- (IDCCommandResult *)nativeResultForError:(NSString *)error success:(NSString *)success {
    if (error) {
        return [self result:[NSString stringWithFormat:@"Error: %@",
                             [self localizedBridgeError:error]]
                     action:IDCCommandActionNone];
    }
    return [self result:success action:IDCCommandActionNone];
}

- (IDCCommandResult *)executeInput:(NSString *)input {
    NSArray<NSString *> *parts = [self commandAndArgument:input];
    NSString *token = parts[0];
    NSString *argument = parts[1];

    if (!token.length) {
        return [self result:@"" action:IDCCommandActionNone];
    }

    NSDictionary<NSString *, id> *definition = [self commandForToken:token];
    if (!definition) {
        return [self result:[NSString stringWithFormat:
            @"未知命令“%@”。输入 help 查看全部命令。", token]
                     action:IDCCommandActionNone];
    }

    NSString *command = definition[@"name"];

    if ([command isEqualToString:@"help"]) {
        if (argument.length) {
            NSDictionary *target = [self commandForToken:argument];
            if (!target) {
                return [self result:@"未知的帮助主题。" action:IDCCommandActionNone];
            }

            NSString *aliases = [target[@"aliases"] componentsJoinedByString:@", "];
            NSString *text = [NSString stringWithFormat:@"%@\n%@%@",
                target[@"usage"], target[@"summary"],
                aliases.length
                    ? [NSString stringWithFormat:@"\n别名：%@\nAliases: %@", aliases, aliases]
                    : @""];

            return [self result:text action:IDCCommandActionNone];
        }

        NSMutableArray<NSString *> *lines = [NSMutableArray arrayWithObject:@"可用命令："];
        for (NSDictionary *entry in self.commands) {
            [lines addObject:[NSString stringWithFormat:@"  %@ — %@",
                              entry[@"usage"], entry[@"summary"]]];
        }
        [lines addObject:@"点击联想建议即可自动填入。会修改游戏的命令需要在暂停的游戏中使用。"];
        return [self result:[lines componentsJoinedByString:@"\n"]
                     action:IDCCommandActionNone];
    }

    if ([command isEqualToString:@"clear"]) {
        return [self result:@"" action:IDCCommandActionClear];
    }
    if ([command isEqualToString:@"close"]) {
        return [self result:@"" action:IDCCommandActionClose];
    }
    if ([command isEqualToString:@"history"]) {
        return [self result:@"" action:IDCCommandActionHistory];
    }
    if ([command isEqualToString:@"version"]) {
        return [self result:[NSString stringWithFormat:
            @"Isaac Debug Console iOS %@", IDCVersion]
                     action:IDCCommandActionNone];
    }

    IDCNativeSnapshot *snapshot = [self.bridge refreshSnapshot];

    if ([command isEqualToString:@"status"]) {
        NSString *state = snapshot.inGame ? (snapshot.paused ? @"已暂停" : @"游戏中") : @"菜单";
        return [self result:[NSString stringWithFormat:
            @"桥接：%@\nUUID：%@\n状态：%@\n目录：%lu 个道具，%lu 个饰品，%lu 张卡牌/符文，%lu 种药丸效果",
            snapshot.supportedBuild ? @"已支持" : @"已禁用", snapshot.executableUUID,
            state, (unsigned long)self.catalog.count, (unsigned long)self.catalog.trinketCount,
            (unsigned long)self.catalog.pocketItemCount,
            (unsigned long)self.catalog.pillEffectCount]
                     action:IDCCommandActionNone];
    }

    if ([@[@"items", @"trinkets", @"cards", @"runes", @"pilleffects"]
            containsObject:command]) {
        if ([command isEqualToString:@"items"] && !argument.length) {
            return [self result:@"用法：items <name|id>" action:IDCCommandActionNone];
        }

        NSArray<IDCItemRecord *> *matches = [self recordsForListCommand:command
                                                                   query:argument
                                                                   limit:30];
        if (!matches.count) {
            return [self result:@"没有匹配的条目。" action:IDCCommandActionNone];
        }

        NSString *prefix = [self prefixForListCommand:command];
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (IDCItemRecord *record in matches) {
            [lines addObject:[self labelForRecord:record prefix:prefix]];
        }
        return [self result:[lines componentsJoinedByString:@"\n"]
                     action:IDCCommandActionNone];
    }

    if (!snapshot.inGame) {
        return [self result:
            @"An active run is required.（该命令需要在进行中的游戏里使用。）"
                     action:IDCCommandActionNone];
    }

    if ([command isEqualToString:@"seed"]) {
        return [self result:snapshot.runSeed
            ? [NSString stringWithFormat:@"本局种子：%u (0x%08X)",
               snapshot.runSeed, snapshot.runSeed]
            : @"无法获取种子。"
                     action:IDCCommandActionNone];
    }

    if ([command isEqualToString:@"room"]) {
        return [self result:snapshot.roomType
            ? [NSString stringWithFormat:@"房间类型：%ld — %@",
               (long)snapshot.roomType, [self roomName:snapshot.roomType]]
            : @"无法获取房间类型。"
                     action:IDCCommandActionNone];
    }

    if ([command isEqualToString:@"position"]) {
        return [self result:[NSString stringWithFormat:
            @"玩家类型 %ld，坐标：%.2f, %.2f",
            (long)snapshot.playerType, snapshot.playerX, snapshot.playerY]
                     action:IDCCommandActionNone];
    }

    if ([command isEqualToString:@"inventory"]) {
        if (!snapshot.collectibleCounts.count) {
            return [self result:@"没有找到已拥有的道具。"
                         action:IDCCommandActionNone];
        }

        NSArray<NSNumber *> *identifiers = [snapshot.collectibleCounts.allKeys
            sortedArrayUsingSelector:@selector(compare:)];
        NSMutableArray<NSString *> *values = [NSMutableArray array];

        for (NSNumber *identifier in identifiers) {
            IDCItemRecord *record = [self.catalog recordForIdentifier:identifier.integerValue];
            NSString *name = record.name ?: [NSString stringWithFormat:@"道具 %@", identifier];
            [values addObject:[NSString stringWithFormat:@"c%@ %@ ×%@",
                identifier, name, snapshot.collectibleCounts[identifier]]];
        }

        return [self result:[values componentsJoinedByString:@"\n"]
                     action:IDCCommandActionNone];
    }

    if ([command isEqualToString:@"giveitem"] || [command isEqualToString:@"remove"]) {
        NSString *lookupError = nil;
        IDCItemRecord *record = [self.catalog recordForSpecifier:argument error:&lookupError];
        if (!record) {
            return [self result:lookupError action:IDCCommandActionNone];
        }

        NSString *nativeError = [command isEqualToString:@"giveitem"]
            ? [self.bridge giveCollectible:record.identifier]
            : [self.bridge removeCollectible:record.identifier];
        NSString *verb = [command isEqualToString:@"giveitem"] ? @"已添加" : @"已移除";

        return [self nativeResultForError:nativeError success:[NSString stringWithFormat:
            @"%@ c%ld — %@", verb, (long)record.identifier, record.name]];
    }

    if ([command isEqualToString:@"spawn"] || [command isEqualToString:@"spawnpickup"]) {
        NSUInteger componentCount = [command isEqualToString:@"spawn"] ? 3 : 2;
        NSArray<NSNumber *> *values = nil;

        if (![self parseUnsignedComponents:argument count:componentCount values:&values]) {
            return [self result:[NSString stringWithFormat:@"用法：%@", definition[@"usage"]]
                         action:IDCCommandActionNone];
        }

        NSInteger type = [command isEqualToString:@"spawn"] ? values[0].integerValue : 5;
        NSInteger index = [command isEqualToString:@"spawn"] ? 1 : 0;
        NSInteger variant = values[(NSUInteger)index].integerValue;
        NSInteger subtype = values[(NSUInteger)index + 1].integerValue;

        NSString *error = [self.bridge spawnEntityType:type variant:variant subtype:subtype];
        return [self nativeResultForError:error success:[NSString stringWithFormat:
            @"已在玩家旁边生成 %ld.%ld.%ld。",
            (long)type, (long)variant, (long)subtype]];
    }

    if ([command isEqualToString:@"spawnitem"]) {
        NSString *lookupError = nil;
        IDCItemRecord *record = [self.catalog recordForSpecifier:argument error:&lookupError];
        if (!record) {
            return [self result:lookupError action:IDCCommandActionNone];
        }

        NSString *error = [self.bridge spawnEntityType:5 variant:100 subtype:record.identifier];
        return [self nativeResultForError:error success:[NSString stringWithFormat:
            @"已生成道具 c%ld — %@。", (long)record.identifier, record.name]];
    }

    if ([command isEqualToString:@"spawntrinket"]) {
        NSString *lookupError = nil;
        IDCItemRecord *record = [self.catalog trinketForSpecifier:argument error:&lookupError];
        if (!record) {
            return [self result:lookupError action:IDCCommandActionNone];
        }

        NSString *error = [self.bridge spawnEntityType:5 variant:350 subtype:record.identifier];
        return [self nativeResultForError:error success:[NSString stringWithFormat:
            @"已生成饰品 t%ld — %@。", (long)record.identifier, record.name]];
    }

    if ([command isEqualToString:@"spawncard"] || [command isEqualToString:@"spawnrune"]) {
        BOOL rune = [command isEqualToString:@"spawnrune"];
        NSString *specifier = argument;

        if (rune && argument.length &&
            [argument rangeOfCharacterFromSet:
                NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound) {
            NSInteger shortID = argument.integerValue;
            if (shortID >= 1 && shortID <= 10) {
                specifier = [NSString stringWithFormat:@"%ld", (long)(shortID + 31)];
            }
        }

        NSString *lookupError = nil;
        IDCItemRecord *record = [self.catalog pocketItemForSpecifier:specifier
            kind:rune ? @"rune" : @"card" error:&lookupError];
        if (!record) {
            return [self result:lookupError action:IDCCommandActionNone];
        }

        NSString *error = [self.bridge spawnEntityType:5 variant:300 subtype:record.identifier];
        return [self nativeResultForError:error success:[NSString stringWithFormat:
            @"已生成%@ %ld — %@。",
            rune ? @"符文" : @"卡牌", (long)record.identifier, record.name]];
    }

    if ([command isEqualToString:@"spawnpill"]) {
        NSString *query = [argument stringByTrimmingCharactersInSet:
            NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL horse = NO;

        NSRange lastSpace = [query rangeOfCharacterFromSet:NSCharacterSet.whitespaceCharacterSet
                                                   options:NSBackwardsSearch];
        NSString *lastToken = lastSpace.location == NSNotFound
            ? query : [query substringFromIndex:NSMaxRange(lastSpace)];

        if ([lastToken.lowercaseString isEqualToString:@"horse"] ||
            [lastToken.lowercaseString isEqualToString:@"horsepill"]) {
            horse = YES;
            query = lastSpace.location == NSNotFound
                ? @""
                : [[query substringToIndex:lastSpace.location]
                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }

        BOOL explicitEffect = [query.lowercaseString hasPrefix:@"effect "];
        if (explicitEffect) {
            query = [[query substringFromIndex:7]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        }

        query = [query stringByReplacingOccurrencesOfString:@"\"" withString:@""];
        BOOL numeric = query.length && [query rangeOfCharacterFromSet:
            NSCharacterSet.decimalDigitCharacterSet.invertedSet].location == NSNotFound;
        NSString *pillName = horse ? @"大药丸" : @"药丸";

        if (numeric && !explicitEffect) {
            NSInteger color = query.integerValue;
            if (color < 1 || color > 14) {
                return [self result:
                    @"药丸颜色必须在 1 到 14 之间。指定效果 ID 请用 ‘effect <id>’。"
                             action:IDCCommandActionNone];
            }

            NSInteger subtype = color | (horse ? (1 << 11) : 0);
            NSString *error = [self.bridge spawnEntityType:5 variant:70 subtype:subtype];
            return [self nativeResultForError:error success:[NSString stringWithFormat:
                @"已生成%@，颜色 %ld。", pillName, (long)color]];
        }

        NSString *lookupError = nil;
        IDCItemRecord *effect = [self.catalog pillEffectForSpecifier:query error:&lookupError];
        if (!effect) {
            return [self result:lookupError action:IDCCommandActionNone];
        }

        NSInteger color = 0;
        NSString *error = [self.bridge spawnPillEffect:effect.identifier horse:horse
                                         resolvedColor:&color];
        return [self nativeResultForError:error success:[NSString stringWithFormat:
            @"已生成%@，颜色 %ld — %@。", pillName, (long)color, effect.name]];
    }

    if ([command isEqualToString:@"rewind"]) {
        NSString *error = [self.bridge rewind];
        return [self nativeResultForError:error success:@"已通过发光沙漏的逻辑触发回溯。"];
    }

    if ([command isEqualToString:@"restart"]) {
        if (argument.length) {
            return [self result:
                @"Usage: restart（用法：restart，别名：rs）"
                         action:IDCCommandActionNone];
        }

        NSString *error = [self.bridge restart];
        if (error) {
            return [self nativeResultForError:error success:@""];
        }

        return [self result:@"已排队执行新一局重开。"
                     action:IDCCommandActionClose];
    }

    return [self result:@"该命令尚未实现。" action:IDCCommandActionNone];
}

- (IDCCommandSuggestion *)suggestion:(NSString *)display replacement:(NSString *)replacement {
    IDCCommandSuggestion *suggestion = [IDCCommandSuggestion new];
    suggestion.displayText = display;
    suggestion.replacementText = replacement;
    return suggestion;
}

- (void)addRecordSuggestions:(NSArray<IDCItemRecord *> *)records
                      command:(NSString *)command
                       prefix:(NSString *)prefix
                           to:(NSMutableArray<IDCCommandSuggestion *> *)suggestions {
    for (IDCItemRecord *record in records) {
        [suggestions addObject:[self suggestion:[self labelForRecord:record prefix:prefix]
            replacement:[NSString stringWithFormat:@"%@ %ld",
                         command, (long)record.identifier]]];
    }
}

- (NSArray<IDCCommandSuggestion *> *)suggestionsForInput:(NSString *)input
                                                   limit:(NSUInteger)limit {
    NSString *trimmedLeading = [input stringByTrimmingCharactersInSet:
        NSCharacterSet.newlineCharacterSet];
    NSRange whitespace = [trimmedLeading rangeOfCharacterFromSet:
        NSCharacterSet.whitespaceCharacterSet];
    NSMutableArray<IDCCommandSuggestion *> *suggestions = [NSMutableArray array];

    if (whitespace.location == NSNotFound) {
        NSString *needle = trimmedLeading.lowercaseString;

        for (NSDictionary<NSString *, id> *command in self.commands) {
            NSString *name = command[@"name"];
            BOOL matches = !needle.length || [name hasPrefix:needle];

            if (!matches) {
                for (NSString *alias in command[@"aliases"]) {
                    if ([alias hasPrefix:needle]) {
                        matches = YES;
                        break;
                    }
                }
            }

            if (!matches) continue;

            [suggestions addObject:[self suggestion:
                [NSString stringWithFormat:@"%@ — %@", command[@"usage"], command[@"summary"]]
                replacement:[name stringByAppendingString:@" "]]];

            if (suggestions.count >= limit) break;
        }
        return suggestions.copy;
    }

    NSString *token = [[trimmedLeading substringToIndex:whitespace.location] lowercaseString];
    NSDictionary *definition = [self commandForToken:token];
    if (!definition) return @[];

    NSString *command = definition[@"name"];
    NSString *argument = [[trimmedLeading substringFromIndex:NSMaxRange(whitespace)]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

    if ([command isEqualToString:@"giveitem"] ||
        [command isEqualToString:@"remove"] ||
        [command isEqualToString:@"items"] ||
        [command isEqualToString:@"spawnitem"]) {

        for (IDCItemRecord *record in [self.catalog recordsMatching:argument limit:limit]) {
            NSString *replacement = [NSString stringWithFormat:@"%@ c%ld",
                command, (long)record.identifier];
            [suggestions addObject:[self suggestion:[self itemLabel:record]
                replacement:replacement]];
        }

    } else if ([command isEqualToString:@"trinkets"] ||
               [command isEqualToString:@"spawntrinket"]) {

        [self addRecordSuggestions:[self.catalog trinketsMatching:argument limit:limit]
                           command:command prefix:@"t" to:suggestions];

    } else if ([command isEqualToString:@"cards"] ||
               [command isEqualToString:@"spawncard"] ||
               [command isEqualToString:@"runes"] ||
               [command isEqualToString:@"spawnrune"]) {

        BOOL rune = [command isEqualToString:@"runes"] ||
                    [command isEqualToString:@"spawnrune"];

        [self addRecordSuggestions:
            [self.catalog pocketItemsMatching:argument
                                         kind:rune ? @"rune" : @"card"
                                        limit:limit]
                            command:command
                             prefix:rune ? @"符文 " : @"卡牌 "
                                 to:suggestions];

    } else if ([command isEqualToString:@"pilleffects"] ||
               [command isEqualToString:@"spawnpill"]) {

        NSString *query = argument;
        if ([query.lowercaseString hasPrefix:@"effect "]) {
            query = [query substringFromIndex:7];
        }

        NSArray<IDCItemRecord *> *effects =
            [self.catalog pillEffectsMatching:query limit:limit];

        for (IDCItemRecord *record in effects) {
            NSString *replacement =
                [command isEqualToString:@"spawnpill"]
                ? [NSString stringWithFormat:@"spawnpill effect %ld",
                   (long)record.identifier]
                : [NSString stringWithFormat:@"pilleffects %ld",
                   (long)record.identifier];

            [suggestions addObject:[self suggestion:
                [self labelForRecord:record prefix:@"效果 "]
                replacement:replacement]];
        }

        if ([command isEqualToString:@"spawnpill"] && !argument.length) {
            [suggestions insertObject:
                [self suggestion:
                    @"spawnpill <color 1-14> [horse]（颜色 1-14，可选 horse 表示大药丸）"
                    replacement:@"spawnpill 1"]
                atIndex:0];
        }

    } else if ([command isEqualToString:@"spawn"]) {

        [suggestions addObject:
            [self suggestion:
                @"type.variant.subtype（示例：5.100.1 = 拾取物 · 道具 · 1）"
                replacement:@"spawn 5.100.1"]];

    } else if ([command isEqualToString:@"spawnpickup"]) {

        [suggestions addObject:
            [self suggestion:
                @"variant.subtype（示例：100.1 = 道具 1）"
                replacement:@"spawnpickup 100.1"]];

    } else if ([command isEqualToString:@"help"]) {

        for (NSDictionary<NSString *, id> *entry in self.commands) {
            NSString *name = entry[@"name"];

            if (!argument.length ||
                [name hasPrefix:argument.lowercaseString]) {

                [suggestions addObject:[self suggestion:
                    [NSString stringWithFormat:@"%@ — %@", name, entry[@"summary"]]
                    replacement:[NSString stringWithFormat:@"help %@", name]]];

                if (suggestions.count >= limit) break;
            }
        }
    }

    if (suggestions.count > limit) {
        [suggestions removeObjectsInRange:
            NSMakeRange(limit, suggestions.count - limit)];
    }

    return suggestions.copy;
}

@end
