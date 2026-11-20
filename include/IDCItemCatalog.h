
#import <Foundation/Foundation.h>

#if __has_include(<UIKit/UIKit.h>)
#import <UIKit/UIKit.h>
#define IDC_ITEM_CATALOG_HAS_UIKIT 1
#else
#define IDC_ITEM_CATALOG_HAS_UIKIT 0
#endif

NS_ASSUME_NONNULL_BEGIN

@interface IDCItemRecord : NSObject
@property(nonatomic) NSInteger identifier;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *kind;
// Icon file name from items.xml (e.g. Collectibles_001_TheSadOnion.png).
@property(nonatomic, copy, nullable) NSString *gfx;
// Chinese name, if the translation table has one.
@property(nonatomic, copy, nullable) NSString *nameZH;
// Chinese name when available, otherwise the English name.
@property(nonatomic, readonly) NSString *displayName;
@end

@interface IDCItemCatalog : NSObject
@property(nonatomic, readonly) NSUInteger count;
@property(nonatomic, readonly) NSUInteger trinketCount;
@property(nonatomic, readonly) NSUInteger pocketItemCount;
@property(nonatomic, readonly) NSUInteger pillEffectCount;

- (nullable IDCItemRecord *)recordForIdentifier:(NSInteger)identifier;
- (nullable IDCItemRecord *)recordForSpecifier:(NSString *)specifier
                                          error:(NSString * _Nullable * _Nullable)error;
- (NSArray<IDCItemRecord *> *)recordsMatching:(NSString *)query limit:(NSUInteger)limit;

- (nullable IDCItemRecord *)trinketForSpecifier:(NSString *)specifier
                                           error:(NSString * _Nullable * _Nullable)error;
- (NSArray<IDCItemRecord *> *)trinketsMatching:(NSString *)query limit:(NSUInteger)limit;

- (nullable IDCItemRecord *)pocketItemForSpecifier:(NSString *)specifier
                                               kind:(nullable NSString *)kind
                                              error:(NSString * _Nullable * _Nullable)error;
- (NSArray<IDCItemRecord *> *)pocketItemsMatching:(NSString *)query
                                              kind:(nullable NSString *)kind
                                             limit:(NSUInteger)limit;

- (nullable IDCItemRecord *)pillEffectForSpecifier:(NSString *)specifier
                                              error:(NSString * _Nullable * _Nullable)error;
- (NSArray<IDCItemRecord *> *)pillEffectsMatching:(NSString *)query limit:(NSUInteger)limit;

// Full lists, sorted by ID, for the icon grid.
- (NSArray<IDCItemRecord *> *)collectibleRecords;
- (NSArray<IDCItemRecord *> *)trinketRecords;
- (NSArray<IDCItemRecord *> *)pocketRecordsOfKind:(NSString *)kind; // @"card" or @"rune"
- (NSArray<IDCItemRecord *> *)pillRecords;

#if IDC_ITEM_CATALOG_HAS_UIKIT
// Icon read at runtime from the installed game. nil if not found.
- (nullable UIImage *)iconForRecord:(IDCItemRecord *)record;
#endif

@end

NS_ASSUME_NONNULL_END
