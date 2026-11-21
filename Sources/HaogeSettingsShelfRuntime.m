#import "HaogeSettingsShelfRuntime.h"
#import "HaogeSettingsShelfGrouping.h"
#import "HaogeSettingsShelfSnapshot.h"
#import "HaogeSettingsShelfPaths.h"
#import "HaogeSettingsShelfGuards.h"
#import "HaogeSettingsShelfCustomization.h"
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <substrate.h>
#import <objc/runtime.h>

static char HaogeSettingsShelfStateKey;
static __weak PSListController *haoge_settingsshelf_root;
static Class haoge_settingsshelf_rootClass;
static NSArray *haoge_settingsshelf_navigation;
static NSUInteger haoge_settingsshelf_hits;
static __thread NSUInteger haoge_settingsshelf_busy;
static __thread BOOL haoge_settingsshelf_reconciling;
static BOOL haoge_settingsshelf_reconcilePending;
static __weak PSListController *haoge_settingsshelf_pendingRoot;
static BOOL haoge_settingsshelf_snapshotPending;
static NSMutableSet *haoge_settingsshelf_installed;
static IMP haoge_settingsshelf_originalSpecifiers;

static BOOL haoge_settingsshelf_isRoot(id value) {
    return value && haoge_settingsshelf_rootClass && [value isKindOfClass:haoge_settingsshelf_rootClass];
}
static HaogeSettingsShelfGroupingState *haoge_settingsshelf_state(id root) {
    HaogeSettingsShelfGroupingState *state = objc_getAssociatedObject(root, &HaogeSettingsShelfStateKey);
    if (!state) {
        state = [HaogeSettingsShelfGroupingState new];
        objc_setAssociatedObject(root, &HaogeSettingsShelfStateKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state;
}
static NSArray *haoge_settingsshelf_navigationRows(void) {
    if (haoge_settingsshelf_navigation.count == 3) {
        for (PSSpecifier *row in haoge_settingsshelf_navigation)
            if ([row.identifier isEqualToString:@"com.haoge.settingsshelf.category.tweaks"]) haoge_settingsshelf_applyCustomization(row);
        return haoge_settingsshelf_navigation;
    }
    Class detail = NSClassFromString(@"HaogeSettingsShelfCategoryListController");
    if (!detail) {
        NSString *path = haoge_settingsshelf_resourcePath(@"/Library/PreferenceBundles/HaogeSettingsShelfPrefs.bundle");
        NSBundle *bundle = [NSBundle bundleWithPath:path]; NSError *error = nil;
        if (![bundle isLoaded] && ![bundle loadAndReturnError:&error]) {
            NSLog(@"[SettingsShelf] preference bundle unavailable: %@", error.localizedDescription); return @[];
        }
        detail = NSClassFromString(@"HaogeSettingsShelfCategoryListController");
    }
    if (!detail) return @[];
    NSMutableArray *rows = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:@"插件收纳"];
    group.identifier = @"com.haoge.settingsshelf.category.group"; [rows addObject:group];
    for (NSString *category in @[@"tweaks", @"apps"]) {
        BOOL apps = [category isEqualToString:@"apps"];
        PSSpecifier *row = [PSSpecifier preferenceSpecifierNamed:apps ? @"应用软件" : @"越狱插件"
            target:nil set:nil get:nil detail:detail cell:PSLinkCell edit:nil];
        row.identifier = [@"com.haoge.settingsshelf.category." stringByAppendingString:category];
        [row setProperty:category forKey:@"HaogeSettingsShelfCategory"];
        NSString *file = apps ? @"HaogeSettingsShelfApps@2x.png" : @"HaogeSettingsShelfTweaks@2x.png";
        NSString *imagePath = [haoge_settingsshelf_resourcePath(@"/Library/PreferenceBundles/HaogeSettingsShelfPrefs.bundle") stringByAppendingPathComponent:file];
        UIImage *image = [UIImage imageWithContentsOfFile:imagePath];
        if (image.CGImage) [row setProperty:[UIImage imageWithCGImage:image.CGImage scale:2 orientation:UIImageOrientationUp] forKey:@"iconImage"];
        if (!apps) haoge_settingsshelf_applyCustomization(row);
        [rows addObject:row];
    }
    haoge_settingsshelf_navigation = [rows copy]; return haoge_settingsshelf_navigation;
}

NSDictionary *haoge_settingsshelf_snapshot(void) {
    if (![NSThread isMainThread]) return @{};
    PSListController *root = haoge_settingsshelf_root;
    HaogeSettingsShelfGroupingState *state = root ? haoge_settingsshelf_state(root) : nil;
    return @{@"loaded":@YES, @"root":root ? NSStringFromClass(root.class) : @"", @"hits":@(haoge_settingsshelf_hits),
        @"tweaks":state.haoge_settingsshelf_tweaks ?: @[], @"apps":state.haoge_settingsshelf_apps ?: @[],
        @"navigation":haoge_settingsshelf_navigation ?: @[]};
}

// Deliver out of the native root transaction and coalesce multiple getter reads.
static void haoge_settingsshelf_scheduleSnapshot(void) {
    if (haoge_settingsshelf_snapshotPending) return;
    haoge_settingsshelf_snapshotPending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        haoge_settingsshelf_snapshotPending = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:HAOGE_SETTINGSSHELF_SNAPSHOT_CHANGED_NOTIFICATION object:nil];
    });
}
static void haoge_settingsshelf_captureRows(PSListController *root, NSArray *rows) {
    BOOL rootChanged = haoge_settingsshelf_root != root;
    haoge_settingsshelf_root = root;
    BOOL changed = [haoge_settingsshelf_state(root) haoge_settingsshelf_capture:rows];
    if (rootChanged || changed) haoge_settingsshelf_scheduleSnapshot();
}

