// Host-only regression executable (macOS Foundation; never inject this file).
// clang -fobjc-arc -fblocks -framework Foundation Validation/GuardTests.m -o /tmp/SettingsShelfGuardTests
// /tmp/SettingsShelfGuardTests
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "../Sources/HaogeSettingsShelfPreferences.h"
static BOOL haoge_settingsshelf_testRepair, haoge_settingsshelf_testUpdate;
static BOOL haoge_settingsshelf_testPreferenceBool(NSString *key) {
    if ([key isEqualToString:@"suppressBatteryServiceWarnings"]) return haoge_settingsshelf_testRepair;
    if ([key isEqualToString:@"suppressSoftwareUpdatePrompt"]) return haoge_settingsshelf_testUpdate;
    return NO;
}
#define HAOGE_SETTINGSSHELF_GUARD_TESTING 1
#define haoge_settingsshelf_preferenceBool haoge_settingsshelf_testPreferenceBool
#import "../Sources/HaogeSettingsShelfGuards.m"
#undef haoge_settingsshelf_preferenceBool

static NSUInteger haoge_settingsshelf_hookCalls, haoge_settingsshelf_originalCalls;
void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls, selector);
    if (!method) abort();
    *original = method_setImplementation(method, replacement);
    ++haoge_settingsshelf_hookCalls;
}
@interface BatteryUIResourceClass : NSObject
+ (int)genuineBatteryStatus;
+ (int)getBatteryHealthServiceState;
+ (id)getBatteryServiceSuggestion;
+ (id)getBatteryServiceSuggestion:(id)value;
@end
@implementation BatteryUIResourceClass
+ (int)genuineBatteryStatus { ++haoge_settingsshelf_originalCalls; return -7; }
+ (int)getBatteryHealthServiceState { ++haoge_settingsshelf_originalCalls; return 42; }
+ (id)getBatteryServiceSuggestion { ++haoge_settingsshelf_originalCalls; return @"service"; }
+ (id)getBatteryServiceSuggestion:(id)value { ++haoge_settingsshelf_originalCalls; return value; }
@end
@interface SystemHealthUI : NSObject
- (id)getCurrentSystemHealthInfoSpecifiers;
- (BOOL)isVaildCAA:(id)value;
// Deliberately incompatible ABI: this spelling must remain unhooked.
- (double)isValidCAA:(id)value;
@end
@implementation SystemHealthUI
- (id)getCurrentSystemHealthInfoSpecifiers { ++haoge_settingsshelf_originalCalls; return @[@"health"]; }
- (BOOL)isVaildCAA:(id)value { (void)value; ++haoge_settingsshelf_originalCalls; return NO; }
- (double)isValidCAA:(id)value { (void)value; return 3.5; }
@end
@interface FLGroupViewModelImpl : NSObject
@property(nonatomic,strong) NSMutableArray *items;
- (void)addItem:(id)item;
@end
@implementation FLGroupViewModelImpl
- (instancetype)init { if ((self = [super init])) _items = [NSMutableArray array]; return self; }
- (void)addItem:(id)item { ++haoge_settingsshelf_originalCalls; [self.items addObject:item]; }
@end
@interface HaogeSettingsShelfGuardTestRow : NSObject
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic,copy) NSString *name;
@property(nonatomic) NSInteger cellType;
@property(nonatomic,strong) NSDictionary *values;
- (id)propertyForKey:(NSString *)key;
@end
@implementation HaogeSettingsShelfGuardTestRow
- (id)propertyForKey:(NSString *)key { return self.values[key]; }
@end
static id haoge_settingsshelf_row(NSString *identifier, NSInteger type, NSDictionary *values) {
    HaogeSettingsShelfGuardTestRow *row = [HaogeSettingsShelfGuardTestRow new];
    row.identifier = identifier; row.cellType = type; row.values = values; return row;
}
static NSUInteger haoge_settingsshelf_assertions;
#define VERIFY(x) do { ++haoge_settingsshelf_assertions; if (!(x)) { NSLog(@"FAILED line %d: %s", __LINE__, #x); return 1; } } while (0)
int main(void) { @autoreleasepool {
    id group = haoge_settingsshelf_row(@"GROUP", 0, @{@"footerText":@"keep mixed footer"});
    id battery = haoge_settingsshelf_row(@"IMPORTANT_BATTERY_MESSAGE", 1, @{});
    id update = haoge_settingsshelf_row(@"prompt", 1, @{@"bundle":@"SoftwareUpdate"});
    id wifi = haoge_settingsshelf_row(@"WIFI", 1, @{});
    id own = haoge_settingsshelf_row(@"com.haoge.settingsshelf.category.apps", 1, @{@"title":@"SoftwareUpdate"});
    NSArray *raw = @[group, battery, update, wifi, own];
    VERIFY(haoge_settingsshelf_guardRowsForFlags(raw, NO, NO) == raw);
    VERIFY(haoge_settingsshelf_guardRowsForFlags(nil, YES, YES) == nil);
    VERIFY(([haoge_settingsshelf_guardRowsForFlags(raw, YES, NO) isEqualToArray:@[group, update, wifi, own]]));
    VERIFY(([haoge_settingsshelf_guardRowsForFlags(raw, NO, YES) isEqualToArray:@[group, battery, wifi, own]]));
    VERIFY(([haoge_settingsshelf_guardRowsForFlags(raw, YES, YES) isEqualToArray:@[group, wifi, own]]));
    VERIFY(raw.count == 5); // Never mutate the source/live table backing array.
    NSArray *section = @[group, battery];
    VERIFY(haoge_settingsshelf_guardRowsForFlags(section, YES, NO).count == 0);
    VERIFY(haoge_settingsshelf_guardRowsForFlags(@[group], YES, YES).count == 1);
    VERIFY(haoge_settingsshelf_guardRowsForFlags(@[wifi], YES, YES)[0] == wifi);
    HaogeSettingsShelfGuardTestRow *named = haoge_settingsshelf_row(@"generic", 1, @{});
    named.name = @"iOS 99 available";
    VERIFY(haoge_settingsshelf_guardRowsForFlags(@[named], NO, YES).count == 0);
    named.name = @"iOS version";
    VERIFY(haoge_settingsshelf_guardRowsForFlags(@[named], NO, YES).count == 1);

    SystemHealthUI *health = [SystemHealthUI new];
    FLGroupViewModelImpl *followup = [FLGroupViewModelImpl new];
    haoge_settingsshelf_installGuards();
    VERIFY(haoge_settingsshelf_hookCalls == 7);
    VERIFY(haoge_settingsshelf_guardRootRows(raw) == raw);
    VERIFY([BatteryUIResourceClass genuineBatteryStatus] == -7);
    VERIFY([BatteryUIResourceClass getBatteryHealthServiceState] == 42);
    VERIFY([[BatteryUIResourceClass getBatteryServiceSuggestion] isEqual:@"service"]);
    VERIFY([BatteryUIResourceClass getBatteryServiceSuggestion:raw] == raw);
    VERIFY([[health getCurrentSystemHealthInfoSpecifiers] isEqual:@[@"health"]]);
    VERIFY([health isVaildCAA:nil] == NO);
    VERIFY([health isValidCAA:nil] == 3.5);
    [followup addItem:@{@"title":@"Battery service"}];
    VERIFY(followup.items.count == 1);
    haoge_settingsshelf_testRepair = YES;
    haoge_settingsshelf_testUpdate = YES;
    haoge_settingsshelf_installGuards();
    NSUInteger calls = haoge_settingsshelf_originalCalls;
    VERIFY([BatteryUIResourceClass genuineBatteryStatus] == 0);
    VERIFY([BatteryUIResourceClass getBatteryHealthServiceState] == 0);
    VERIFY([BatteryUIResourceClass getBatteryServiceSuggestion] == nil);
    VERIFY([BatteryUIResourceClass getBatteryServiceSuggestion:raw] == nil);
    VERIFY([health getCurrentSystemHealthInfoSpecifiers] == nil);
    VERIFY([health isVaildCAA:nil] == YES);
    VERIFY([health isValidCAA:nil] == 3.5);
    [followup addItem:@{@"title":@"Battery service"}];
    VERIFY(followup.items.count == 1);
    VERIFY(haoge_settingsshelf_originalCalls == calls);
    [followup addItem:@{@"title":@"Account notice"}];
    VERIFY(followup.items.count == 2);
    VERIFY(([haoge_settingsshelf_guardRootRows(raw) isEqualToArray:@[group, wifi, own]]));
    for (NSUInteger i = 0; i < 100; ++i) {
        haoge_settingsshelf_testRepair = NO; haoge_settingsshelf_testUpdate = NO;
        haoge_settingsshelf_installGuards();
        VERIFY(haoge_settingsshelf_guardRootRows(raw) == raw);
        VERIFY([BatteryUIResourceClass genuineBatteryStatus] == -7);
        VERIFY([[BatteryUIResourceClass getBatteryServiceSuggestion] isEqual:@"service"]);
        VERIFY([health isVaildCAA:nil] == NO);
        haoge_settingsshelf_testRepair = YES;
        haoge_settingsshelf_installGuards();
        VERIFY([BatteryUIResourceClass genuineBatteryStatus] == 0);
        VERIFY(haoge_settingsshelf_hookCalls == 7);
    }
    haoge_settingsshelf_testRepair = NO;
    haoge_settingsshelf_testUpdate = YES;
    haoge_settingsshelf_installGuards();
    VERIFY([BatteryUIResourceClass getBatteryHealthServiceState] == 42);
    VERIFY(([haoge_settingsshelf_guardRootRows(raw) isEqualToArray:@[group, battery, wifi, own]]));
    haoge_settingsshelf_testUpdate = NO;
    haoge_settingsshelf_installGuards();
    VERIFY(haoge_settingsshelf_guardRootRows(raw) == raw);
    VERIFY([BatteryUIResourceClass getBatteryServiceSuggestion:raw] == raw);
    VERIFY([[health getCurrentSystemHealthInfoSpecifiers] isEqual:@[@"health"]]);
    [followup addItem:@{@"title":@"Battery service"}];
    VERIFY(followup.items.count == 3);
    VERIFY(haoge_settingsshelf_hookCalls == 7);
    NSLog(@"PASS %lu guard assertions (host mock runtime, NOT iOS)", (unsigned long)haoge_settingsshelf_assertions);
    return 0;
} }
