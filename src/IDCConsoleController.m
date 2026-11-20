#import "IDCConsoleController.h"
#import "IDCCommandEngine.h"
#import "IDCItemCatalog.h"
#import "IDCLogger.h"
#import "IDCNativeBridge.h"
#import "IDCHotkey.h"
#include "IDCConsoleLayout.h"

#import <UIKit/UIKit.h>

static const NSInteger IDCInteractiveTag = 0x1DC;

typedef NS_ENUM(NSInteger, IDCTab) {
    IDCTabCommand = 0,
    IDCTabItems,
    IDCTabTrinkets,
    IDCTabCards,
    IDCTabRunes,
    IDCTabPills,
};

#pragma mark - Passthrough root

@interface IDCPassthroughView : UIView
@property(nonatomic, copy) void (^layoutHandler)(void);
@end

@implementation IDCPassthroughView
- (void)layoutSubviews { [super layoutSubviews]; if (self.layoutHandler) self.layoutHandler(); }
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (!hit || hit == self) return nil;
    if ([hit isKindOfClass:UIControl.class]) return hit;
    for (UIView *view = hit; view && view != self; view = view.superview) {
        if (view.tag == IDCInteractiveTag) return hit;
    }
    return nil;
}
@end

#pragma mark - Grid cell (icon on top, name below)

@interface IDCItemCell : UICollectionViewCell
@property(nonatomic, strong) UIImageView *iconView;
@property(nonatomic, strong) UILabel *nameLabel;
@end

@implementation IDCItemCell
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.contentView.backgroundColor = UIColor.secondarySystemFillColor;
        self.contentView.layer.cornerRadius = 12;
        self.contentView.clipsToBounds = YES;
        _iconView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        _iconView.layer.magnificationFilter = kCAFilterNearest; // keep pixel art sharp
        _iconView.tintColor = UIColor.tertiaryLabelColor;
        [self.contentView addSubview:_iconView];
        _nameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _nameLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
        _nameLabel.textColor = UIColor.labelColor;
        _nameLabel.textAlignment = NSTextAlignmentCenter;
        _nameLabel.numberOfLines = 2;
        [self.contentView addSubview:_nameLabel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat height = self.contentView.bounds.size.height;
    CGFloat icon = MAX(8, MIN(width - 24, height - 44));
    self.iconView.frame = CGRectMake((width - icon) / 2, 8, icon, icon);
    CGFloat labelTop = 8 + icon + 4;
    self.nameLabel.frame = CGRectMake(4, labelTop, width - 8, MAX(0, height - labelTop - 4));
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.contentView.alpha = highlighted ? 0.55 : 1;
}
@end

#pragma mark - Controller

@interface IDCConsoleController () <UITextFieldDelegate, UITableViewDataSource,
                                    UITableViewDelegate, UICollectionViewDataSource,
                                    UICollectionViewDelegate>
@property(nonatomic, strong) IDCNativeBridge *bridge;
@property(nonatomic, strong) IDCCommandEngine *engine;
@property(nonatomic, strong) IDCItemCatalog *catalog;
@property(nonatomic, strong) IDCPassthroughView *rootView;
@property(nonatomic, strong) UIButton *consoleButton;
@property(nonatomic, strong) UIVisualEffectView *panel;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UILabel *statusLabel;
@property(nonatomic, strong) UIButton *closeButton;
@property(nonatomic, strong) UISegmentedControl *tabControl;
@property(nonatomic, strong) UITextView *outputView;
@property(nonatomic, strong) UITableView *suggestionsTable;
@property(nonatomic, strong) UICollectionView *grid;
@property(nonatomic, strong) UIView *toastView;
@property(nonatomic, strong) UILabel *toastLabel;
@property(nonatomic) NSInteger toastGeneration;
@property(nonatomic, strong) UITextField *inputField;
@property(nonatomic, strong) UIButton *runButton;
@property(nonatomic, strong) UIButton *previousButton;
@property(nonatomic, strong) UIButton *nextButton;
@property(nonatomic, strong) UIButton *keyboardButton;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSArray<IDCCommandSuggestion *> *suggestions;
@property(nonatomic, copy) NSArray<IDCItemRecord *> *gridRecords;
@property(nonatomic) IDCTab tab;
@property(nonatomic) CGFloat lastGridWidth;
@property(nonatomic, strong) NSMutableArray<NSString *> *history;
@property(nonatomic) NSInteger historyIndex;
@property(nonatomic) CGFloat keyboardOverlap;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic, strong) IDCHotkey *hotkey;
@end