static NSArray *haoge_settingsshelf_prepareRows(PSListController *root, NSArray *current, NSArray *navigation) {
    HaogeSettingsShelfGroupingState *state = haoge_settingsshelf_state(root);
    NSArray *desired = [state haoge_settingsshelf_transform:current enabled:YES navigation:navigation];
    for (id row in state.haoge_settingsshelf_tweaks) haoge_settingsshelf_applyCustomization(row);
    return haoge_settingsshelf_guardRootRows(desired);
}
// Match TweaksHub's deferred root insertion flow: let the system transaction
// finish, then remove each moved contiguous run through PSListController APIs.
static void haoge_settingsshelf_reconcile(PSListController *root) {
    if (!root || !haoge_settingsshelf_isRoot(root) || haoge_settingsshelf_busy || ![NSThread isMainThread]) return;
    ++haoge_settingsshelf_busy;
    haoge_settingsshelf_reconciling = YES;
    @try {
        NSArray *current = [root specifiers];
        if (![current isKindOfClass:NSArray.class]) return;
        // Save original identities and indices even if the native API mutates
        // its backing array in place during reverse-order removals.
        current = [current copy];
        haoge_settingsshelf_captureRows(root, current);
        NSArray *navigation = haoge_settingsshelf_navigationRows();
        if (navigation.count != 3) return;
        // Fail closed on a host without the native insertion API. Do not
        // remove rows unless the complete navigation can be inserted safely.
        if (![root respondsToSelector:@selector(insertContiguousSpecifiers:atIndex:animated:)]) return;
        NSArray *desired = haoge_settingsshelf_prepareRows(root, current, navigation);
        BOOL insertNavigation = NO;
        NSArray<NSValue *> *ranges = haoge_settingsshelf_rootRemovalRanges(current, desired, navigation, &insertNavigation);
        for (NSValue *value in ranges.reverseObjectEnumerator) {
            NSArray *run = [current subarrayWithRange:value.rangeValue];
            if (run.count) [root removeContiguousSpecifiers:run animated:NO];
        }

        if (insertNavigation) {
            NSUInteger insertionIndex = haoge_settingsshelf_navigationInsertionIndex([root specifiers]);
            [root insertContiguousSpecifiers:navigation atIndex:insertionIndex animated:NO];
        }
        haoge_settingsshelf_root = root; ++haoge_settingsshelf_hits;
    } @finally {
        haoge_settingsshelf_reconciling = NO;
        --haoge_settingsshelf_busy;
    }
}
static void haoge_settingsshelf_schedule(id controller) {
    if (![NSThread isMainThread] || !haoge_settingsshelf_isRoot(controller) || haoge_settingsshelf_busy) return;
    haoge_settingsshelf_pendingRoot = controller;
    if (haoge_settingsshelf_reconcilePending) return;
    haoge_settingsshelf_reconcilePending = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        haoge_settingsshelf_reconcilePending = NO;
        PSListController *root = haoge_settingsshelf_pendingRoot;
        haoge_settingsshelf_pendingRoot = nil;
        haoge_settingsshelf_reconcile(root);
    });
}

