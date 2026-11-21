#import <UIKit/UIKit.h>
#import <Preferences/PSSpecifier.h>
#import <substrate.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "HaogeSettingsShelfConfig.h"
#import "HaogeSettingsShelfPaths.h"

static NSString * const HaogeSettingsShelfCategoryKey = @"HaogeSettingsShelfCategory";
static NSString * const HaogeSettingsShelfChangedNotification = @"com.haoge.settingsshelf.preferences-changed";
static NSString * const HaogeSettingsShelfRootControllerName = @"HaogeSettingsShelfCategoryListController";
static NSString * const HaogeSettingsShelfPrefsBundleName = @"HaogeSettingsShelfPrefs";
static NSString * const HaogeSettingsShelfTweaksRowID = @"com.haoge.settingsshelf.category.tweaks";
static NSString * const HaogeSettingsShelfAppsRowID = @"com.haoge.settingsshelf.category.apps";

static IMP haoge_settingsshelf_originalSpecifiers = NULL;
static BOOL haoge_settingsshelf_hookInstalled = NO;
static Class haoge_settingsshelf_rootClass = Nil;
static NSBundle *haoge_settingsshelf_prefsBundle = nil;
static NSHashTable *haoge_settingsshelf_rootControllers = nil;
static NSArray<PSSpecifier *> *haoge_settingsshelf_appSpecifiers = nil;

#ifdef __cplusplus
extern "C"
#endif
__attribute__((visibility("default"))) NSArray<PSSpecifier *> *haoge_settingsshelf_appsSpecifiers(void) {
    @synchronized ([PSSpecifier class]) { return haoge_settingsshelf_appSpecifiers ?: @[]; }
}

static void haoge_settingsshelf_captureAppSpecifiers(NSArray *specifiers) {
    NSMutableArray<PSSpecifier *> *apps = [NSMutableArray array];
    for (id object in specifiers) {
        if (![object isKindOfClass:[PSSpecifier class]]) continue;
        PSSpecifier *item = object;
        if (item.cellType == PSGroupCell) continue;
        id bundleID = [item propertyForKey:@"AppBundleID"];
        if (![bundleID isKindOfClass:[NSString class]] || [bundleID length] == 0 ||
            [bundleID hasPrefix:@"/System"]) continue;
        [apps addObject:item];
    }
    @synchronized ([PSSpecifier class]) { haoge_settingsshelf_appSpecifiers = [apps copy]; }
}

static PSSpecifier *haoge_settingsshelf_categorySpecifier(NSString *title, NSString *identifier,
                                                           NSString *category) {
    NSString *bundlePath = haoge_settingsshelf_resourcePath(@"/Library/PreferenceBundles/HaogeSettingsShelfPrefs.bundle");
    if (!haoge_settingsshelf_prefsBundle || !haoge_settingsshelf_prefsBundle.isLoaded) {
        haoge_settingsshelf_prefsBundle = [NSBundle bundleWithPath:bundlePath];
        if (!haoge_settingsshelf_prefsBundle || ![haoge_settingsshelf_prefsBundle load]) return nil;
    }
    Class detailClass = [haoge_settingsshelf_prefsBundle classNamed:HaogeSettingsShelfRootControllerName];
    if (!detailClass) return nil;
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title target:nil set:nil get:nil
        detail:detailClass cell:PSLinkCell edit:nil];
    specifier.identifier = identifier;
    specifier.detailControllerClass = detailClass;
    [specifier setProperty:NSStringFromClass(detailClass) forKey:@"detail"];
    [specifier setProperty:HaogeSettingsShelfPrefsBundleName forKey:@"bundle"];
    [specifier setProperty:bundlePath forKey:@"lazy-bundle"];
    [specifier setProperty:@YES forKey:@"isController"];
    [specifier setProperty:category forKey:HaogeSettingsShelfCategoryKey];
    NSString *iconName = [category isEqualToString:@"apps"]
        ? @"HaogeSettingsShelfApps@2x.png" : @"HaogeSettingsShelfTweaks@2x.png";
    UIImage *sourceIcon = [UIImage imageWithContentsOfFile:[bundlePath stringByAppendingPathComponent:iconName]];
    if (sourceIcon.CGImage) {
        UIImage *icon = [UIImage imageWithCGImage:sourceIcon.CGImage scale:2.0 orientation:UIImageOrientationUp];
        [specifier setProperty:icon forKey:@"iconImage"];
    }
    return specifier;
}