@implementation IDCConsoleController

- (instancetype)initWithBridge:(IDCNativeBridge *)bridge engine:(IDCCommandEngine *)engine {
    self = [super init];
    if (self) {
        _bridge = bridge;
        _engine = engine;
        _suggestions = @[];
        _gridRecords = @[];
        _history = [NSMutableArray array];
        _historyIndex = 0;
        _tab = IDCTabCommand;
    }
    return self;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (IDCItemCatalog *)catalog {
    if (!_catalog) _catalog = [IDCItemCatalog new];
    return _catalog;
}

- (void)start {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(keyboardFrameChanged:)
                       name:UIKeyboardWillChangeFrameNotification object:nil];
        [center addObserver:self selector:@selector(keyboardWillHide:)
                       name:UIKeyboardWillHideNotification object:nil];
        [center addObserver:self selector:@selector(suspendConsole)
                       name:UIApplicationWillResignActiveNotification object:nil];
        [center addObserver:self selector:@selector(suspendConsole)
                       name:@"NSApplicationWillResignActiveNotification" object:nil];
        [center addObserver:self selector:@selector(escapeCloseRequested:)
                       name:@"com.emp0ry.isaacconsole.closeForEscape" object:nil];
        [self attachIfNeeded];
        __weak IDCConsoleController *weakSelf = self;
        self.hotkey = [[IDCHotkey alloc] initWithHandler:^BOOL {
            return [weakSelf toggleFromKeyboard];
        } closeHandler:^BOOL {
            return [weakSelf closeFromKeyboard];
        }];
        [self.hotkey start];
        self.timer = [NSTimer timerWithTimeInterval:0.1 target:self
                                          selector:@selector(tick:) userInfo:nil repeats:YES];
        [NSRunLoop.mainRunLoop addTimer:self.timer forMode:NSRunLoopCommonModes];
    });
}

- (UIWindow *)gameWindow {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.hidden || window.alpha <= 0 || window.windowLevel != UIWindowLevelNormal) continue;
            if (window.isKeyWindow) return window;
            if (!fallback) fallback = window;
        }
    }
    return fallback;
}

#pragma mark - View construction