static id haoge_settingsshelf_specifiersHook(id controller, SEL selector) {
    NSArray *rows = ((id (*)(id, SEL))haoge_settingsshelf_originalSpecifiers)(controller, selector);
    if (![NSThread isMainThread] || haoge_settingsshelf_reconciling || !haoge_settingsshelf_isRoot(controller) ||
        ![rows isKindOfClass:NSArray.class]) return rows;
    // A native reload can expose useful rows briefly while busy. Observe them,
    // but never reorder the host list inside that transaction.
    haoge_settingsshelf_captureRows(controller, rows);
    ++haoge_settingsshelf_hits;
    if (haoge_settingsshelf_busy) return rows;
    // Keep the existing cold-list path; live tables use native transactions.
    if ([controller isViewLoaded]) { haoge_settingsshelf_schedule(controller); return rows; }
    NSArray *navigation = haoge_settingsshelf_navigationRows();
    NSArray *result = haoge_settingsshelf_prepareRows(controller, rows, navigation);
    NSMutableArray *live = [rows isKindOfClass:NSMutableArray.class] ? (NSMutableArray *)rows : [rows mutableCopy];
    if (!haoge_settingsshelf_sameRows(live, result)) [live setArray:result];
    return live;
}

static void haoge_settingsshelf_installBoolHook(Class cls, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSString *installedKey = [NSStringFromClass(cls) stringByAppendingFormat:@".%@", name];
    if ([haoge_settingsshelf_installed containsObject:installedKey] || ![cls instancesRespondToSelector:selector]) return;
    __block IMP original = NULL;
    IMP replacement = imp_implementationWithBlock(^(id controller, BOOL flag) {
        ++haoge_settingsshelf_busy;
        @try { ((void (*)(id, SEL, BOOL))original)(controller, selector, flag); }
        @finally { --haoge_settingsshelf_busy; }
        haoge_settingsshelf_schedule(controller);
    });
    MSHookMessageEx(cls, selector, replacement, &original);
    if (original) [haoge_settingsshelf_installed addObject:installedKey];
}
static void haoge_settingsshelf_installRootHooks(void) {
    if (!haoge_settingsshelf_rootClass) {
        for (NSString *name in @[@"PSUIPrefsListController", @"PrefsListController", @"PSGGeneralController"]) {
            Class candidate = NSClassFromString(name);
            if (candidate) { haoge_settingsshelf_rootClass = candidate; break; }
        }
    }
    Class cls = haoge_settingsshelf_rootClass;
    if (!cls) return;
    if (!haoge_settingsshelf_installed) haoge_settingsshelf_installed = [NSMutableSet set];

    NSString *specifiersKey = [NSStringFromClass(cls) stringByAppendingFormat:@".%@", NSStringFromSelector(@selector(specifiers))];
    if (![haoge_settingsshelf_installed containsObject:specifiersKey]) {
        IMP original = NULL;
        MSHookMessageEx(cls, @selector(specifiers), (IMP)haoge_settingsshelf_specifiersHook, &original);
        haoge_settingsshelf_originalSpecifiers = original;
        if (original) [haoge_settingsshelf_installed addObject:specifiersKey];
    }

    SEL insertSelector = NSSelectorFromString(@"_insertContiguousSpecifiers:atIndex:animated:");
    NSString *insertKey = [NSStringFromClass(cls) stringByAppendingFormat:@".%@", NSStringFromSelector(insertSelector)];
    if (![haoge_settingsshelf_installed containsObject:insertKey] && [cls instancesRespondToSelector:insertSelector]) {
        __block IMP original = NULL;
        IMP replacement = imp_implementationWithBlock(^(id controller, NSArray *rows, NSInteger index, BOOL animated) {
            ++haoge_settingsshelf_busy;
            @try { ((void (*)(id, SEL, id, NSInteger, BOOL))original)(controller, insertSelector, rows, index, animated); }
            @finally { --haoge_settingsshelf_busy; }
            haoge_settingsshelf_schedule(controller);
        });
        MSHookMessageEx(cls, insertSelector, replacement, &original);
        if (original) [haoge_settingsshelf_installed addObject:insertKey];
    }
    haoge_settingsshelf_installBoolHook(cls, @"insertMovedThirdPartySpecifiersAnimated:");
    haoge_settingsshelf_installBoolHook(cls, @"viewWillAppear:");
    haoge_settingsshelf_installBoolHook(cls, @"viewDidAppear:");

    SEL reloadSelector = @selector(reloadSpecifiers);
    NSString *reloadKey = [NSStringFromClass(cls) stringByAppendingFormat:@".%@", NSStringFromSelector(reloadSelector)];
    if (![haoge_settingsshelf_installed containsObject:reloadKey] && [cls instancesRespondToSelector:reloadSelector]) {
        __block IMP original = NULL;
        IMP replacement = imp_implementationWithBlock(^(id controller) {
            ++haoge_settingsshelf_busy;
            @try { ((void (*)(id, SEL))original)(controller, reloadSelector); }
            @finally { --haoge_settingsshelf_busy; }
            haoge_settingsshelf_schedule(controller);
        });
        MSHookMessageEx(cls, reloadSelector, replacement, &original);
        if (original) [haoge_settingsshelf_installed addObject:reloadKey];
    }
    NSLog(@"[SettingsShelf] root-only original-style hooks installed: %@", NSStringFromClass(cls));
}