static NSArray *haoge_settingsshelf_specifiersHook(id self, SEL _cmd) {
    NSArray *original = nil;
    if (haoge_settingsshelf_originalSpecifiers) {
        original = ((id (*)(id, SEL))haoge_settingsshelf_originalSpecifiers)(self, _cmd);
    }
    if (!original || !haoge_settingsshelf_rootClass || ![self isKindOfClass:haoge_settingsshelf_rootClass]) return original;
    haoge_settingsshelf_captureAppSpecifiers(original);
    if (haoge_settingsshelf_rootControllers) [haoge_settingsshelf_rootControllers addObject:self];
    if (![[HaogeSettingsShelfConfig haoge_settingsshelf_shared] haoge_settingsshelf_isEnabled]) return original;

    NSMutableArray *result = [original mutableCopy];
    BOOL hasTweaks = NO, hasApps = NO;
    for (PSSpecifier *item in result) {
        if (![item isKindOfClass:[PSSpecifier class]]) continue;
        hasTweaks |= [item.identifier isEqualToString:HaogeSettingsShelfTweaksRowID];
        hasApps |= [item.identifier isEqualToString:HaogeSettingsShelfAppsRowID];
    }
    if (hasTweaks && hasApps) return original;

    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"越狱插件和应用软件"];
    group.identifier = @"com.haoge.settingsshelf.category.group";
    PSSpecifier *tweaks = hasTweaks ? nil : haoge_settingsshelf_categorySpecifier(@"越狱插件", HaogeSettingsShelfTweaksRowID, @"tweaks");
    PSSpecifier *apps = hasApps ? nil : haoge_settingsshelf_categorySpecifier(@"应用软件", HaogeSettingsShelfAppsRowID, @"apps");
    if ((!hasTweaks && !tweaks) || (!hasApps && !apps)) return original;
    [result addObject:group];
    if (tweaks) [result addObject:tweaks];
    if (apps) [result addObject:apps];
    return result;
}

static BOOL haoge_settingsshelf_installRootHook(void) {
    if (haoge_settingsshelf_hookInstalled) return YES;
    SEL selector = @selector(specifiers);
    NSArray *candidates = @[@"PSUIPrefsListController", @"PrefsListController", @"PSGGeneralController"];
    for (NSString *name in candidates) {
        Class cls = NSClassFromString(name);
        if (!cls || !class_getInstanceMethod(cls, selector)) continue;
        haoge_settingsshelf_rootClass = cls;
        MSHookMessageEx(cls, selector, (IMP)haoge_settingsshelf_specifiersHook,
                        &haoge_settingsshelf_originalSpecifiers);
        if (haoge_settingsshelf_originalSpecifiers) {
            haoge_settingsshelf_hookInstalled = YES;
            return YES;
        }
    }
    return NO;
}

static void haoge_settingsshelf_refreshRoots(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        SEL reloadSelector = sel_registerName("reloadSpecifiers");
        for (id controller in haoge_settingsshelf_rootControllers.allObjects) {
            if ([controller respondsToSelector:reloadSelector])
                ((void (*)(id, SEL))objc_msgSend)(controller, reloadSelector);
        }
    });
}

static void haoge_settingsshelf_retryRootHook(NSUInteger attempt) {
    if (haoge_settingsshelf_installRootHook() || attempt >= 40) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{ haoge_settingsshelf_retryRootHook(attempt + 1); });
}

__attribute__((constructor)) static void haoge_settingsshelf_constructor(void) {
    @autoreleasepool {
        haoge_settingsshelf_rootControllers = [NSHashTable weakObjectsHashTable];
        [HaogeSettingsShelfConfig haoge_settingsshelf_shared];
        [[NSNotificationCenter defaultCenter] addObserverForName:HaogeSettingsShelfChangedNotification
            object:nil queue:[NSOperationQueue mainQueue]
            usingBlock:^(__unused NSNotification *note) { haoge_settingsshelf_refreshRoots(); }];
        dispatch_async(dispatch_get_main_queue(), ^{ haoge_settingsshelf_retryRootHook(0); });
    }
}