- (UIButton *)symbolButtonWithSymbol:(NSString *)symbol
                               label:(NSString *)label
                              action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    button.tintColor = UIColor.labelColor;
    button.backgroundColor = UIColor.tertiarySystemFillColor;
    button.layer.cornerRadius = 10;
    button.accessibilityLabel = label;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)attachIfNeeded {
    UIWindow *window = [self gameWindow];
    if (!window || CGRectIsEmpty(window.bounds)) return;
    if (self.rootView.superview == window) return;
    [self.rootView removeFromSuperview];

    IDCPassthroughView *root = [[IDCPassthroughView alloc] initWithFrame:window.bounds];
    root.backgroundColor = UIColor.clearColor;
    root.userInteractionEnabled = YES;
    root.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    __weak IDCConsoleController *weakSelf = self;
    root.layoutHandler = ^{ [weakSelf layoutConsole]; };

    // Floating "Console" button, shown while the game is paused.
    UIButton *consoleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *buttonConfig = [UIButtonConfiguration filledButtonConfiguration];
    buttonConfig.title = @"控制台";
    buttonConfig.image = [UIImage systemImageNamed:@"terminal"];
    buttonConfig.imagePadding = 6;
    buttonConfig.cornerStyle = UIButtonConfigurationCornerStyleCapsule;
    buttonConfig.baseBackgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
    buttonConfig.baseForegroundColor = UIColor.whiteColor;
    consoleButton.configuration = buttonConfig;
    [consoleButton addTarget:self action:@selector(toggleConsole:)
            forControlEvents:UIControlEventTouchUpInside];
    consoleButton.frame = CGRectMake(14, window.bounds.size.height - 52, 108, 38);
    consoleButton.autoresizingMask = UIViewAutoresizingFlexibleRightMargin |
        UIViewAutoresizingFlexibleTopMargin;
    consoleButton.hidden = YES;

    // Main panel: system blur material, adapts to light/dark mode.
    UIVisualEffectView *panel = [[UIVisualEffectView alloc] initWithEffect:
        [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    panel.clipsToBounds = YES;
    panel.tag = IDCInteractiveTag;
    panel.hidden = YES;
    UIView *host = panel.contentView;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.text = @"控制台";
    title.textColor = UIColor.labelColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [host addSubview:title];

    UILabel *status = [[UILabel alloc] initWithFrame:CGRectZero];
    status.textColor = UIColor.secondaryLabelColor;
    status.textAlignment = NSTextAlignmentCenter;
    status.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    [host addSubview:status];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"完成" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    close.contentHorizontalAlignment = UIControlContentHorizontalAlignmentRight;
    [close addTarget:self action:@selector(closeConsole:)
        forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:close];

    UISegmentedControl *tabs = [[UISegmentedControl alloc] initWithItems:
        @[@"命令", @"道具", @"饰品", @"卡牌", @"符文", @"药丸"]];
    tabs.selectedSegmentIndex = 0;
    [tabs setTitleTextAttributes:@{NSFontAttributeName:
        [UIFont systemFontOfSize:13 weight:UIFontWeightMedium]} forState:UIControlStateNormal];
    [tabs addTarget:self action:@selector(tabChanged:) forControlEvents:UIControlEventValueChanged];
    [host addSubview:tabs];

    // Command tab: output + suggestions.
    UITextView *output = [[UITextView alloc] initWithFrame:CGRectZero];
    output.backgroundColor = UIColor.tertiarySystemFillColor;
    output.textColor = UIColor.labelColor;
    output.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    output.editable = NO;
    output.selectable = YES;
    output.layer.cornerRadius = 12;
    output.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    output.text = @"Isaac Debug Console iOS 0.4.0\n"
                   @"输入 help 查看全部命令（命令本身保持英文），输入时会显示联想建议。\n"
                   @"按 ` 键打开并暂停游戏，再按 ` 或 Esc 关闭。\n"
                   @"切换到上方「道具 / 饰品 / 卡牌 / 符文 / 药丸」，点图标即可直接生成。\n";
    [host addSubview:output];

    UITableView *suggestionsTable = [[UITableView alloc] initWithFrame:CGRectZero
                                                                 style:UITableViewStylePlain];
    suggestionsTable.backgroundColor = UIColor.tertiarySystemFillColor;
    suggestionsTable.separatorColor = UIColor.separatorColor;
    suggestionsTable.rowHeight = 36;
    suggestionsTable.dataSource = self;
    suggestionsTable.delegate = self;
    suggestionsTable.layer.cornerRadius = 12;
    suggestionsTable.hidden = YES;
    [host addSubview:suggestionsTable];

    // Grid tabs: icon on top, name below.
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumLineSpacing = 10;
    layout.minimumInteritemSpacing = 10;
    layout.itemSize = CGSizeMake(80, 114);
    UICollectionView *grid = [[UICollectionView alloc] initWithFrame:CGRectZero
                                                collectionViewLayout:layout];
    grid.backgroundColor = UIColor.clearColor;
    grid.alwaysBounceVertical = YES;
    grid.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    grid.dataSource = self;
    grid.delegate = self;
    [grid registerClass:IDCItemCell.class forCellWithReuseIdentifier:@"Item"];
    grid.hidden = YES;
    [host addSubview:grid];

    // Toast: shows what was run, keeping the original English command.
    UIView *toastView = [[UIView alloc] initWithFrame:CGRectZero];
    toastView.backgroundColor = UIColor.secondarySystemBackgroundColor;
    toastView.layer.cornerRadius = 14;
    toastView.layer.shadowColor = UIColor.blackColor.CGColor;
    toastView.layer.shadowOpacity = 0.18;
    toastView.layer.shadowRadius = 8;
    toastView.layer.shadowOffset = CGSizeMake(0, 2);
    toastView.alpha = 0;
    toastView.hidden = YES;
    toastView.userInteractionEnabled = NO;
    UILabel *toastLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    toastLabel.numberOfLines = 3;
    toastLabel.textColor = UIColor.labelColor;
    toastLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [toastView addSubview:toastLabel];
    [host addSubview:toastView];

    // Bottom bar.
    UITextField *input = [[UITextField alloc] initWithFrame:CGRectZero];
    input.backgroundColor = UIColor.tertiarySystemFillColor;
    input.textColor = UIColor.labelColor;
    input.tintColor = UIColor.systemBlueColor;
    input.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    input.layer.cornerRadius = 10;
    input.placeholder = @"输入命令…";
    input.autocorrectionType = UITextAutocorrectionTypeNo;
    input.autocapitalizationType = UITextAutocapitalizationTypeNone;
    input.spellCheckingType = UITextSpellCheckingTypeNo;
    input.returnKeyType = UIReturnKeyGo;
    input.clearButtonMode = UITextFieldViewModeWhileEditing;
    input.delegate = self;
    [input addTarget:self action:@selector(inputChanged:)
       forControlEvents:UIControlEventEditingChanged];
    UIView *padding = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, 1)];
    input.leftView = padding;
    input.leftViewMode = UITextFieldViewModeAlways;
    [host addSubview:input];

    UIButton *previous = [self symbolButtonWithSymbol:@"arrow.up" label:@"上一条命令"
                                               action:@selector(previousHistory:)];
    UIButton *next = [self symbolButtonWithSymbol:@"arrow.down" label:@"下一条命令"
                                           action:@selector(nextHistory:)];
    UIButton *keyboard = [self symbolButtonWithSymbol:@"keyboard.chevron.compact.down"
                                                label:@"收起键盘"
                                               action:@selector(toggleKeyboard:)];
    UIButton *run = [UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *runConfig = [UIButtonConfiguration filledButtonConfiguration];
    runConfig.title = @"运行";
    runConfig.cornerStyle = UIButtonConfigurationCornerStyleMedium;
    run.configuration = runConfig;
    [run addTarget:self action:@selector(runCommand:) forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:previous];
    [host addSubview:next];
    [host addSubview:keyboard];
    [host addSubview:run];

    [root addSubview:consoleButton];
    [root addSubview:panel];
    [window addSubview:root];
    self.rootView = root;
    self.consoleButton = consoleButton;
    self.panel = panel;
    self.titleLabel = title;
    self.statusLabel = status;
    self.closeButton = close;
    self.tabControl = tabs;
    self.outputView = output;
    self.suggestionsTable = suggestionsTable;
    self.grid = grid;
    self.toastView = toastView;
    self.toastLabel = toastLabel;
    self.inputField = input;
    self.previousButton = previous;
    self.nextButton = next;
    self.keyboardButton = keyboard;
    self.runButton = run;
    [self updateKeyboardButton];
    [self layoutConsole];
    [self updateSuggestions];
    IDCLog(@"console overlay attached to Isaac window");
}

#pragma mark - Layout

- (void)layoutConsole {
    if (!self.rootView || !self.panel) return;
    CGFloat width = self.rootView.bounds.size.width;
    IDCPanelRect rect = IDCFullPanel(width, self.rootView.bounds.size.height, self.keyboardOverlap);
    CGFloat panelWidth = rect.width, panelHeight = rect.height;
    self.panel.frame = CGRectMake(rect.x, rect.y, panelWidth, panelHeight);
    UIEdgeInsets safe = self.rootView.safeAreaInsets;
    CGFloat left = MAX(16, safe.left + 12), right = MAX(16, safe.right + 12);
    CGFloat top = MAX(10, safe.top + 4);
    CGFloat uiScale = NSClassFromString(@"NSApplication") ? MIN(1.6, MAX(1.15, width / 900)) : 1;
    CGFloat controlHeight = 40 * uiScale;
    BOOL gridMode = self.tab != IDCTabCommand;

    self.outputView.font = [UIFont monospacedSystemFontOfSize:12 * uiScale weight:UIFontWeightRegular];
    self.inputField.font = [UIFont monospacedSystemFontOfSize:14 * uiScale weight:UIFontWeightRegular];
    self.suggestionsTable.rowHeight = 36 * uiScale;

    // Header.
    CGFloat titleHeight = 22 * uiScale, statusHeight = 14 * uiScale;
    self.titleLabel.font = [UIFont systemFontOfSize:17 * uiScale weight:UIFontWeightSemibold];
    self.titleLabel.frame = CGRectMake(0, top, panelWidth, titleHeight);
    self.statusLabel.frame = CGRectMake(0, top + titleHeight, panelWidth, statusHeight);
    CGFloat closeWidth = 64 * uiScale;
    self.closeButton.frame = CGRectMake(panelWidth - right - closeWidth, top, closeWidth, titleHeight + statusHeight);
    self.tabControl.frame = CGRectMake(left, top + titleHeight + statusHeight + 8,
                                       MAX(1, panelWidth - left - right), 32 * uiScale);
    CGFloat contentTop = CGRectGetMaxY(self.tabControl.frame) + 10;

    // Bottom bar.
    CGFloat bottomY = MAX(contentTop,
        panelHeight - controlHeight - (self.keyboardOverlap > 0 ? 8 : safe.bottom + 8));
    CGFloat iconWidth = controlHeight;
    CGFloat runWidth = 64 * uiScale;
    self.previousButton.hidden = gridMode;
    self.nextButton.hidden = gridMode;
    self.runButton.hidden = gridMode;
    if (gridMode) {
        self.keyboardButton.frame = CGRectMake(panelWidth - right - iconWidth, bottomY,
                                               iconWidth, controlHeight);
        self.inputField.frame = CGRectMake(left, bottomY,
            MAX(1, CGRectGetMinX(self.keyboardButton.frame) - left - 8), controlHeight);
    } else {
        self.previousButton.frame = CGRectMake(left, bottomY, iconWidth, controlHeight);
        self.nextButton.frame = CGRectMake(left + iconWidth + 6, bottomY, iconWidth, controlHeight);
        self.runButton.frame = CGRectMake(panelWidth - runWidth - right, bottomY, runWidth, controlHeight);
        self.keyboardButton.frame = CGRectMake(CGRectGetMinX(self.runButton.frame) - iconWidth - 6,
                                               bottomY, iconWidth, controlHeight);
        CGFloat inputX = CGRectGetMaxX(self.nextButton.frame) + 6;
        self.inputField.frame = CGRectMake(inputX, bottomY,
            MAX(1, CGRectGetMinX(self.keyboardButton.frame) - inputX - 6), controlHeight);
    }

    // Content.
    self.outputView.hidden = gridMode;
    self.grid.hidden = !gridMode;
    if (gridMode) {
        self.suggestionsTable.hidden = YES;
        CGFloat gridHeight = MAX(1, bottomY - 8 - contentTop);
        self.grid.frame = CGRectMake(0, contentTop, panelWidth, gridHeight);
        [self updateGridLayoutForWidth:panelWidth left:left right:right];
    } else {
        CGFloat suggestionHeight = self.suggestions.count
            ? MIN(MIN(220, MAX(0, (bottomY - contentTop) * .35)),
                  self.suggestions.count * self.suggestionsTable.rowHeight) : 0;
        CGFloat outputBottom = bottomY - 8 - suggestionHeight;
        self.outputView.frame = CGRectMake(left, contentTop, MAX(1, panelWidth - left - right),
                                           MAX(1, outputBottom - contentTop));
        self.suggestionsTable.frame = CGRectMake(left, CGRectGetMaxY(self.outputView.frame) + 4,
                                                  MAX(1, panelWidth - left - right), suggestionHeight);
        self.suggestionsTable.hidden = suggestionHeight <= 0;
    }

    // Toast sits just above the bottom bar.
    CGFloat toastHeight = 66;
    CGFloat toastWidth = MAX(1, panelWidth - left - right);
    self.toastView.frame = CGRectMake(left, MAX(contentTop, bottomY - 8 - toastHeight),
                                      toastWidth, toastHeight);
    self.toastLabel.frame = CGRectInset(self.toastView.bounds, 14, 8);
    [self.panel.contentView bringSubviewToFront:self.toastView];
}

- (void)updateGridLayoutForWidth:(CGFloat)panelWidth left:(CGFloat)left right:(CGFloat)right {
    if (fabs(panelWidth - self.lastGridWidth) < 0.5) return;
    self.lastGridWidth = panelWidth;
    UICollectionViewFlowLayout *layout = (UICollectionViewFlowLayout *)self.grid.collectionViewLayout;
    CGFloat spacing = 10;
    CGFloat usable = MAX(1, panelWidth - left - right);
    NSInteger columns = MAX(3, (NSInteger)floor((usable + spacing) / (84 + spacing)));
    CGFloat itemWidth = floor((usable - spacing * (columns - 1)) / columns);
    layout.itemSize = CGSizeMake(itemWidth, itemWidth + 36);
    layout.sectionInset = UIEdgeInsetsMake(2, left, 16, right);
    [layout invalidateLayout];
}

#pragma mark - Tick / open / close

- (void)tick:(NSTimer *)timer {
    (void)timer;
    [self attachIfNeeded];
    IDCNativeSnapshot *snapshot = [self.bridge refreshSnapshot];
    BOOL available = snapshot.supportedBuild && snapshot.inGame && snapshot.presentationVisible &&
        snapshot.pauseStateAvailable;
    self.consoleButton.hidden = !(available && snapshot.paused);
    self.statusLabel.text = snapshot.inGame
        ? [NSString stringWithFormat:@"%@ · 种子 %08X", snapshot.paused ? @"已暂停" : @"游戏中",
           snapshot.runSeed]
        : @"没有进行中的游戏";
    if ((!available || !snapshot.paused) && !self.panel.hidden) {
        [self.bridge cancelConsolePauseOwnership]; [self closeConsole:nil];
    }
    if (!self.panel.hidden) { [self.rootView bringSubviewToFront:self.panel]; [self layoutConsole]; }
}

- (void)toggleConsole:(UIButton *)sender {
    (void)sender;
    if (self.panel.hidden) {
        UIWindow *window = [self gameWindow];
        if (!window || window.rootViewController.presentedViewController ||
            ![self.bridge beginConsolePause]) return;
        self.panel.hidden = NO;
        [window bringSubviewToFront:self.rootView];
        [self.rootView bringSubviewToFront:self.panel];
        [self layoutConsole];
        if (self.tab == IDCTabCommand) [self.inputField becomeFirstResponder];
    } else {
        [self closeConsole:nil];
    }
}

- (BOOL)hasOtherTextInput:(UIView *)view {
    if (view.isFirstResponder && view != self.inputField &&
        ![view isKindOfClass:NSClassFromString(@"AAPLOpenGLView")] &&
        [view conformsToProtocol:@protocol(UITextInput)]) return YES;
    for (UIView *child in view.subviews) {
        if ([self hasOtherTextInput:child]) return YES;
    }
    return NO;
}

- (BOOL)toggleFromKeyboard {
    [self attachIfNeeded];
    UIWindow *window = [self gameWindow];
    if (!self.panel || !window.isKeyWindow || window.rootViewController.presentedViewController) return NO;
    if (!self.panel.hidden) {
        return [self closeFromKeyboard];
    }
    if ([self hasOtherTextInput:window]) return NO;
    [self toggleConsole:nil];
    return !self.panel.hidden;
}

- (BOOL)closeFromKeyboard {
    UIWindow *window = [self gameWindow];
    if (!self.panel || self.panel.hidden || !window.isKeyWindow ||
        window.rootViewController.presentedViewController ||
        UIApplication.sharedApplication.applicationState != UIApplicationStateActive) return NO;
    [self closeConsole:nil];
    return YES;
}

- (void)escapeCloseRequested:(NSNotification *)notification {
    // Synchronous optional coordination with Isaac Fixes. Whichever key
    // monitor runs first owns Escape, including its repeat and key-up events.
    if ([notification.object isKindOfClass:NSMutableDictionary.class] && [self closeFromKeyboard])
        ((NSMutableDictionary *)notification.object)[@"handled"] = @YES;
}

- (void)closeConsole:(UIButton *)sender {
    (void)sender;
    self.panel.hidden = YES;
    self.keyboardOverlap = 0;
    [self.inputField resignFirstResponder];
    [self.bridge endConsolePause];
    [self layoutConsole];
}

- (void)suspendConsole {
    [self.bridge cancelConsolePauseOwnership];
    [self closeConsole:nil];
}

#pragma mark - Output and commands

- (void)appendLine:(NSString *)line {
    if (!line.length) return;
    NSString *existing = self.outputView.text ?: @"";
    self.outputView.text = [existing stringByAppendingFormat:@"%@%@\n",
                            existing.length && ![existing hasSuffix:@"\n"] ? @"\n" : @"", line];
    NSRange end = NSMakeRange(self.outputView.text.length, 0);
    [self.outputView scrollRangeToVisible:end];
}

// Runs one command string (always the original English command) and logs it.
- (IDCCommandResult *)performInput:(NSString *)input {
    [self appendLine:[@"> " stringByAppendingString:input]];
    if (![self.history.lastObject isEqualToString:input]) [self.history addObject:input];
    self.historyIndex = self.history.count;
    IDCCommandResult *result = [self.engine executeInput:input];
    if (result.action == IDCCommandActionClear) {
        self.outputView.text = @"";
    } else if (result.action == IDCCommandActionClose) {
        [self closeConsole:nil];
    } else if (result.action == IDCCommandActionHistory) {
        if (!self.history.count) {
            [self appendLine:@"历史记录为空。"];
        } else {
            NSMutableArray<NSString *> *lines = [NSMutableArray array];
            [self.history enumerateObjectsUsingBlock:
                ^(NSString *command, NSUInteger index, BOOL *stop) {
                (void)stop;
                [lines addObject:[NSString stringWithFormat:@"%lu  %@",
                                  (unsigned long)(index + 1), command]];
            }];
            [self appendLine:[lines componentsJoinedByString:@"\n"]];
        }
    } else if (result.output.length) {
        [self appendLine:result.output];
    }
    return result;
}

- (void)runCommand:(UIButton *)sender {
    (void)sender;
    if (self.tab != IDCTabCommand) return;
    NSString *input = [self.inputField.text stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!input.length) return;
    [self performInput:input];
    self.inputField.text = @"";
    [self updateSuggestions];
}

- (void)previousHistory:(UIButton *)sender {
    (void)sender;
    if (!self.history.count) return;
    self.historyIndex = MAX(0, self.historyIndex - 1);
    self.inputField.text = self.history[(NSUInteger)self.historyIndex];
    [self updateSuggestions];
}

- (void)nextHistory:(UIButton *)sender {
    (void)sender;
    if (!self.history.count) return;
    self.historyIndex = MIN((NSInteger)self.history.count, self.historyIndex + 1);
    self.inputField.text = self.historyIndex < (NSInteger)self.history.count
        ? self.history[(NSUInteger)self.historyIndex] : @"";
    [self updateSuggestions];
}

- (void)updateKeyboardButton {
    NSString *symbol = self.keyboardVisible ? @"keyboard.chevron.compact.down" : @"keyboard";
    [self.keyboardButton setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    self.keyboardButton.accessibilityLabel = self.keyboardVisible ? @"收起键盘" : @"显示键盘";
}

- (void)toggleKeyboard:(UIButton *)sender {
    (void)sender;
    if (self.inputField.isFirstResponder) {
        [self.inputField resignFirstResponder];
        self.keyboardVisible = NO;
    } else {
        [self.inputField becomeFirstResponder];
        self.keyboardVisible = YES;
    }
    [self updateKeyboardButton];
}

#pragma mark - Tabs and grid

- (NSArray<IDCItemRecord *> *)recordsForCurrentTab {
    switch (self.tab) {
        case IDCTabItems: return [self.catalog collectibleRecords];
        case IDCTabTrinkets: return [self.catalog trinketRecords];
        case IDCTabCards: return [self.catalog pocketRecordsOfKind:@"card"];
        case IDCTabRunes: return [self.catalog pocketRecordsOfKind:@"rune"];
        case IDCTabPills: return [self.catalog pillRecords];
        default: return @[];
    }
}

- (NSString *)commandForRecord:(IDCItemRecord *)record {
    long identifier = (long)record.identifier;
    switch (self.tab) {
        case IDCTabItems: return [NSString stringWithFormat:@"spawnitem %ld", identifier];
        case IDCTabTrinkets: return [NSString stringWithFormat:@"spawntrinket %ld", identifier];
        case IDCTabCards: return [NSString stringWithFormat:@"spawncard %ld", identifier];
        case IDCTabRunes: return [NSString stringWithFormat:@"spawnrune %ld", identifier];
        case IDCTabPills: return [NSString stringWithFormat:@"spawnpill effect %ld", identifier];
        default: return @"";
    }
}

- (void)tabChanged:(UISegmentedControl *)sender {
    self.tab = (IDCTab)sender.selectedSegmentIndex;
    self.inputField.text = @"";
    if (self.tab == IDCTabCommand) {
        self.inputField.placeholder = @"输入命令…";
        self.inputField.returnKeyType = UIReturnKeyGo;
        [self updateSuggestions];
    } else {
        self.inputField.placeholder = @"搜索名称或 ID…";
        self.inputField.returnKeyType = UIReturnKeyDone;
        [self.inputField resignFirstResponder];
        [self applyFilter];
    }
    [self layoutConsole];
}

- (void)applyFilter {
    NSArray<IDCItemRecord *> *base = [self recordsForCurrentTab];
    NSString *query = [[self.inputField.text stringByTrimmingCharactersInSet:
        NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseString];
    if (!query.length) {
        self.gridRecords = base;
    } else {
        self.gridRecords = [base filteredArrayUsingPredicate:
            [NSPredicate predicateWithBlock:^BOOL(IDCItemRecord *record, NSDictionary *bindings) {
            (void)bindings;
            NSString *identifier = [NSString stringWithFormat:@"%ld", (long)record.identifier];
            return [identifier hasPrefix:query] ||
                   [record.name.lowercaseString containsString:query] ||
                   [record.nameZH containsString:query];
        }]];
    }
    [self.grid reloadData];
    [self.grid setContentOffset:CGPointZero animated:NO];
}

- (void)inputChanged:(UITextField *)field {
    (void)field;
    if (self.tab == IDCTabCommand) [self updateSuggestions]; else [self applyFilter];
}

- (void)updateSuggestions {
    if (self.tab != IDCTabCommand) return;
    self.suggestions = [self.engine suggestionsForInput:self.inputField.text ?: @"" limit:64];
    [self.suggestionsTable reloadData];
    [self layoutConsole];
}

- (void)showToastTitle:(NSString *)title command:(NSString *)command detail:(NSString *)detail {
    NSMutableString *text = [NSMutableString stringWithFormat:@"%@\n%@", title, command];
    NSString *firstLine = [[detail componentsSeparatedByString:@"\n"] firstObject];
    if (firstLine.length) [text appendFormat:@"\n%@", firstLine];
    self.toastLabel.text = text;
    self.toastView.hidden = NO;
    [self.panel.contentView bringSubviewToFront:self.toastView];
    [UIView animateWithDuration:0.18 animations:^{ self.toastView.alpha = 1; }];
    NSInteger generation = ++self.toastGeneration;
    __weak IDCConsoleController *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        IDCConsoleController *strongSelf = weakSelf;
        if (!strongSelf || generation != strongSelf.toastGeneration) return;
        [UIView animateWithDuration:0.25 animations:^{ strongSelf.toastView.alpha = 0; }
                         completion:^(BOOL finished) {
            (void)finished;
            if (generation == strongSelf.toastGeneration) strongSelf.toastView.hidden = YES;
        }];
    });
}

#pragma mark - Text field

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (self.tab == IDCTabCommand) {
        [self runCommand:nil];
    } else {
        [textField resignFirstResponder];
    }
    return NO;
}