static BOOL haoge_settingsshelf_refreshPending;
static void haoge_settingsshelf_preferencesChanged(CFNotificationCenterRef center, void *observer,
    CFStringRef name, const void *object, CFDictionaryRef info) {
    (void)center; (void)observer; (void)name; (void)object; (void)info;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (haoge_settingsshelf_refreshPending) return;
        haoge_settingsshelf_refreshPending = YES;
        dispatch_async(dispatch_get_main_queue(), ^{
            haoge_settingsshelf_refreshPending = NO;
            haoge_settingsshelf_invalidateCustomization();
            haoge_settingsshelf_installGuards();
            PSListController *root = haoge_settingsshelf_root;
            // Rebuild from the system source so disabling a guard restores
            // its rows as well; never write into a live specifier array.
            if (root && !haoge_settingsshelf_busy) [root reloadSpecifiers];
            haoge_settingsshelf_schedule(root);
        });
    });
}

void haoge_settingsshelf_start(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            haoge_settingsshelf_preferencesChanged, CFSTR("com.haoge.settingsshelf.preferences-changed"),
            NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { haoge_settingsshelf_installRootHooks(); haoge_settingsshelf_installGuards(); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:@"com.haoge.settingsshelf.regroup" object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) { haoge_settingsshelf_schedule(haoge_settingsshelf_root); }];
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue
            usingBlock:^(__unused NSNotification *note) {
                haoge_settingsshelf_invalidateCustomization();
                haoge_settingsshelf_installRootHooks(); haoge_settingsshelf_installGuards();
                haoge_settingsshelf_schedule(haoge_settingsshelf_root);
            }];
        for (NSUInteger i = 0; i < 16; ++i) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(i * 0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ haoge_settingsshelf_installRootHooks(); });
        haoge_settingsshelf_installRootHooks(); haoge_settingsshelf_installGuards();
        NSLog(@"[SettingsShelf] root-list flow active; navigation between account and connectivity");
    });
}
