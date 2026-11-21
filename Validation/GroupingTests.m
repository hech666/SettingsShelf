#import <Foundation/Foundation.h>
#import "HaogeSettingsShelfGrouping.h"
#import "HaogeSettingsShelfSnapshot.h"

@interface HaogeSettingsShelfTestEntry : NSObject
@property(nonatomic,copy) NSString *identifier;
@property(nonatomic) NSInteger cellType;
@property(nonatomic,strong) NSDictionary *values;
- (id)propertyForKey:(NSString *)key;
@end
@implementation HaogeSettingsShelfTestEntry
- (id)propertyForKey:(NSString *)key { return self.values[key]; }
@end
static HaogeSettingsShelfTestEntry *haoge_settingsshelf_testEntry(NSString *identifier, NSInteger type, NSDictionary *values) {
    HaogeSettingsShelfTestEntry *e = [HaogeSettingsShelfTestEntry new]; e.identifier = identifier; e.cellType = type; e.values = values; return e;
}
static NSUInteger haoge_settingsshelf_assertions;
#define VERIFY(x) do { ++haoge_settingsshelf_assertions; if (!(x)) { NSLog(@"FAILED line %d: %s", __LINE__, #x); return 1; } } while(0)
int main(void) { @autoreleasepool {
    id systemGroup = haoge_settingsshelf_testEntry(@"WIRELESS_GROUP",0,@{});
    id wifi = haoge_settingsshelf_testEntry(@"WIFI",1,@{@"lazy-bundle":@"/System/Library/PreferenceBundles/WiFi.bundle"});
    id tweaksGroup = haoge_settingsshelf_testEntry(@"JAILBREAK_GROUP",0,@{});
    id tweak = haoge_settingsshelf_testEntry(@"kayoko",1,@{@"lazy-bundle":@"/var/jb/Library/PreferenceBundles/Kayoko.bundle",@"target":@"original-target"});
    id own = haoge_settingsshelf_testEntry(@"settingsshelf",1,@{@"lazy-bundle":@"/var/containers/Bundle/Application/.jbroot-test/Library/PreferenceBundles/HaogeSettingsShelfPrefs.bundle"});
    id appsGroup = haoge_settingsshelf_testEntry(@"THIRD_PARTY_GROUP",0,@{});
    id app = haoge_settingsshelf_testEntry(@"app",1,@{@"AppBundleID":@"com.thirdparty.test"});
    id navGroup = haoge_settingsshelf_testEntry(@"com.haoge.settingsshelf.category.group",0,@{});
    id nav1 = haoge_settingsshelf_testEntry(@"com.haoge.settingsshelf.category.tweaks",1,@{});
    id nav2 = haoge_settingsshelf_testEntry(@"com.haoge.settingsshelf.category.apps",1,@{});
    NSArray *nav = @[navGroup,nav1,nav2];
    NSArray *raw = @[systemGroup,wifi,tweaksGroup,tweak,own,appsGroup,app];
    HaogeSettingsShelfGroupingState *state = [HaogeSettingsShelfGroupingState new];
    VERIFY(haoge_settingsshelf_entryCategory(wifi)==0);
    VERIFY(haoge_settingsshelf_entryCategory(tweak)==1);
    VERIFY(haoge_settingsshelf_entryCategory(app)==2);
    VERIFY(haoge_settingsshelf_entryCategory(nav1)==0);
    NSArray *output = [state haoge_settingsshelf_transform:raw enabled:YES navigation:nav];
    VERIFY(([output isEqualToArray:@[navGroup,nav1,nav2,systemGroup,wifi]]));
    VERIFY(state.haoge_settingsshelf_tweaks.count==1);
    VERIFY(state.haoge_settingsshelf_apps.count==1);
    VERIFY(state.haoge_settingsshelf_tweaks[0]==tweak);
    VERIFY([state.haoge_settingsshelf_tweaks[0] propertyForKey:@"target"]==[tweak propertyForKey:@"target"]);
    for (NSUInteger i=0;i<100;i++) {
        output=[state haoge_settingsshelf_transform:output enabled:YES navigation:nav];
        VERIFY(output.count==5); VERIFY(state.haoge_settingsshelf_tweaks.count==1); VERIFY(state.haoge_settingsshelf_apps.count==1);
    }
    id late=haoge_settingsshelf_testEntry(@"late",1,@{@"AppBundleID":@"com.late.app"});
    output=[state haoge_settingsshelf_transform:[output arrayByAddingObject:late] enabled:YES navigation:nav];
    VERIFY(![output containsObject:late]); VERIFY(state.haoge_settingsshelf_apps.count==2);
    VERIFY(state.haoge_settingsshelf_apps[1]==late);
    // A navigation-free reload is not necessarily a complete inventory.
    id newWifi = haoge_settingsshelf_testEntry(@"WIFI",1,@{});
    id account = haoge_settingsshelf_testEntry(@"AppleID",1,@{});
    NSArray *partial = @[account, systemGroup, newWifi, tweak];
    output = [state haoge_settingsshelf_transform:partial enabled:YES navigation:nav];
    VERIFY(([output isEqualToArray:@[account, navGroup, nav1, nav2, systemGroup, newWifi]]));
    VERIFY(state.haoge_settingsshelf_tweaks[0] == tweak);
    VERIFY(state.haoge_settingsshelf_apps.count == 2);
    VERIFY(![output containsObject:wifi]);

    // Model what an already open category rendered, then observe a transient
    // getter result during host reload (without transforming that source).
    NSArray *renderedTweaks = state.haoge_settingsshelf_tweaks;
    NSArray *renderedApps = state.haoge_settingsshelf_apps;
    id delayed = haoge_settingsshelf_testEntry(@"ControlCenter18",1,@{ @"lazy-bundle":@"ControlCenter18" });
    id replacementTarget = [NSObject new];
    id replacement = haoge_settingsshelf_testEntry(@"kayoko",1,@{ @"lazy-bundle":@"KayokoNew", @"target":replacementTarget });
    NSMutableArray *busy = [@[delayed, tweak, replacement, own] mutableCopy];
    VERIFY([state haoge_settingsshelf_capture:busy]);
    VERIFY(busy.count == 4 && busy[1] == tweak && busy[2] == replacement);
    [busy removeAllObjects];
    output = [state haoge_settingsshelf_transform:output enabled:YES navigation:nav];
    VERIFY(!haoge_settingsshelf_sameRows(renderedTweaks, state.haoge_settingsshelf_tweaks));
    VERIFY(haoge_settingsshelf_sameRows(renderedApps, state.haoge_settingsshelf_apps));
    VERIFY(state.haoge_settingsshelf_tweaks.count == 2);
    VERIFY(state.haoge_settingsshelf_tweaks[0] == replacement);
    VERIFY([state.haoge_settingsshelf_tweaks[0] propertyForKey:@"target"] == replacementTarget);
    VERIFY(state.haoge_settingsshelf_tweaks[1] == delayed);
    renderedTweaks = state.haoge_settingsshelf_tweaks;
    VERIFY((![state haoge_settingsshelf_capture:@[tweak, replacement, delayed]]));
    VERIFY(haoge_settingsshelf_sameRows(renderedTweaks, state.haoge_settingsshelf_tweaks));
    id replacementAgain = haoge_settingsshelf_testEntry(@"kayoko",1,@{ @"lazy-bundle":@"KayokoNew" });
    VERIFY([state haoge_settingsshelf_capture:@[replacementAgain]]);
    VERIFY(!haoge_settingsshelf_sameRows(renderedTweaks, state.haoge_settingsshelf_tweaks));
    VERIFY(state.haoge_settingsshelf_tweaks[0] == replacementAgain);

    // ID-less objects use the observed source; category-local identifiers
    // must not hide an app or system specifier with the same identifier.
    id anon = haoge_settingsshelf_testEntry(nil,1,@{ @"lazy-bundle":@"AnonBundle" });
    id anonNew = haoge_settingsshelf_testEntry(nil,1,@{ @"lazy-bundle":@"AnonBundle" });
    id collisionApp = haoge_settingsshelf_testEntry(@"kayoko",1,@{ @"AppBundleID":@"org.example.sameid" });
    id systemCollision = haoge_settingsshelf_testEntry(@"kayoko",1,@{});
    NSArray *collisions = @[systemCollision, collisionApp, anon, anonNew];
    output = [state haoge_settingsshelf_transform:collisions enabled:YES navigation:nav];
    VERIFY([output containsObject:systemCollision]);
    VERIFY(state.haoge_settingsshelf_tweaks.count == 3 && state.haoge_settingsshelf_tweaks[2] == anonNew);
    VERIFY(state.haoge_settingsshelf_apps.count == 3 && state.haoge_settingsshelf_apps[2] == collisionApp);
    HaogeSettingsShelfGroupingState *newSession = [HaogeSettingsShelfGroupingState new];
    [newSession haoge_settingsshelf_transform:partial enabled:YES navigation:nav];
    VERIFY(newSession.haoge_settingsshelf_apps.count == 0);
    VERIFY(newSession.haoge_settingsshelf_tweaks.count == 1 && newSession.haoge_settingsshelf_tweaks[0] == tweak);
    VERIFY([state haoge_settingsshelf_transform:raw enabled:YES navigation:@[]] == raw);
    VERIFY([state haoge_settingsshelf_transform:raw enabled:NO navigation:nav] == raw);
    VERIFY(haoge_settingsshelf_entryCategory(haoge_settingsshelf_testEntry(@"weird",1,@{@"lazy-bundle":@42}))==0);
    VERIFY(haoge_settingsshelf_entryCategory(haoge_settingsshelf_testEntry(@"apple",1,@{@"AppBundleID":@"com.apple.Preferences"}))==0);
    NSLog(@"SettingsShelf grouping: %lu assertions passed",(unsigned long)haoge_settingsshelf_assertions);
    return 0;
} }