#pragma mark - Suggestions table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return self.suggestions.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"Suggestion";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                             reuseIdentifier:identifier];
    cell.backgroundColor = UIColor.clearColor;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    cell.textLabel.text = self.suggestions[(NSUInteger)indexPath.row].displayText;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    IDCCommandSuggestion *suggestion = self.suggestions[(NSUInteger)indexPath.row];
    self.inputField.text = suggestion.replacementText;
    [self updateSuggestions];
    [self.inputField becomeFirstResponder];
}

#pragma mark - Grid data source / delegate

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    (void)collectionView; (void)section;
    return self.gridRecords.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    IDCItemCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"Item"
                                                                  forIndexPath:indexPath];
    IDCItemRecord *record = self.gridRecords[(NSUInteger)indexPath.item];
    UIImage *icon = [self.catalog iconForRecord:record];
    if (icon) {
        cell.iconView.image = icon;
    } else {
        cell.iconView.image = [UIImage systemImageNamed:@"shippingbox"];
    }
    cell.nameLabel.text = record.displayName;
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView
didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    IDCItemRecord *record = self.gridRecords[(NSUInteger)indexPath.item];
    NSString *command = [self commandForRecord:record];
    if (!command.length) return;
    UIImpactFeedbackGenerator *haptic =
        [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [haptic impactOccurred];
    IDCCommandResult *result = [self performInput:command];
    [self showToastTitle:[NSString stringWithFormat:@"已执行：%@", record.displayName]
                 command:command
                  detail:result.output];
}

#pragma mark - Keyboard

- (void)keyboardFrameChanged:(NSNotification *)notification {
    UIWindow *window = [self gameWindow];
    if (!window) return;
    CGRect screenFrame = [notification.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect localFrame = [window convertRect:screenFrame fromWindow:nil];
    self.keyboardOverlap = MAX(0, CGRectGetMaxY(window.bounds) - CGRectGetMinY(localFrame));
    self.keyboardVisible = self.keyboardOverlap > 1;
    [self updateKeyboardButton];
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey]
        doubleValue];
    [UIView animateWithDuration:duration animations:^{ [self layoutConsole]; }];
}

- (void)keyboardWillHide:(NSNotification *)notification {
    NSTimeInterval duration = [notification.userInfo[UIKeyboardAnimationDurationUserInfoKey]
        doubleValue];
    self.keyboardOverlap = 0;
    self.keyboardVisible = NO;
    [self updateKeyboardButton];
    [UIView animateWithDuration:duration animations:^{ [self layoutConsole]; }];
}

@end
